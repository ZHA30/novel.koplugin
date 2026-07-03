local _ = require("novel.i18n")
local Context = require("novel.reader.context")
local Navigation = require("novel.reader.navigation")
local Patches = require("novel.reader.patches")
local Store = require("novel.library.store")
local UIManager = require("ui/uimanager")

local Reader = {}

local state = {
    pending_return = nil,
    suppress_return_ui = nil,
}

function Reader.close(plugin)
    Navigation.close(plugin)
end

function Reader.restorePending(plugin)
    if not state.pending_return or not plugin or not plugin.app
        or not plugin.ui or plugin.ui.document then
        return false
    end

    local pending = state.pending_return
    state.pending_return = nil
    UIManager:nextTick(function()
        if not plugin.app then
            return
        end
        local manifest = Store:new():load(pending.book_id)
        if not manifest then
            return
        end
        local Chapters = require("novel.ui.chapters")
        Chapters.showManifest(plugin, manifest, {
            filter = pending.filter,
        })
    end)
    return true
end

function Reader.init(plugin)
    state.restore_pending = Reader.restorePending
    Patches.install(state)

    if not plugin or not plugin.ui then
        return
    end
    if plugin.ui.document then
        if plugin.ui.registerPostInitCallback then
            plugin.ui:registerPostInitCallback(function()
                Patches.patchStatisticsInstance(plugin.ui.statistics)
            end)
        end
    elseif plugin.ui.registerPostInitCallback then
        plugin.ui:registerPostInitCallback(function()
            Reader.restorePending(plugin)
        end)
    end
end

function Reader.stopPlugin()
    Patches.restore()
    state.pending_return = nil
    state.suppress_return_ui = nil
end

function Reader.onCloseDocument(plugin)
    local context = Context.current(plugin)
    if not context or plugin.novel_switching_chapter
        or plugin.ui == state.suppress_return_ui then
        return false
    end

    state.pending_return = {
        book_id = context.book_id,
        filter = plugin.novel_toc_filter
            and plugin.novel_toc_filter[context.book_id] or nil,
    }
    return true
end

function Reader.setup(plugin)
    return Navigation.setup(plugin)
end

function Reader.addToMainMenu(plugin, menu_items)
    if not Context.current(plugin) then
        return false
    end

    menu_items.table_of_contents = {
        text = _("Chapters"),
        callback = function()
            local Chapters = require("novel.ui.chapters")
            Chapters.showCurrent(plugin)
        end,
    }
    return true
end

return Reader
