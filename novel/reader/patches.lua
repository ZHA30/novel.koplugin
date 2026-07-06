local _ = require("novel.i18n")
local ChapterDoc = require("novel.reader.chapterdoc")
local lfs = require("libs/libkoreader-lfs")

local Patches = {}
local patches = {}

local function firstNonNovelHistoryFile(ReadHistory)
    if type(ReadHistory.hist) ~= "table" then
        return nil
    end
    for index = 1, #ReadHistory.hist do
        local item = ReadHistory.hist[index]
        if item and item.file and not ChapterDoc.chapterByFile(item.file) then
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
    if ChapterDoc.chapterByFile(lastfile) then
        local fallback = firstNonNovelHistoryFile(ReadHistory)
        if fallback then
            G_reader_settings:saveSetting("lastfile", fallback)
            G_reader_settings:saveSetting("lastdir", fallback:match("^(.*)/"))
        else
            G_reader_settings:delSetting("lastfile")
            G_reader_settings:delSetting("lastdir")
        end
        changed = true
    elseif ChapterDoc.isNovelPath(G_reader_settings:readSetting("lastdir")) then
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
        if item and ChapterDoc.chapterByFile(item.file) then
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

local function readerTocNovelPlugin(reader_toc)
    local reader_ui = reader_toc and reader_toc.ui
    if not reader_ui or not reader_ui.document then
        return nil
    end
    if not ChapterDoc.isNovelPath(reader_ui.document.file) then
        return nil
    end
    return reader_ui.novel
end

local function showNovelChapters(reader_toc)
    local plugin = readerTocNovelPlugin(reader_toc)
    if not plugin or not plugin.app then
        return false
    end
    local ChaptersFlow = require("novel.ui.chapters.flow")
    ChaptersFlow.showCurrent(plugin)
    return true
end

local function refreshDocCacheSnapshot(doc_cache)
    if not doc_cache then
        return
    end
    if type(doc_cache.refreshSnapshot) == "function" then
        doc_cache:refreshSnapshot()
    end
    if type(doc_cache.cached) ~= "table" then
        return
    end
    for key, file in pairs(doc_cache.cached) do
        local access = file and lfs.attributes(file, "access")
        local size = file and lfs.attributes(file, "size")
        if not access or not size then
            doc_cache.cached[key] = nil
        end
    end
end

local function installCorePatches(state)
    local ok_history, ReadHistory = pcall(require, "readhistory")
    if ok_history and ReadHistory then
        installPatch("readhistory_add_item", ReadHistory, "addItem", function(original)
            return function(history, file, ...)
                if ChapterDoc.chapterByFile(file) then
                    return
                end
                return original(history, file, ...)
            end
        end)
        installPatch("readhistory_update_last_book_time", ReadHistory,
            "updateLastBookTime", function(original)
            return function(history, ...)
                if ChapterDoc.chapterByFile(ChapterDoc.currentReaderFile()) then
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
                if ChapterDoc.chapterByFile(file) then
                    return
                end
                return original(collection, file, ...)
            end
        end)
    end

    local ok_doccache, DocCache = pcall(require, "document/doccache")
    if ok_doccache and DocCache then
        installPatch("doccache_serialize", DocCache, "serialize", function(original)
            return function(doc_cache, doc_path, ...)
                refreshDocCacheSnapshot(doc_cache)
                if ChapterDoc.chapterByFile(doc_path) then
                    return
                end
                return original(doc_cache, doc_path, ...)
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
                    and ChapterDoc.chapterByFile(reader_ui.document.file) then
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
                if state.pending_return and ChapterDoc.chapterByFile(file) then
                    file = nil
                end
                local results = { pcall(original, reader_ui, file, selected_files) }
                if not results[1] then
                    error(results[2])
                end
                table.remove(results, 1)
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
    return ui and ui.document and ChapterDoc.chapterByFile(ui.document.file) or nil
end

function Patches.patchStatisticsInstance(statistics)
    if not statistics or statistics.novel_patched then
        return
    end
    statistics.novel_patched = true
    statistics.novel_patch_methods = {}

    local function wrap(method, blocked_value)
        local original = statistics[method]
        if type(original) ~= "function" then
            return
        end
        local wrapper
        wrapper = function(statistics_self, ...)
            if isCurrentStatsDocumentNovel(statistics_self) then
                return blocked_value
            end
            return original(statistics_self, ...)
        end
        statistics[method] = wrapper
        statistics.novel_patch_methods[method] = {
            original = original,
            wrapper = wrapper,
        }
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
        local wrapper
        wrapper = function(statistics_self, ...)
            if isCurrentStatsDocumentNovel(statistics_self) then
                statistics_self.is_doc = false
                statistics_self.is_doc_not_frozen = false
                return
            end
            return original_reader_ready(statistics_self, ...)
        end
        statistics.onReaderReady = wrapper
        statistics.novel_patch_methods.onReaderReady = {
            original = original_reader_ready,
            wrapper = wrapper,
        }
    end
end

function Patches.restoreStatisticsInstance(statistics)
    local patched = statistics and statistics.novel_patch_methods
    if type(patched) ~= "table" then
        return
    end
    for method, patch in pairs(patched) do
        if statistics[method] == patch.wrapper then
            statistics[method] = patch.original
        end
    end
    statistics.novel_patch_methods = nil
    statistics.novel_patched = nil
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
