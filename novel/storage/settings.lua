-- luacheck: globals G_reader_settings

local Settings = {
    key = "novel",
}

Settings.defaults = {
    schema_version = 1,
    debug = {
        enabled = false,
        max_entries = 200,
    },
    storage = {
        backend = "prototype",
        target_backend = "sqlite",
        schema_version = 0,
    },
    chapter_list = {
        books = {},
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

function Settings.load()
    local settings = G_reader_settings:readSetting(Settings.key)
    local changed = false

    if type(settings) ~= "table" then
        settings = {}
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
