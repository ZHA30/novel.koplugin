local _ = require("novel.i18n")
local ChapterOpen = require("novel.reader.chapteropen")
local ChapterDoc = require("novel.reader.chapterdoc")
local ChapterTurn = require("novel.reader.chapterturn")
local Patches = require("novel.reader.patches")
local Prefetch = require("novel.reader.prefetch")
local ReturnController = require("novel.reader.returncontroller")
local ReaderSettings = require("novel.reader.settings")

local ReaderHooks = {}

function ReaderHooks.close(plugin)
    ChapterOpen.close(plugin)
    Prefetch.close(plugin)
    ChapterTurn.close(plugin)
end

function ReaderHooks.restorePending(plugin)
    return ReturnController.scheduleRestore(plugin)
end

function ReaderHooks.init(plugin)
    Patches.install(ReturnController.state)

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
    ReturnController.clear()
end

function ReaderHooks.onCloseDocument(plugin)
    ReaderSettings.capture(plugin)
    return ReturnController.capture(plugin)
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
