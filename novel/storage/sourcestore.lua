-- luacheck: globals lfs

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local SourceRecord = require("novel.storage.sourcerecord")

local SourceStore = {
    state_path = DataStorage:getSettingsDir() .. "/novel_sources.lua",
    source_dir = (debug.getinfo(1, "S").source:match("^@(.*/)novel/storage/sourcestore%.lua$")
        or "./") .. "source",
    signature_check_interval = 5,
}
SourceStore.__index = SourceStore

local function sourceKey(source)
    return SourceRecord.key(source)
end

local function sortSources(sources)
    table.sort(sources, function(left, right)
        if left.customOrder ~= right.customOrder then
            return left.customOrder < right.customOrder
        end
        return (left.bookSourceName or "") < (right.bookSourceName or "")
    end)
end

function SourceStore:new()
    return setmetatable({
        settings = LuaSettings:open(SourceStore.state_path),
        cache = nil,
    }, self)
end

local function isJSONFile(entry)
    return type(entry) == "string" and entry:lower():match("%.json$") ~= nil
end

local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err or "failed to open file"
    end

    local content = file:read("*a")
    file:close()
    return content
end

local function sourceFiles()
    if lfs.attributes(SourceStore.source_dir, "mode") ~= "directory" then
        return {}
    end

    local ok, iter, dir_obj = pcall(lfs.dir, SourceStore.source_dir)
    if not ok then
        return {}
    end

    local files = {}
    for entry in iter, dir_obj do
        if isJSONFile(entry) then
            local path = SourceStore.source_dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "file" or mode == "link" then
                table.insert(files, path)
            end
        end
    end
    table.sort(files)
    return files
end

local function sourceSignature(files)
    local parts = { tostring(#files) }
    for file_index = 1, #files do
        local path = files[file_index]
        local attr = lfs.attributes(path) or {}
        parts[#parts + 1] = path
        parts[#parts + 1] = tostring(attr.modification or "")
        parts[#parts + 1] = tostring(attr.size or "")
    end
    return table.concat(parts, "\n")
end

local function loadFile(path)
    local content, read_err = readFile(path)
    if not content then
        return {}, {
            { file = path, error = read_err },
        }
    end

    local sources, errors = SourceRecord.fromJSON(content)
    if not sources then
        return {}, {
            { file = path, error = errors },
        }
    end

    if type(errors) == "table" then
        for error_index = 1, #errors do
            errors[error_index].file = path
        end
    end
    return sources, errors or {}
end

function SourceStore:enabledStates()
    return self.settings:readSetting("source_enabled") or {}
end

local function applyState(source, states)
    local state = states[sourceKey(source)]
    if state ~= nil then
        source.enabled = state == true
    end
    return source
end

function SourceStore:listWithErrors()
    local timestamp = os.time()
    if self.cache
        and self.cache.checked_at
        and timestamp - self.cache.checked_at < SourceStore.signature_check_interval then
        return self.cache.sources, self.cache.errors
    end

    local files = sourceFiles()
    local signature = sourceSignature(files)
    if self.cache and self.cache.signature == signature then
        self.cache.checked_at = timestamp
        return self.cache.sources, self.cache.errors
    end

    local sources, errors, index = {}, {}, {}
    local states = self:enabledStates()

    for file_index = 1, #files do
        local imported, file_errors = loadFile(files[file_index])
        for error_index = 1, #file_errors do
            table.insert(errors, file_errors[error_index])
        end
        for source_index = 1, #imported do
            local source = applyState(imported[source_index], states)
            local key = sourceKey(source)
            local existing_position = index[key]
            if existing_position then
                sources[existing_position] = source
            else
                index[key] = #sources + 1
                table.insert(sources, source)
            end
        end
    end

    sortSources(sources)
    self.cache = {
        signature = signature,
        checked_at = timestamp,
        sources = sources,
        errors = errors,
    }
    return sources, errors
end

function SourceStore:list()
    local sources = self:listWithErrors()
    return sources
end

function SourceStore:get(book_source_url)
    for _, source in ipairs(self:list()) do
        if source.bookSourceUrl == book_source_url then
            return source
        end
    end
end

function SourceStore:count()
    return #self:list()
end

function SourceStore:groups()
    local groups = {}
    for _, source in ipairs(self:list()) do
        local group = source.bookSourceGroup or ""
        groups[group] = (groups[group] or 0) + 1
    end
    return groups
end

function SourceStore:listGroups()
    local groups, group_index = {}, {}
    for _, source in ipairs(self:list()) do
        local group_name = source.bookSourceGroup or ""
        local position = group_index[group_name]
        if not position then
            position = #groups + 1
            group_index[group_name] = position
            groups[position] = {
                name = group_name,
                sources = {},
            }
        end
        table.insert(groups[position].sources, source)
    end

    table.sort(groups, function(left, right)
        if left.name == "" then
            return false
        end
        if right.name == "" then
            return true
        end
        return left.name < right.name
    end)

    return groups
end

function SourceStore:setEnabled(book_source_url, enabled)
    if not self:get(book_source_url) then
        return false
    end

    local states = self:enabledStates()
    states[book_source_url] = enabled == true
    self.settings:saveSetting("source_enabled", states)
    self.settings:flush()
    self.cache = nil
    return true
end

function SourceStore.deleteStorage()
    os.remove(SourceStore.state_path)
    os.remove(SourceStore.state_path .. ".old")
end

function SourceStore.key(source)
    return SourceRecord.key(source)
end

function SourceStore.title(source)
    return SourceRecord.title(source)
end

function SourceStore.canSearch(source)
    return SourceRecord.canSearch(source)
end

function SourceStore.canExplore(source)
    return SourceRecord.canExplore(source)
end

function SourceStore.searchable(sources)
    return SourceRecord.searchable(sources)
end

SourceStore.normalize = SourceRecord.normalize
SourceStore.fromJSON = SourceRecord.fromJSON

return SourceStore
