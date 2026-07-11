local ChapterDoc = require("novel.reader.chapterdoc")
local Manifest = require("novel.storage.manifest")
local Shell = require("novel.ui.shell")
local ShellRoutes = require("novel.ui.shellroutes")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local ReturnController = {}

local state = {
    entry_context = nil,
    exit_request = nil,
    restore_action = nil,
    plugin_name = nil,
    restore_retry_count = 0,
}

local function isFileManagerPlugin(plugin)
    return plugin and plugin.app and plugin.ui and not plugin.ui.document
end

local function pluginKey(plugin)
    local path = plugin and plugin.path
    if type(path) == "string" then
        local key = path:match("([^/]+)%.koplugin/?$")
        if key and key ~= "" then
            return key
        end
    end
    return "novel"
end

local function clearRestoreAction(action)
    if state.restore_action == action then
        state.restore_action = nil
    end
end

local function unscheduleRestoreAction()
    if state.restore_action then
        UIManager:unschedule(state.restore_action)
        state.restore_action = nil
    end
end

local function clearRestoreState()
    unscheduleRestoreAction()
    state.entry_context = nil
    state.exit_request = nil
    state.plugin_name = nil
    state.restore_retry_count = 0
end

local function cloneState(snapshot)
    return ShellSession.clone(snapshot)
end

function ReturnController.captureEntry(plugin)
    if not isFileManagerPlugin(plugin) then
        return false
    end

    clearRestoreState()
    state.plugin_name = pluginKey(plugin)
    state.entry_context = {
        shell_state = ShellSession.snapshot(plugin),
    }
    return true
end

function ReturnController.canReturnFromReader(reader_ui, file)
    local reader_file = file
        or (reader_ui and reader_ui.document and reader_ui.document.file)
    return state.entry_context ~= nil
        and ChapterDoc.chapterByFile(reader_file) ~= nil
end

function ReturnController.prepareReturnFromReader(reader_ui, file)
    if state.exit_request then
        return true
    end
    if not ReturnController.canReturnFromReader(reader_ui, file) then
        return false
    end

    state.exit_request = {
        kind = "restore_entry",
        shell_state = cloneState(state.entry_context.shell_state),
    }
    return true
end

function ReturnController.requestFinishExit(reader_ui, current_chapter)
    local file = reader_ui and reader_ui.document and reader_ui.document.file
    current_chapter = current_chapter or ChapterDoc.chapterByFile(file)
    if not file or not current_chapter or not current_chapter.book_id then
        return false
    end

    unscheduleRestoreAction()
    state.exit_request = {
        kind = "finish",
        file = file,
        shell_state = state.entry_context
            and cloneState(state.entry_context.shell_state) or nil,
        book_id = current_chapter.book_id,
        close_pending = true,
    }
    state.plugin_name = state.plugin_name or "novel"
    state.restore_retry_count = 0
    return true
end

function ReturnController.requestCloseRestore(reader_ui, file)
    file = file or (reader_ui and reader_ui.document and reader_ui.document.file)
    if not ReturnController.prepareReturnFromReader(reader_ui, file) then
        return false
    end
    state.exit_request.file = file
    state.exit_request.close_pending = true
    return true
end

function ReturnController.consumeCloseRestoreRequest()
    local request = state.exit_request
    if not request or not request.close_pending or not request.file then
        return nil
    end
    request.close_pending = nil
    return request.file
end

local function restoreEntry(plugin, shell_state)
    if shell_state then
        ShellSession.restore(plugin, shell_state)
        return
    end
    ShellSession.resetStack(plugin)
    ShellSession.setActiveTab(plugin, "bookshelf")
    ShellSession.push(plugin, ShellRoutes.bookshelf())
end

local function takeExitRequest()
    local request = state.exit_request
    state.exit_request = nil
    state.entry_context = nil
    state.plugin_name = nil
    state.restore_retry_count = 0
    return request
end

function ReturnController.restoreNow(plugin)
    if not state.exit_request or not isFileManagerPlugin(plugin) then
        return false
    end

    local request = takeExitRequest()
    restoreEntry(plugin, request.shell_state)

    if request.kind == "finish" then
        local manifest = Manifest:new():load(request.book_id)
        if manifest then
            local current = ShellSession.currentRoute(plugin)
            local tab = current and current.tab or ShellSession.activeTab(plugin)
            local ChaptersFlow = require("novel.ui.chapters.flow")
            ChaptersFlow.showManifestImmediate(plugin, manifest, {
                tab = tab,
            })
            return true
        end
    end

    Shell.show(plugin, {
        force_repaint = true,
    })
    return true
end

function ReturnController.restoreFromLoadedPlugin()
    if not state.exit_request then
        return false
    end

    local PluginLoader = require("pluginloader")
    local plugin = PluginLoader:getPluginInstance(state.plugin_name or "novel")
    if not plugin or not isFileManagerPlugin(plugin) then
        return false
    end

    unscheduleRestoreAction()
    state.restore_retry_count = 0
    return ReturnController.restoreNow(plugin)
end

function ReturnController.scheduleRestoreFromLoadedPlugin()
    if not state.exit_request or state.restore_action then
        return false
    end

    local action
    action = function()
        clearRestoreAction(action)

        if ReturnController.restoreFromLoadedPlugin() then
            return
        end

        state.restore_retry_count = (state.restore_retry_count or 0) + 1
        if state.restore_retry_count < 6 and state.exit_request then
            state.restore_action = action
            UIManager:nextTick(action)
        else
            clearRestoreState()
        end
    end

    state.restore_action = action
    UIManager:nextTick(action)
    return true
end

function ReturnController.clear()
    clearRestoreState()
end

return ReturnController
