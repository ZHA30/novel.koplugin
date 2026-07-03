local _ = require("novel.i18n")
local ReaderDocument = require("novel.reader.document")

local Patches = {}
local patches = {}

local function firstNonNovelHistoryFile(ReadHistory)
    if type(ReadHistory.hist) ~= "table" then
        return nil
    end
    for index = 1, #ReadHistory.hist do
        local item = ReadHistory.hist[index]
        if item and item.file and not ReaderDocument.chapterByFile(item.file) then
            return item.file
        end
    end
    return nil
end

local function cleanLastFileSettings(ReadHistory)
    if not G_reader_settings then
        return
    end

    local changed = false
    local lastfile = G_reader_settings:readSetting("lastfile")
    if ReaderDocument.chapterByFile(lastfile) then
        local fallback = firstNonNovelHistoryFile(ReadHistory)
        if fallback then
            G_reader_settings:saveSetting("lastfile", fallback)
            G_reader_settings:saveSetting("lastdir", fallback:match("^(.*)/"))
        else
            G_reader_settings:delSetting("lastfile")
            G_reader_settings:delSetting("lastdir")
        end
        changed = true
    elseif ReaderDocument.isNovelPath(G_reader_settings:readSetting("lastdir")) then
        G_reader_settings:delSetting("lastdir")
        changed = true
    end

    if changed and type(G_reader_settings.flush) == "function" then
        G_reader_settings:flush()
    end
end

local function cleanReadHistory(ReadHistory)
    if type(ReadHistory.hist) ~= "table" then
        cleanLastFileSettings(ReadHistory)
        return
    end

    local removed = false
    for index = #ReadHistory.hist, 1, -1 do
        local item = ReadHistory.hist[index]
        if item and ReaderDocument.chapterByFile(item.file) then
            ReadHistory:removeItem(item, index, true)
            removed = true
        end
    end
    if removed then
        if type(ReadHistory.ensureLastFile) == "function" then
            ReadHistory:ensureLastFile()
        end
        if type(ReadHistory._flush) == "function" then
            ReadHistory:_flush()
        end
    end
    cleanLastFileSettings(ReadHistory)
end

local function installPatch(key, target, method, wrapper)
    if patches[key] or not target or type(target[method]) ~= "function" then
        return
    end

    local original = target[method]
    target[method] = wrapper(original)
    patches[key] = {
        target = target,
        method = method,
        original = original,
        wrapper = target[method],
    }
end

local function restorePendingFromFileManager(state)
    if not state.pending_return then
        return false
    end

    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local plugin = ok and FileManager.instance and FileManager.instance.novel
    if plugin and state.restore_pending then
        return state.restore_pending(plugin)
    end
    return false
end

local function readerTocNovelPlugin(reader_toc)
    local reader_ui = reader_toc and reader_toc.ui
    if not reader_ui or not reader_ui.document then
        return nil
    end
    if not ReaderDocument.isNovelPath(reader_ui.document.file) then
        return nil
    end
    return reader_ui.novel
end

local function showNovelChapters(reader_toc)
    local plugin = readerTocNovelPlugin(reader_toc)
    if not plugin or not plugin.app then
        return false
    end
    local Chapters = require("novel.ui.chapters")
    Chapters.showCurrent(plugin)
    return true
end

local function installCorePatches(state)
    local ok_history, ReadHistory = pcall(require, "readhistory")
    if ok_history and ReadHistory then
        installPatch("readhistory_add_item", ReadHistory, "addItem", function(original)
            return function(history, file, ...)
                if ReaderDocument.chapterByFile(file) then
                    return
                end
                return original(history, file, ...)
            end
        end)
        installPatch("readhistory_update_last_book_time", ReadHistory,
            "updateLastBookTime", function(original)
            return function(history, ...)
                if ReaderDocument.chapterByFile(ReaderDocument.currentReaderFile()) then
                    return
                end
                return original(history, ...)
            end
        end)
        cleanReadHistory(ReadHistory)
    end

    local ok_collection, ReadCollection = pcall(require, "readcollection")
    if ok_collection and ReadCollection then
        installPatch("readcollection_update_last_book_time", ReadCollection,
            "updateLastBookTime", function(original)
            return function(collection, file, ...)
                if ReaderDocument.chapterByFile(file) then
                    return
                end
                return original(collection, file, ...)
            end
        end)
    end

    local ok_readerui, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_readerui and ReaderUI then
        installPatch("readerui_switch_document", ReaderUI, "switchDocument",
            function(original)
            return function(reader_ui, ...)
                local previous = state.suppress_return_ui
                if reader_ui and reader_ui.document
                    and ReaderDocument.chapterByFile(reader_ui.document.file) then
                    state.suppress_return_ui = reader_ui
                end
                local results = { pcall(original, reader_ui, ...) }
                state.suppress_return_ui = previous
                if not results[1] then
                    error(results[2])
                end
                table.remove(results, 1)
                return unpack(results)
            end
        end)
        installPatch("readerui_show_file_manager", ReaderUI, "showFileManager",
            function(original)
            return function(reader_ui, file, selected_files)
                if state.pending_return and ReaderDocument.chapterByFile(file) then
                    file = nil
                end
                local results = { pcall(original, reader_ui, file, selected_files) }
                if not results[1] then
                    error(results[2])
                end
                table.remove(results, 1)
                restorePendingFromFileManager(state)
                return unpack(results)
            end
        end)
    end

    local ok_readertoc, ReaderToc = pcall(require, "apps/reader/modules/readertoc")
    if ok_readertoc and ReaderToc then
        installPatch("readertoc_get_title", ReaderToc, "getTitle", function(original)
            return function(reader_toc, ...)
                if readerTocNovelPlugin(reader_toc) then
                    return _("Chapters")
                end
                return original(reader_toc, ...)
            end
        end)
        installPatch("readertoc_on_show_toc", ReaderToc, "onShowToc", function(original)
            return function(reader_toc, ...)
                if showNovelChapters(reader_toc) then
                    return true
                end
                return original(reader_toc, ...)
            end
        end)
    end
end

local function isCurrentStatsDocumentNovel(statistics)
    local ui = statistics and statistics.ui
    return ui and ui.document and ReaderDocument.chapterByFile(ui.document.file) or nil
end

function Patches.patchStatisticsInstance(statistics)
    if not statistics or statistics.novel_patched then
        return
    end
    statistics.novel_patched = true

    local function wrap(method, blocked_value)
        local original = statistics[method]
        if type(original) ~= "function" then
            return
        end
        statistics[method] = function(statistics_self, ...)
            if isCurrentStatsDocumentNovel(statistics_self) then
                return blocked_value
            end
            return original(statistics_self, ...)
        end
    end

    wrap("isEnabled", false)
    wrap("isEnabledAndNotFrozen", false)
    wrap("insertDB")
    wrap("onPageUpdate")
    wrap("onCloseDocument")
    wrap("onSaveSettings")
    wrap("onSuspend")
    wrap("onResume")
    wrap("onAnnotationsModified")

    local original_reader_ready = statistics.onReaderReady
    if type(original_reader_ready) == "function" then
        statistics.onReaderReady = function(statistics_self, ...)
            if isCurrentStatsDocumentNovel(statistics_self) then
                statistics_self.is_doc = false
                statistics_self.is_doc_not_frozen = false
                return
            end
            return original_reader_ready(statistics_self, ...)
        end
    end
end

function Patches.install(state)
    installCorePatches(state)
end

function Patches.restore()
    for key, patch in pairs(patches) do
        if patch.target and patch.method
            and patch.target[patch.method] == patch.wrapper then
            patch.target[patch.method] = patch.original
        end
        patches[key] = nil
    end
end

return Patches
