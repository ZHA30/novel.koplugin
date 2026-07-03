local _ = require("novel.i18n")
local Library = require("novel.storage.library")
local UIManager = require("ui/uimanager")

local Reader = {}
local pending_return
local patches = {}
local suppress_return_ui

local function isNovelPath(path)
    path = tostring(path or "")
    local root = Library.root_dir
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function contextByFile(file)
    if not isNovelPath(file) then
        return nil
    end
    return Library:new():findContextByFile(file)
end

local function currentReaderFile()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader_ui = ok and ReaderUI.instance
    return reader_ui and reader_ui.document and reader_ui.document.file
end

local function currentContext(plugin)
    if not plugin or not plugin.ui or not plugin.ui.document then
        return nil
    end
    return contextByFile(plugin.ui.document.file)
end

local function restoreWrapper(wrapper)
    if wrapper and wrapper.owner and wrapper.method
        and wrapper.owner[wrapper.method] == wrapper.wrapper then
        wrapper.owner[wrapper.method] = wrapper.original
    end
end

local function firstNonNovelHistoryFile(ReadHistory)
    if type(ReadHistory.hist) ~= "table" then
        return nil
    end
    for index = 1, #ReadHistory.hist do
        local item = ReadHistory.hist[index]
        if item and item.file and not contextByFile(item.file) then
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
    if contextByFile(lastfile) then
        local fallback = firstNonNovelHistoryFile(ReadHistory)
        if fallback then
            G_reader_settings:saveSetting("lastfile", fallback)
            G_reader_settings:saveSetting("lastdir", fallback:match("^(.*)/"))
        else
            G_reader_settings:delSetting("lastfile")
            G_reader_settings:delSetting("lastdir")
        end
        changed = true
    elseif isNovelPath(G_reader_settings:readSetting("lastdir")) then
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
        if item and contextByFile(item.file) then
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

local function restorePatches()
    for key, patch in pairs(patches) do
        if patch.target and patch.method
            and patch.target[patch.method] == patch.wrapper then
            patch.target[patch.method] = patch.original
        end
        patches[key] = nil
    end
end

local function restorePendingFromFileManager()
    if not pending_return then
        return false
    end

    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local plugin = ok and FileManager.instance and FileManager.instance.novel
    if plugin then
        return Reader.restorePending(plugin)
    end
    return false
end

local function installCorePatches()
    local ok_history, ReadHistory = pcall(require, "readhistory")
    if ok_history and ReadHistory then
        installPatch("readhistory_add_item", ReadHistory, "addItem", function(original)
            return function(history, file, ...)
                if contextByFile(file) then
                    return
                end
                return original(history, file, ...)
            end
        end)
        installPatch("readhistory_update_last_book_time", ReadHistory,
            "updateLastBookTime", function(original)
            return function(history, ...)
                if contextByFile(currentReaderFile()) then
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
                if contextByFile(file) then
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
                local previous = suppress_return_ui
                if reader_ui and reader_ui.document
                    and contextByFile(reader_ui.document.file) then
                    suppress_return_ui = reader_ui
                end
                local results = { pcall(original, reader_ui, ...) }
                suppress_return_ui = previous
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
                if pending_return and contextByFile(file) then
                    file = nil
                end
                local results = { pcall(original, reader_ui, file, selected_files) }
                if not results[1] then
                    error(results[2])
                end
                table.remove(results, 1)
                restorePendingFromFileManager()
                return unpack(results)
            end
        end)
    end
end

local function isCurrentStatsDocumentNovel(statistics)
    local ui = statistics and statistics.ui
    return ui and ui.document and contextByFile(ui.document.file) or nil
end

local function patchStatisticsInstance(statistics)
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

function Reader.close(plugin)
    if not plugin then
        return
    end
    restoreWrapper(plugin.novel_paging_wrapper)
    restoreWrapper(plugin.novel_rolling_wrapper)
    plugin.novel_paging_wrapper = nil
    plugin.novel_rolling_wrapper = nil
    plugin.novel_reader_context = nil
    plugin.novel_switching_chapter = nil
end

function Reader.init(plugin)
    installCorePatches()

    if not plugin or not plugin.ui then
        return
    end
    if plugin.ui.document then
        if plugin.ui.registerPostInitCallback then
            plugin.ui:registerPostInitCallback(function()
                patchStatisticsInstance(plugin.ui.statistics)
            end)
        end
    elseif plugin.ui.registerPostInitCallback then
        plugin.ui:registerPostInitCallback(function()
            Reader.restorePending(plugin)
        end)
    end
end

function Reader.stopPlugin()
    restorePatches()
    pending_return = nil
    suppress_return_ui = nil
end

function Reader.onCloseDocument(plugin)
    local context = currentContext(plugin)
    if not context or plugin.novel_switching_chapter
        or plugin.ui == suppress_return_ui then
        return false
    end

    pending_return = {
        book_id = context.book_id,
        filter = plugin.novel_toc_filter
            and plugin.novel_toc_filter[context.book_id] or nil,
    }
    return true
end

function Reader.restorePending(plugin)
    if not pending_return or not plugin or not plugin.app
        or not plugin.ui or plugin.ui.document then
        return false
    end

    local state = pending_return
    pending_return = nil
    UIManager:nextTick(function()
        if not plugin.app then
            return
        end
        local manifest = Library:new():load(state.book_id)
        if not manifest then
            return
        end
        local Toc = require("novel.ui.toc")
        Toc.showManifest(plugin, manifest, {
            filter = state.filter,
        })
    end)
    return true
end

local function pageScrollAtEnd(paging)
    local states = paging.view and paging.view.page_states
    local last_state = states and states[#states]
    if not last_state or not last_state.visible_area or not last_state.page_area then
        return false
    end
    return paging.ui.document:getNextPage(last_state.page) == 0
        and last_state.visible_area.y + last_state.visible_area.h
            >= last_state.page_area.h
end

local function pageScrollAtStart(paging)
    local states = paging.view and paging.view.page_states
    local first_state = states and states[1]
    if not first_state or not first_state.visible_area then
        return false
    end
    return paging.ui.document:getPrevPage(first_state.page) == 0
        and first_state.visible_area.y <= 0
end

local function pagingAtBoundary(paging, diff)
    if not paging or type(diff) ~= "number" or diff == 0 then
        return nil
    end
    if paging.view and paging.view.page_scroll then
        if diff > 0 and pageScrollAtEnd(paging) then
            return 1
        elseif diff < 0 and pageScrollAtStart(paging) then
            return -1
        end
        return nil
    end

    local current_page = paging.current_page
        or (paging.ui and paging.ui.document and paging.ui.document:getCurrentPage())
        or 1
    local page_count = paging.number_of_pages
        or (paging.ui and paging.ui.document and paging.ui.document:getPageCount())
        or 1
    if diff > 0 and current_page >= page_count then
        return 1
    elseif diff < 0 and current_page <= 1 then
        return -1
    end
    return nil
end

local function rollingMaxPos(rolling)
    local document = rolling.ui and rolling.ui.document
    if not document or not document.info then
        return 0
    end
    local footer_height = rolling.view and rolling.view.footer
        and rolling.view.footer.getHeight and rolling.view.footer:getHeight()
        or 0
    local max_pos = (document.info.doc_height or 0)
        - (rolling.ui.dimen and rolling.ui.dimen.h or 0)
        + footer_height
    return math.max(max_pos, 0)
end

local function rollingAtBoundary(rolling, diff)
    if not rolling or type(diff) ~= "number" or diff == 0 then
        return nil
    end
    if rolling.view and rolling.view.view_mode == "scroll" then
        local current_pos = tonumber(rolling.current_pos) or 0
        local max_pos = rollingMaxPos(rolling)
        if diff > 0 and current_pos >= max_pos then
            return 1
        elseif diff < 0 and current_pos <= 0 then
            return -1
        end
        return nil
    end

    local current_page = tonumber(rolling.current_page) or 1
    local page_count = rolling.ui and rolling.ui.document
        and rolling.ui.document:getPageCount() or 1
    if diff > 0 and current_page >= page_count then
        return 1
    elseif diff < 0 and current_page <= 1 then
        return -1
    end
    return nil
end

local function switchChapter(plugin, direction)
    if plugin.novel_switching_chapter then
        return true
    end

    local context = plugin.novel_reader_context or currentContext(plugin)
    local manifest = context and context.manifest
    if not manifest then
        return false
    end
    local target_position = (context.position or 1) + direction
    if target_position < 1 or target_position > #(manifest.chapters or {}) then
        return false
    end

    plugin.novel_switching_chapter = true
    if direction > 0 then
        Library:new():markRead(manifest, context.position)
    end
    UIManager:nextTick(function()
        if not plugin.app then
            return
        end
        local Toc = require("novel.ui.toc")
        Toc.openChapter(plugin, manifest, target_position, {
            from_reader = true,
            jump = direction > 0 and "start" or "end",
        })
    end)
    return true
end

local function installWrapper(plugin, owner, method, boundary_func, key)
    if not owner or type(owner[method]) ~= "function" or plugin[key] then
        return
    end

    local original = owner[method]
    local wrapper
    wrapper = function(owner_self, diff, no_page_turn, ...)
        if no_page_turn == true then
            return original(owner_self, diff, no_page_turn, ...)
        end
        local direction = boundary_func(owner_self, diff)
        if direction and switchChapter(plugin, direction) then
            return true
        end
        return original(owner_self, diff, no_page_turn, ...)
    end

    owner[method] = wrapper
    plugin[key] = {
        owner = owner,
        method = method,
        original = original,
        wrapper = wrapper,
    }
end

function Reader.setup(plugin)
    Reader.close(plugin)
    local context = currentContext(plugin)
    if not context then
        return false
    end

    plugin.novel_reader_context = context
    installWrapper(plugin, plugin.ui.paging, "onGotoViewRel",
        pagingAtBoundary, "novel_paging_wrapper")
    installWrapper(plugin, plugin.ui.rolling, "onGotoViewRel",
        rollingAtBoundary, "novel_rolling_wrapper")
    return true
end

function Reader.addToMainMenu(plugin, menu_items)
    if not currentContext(plugin) then
        return false
    end

    menu_items.table_of_contents = {
        text = _("Chapters"),
        callback = function()
            local Toc = require("novel.ui.toc")
            Toc.showCurrent(plugin)
        end,
    }
    return true
end

return Reader
