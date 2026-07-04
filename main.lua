local _ = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "i18n/po.lua")
local App = require("novel.app")
local Bookshelf = require("novel.ui.bookshelf")
local Discover = require("novel.ui.discover")
local Dialog = require("novel.widget.dialog")
local Icons = require("novel.icons")
local Loading = require("novel.widget.loading")
local Menu = require("novel.widget.menu")
local ReaderLifecycle = require("novel.reader.lifecycle")
local Search = require("novel.ui.search")
local Size = require("ui/size")
local Sources = require("novel.ui.sources")
local Chapters = require("novel.ui.chapters")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local MENU_ICON_WIDTH = Icons.size.menu + Size.padding.default

local Novel = WidgetContainer:extend{
    name = "novel",
    settings_key = "novel",
}

function Novel:init()
    self.app = App:new{ plugin = self }
    self.app:init()
    ReaderLifecycle.init(self)

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Novel:onCloseDocument()
    ReaderLifecycle.onCloseDocument(self)
end

function Novel:onCloseWidget()
    ReaderLifecycle.close(self)
    Loading.closeKeys(self, {
        "bookshelf_refresh_loading",
        "bookshelf_switch_loading",
        "chapters_loading",
        "detail_loading",
        "discover_loading",
        "search_loading",
    })
    Chapters.close(self)
    if self.novel_menu then
        local novel_menu = self.novel_menu
        self.novel_menu = nil
        if UIManager:isWidgetShown(novel_menu) then
            UIManager:close(novel_menu)
        end
    end
    Sources.close(self)
    Bookshelf.close(self)
    Search.close(self)
    Discover.close(self)
    if self.app then
        self.app:onClose()
        self.app = nil
    end
end

function Novel:onReaderReady()
    ReaderLifecycle.setup(self)
end

function Novel.deletePluginSettings()
    App.deleteStoredSettings()
end

function Novel:stopPlugin()
    ReaderLifecycle.stopPlugin(self)
end

function Novel:addToMainMenu(menu_items)
    ReaderLifecycle.addToMainMenu(self, menu_items)
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
        if UIManager:isWidgetShown(self.novel_menu) then
            UIManager:close(self.novel_menu)
        end
        self.novel_menu = nil
    end

    local novel_menu
    novel_menu = Menu:new{
        title = _("Novel"),
        item_table = {
            {
                text = _("Bookshelf"),
                state = Icons.menuState("bookshelf", MENU_ICON_WIDTH),
                callback = function()
                    Bookshelf.show(self)
                end,
            },
            {
                text = _("Discover"),
                state = Icons.menuState("discover", MENU_ICON_WIDTH),
                callback = function()
                    Discover.show(self)
                end,
            },
            {
                text = _("Sources"),
                state = Icons.menuState("sources", MENU_ICON_WIDTH),
                callback = function()
                    Sources.show(self)
                end,
            },
        },
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        state_w = MENU_ICON_WIDTH,
        close_callback = function()
            if self.novel_menu == novel_menu then
                self.novel_menu = nil
            end
        end,
    }
    self.novel_menu = novel_menu
    UIManager:show(self.novel_menu)
end

function Novel.showUnderDevelopment(message)
    Dialog.message(message)
end

return Novel
