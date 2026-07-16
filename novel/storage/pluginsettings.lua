-- luacheck: globals G_reader_settings

local PluginSettings = {
    key = "novel",
}

PluginSettings.defaults = {
    schema_version = 7,
    debug = {
        enabled = false,
    },
    download = {
        background_mode = "pause_while_reading",
        workers = 1,
    },
    cache = {
        enabled = true,
        chapter_content_enabled = true,
        search_ttl_days = 1,
        detail_ttl_days = 7,
        toc_ttl_days = 1,
        content_ttl_days = 14,
        max_metadata_records = 10000,
        max_metadata_bytes = 20 * 1024 * 1024,
    },
    chapter_list = {
        books = {},
    },
    book_list = {
        detail_visited = {},
    },
    ui = {
        action_bar = {
            placement = "bottom",
            follow_side = true,
        },
        intro = {
            font_size = 22,
            vertical_margin = 16,
            horizontal_margin = 16,
        },
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
    if version >= PluginSettings.defaults.schema_version then
        return false
    end

    settings.cache = settings.cache or {}
    if version < 2 then
        settings.cache.chapter_content_enabled = settings.cache.chapter_content_enabled ~= false
        settings.cleanup = nil
    end
    if version < 3 then
        settings.cache.search_ttl_days = settings.cache.search_ttl_days == 0
            and PluginSettings.defaults.cache.search_ttl_days
            or (settings.cache.search_ttl_days
                or PluginSettings.defaults.cache.search_ttl_days)
        settings.cache.detail_ttl_days = settings.cache.detail_ttl_days == 0
            and PluginSettings.defaults.cache.detail_ttl_days
            or (settings.cache.detail_ttl_days
                or PluginSettings.defaults.cache.detail_ttl_days)
        settings.cache.toc_ttl_days = settings.cache.toc_ttl_days == 0
            and PluginSettings.defaults.cache.toc_ttl_days
            or (settings.cache.toc_ttl_days
                or PluginSettings.defaults.cache.toc_ttl_days)
        settings.cache.content_ttl_days = settings.cache.content_ttl_days == 0
            and PluginSettings.defaults.cache.content_ttl_days
            or (settings.cache.content_ttl_days
                or PluginSettings.defaults.cache.content_ttl_days)
        settings.cache.max_metadata_records = settings.cache.max_metadata_records
            or PluginSettings.defaults.cache.max_metadata_records
        settings.cache.max_metadata_bytes = settings.cache.max_metadata_bytes
            or PluginSettings.defaults.cache.max_metadata_bytes
    end
    if version < 4 then
        settings.cleanup = nil
        settings.storage = nil
        if type(settings.debug) == "table" then
            settings.debug.max_entries = nil
        end
    end
    if version < 5 then
        settings.prefetch = nil
    end
    if version > 0 and version < 6 then
        settings.download = settings.download or {}
        settings.download.background_mode = settings.download.background_mode
            or "always"
        settings.download.workers = tonumber(settings.download.workers) or 1
    end
    settings.schema_version = PluginSettings.defaults.schema_version
    return true
end

function PluginSettings.load()
    local settings = G_reader_settings:readSetting(PluginSettings.key)
    local changed = false

    if type(settings) ~= "table" then
        settings = {}
        changed = true
    end

    if migrate(settings) then
        changed = true
    end
    if mergeDefaults(settings, PluginSettings.defaults) then
        changed = true
    end

    if changed then
        PluginSettings.save(settings)
    end

    return settings
end

function PluginSettings.save(settings)
    G_reader_settings:saveSetting(PluginSettings.key, settings)
end

function PluginSettings.reset()
    local settings = clone(PluginSettings.defaults)
    PluginSettings.save(settings)
    return settings
end

function PluginSettings.delete()
    G_reader_settings:delSetting(PluginSettings.key)
end

return PluginSettings
