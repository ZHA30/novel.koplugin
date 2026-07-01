local DataStorage = require("datastorage")
local Importer = require("novel.source.importer")
local LuaSettings = require("luasettings")

local Repo = {
    path = DataStorage:getSettingsDir() .. "/novel_sources.lua",
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
        settings = LuaSettings:open(Repo.path),
    }, self)
end

function Repo:list()
    local sources = self.settings:readSetting("sources") or {}
    sortSources(sources)
    return sources
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

function Repo.deleteStorage()
    os.remove(Repo.path)
    os.remove(Repo.path .. ".old")
end

return Repo
