local DataStorage = require("datastorage")
local Importer = require("novel.source.importer")
local LuaSettings = require("luasettings")
local rapidjson = require("rapidjson")

local Repo = {
    path = DataStorage:getSettingsDir() .. "/novel_sources.lua",
    export_path = DataStorage:getSettingsDir() .. "/novel_sources_export.json",
}
Repo.__index = Repo

local function sourceKey(source)
    return source.bookSourceUrl
end

local function healthKey(book_source_url)
    return tostring(book_source_url or "")
end

local function sortSources(sources)
    table.sort(sources, function(left, right)
        if left.customOrder ~= right.customOrder then
            return left.customOrder < right.customOrder
        end
        return (left.bookSourceName or "") < (right.bookSourceName or "")
    end)
end

local function compactError(error)
    if type(error) ~= "table" then
        return nil
    end
    return {
        kind = error.kind or "unknown",
        message = error.message or tostring(error.kind or ""),
    }
end

local function compactResponse(response)
    if type(response) ~= "table" then
        return nil
    end
    return {
        request_url = response.request_url,
        final_url = response.final_url or response.url,
        status = response.status,
        bytes = response.bytes,
    }
end

local function compactHealth(item, keyword, checked_at)
    return {
        source = item.source or "",
        source_url = item.source_url or "",
        status = item.status or "unknown",
        ok = item.ok == true,
        books_count = item.books_count or 0,
        keyword = keyword or "",
        checked_at = checked_at,
        error = compactError(item.error),
        response = compactResponse(item.response),
        unsupported_count = #(item.unsupported or {}),
    }
end

function Repo:new()
    return setmetatable({
        settings = LuaSettings:open(Repo.path),
    }, self)
end

function Repo:list()
    local sources = self.settings:readSetting("sources") or {}
    sortSources(sources)
    return sources
end

function Repo:getHealth(book_source_url)
    local health = self.settings:readSetting("source_health") or {}
    return health[healthKey(book_source_url)]
end

function Repo:listHealth()
    return self.settings:readSetting("source_health") or {}
end

function Repo:saveHealthFromCheck(result)
    if type(result) ~= "table" or type(result.results) ~= "table" then
        return 0
    end

    local health = self:listHealth()
    local checked_at = os.time()
    local saved = 0
    for index = 1, #result.results do
        local item = result.results[index]
        local key = healthKey(item.source_url)
        if key ~= "" then
            health[key] = compactHealth(item, result.keyword, checked_at)
            saved = saved + 1
        end
    end

    if saved > 0 then
        self.settings:saveSetting("source_health", health)
        self.settings:flush()
    end
    return saved
end

function Repo:clearHealth(book_source_url)
    if book_source_url == nil then
        self.settings:saveSetting("source_health", {})
        self.settings:flush()
        return true
    end

    local health = self:listHealth()
    local key = healthKey(book_source_url)
    if health[key] == nil then
        return false
    end
    health[key] = nil
    self.settings:saveSetting("source_health", health)
    self.settings:flush()
    return true
end

function Repo:saveAll(sources)
    sortSources(sources)
    self.settings:saveSetting("sources", sources)
    self.settings:flush()
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

function Repo:importJSON(json)
    local imported, errors = Importer.fromJSON(json)
    if not imported then
        return {
            imported = 0,
            errors = {
                { error = errors },
            },
        }
    end

    local sources = self:list()
    local index = {}
    for position, source in ipairs(sources) do
        index[sourceKey(source)] = position
    end

    for _, source in ipairs(imported) do
        local existing_position = index[sourceKey(source)]
        if existing_position then
            sources[existing_position] = source
        else
            table.insert(sources, source)
        end
    end

    if #imported > 0 then
        self:saveAll(sources)
    end

    return {
        imported = #imported,
        errors = errors or {},
    }
end

function Repo:importFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        return {
            imported = 0,
            errors = {
                { error = err or "failed to open file" },
            },
        }
    end

    local content = file:read("*a")
    file:close()
    return self:importJSON(content)
end

function Repo:exportJSON()
    return rapidjson.encode(self:list(), { pretty = true })
end

function Repo:exportFile(path)
    local content = self:exportJSON()
    local file, err = io.open(path, "wb")
    if not file then
        return nil, err or "failed to open file"
    end
    file:write(content)
    file:close()
    return true
end

function Repo:setEnabled(book_source_url, enabled)
    local sources = self:list()
    local changed = false
    for _, source in ipairs(sources) do
        if source.bookSourceUrl == book_source_url then
            source.enabled = enabled == true
            changed = true
            break
        end
    end
    if changed then
        self:saveAll(sources)
    end
    return changed
end

function Repo:setEnabledExplore(book_source_url, enabled)
    local sources = self:list()
    local changed = false
    for _, source in ipairs(sources) do
        if source.bookSourceUrl == book_source_url then
            source.enabledExplore = enabled == true
            changed = true
            break
        end
    end
    if changed then
        self:saveAll(sources)
    end
    return changed
end

function Repo:remove(book_source_url)
    local sources = self:list()
    local removed = false
    for index = #sources, 1, -1 do
        if sources[index].bookSourceUrl == book_source_url then
            table.remove(sources, index)
            removed = true
            break
        end
    end
    if removed then
        self:saveAll(sources)
        self:clearHealth(book_source_url)
    end
    return removed
end

function Repo:clear()
    self:saveAll({})
    self:clearHealth()
end

function Repo.deleteStorage()
    os.remove(Repo.path)
    os.remove(Repo.path .. ".old")
end

return Repo
