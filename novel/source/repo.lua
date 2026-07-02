-- luacheck: globals lfs

local DataStorage = require("datastorage")
local Importer = require("novel.source.importer")
local LuaSettings = require("luasettings")

local Repo = {
    state_path = DataStorage:getSettingsDir() .. "/novel_sources.lua",
    source_dir = (debug.getinfo(1, "S").source:match("^@(.*/)novel/source/repo%.lua$")
        or "./") .. "source",
}
Repo.__index = Repo

local function sourceKey(source)
    return source.bookSourceUrl
end

local function sortSources(sources)
    table.sort(sources, function(left, right)
        if left.customOrder ~= right.customOrder then
            return left.customOrder < right.customOrder
        end
        return (left.bookSourceName or "") < (right.bookSourceName or "")
    end)
end

function Repo:new()
    return setmetatable({
        settings = LuaSettings:open(Repo.state_path),
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
    if lfs.attributes(Repo.source_dir, "mode") ~= "directory" then
        return {}
    end

    local ok, iter, dir_obj = pcall(lfs.dir, Repo.source_dir)
    if not ok then
        return {}
    end

    local files = {}
    for entry in iter, dir_obj do
        if isJSONFile(entry) then
            local path = Repo.source_dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "file" or mode == "link" then
                table.insert(files, path)
            end
        end
    end
    table.sort(files)
    return files
end

local function loadFile(path)
    local content, read_err = readFile(path)
    if not content then
        return {}, {
            { file = path, error = read_err },
        }
    end

    local sources, errors = Importer.fromJSON(content)
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

function Repo:enabledStates()
    return self.settings:readSetting("source_enabled") or {}
end

local function applyState(source, states)
    local state = states[sourceKey(source)]
    if state ~= nil then
        source.enabled = state == true
    end
    return source
end

function Repo:listWithErrors()
    local sources, errors, index = {}, {}, {}
    local states = self:enabledStates()
    local files = sourceFiles()

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
    return sources, errors
end

function Repo:list()
    local sources = self:listWithErrors()
    return sources
end

function Repo:get(book_source_url)
    for _, source in ipairs(self:list()) do
        if source.bookSourceUrl == book_source_url then
            return source
        end
    end
end

function Repo:count()
    return #self:list()
end

function Repo:groups()
    local groups = {}
    for _, source in ipairs(self:list()) do
        local group = source.bookSourceGroup or ""
        groups[group] = (groups[group] or 0) + 1
    end
    return groups
end

function Repo:listGroups()
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

function Repo:setEnabled(book_source_url, enabled)
    if not self:get(book_source_url) then
        return false
    end

    local states = self:enabledStates()
    states[book_source_url] = enabled == true
    self.settings:saveSetting("source_enabled", states)
    self.settings:flush()
    return true
end

function Repo.deleteStorage()
    os.remove(Repo.state_path)
    os.remove(Repo.state_path .. ".old")
end

return Repo
