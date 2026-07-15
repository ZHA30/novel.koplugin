local FontChooser = require("ui/widget/fontchooser")
local Font = require("ui/font")
local FontList = require("fontlist")

local DetailSettings = {}

DetailSettings.DEFAULTS = {
    font_size = 22,
    vertical_margin = 16,
    horizontal_margin = 16,
}

local function settingsFor(plugin)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil
    end
    settings.ui = settings.ui or {}
    settings.ui.intro = settings.ui.intro or {}
    return settings.ui.intro
end

function DetailSettings.get(plugin)
    local settings = settingsFor(plugin) or {}
    local result = {}
    for key, value in pairs(DetailSettings.DEFAULTS) do
        result[key] = settings[key]
        if result[key] == nil then
            result[key] = value
        end
    end
    result.font_face = settings.font_face
    if result.font_face and not FontChooser.isFontRegistered(result.font_face) then
        result.font_face = nil
    end
    return result
end

function DetailSettings.defaultFontFace()
    local filename = Font.fontmap.cfont
    FontList:getFontList()
    for path in pairs(FontList.fontinfo) do
        if path == filename or path:sub(-#filename) == filename then
            return path
        end
    end
end

function DetailSettings.save(plugin, values)
    local settings = settingsFor(plugin)
    if not settings then
        return
    end
    for key, value in pairs(values or {}) do
        settings[key] = value == false and nil or value
    end
    plugin.app:saveSettings()
end

return DetailSettings
