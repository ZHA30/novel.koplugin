local Context = require("novel.reader.context")

local Patches = {}
local patches = {}

local function firstNonNovelHistoryFile(ReadHistory)
    if type(ReadHistory.hist) ~= "table" then
        return nil
    end
    for index = 1, #ReadHistory.hist do
        local item = ReadHistory.hist[index]
        if item and item.file and not Context.byFile(item.file) then
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
    if Context.byFile(lastfile) then
        local fallback = firstNonNovelHistoryFile(ReadHistory)
        if fallback then
            G_reader_settings:saveSetting("lastfile", fallback)
            G_reader_settings:saveSetting("lastdir", fallback:match("^(.*)/"))
        else
            G_reader_settings:delSetting("lastfile")
            G_reader_settings:delSetting("lastdir")
        end
        changed = true
    elseif Context.isNovelPath(G_reader_settings:readSetting("lastdir")) then
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
        if item and Context.byFile(item.file) then
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

local function installCorePatches(state)
    local ok_history, ReadHistory = pcall(require, "readhistory")
    if ok_history and ReadHistory then
        installPatch("readhistory_add_item", ReadHistory, "addItem", function(original)
            return function(history, file, ...)
                if Context.byFile(file) then
                    return
                end
                return original(history, file, ...)
            end
        end)
        installPatch("readhistory_update_last_book_time", ReadHistory,
            "updateLastBookTime", function(original)
            return function(history, ...)
                if Context.byFile(Context.currentReaderFile()) then
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
                if Context.byFile(file) then
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
                    and Context.byFile(reader_ui.document.file) then
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
                if state.pending_return and Context.byFile(file) then
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
end

local function isCurrentStatsDocumentNovel(statistics)
    local ui = statistics and statistics.ui
    return ui and ui.document and Context.byFile(ui.document.file) or nil
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
