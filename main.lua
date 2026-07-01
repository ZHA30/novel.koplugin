local _ = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "i18n/po.lua")
local App = require("novel.app")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Novel = WidgetContainer:extend{
    name = "novel",
    settings_key = "novel",
}

function Novel:init()
    self.app = App:new{ plugin = self }
    self.app:init()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Novel:onCloseWidget()
    if self.novel_menu then
        local novel_menu = self.novel_menu
        self.novel_menu = nil
        UIManager:close(novel_menu)
    end
    if self.app then
        self.app:onClose()
        self.app = nil
    end
end

function Novel.deletePluginSettings()
    App.deleteStoredSettings()
end

function Novel:addToMainMenu(menu_items)
    menu_items.novel_search = {
        text = _("Novel"),
        sorting_hint = "search",
        callback = function()
            self:onShowNovelMenu()
        end,
    }
end

function Novel:onShowNovelMenu()
    if self.novel_menu then
        UIManager:close(self.novel_menu)
        self.novel_menu = nil
    end

    local novel_menu
    novel_menu = Menu:new{
        title = _("Novel"),
        item_table = {
            {
                text = _("Bookshelf"),
                callback = function()
                    Novel.showUnderDevelopment(_("Bookshelf is under development."))
                end,
            },
            {
                text = _("Discover"),
                callback = function()
                    Novel.showUnderDevelopment(_("Discover is under development."))
                end,
            },
            {
                text = _("Sources"),
                callback = function()
                    Novel.showUnderDevelopment(_("Sources are under development."))
                end,
            },
        },
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(novel_menu)
            if self.novel_menu == novel_menu then
                self.novel_menu = nil
            end
        end,
    }
    self.novel_menu = novel_menu
    UIManager:show(self.novel_menu)
end

function Novel.showUnderDevelopment(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

return Novel
