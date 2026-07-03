local Icons = require("novel.icons")
local Size = require("ui/size")

local Grouping = {
    state_w = Icons.size.menu + Size.padding.default,
}

function Grouping.state(plugin, field)
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
end

function Grouping.icon(collapsed)
    local name = collapsed and "group-collapsed" or "group-expanded"
    return Icons.menuState(name, Grouping.state_w)
end

return Grouping
