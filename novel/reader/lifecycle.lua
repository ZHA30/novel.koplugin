local _ = require("novel.i18n")
local ReaderChapter = require("novel.reader.chapter")
local ReaderDocument = require("novel.reader.document")
local Navigation = require("novel.reader.navigation")
local Patches = require("novel.reader.patches")
local Prefetch = require("novel.reader.prefetch")
local ReaderSettings = require("novel.reader.settings")
local Manifest = require("novel.books.manifest")
local UIManager = require("ui/uimanager")

local ReaderLifecycle = {}

local state = {
    pending_return = nil,
    suppress_return_ui = nil,
}

local RETURN_TO_NOVEL_MENU = "novel_menu"

function ReaderLifecycle.close(plugin)
    ReaderChapter.close(plugin)
    Prefetch.close(plugin)
    Navigation.close(plugin)
end

function ReaderLifecycle.restorePending(plugin)
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
        local manifest = Manifest:new():load(pending.book_id)
        if not manifest then
            return
        end
        local Chapters = require("novel.ui.chapters")
        Chapters.showManifest(plugin, manifest, {
            filter = pending.filter,
            sort = pending.sort,
            return_to = pending.return_to or RETURN_TO_NOVEL_MENU,
        })
    end)
    return true
end

function ReaderLifecycle.init(plugin)
    state.restore_pending = ReaderLifecycle.restorePending
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
            ReaderLifecycle.restorePending(plugin)
        end)
    end
end

function ReaderLifecycle.stopPlugin(plugin)
    ReaderChapter.close(plugin, true)
    ReaderChapter.clearReturnTarget()
    Prefetch.close(plugin)
    Navigation.close(plugin)
    Patches.restoreStatisticsInstance(plugin and plugin.ui and plugin.ui.statistics)
    Patches.restore()
    state.pending_return = nil
    state.suppress_return_ui = nil
end

function ReaderLifecycle.onCloseDocument(plugin)
    ReaderSettings.capture(plugin)

    local current_chapter = ReaderDocument.currentChapter(plugin)
    if not current_chapter or plugin.novel_switching_chapter
        or plugin.ui == state.suppress_return_ui then
        return false
    end

    state.pending_return = {
        book_id = current_chapter.book_id,
        filter = plugin.novel_chapters_filter
            and plugin.novel_chapters_filter[current_chapter.book_id] or nil,
        sort = plugin.novel_chapters_sort
            and plugin.novel_chapters_sort[current_chapter.book_id] or nil,
        return_to = ReaderChapter.returnTarget(),
    }
    return true
end

function ReaderLifecycle.onSaveSettings(plugin)
    if plugin and plugin.novel_skip_reader_settings_capture then
        return
    end
    ReaderSettings.capture(plugin)
end

function ReaderLifecycle.setup(plugin)
    local is_novel = Navigation.setup(plugin)
    if is_novel then
        Prefetch.setup(plugin)
    else
        Prefetch.close(plugin)
    end
    return is_novel
end

function ReaderLifecycle.addToMainMenu(plugin, menu_items)
    if not ReaderDocument.currentChapter(plugin) then
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

return ReaderLifecycle
