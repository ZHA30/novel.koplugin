local _ = require("novel.i18n")
local ActionBarPlacement = require("novel.ui.actionbarplacement")
local ContentBuilder = require("novel.ui.contentbuilder")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local UIManager = require("ui/uimanager")

local InterfacePage = {}

local OPTIONS = {
    {
        value = ActionBarPlacement.BOTTOM,
        label = _("Bottom"),
    },
    {
        value = ActionBarPlacement.LEFT,
        label = _("Left"),
    },
    {
        value = ActionBarPlacement.RIGHT,
        label = _("Right"),
    },
}

local function placementLabel(placement)
    for option_index = 1, #OPTIONS do
        local option = OPTIONS[option_index]
        if option.value == placement then
            return option.label
        end
    end
    return OPTIONS[1].label
end

local function showPlacementDialog(plugin, route, runtime)
    local placement = ActionBarPlacement.get(plugin)
    local radio_buttons = {}
    for option_index = 1, #OPTIONS do
        local option = OPTIONS[option_index]
        table.insert(radio_buttons, {{
            text = option.label,
            provider = option.value,
            checked = option.value == placement,
        }})
    end
    UIManager:show(RadioButtonWidget:new{
        title_text = _("Action bar position"),
        info_text = _("Place the action bar near the hand holding the device."),
        radio_buttons = radio_buttons,
        callback = function(radio)
            if ActionBarPlacement.set(plugin, radio.provider) then
                runtime.replace(plugin, route)
            end
        end,
    })
end

function InterfacePage.build(shell, plugin, route, runtime)
    local placement = ActionBarPlacement.get(plugin)
    local follows_side = ActionBarPlacement.followsSide(plugin)
    return ContentBuilder.buildList(shell, {
        {
            title = _("Action bar position"),
            subtitle = _("Move the main controls for easier one-handed use."),
            mandatory = placementLabel(placement),
            callback = function()
                showPlacementDialog(plugin, route, runtime)
            end,
        },
        {
            title = _("Follow action bar side"),
            subtitle = _("When the action bar is on the left, move other controls to the left."),
            mandatory = follows_side and _("Enabled") or _("Disabled"),
            callback = function()
                if ActionBarPlacement.setFollowsSide(plugin,
                        not follows_side) then
                    runtime.replace(plugin, route)
                end
            end,
        },
    })
end

return InterfacePage
