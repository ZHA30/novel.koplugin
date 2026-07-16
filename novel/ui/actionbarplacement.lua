local ActionBarPlacement = {
    BOTTOM = "bottom",
    LEFT = "left",
    RIGHT = "right",
}

local VALID = {
    bottom = true,
    left = true,
    right = true,
}

function ActionBarPlacement.normalize(value)
    if VALID[value] then
        return value
    end
    return ActionBarPlacement.BOTTOM
end

local function settingsFor(plugin, create)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil
    end
    if type(settings.ui) ~= "table" then
        if not create then
            return nil
        end
        settings.ui = {}
    end
    if type(settings.ui.action_bar) ~= "table" then
        if not create then
            return nil
        end
        settings.ui.action_bar = {}
    end
    return settings.ui.action_bar
end

local function save(plugin)
    if plugin.app and type(plugin.app.saveSettings) == "function" then
        plugin.app:saveSettings()
    end
end

function ActionBarPlacement.get(plugin)
    local settings = settingsFor(plugin, false)
    return ActionBarPlacement.normalize(settings and settings.placement)
end

function ActionBarPlacement.set(plugin, placement)
    local settings = settingsFor(plugin, true)
    if not settings then
        return false
    end
    settings.placement = ActionBarPlacement.normalize(placement)
    save(plugin)
    return true
end

function ActionBarPlacement.followsSide(plugin)
    local settings = settingsFor(plugin, false)
    return not settings or settings.follow_side ~= false
end

function ActionBarPlacement.setFollowsSide(plugin, enabled)
    local settings = settingsFor(plugin, true)
    if not settings then
        return false
    end
    settings.follow_side = enabled ~= false
    save(plugin)
    return true
end

function ActionBarPlacement.actionSide(plugin)
    if ActionBarPlacement.get(plugin) == ActionBarPlacement.LEFT
            and ActionBarPlacement.followsSide(plugin) then
        return ActionBarPlacement.LEFT
    end
    return ActionBarPlacement.RIGHT
end

return ActionBarPlacement
