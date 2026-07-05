local Icons = require("novel.icons")
local Size = require("ui/size")

local Grouping = {
    state_w = Icons.size.menu + Size.padding.default,
}

local function persistentGrouping(plugin, create)
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
    if type(settings.ui.grouping) ~= "table" then
        if not create then
            return nil
        end
        settings.ui.grouping = {}
    end

    return settings.ui.grouping
end

function Grouping.state(plugin, field)
    local grouping = persistentGrouping(plugin, true)
    if grouping then
        if type(grouping[field]) ~= "table" then
            grouping[field] = {}
        end
        return grouping[field]
    end

    plugin[field] = plugin[field] or {}
    return plugin[field]
end

function Grouping.collapsed(plugin, field, key)
    return Grouping.state(plugin, field)[key or ""] == true
end

function Grouping.toggle(plugin, field, key)
    local state = Grouping.state(plugin, field)
    key = key or ""
    state[key] = not state[key] or nil

    if persistentGrouping(plugin, false)
        and plugin
        and plugin.app
        and type(plugin.app.saveSettings) == "function" then
        plugin.app:saveSettings()
    end
end

function Grouping.icon(collapsed)
    local name = collapsed and "group-collapsed" or "group-expanded"
    return Icons.menuState(name, Grouping.state_w)
end

return Grouping
