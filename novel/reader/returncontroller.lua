local ChapterDoc = require("novel.reader.chapterdoc")
local Manifest = require("novel.storage.manifest")
local UIManager = require("ui/uimanager")

local ReturnController = {}

local state = {
    ensure_filemanager_action = nil,
    pending_return = nil,
    restore_action = nil,
    suppress_return_ui = nil,
}

ReturnController.state = state

local function isFileManagerPlugin(plugin)
    return plugin and plugin.app and plugin.ui and not plugin.ui.document
end

local function clearRestoreAction(action)
    if state.restore_action == action then
        state.restore_action = nil
    end
end

local function clearEnsureFileManagerAction(action)
    if state.ensure_filemanager_action == action then
        state.ensure_filemanager_action = nil
    end
end

local function ensureFileManager()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if ok and FileManager and not FileManager.instance then
        FileManager:showFiles()
    end
end

function ReturnController.scheduleFileManagerFallback()
    if not state.pending_return or state.ensure_filemanager_action then
        return false
    end

    local action
    action = function()
        clearEnsureFileManagerAction(action)
        if state.pending_return then
            ensureFileManager()
        end
    end
    state.ensure_filemanager_action = action
    UIManager:nextTick(action)
    return true
end

function ReturnController.capture(plugin)
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
    ReturnController.scheduleFileManagerFallback()
    return true
end

function ReturnController.restoreNow(plugin)
    if not state.pending_return or not isFileManagerPlugin(plugin) then
        return false
    end

    local pending = state.pending_return
    state.pending_return = nil

    local manifest = Manifest:new():load(pending.book_id)
    if not manifest then
        return false
    end

    local ChaptersFlow = require("novel.ui.chapters.flow")
    return ChaptersFlow.showManifestImmediate(plugin, manifest, {
        filter = pending.filter,
        sort = pending.sort,
    }) ~= false
end

function ReturnController.scheduleRestore(plugin)
    if not state.pending_return or not isFileManagerPlugin(plugin)
        or state.restore_action then
        return false
    end

    local action
    action = function()
        clearRestoreAction(action)
        ReturnController.restoreNow(plugin)
    end
    state.restore_action = action
    UIManager:nextTick(action)
    return true
end

function ReturnController.clear()
    if state.ensure_filemanager_action then
        UIManager:unschedule(state.ensure_filemanager_action)
    end
    if state.restore_action then
        UIManager:unschedule(state.restore_action)
    end
    state.ensure_filemanager_action = nil
    state.pending_return = nil
    state.restore_action = nil
    state.suppress_return_ui = nil
end

return ReturnController
