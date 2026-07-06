local ChapterDoc = require("novel.reader.chapterdoc")
local Shell = require("novel.ui.shell")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local ReturnController = {}

local state = {
    entry_context = nil,
    pending_restore = nil,
    restore_action = nil,
    close_request_file = nil,
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

local function cloneState(snapshot)
    return ShellSession.clone(snapshot)
end

function ReturnController.captureEntry(plugin)
    if not isFileManagerPlugin(plugin) then
        return false
    end

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
    if not ReturnController.canReturnFromReader(reader_ui, file) then
        return false
    end

    state.pending_restore = {
        shell_state = cloneState(state.entry_context.shell_state),
    }
    return true
end

function ReturnController.requestCloseRestore(reader_ui, file)
    file = file or (reader_ui and reader_ui.document and reader_ui.document.file)
    if not ReturnController.prepareReturnFromReader(reader_ui, file) then
        return false
    end
    state.close_request_file = file
    return true
end

function ReturnController.consumeCloseRestoreRequest()
    local file = state.close_request_file
    state.close_request_file = nil
    if not file or not state.pending_restore then
        return nil
    end
    return file
end

function ReturnController.restoreNow(plugin)
    if not state.pending_restore or not isFileManagerPlugin(plugin) then
        return false
    end

    local pending = state.pending_restore
    state.pending_restore = nil
    state.entry_context = nil

    ShellSession.restore(plugin, pending.shell_state)
    Shell.show(plugin)
    return true
end

function ReturnController.scheduleRestoreFromLoadedPlugin()
    if not state.pending_restore or state.restore_action then
        return false
    end

    local action
    action = function()
        clearRestoreAction(action)

        local PluginLoader = require("pluginloader")
        local plugin = PluginLoader:getPluginInstance(state.plugin_name or "novel")
        if plugin and isFileManagerPlugin(plugin) then
            state.restore_retry_count = 0
            ReturnController.restoreNow(plugin)
            return
        end

        state.restore_retry_count = (state.restore_retry_count or 0) + 1
        if state.restore_retry_count < 6 and state.pending_restore then
            state.restore_action = action
            UIManager:nextTick(action)
        else
            state.restore_retry_count = 0
        end
    end

    state.restore_action = action
    UIManager:nextTick(action)
    return true
end

function ReturnController.clear()
    if state.restore_action then
        UIManager:unschedule(state.restore_action)
    end
    state.entry_context = nil
    state.pending_restore = nil
    state.restore_action = nil
    state.close_request_file = nil
    state.plugin_name = nil
    state.restore_retry_count = 0
end

return ReturnController
