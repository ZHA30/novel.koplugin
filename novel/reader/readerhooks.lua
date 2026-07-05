local _ = require("novel.i18n")
local ChapterOpen = require("novel.reader.chapteropen")
local ChapterDoc = require("novel.reader.chapterdoc")
local ChapterTurn = require("novel.reader.chapterturn")
local Patches = require("novel.reader.patches")
local Prefetch = require("novel.reader.prefetch")
local ReaderSettings = require("novel.reader.settings")
local Manifest = require("novel.storage.manifest")
local UIManager = require("ui/uimanager")

local ReaderHooks = {}

local state = {
    pending_return = nil,
    suppress_return_ui = nil,
}

function ReaderHooks.close(plugin)
    ChapterOpen.close(plugin)
    Prefetch.close(plugin)
    ChapterTurn.close(plugin)
end

function ReaderHooks.restorePending(plugin)
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
        local ChaptersFlow = require("novel.ui.chapters.flow")
        ChaptersFlow.showManifest(plugin, manifest, {
            filter = pending.filter,
            sort = pending.sort,
        })
    end)
    return true
end

function ReaderHooks.init(plugin)
    state.restore_pending = ReaderHooks.restorePending
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
            ReaderHooks.restorePending(plugin)
        end)
    end
end

function ReaderHooks.stopPlugin(plugin)
    ChapterOpen.close(plugin, true)
    Prefetch.close(plugin)
    ChapterTurn.close(plugin)
    Patches.restoreStatisticsInstance(plugin and plugin.ui and plugin.ui.statistics)
    Patches.restore()
    state.pending_return = nil
    state.suppress_return_ui = nil
end

function ReaderHooks.onCloseDocument(plugin)
    ReaderSettings.capture(plugin)

    local current_chapter = ChapterDoc.currentChapter(plugin)
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
    }
    return true
end

function ReaderHooks.onSaveSettings(plugin)
    if plugin and plugin.novel_skip_reader_settings_capture then
        return
    end
    ReaderSettings.capture(plugin)
end

function ReaderHooks.setup(plugin)
    local is_novel = ChapterTurn.setup(plugin)
    if is_novel then
        Prefetch.setup(plugin)
    else
        Prefetch.close(plugin)
    end
    return is_novel
end

function ReaderHooks.addToMainMenu(plugin, menu_items)
    if not ChapterDoc.currentChapter(plugin) then
        return false
    end

    menu_items.table_of_contents = {
        text = _("Chapters"),
        callback = function()
            local ChaptersFlow = require("novel.ui.chapters.flow")
            ChaptersFlow.showCurrent(plugin)
        end,
    }
    return true
end

return ReaderHooks
