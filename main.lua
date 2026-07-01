local _ = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "i18n/po.lua")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Novel = WidgetContainer:extend{
    name = "novel",
}

function Novel:init()
    self.ui.menu:registerToMainMenu(self)
end

function Novel:addToMainMenu(menu_items)
    menu_items.novel_search = {
        text = _("Novel"),
        sorting_hint = "search",
        callback = function()
            self.onShowNovelSearch()
        end,
    }
end

function Novel.onShowNovelSearch()
    UIManager:show(InfoMessage:new{
        text = _("Novel online search is under development."),
    })
end

return Novel
