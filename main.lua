local _ = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "i18n/po.lua")
local AppContext = require("novel.appcontext")
local BookshelfFlow = require("novel.ui.bookshelf.flow")
local DiscoverFlow = require("novel.ui.discover.flow")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local ReaderHooks = require("novel.reader.readerhooks")
local SearchFlow = require("novel.ui.search.flow")
local ChaptersFlow = require("novel.ui.chapters.flow")
local Shell = require("novel.ui.shell")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local Novel = WidgetContainer:extend{
    name = "novel",
    settings_key = "novel",
}

function Novel:init()
    self.app = AppContext:new{ plugin = self }
    self.app:init()
    ReaderHooks.init(self)

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function Novel:onCloseDocument()
    ReaderHooks.onCloseDocument(self)
end

function Novel:onSaveSettings()
    ReaderHooks.onSaveSettings(self)
end

function Novel:onCloseWidget()
    ReaderHooks.close(self)
    Loading.closeKeys(self, {
        "bookshelf_refresh_loading",
        "chapters_loading",
        "novel_chapter_cache_loading",
        "detail_loading",
        "discover_loading",
        "search_loading",
    })
    ChaptersFlow.close(self)
    Shell.close(self)
    BookshelfFlow.close(self)
    SearchFlow.close(self)
    DiscoverFlow.close(self)
    if self.app then
        self.app:onClose()
        self.app = nil
    end
end

function Novel:onReaderReady()
    ReaderHooks.setup(self)
end

function Novel.deletePluginSettings()
    AppContext.deleteStoredSettings()
end

function Novel:stopPlugin()
    ReaderHooks.stopPlugin(self)
end

function Novel:addToMainMenu(menu_items)
    ReaderHooks.addToMainMenu(self, menu_items)
    menu_items.novel_search = {
        text = _("Novel"),
        sorting_hint = "search",
        callback = function()
            self:onShowNovelMenu()
        end,
    }
end

function Novel:onShowNovelMenu()
    Shell.show(self)
end

function Novel.showUnderDevelopment(message)
    Dialog.message(message)
end

return Novel
