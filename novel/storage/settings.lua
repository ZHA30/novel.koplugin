-- luacheck: globals G_reader_settings

local Settings = {
    key = "novel",
}

Settings.defaults = {
    schema_version = 2,
    debug = {
        enabled = false,
        max_entries = 200,
    },
    cache = {
        enabled = true,
        chapter_content_enabled = true,
        search_ttl_days = 0,
        detail_ttl_days = 0,
        toc_ttl_days = 0,
        content_ttl_days = 0,
        max_metadata_records = 10000,
    },
    prefetch = {
        enabled = true,
        lookahead = 1,
        initial_delay = 0.8,
        timeout_seconds = 45,
    },
    storage = {
        backend = "prototype",
        target_backend = "sqlite",
        schema_version = 0,
    },
    chapter_list = {
        books = {},
    },
    book_list = {
        detail_visited = {},
    },
    ui = {
        grouping = {
            sources_collapsed_groups = {},
            discover_collapsed_sources = {},
        },
    },
}

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function mergeDefaults(settings, defaults)
    local changed = false
    for key, default_value in pairs(defaults) do
        if settings[key] == nil then
            settings[key] = clone(default_value)
            changed = true
        elseif type(settings[key]) == "table" and type(default_value) == "table" then
            if mergeDefaults(settings[key], default_value) then
                changed = true
            end
        end
    end
    return changed
end

local function migrate(settings)
    local version = tonumber(settings.schema_version) or 0
    if version >= Settings.defaults.schema_version then
        return false
    end

    settings.cache = settings.cache or {}
    settings.cache.chapter_content_enabled = settings.cache.chapter_content_enabled ~= false
    settings.cache.search_ttl_days = 0
    settings.cache.detail_ttl_days = 0
    settings.cache.toc_ttl_days = 0
    settings.cache.content_ttl_days = 0
    settings.cache.max_metadata_records = settings.cache.max_metadata_records or 10000
    settings.cleanup = nil
    settings.schema_version = Settings.defaults.schema_version
    return true
end

function Settings.load()
    local settings = G_reader_settings:readSetting(Settings.key)
    local changed = false

    if type(settings) ~= "table" then
        settings = {}
        changed = true
    end

    if migrate(settings) then
        changed = true
    end
    if mergeDefaults(settings, Settings.defaults) then
        changed = true
    end

    if changed then
        Settings.save(settings)
    end

    return settings
end

function Settings.save(settings)
    G_reader_settings:saveSetting(Settings.key, settings)
end

function Settings.reset()
    local settings = clone(Settings.defaults)
    Settings.save(settings)
    return settings
end

function Settings.delete()
    G_reader_settings:delSetting(Settings.key)
end

return Settings
