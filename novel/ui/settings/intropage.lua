local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailSettings = require("novel.ui.detail.settings")
local DoubleSpinWidget = require("ui/widget/doublespinwidget")
local FontChooser = require("ui/widget/fontchooser")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local IntroPage = {}
local FONT_SIZE_MIN = 8
local FONT_SIZE_MAX = 72
local MARGIN_MIN = 0
local MARGIN_MAX = 64

local function save(plugin, route, runtime, values)
    DetailSettings.save(plugin, values)
    runtime.replace(plugin, route)
end

local function fontLabel(settings)
    if not settings.font_face then
        return _("default")
    end
    return FontChooser.getFontNameText(settings.font_face) or settings.font_face
end

local function showFont(plugin, route, runtime, settings)
    local default_font_face = DetailSettings.defaultFontFace()
    UIManager:show(FontChooser:new{
        title = _("Font"),
        font_file = settings.font_face or default_font_face,
        default_font_file = default_font_face,
        callback = function(font_face)
            save(plugin, route, runtime, {
                font_face = font_face == default_font_face and false or font_face,
            })
        end,
    })
end

local function showFontSize(plugin, route, runtime, settings)
    UIManager:show(SpinWidget:new{
        title_text = _("Font size"),
        value = settings.font_size,
        value_min = FONT_SIZE_MIN,
        value_max = FONT_SIZE_MAX,
        value_step = 1,
        value_hold_step = 4,
        default_value = DetailSettings.DEFAULTS.font_size,
        callback = function(spin)
            save(plugin, route, runtime, { font_size = spin.value })
        end,
    })
end

local function showMargins(plugin, route, runtime, settings)
    UIManager:show(DoubleSpinWidget:new{
        title_text = _("Margins"),
        left_text = _("Vertical"),
        left_value = settings.vertical_margin,
        left_min = MARGIN_MIN,
        left_max = MARGIN_MAX,
        left_default = DetailSettings.DEFAULTS.vertical_margin,
        right_text = _("Horizontal"),
        right_value = settings.horizontal_margin,
        right_min = MARGIN_MIN,
        right_max = MARGIN_MAX,
        right_default = DetailSettings.DEFAULTS.horizontal_margin,
        callback = function(vertical_margin, horizontal_margin)
            save(plugin, route, runtime, {
                vertical_margin = vertical_margin,
                horizontal_margin = horizontal_margin,
            })
        end,
    })
end

function IntroPage.build(shell, plugin, route, runtime)
    local settings = DetailSettings.get(plugin)
    return ContentBuilder.buildList(shell, {
        {
            title = _("Font"),
            mandatory = fontLabel(settings),
            callback = function()
                showFont(plugin, route, runtime, settings)
            end,
        },
        {
            title = _("Font size"),
            mandatory = tostring(settings.font_size),
            callback = function()
                showFontSize(plugin, route, runtime, settings)
            end,
        },
        {
            title = _("Margins"),
            mandatory = string.format("%d / %d",
                settings.vertical_margin, settings.horizontal_margin),
            callback = function()
                showMargins(plugin, route, runtime, settings)
            end,
        },
    })
end

return IntroPage
