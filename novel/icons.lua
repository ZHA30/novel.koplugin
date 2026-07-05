local CenterContainer = require("ui/widget/container/centercontainer")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local Screen = require("device").screen

local BASE_DIR = (debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "../"

local Icons = {
    size = {
        menu = Screen:scaleBySize(24),
    },
}

function Icons.path(name)
    return BASE_DIR .. "assets/icons/" .. name .. ".svg"
end

function Icons.widget(name, opts)
    opts = opts or {}
    local size = opts.size or Icons.size.menu
    return IconWidget:new{
        file = Icons.path(name),
        width = opts.width or size,
        height = opts.height or size,
        alpha = opts.alpha ~= false,
        dim = opts.dim,
    }
end

function Icons.menuState(name, width)
    width = width or Icons.size.menu
    return CenterContainer:new{
        dimen = Geom:new{
            w = width,
            h = width,
        },
        Icons.widget(name),
    }
end

return Icons
