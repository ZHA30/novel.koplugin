local ChapterRecord = require("novel.reader.chapterrecord")
local ChapterDoc = require("novel.reader.chapterdoc")
local Manifest = require("novel.storage.manifest")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local buffer = require("string.buffer")
local ffiutil = require("ffi/util")
local logger = require("logger")

local Prefetch = {}

local DEFAULT_INITIAL_DELAY = 0.8
local DEFAULT_POLL_INTERVAL = 0.25
local DEFAULT_COLLECT_INTERVAL = 1
local DEFAULT_LOOKAHEAD = 1
local DEFAULT_TIMEOUT = 45

local STATUS_SCHEDULED = "scheduled"
local STATUS_RUNNING = "running"
local STATUS_DONE = "done"
local STATUS_FAILED = "failed"
local STATUS_CANCELED = "canceled"

local function now()
    return os.time()
end

local function prefetchSettings(plugin)
    local settings = plugin and plugin.app and plugin.app.settings
    return settings and settings.prefetch or {}
end

local function isChapterCurrent(manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    return Manifest.chapterFileExists(manifest, position)
        and ChapterDoc.contentIsCurrent(manifest, chapter)
end

local function networkAvailable()
    if NetworkMgr.getConnectionState then
        return NetworkMgr:getConnectionState()
    end
    return true
end

local function nextContentUrl(manifest, position)
    local next_chapter = ChapterRecord.nextOpenable(manifest.chapters, position, 1)
    return next_chapter and next_chapter.url or nil
end

local function findTarget(manifest, current_position, lookahead)
    local position = current_position
    local checked = 0
    lookahead = tonumber(lookahead) or DEFAULT_LOOKAHEAD
    while checked < math.max(lookahead, 1) do
        checked = checked + 1
        local chapter, target_position = ChapterRecord.nextOpenable(
            manifest.chapters, position, 1)
        if not chapter then
            return nil
        end
        if not isChapterCurrent(manifest, target_position) then
            return target_position, chapter
        end
        position = target_position
    end
    return nil
end

local function collectLater(pid, read_fd)
    local collect
    collect = function()
        if ffiutil.isSubProcessDone(pid) then
            if read_fd then
                ffiutil.readAllFromFD(read_fd)
            end
            return
        end
        UIManager:scheduleIn(DEFAULT_COLLECT_INTERVAL, collect)
    end
    UIManager:scheduleIn(DEFAULT_COLLECT_INTERVAL, collect)
end

local function notify(state, ok, reason)
    local callbacks = state and state.callbacks
    if state then
        state.callbacks = nil
    end
    if not callbacks then
        return
    end
    for callback_index = 1, #callbacks do
        callbacks[callback_index](ok, reason)
    end
end

local function finish(plugin, state, encoded)
    if plugin.novel_prefetch == state then
        plugin.novel_prefetch = nil
    end
    if not plugin.app then
        state.status = STATUS_CANCELED
        notify(state, false, "closed")
        return
    end

    local decoded, result = pcall(buffer.decode, encoded or "")
    if not decoded or type(result) ~= "table" then
        state.status = STATUS_FAILED
        logger.warn("novel prefetch: cannot decode result:", result)
        notify(state, false, "failed")
        return
    end
    if not result.ok then
        state.status = STATUS_FAILED
        logger.dbg("novel prefetch failed:", result.error
            and result.error.message or "unknown")
        notify(state, false, "failed")
        return
    end

    local manifest_store = Manifest:new()
    local manifest = manifest_store:load(state.book_id)
    local chapter = manifest and manifest.chapters
        and manifest.chapters[state.position]
    if not chapter then
        state.status = STATUS_FAILED
        notify(state, false, "failed")
        return
    end
    if isChapterCurrent(manifest, state.position) then
        state.status = STATUS_DONE
        notify(state, true, "done")
        return
    end

    local html = ChapterDoc.html(chapter, result.text, result.content_type)
    local file, err = manifest_store:saveChapter(manifest, state.position, html, {
        content_type = result.content_type,
    })
    if file then
        state.status = STATUS_DONE
        logger.dbg("novel prefetch saved:", file)
        notify(state, true, "done")
    else
        state.status = STATUS_FAILED
        logger.warn("novel prefetch save failed:", err)
        notify(state, false, "failed")
    end
end

local function cancelRunning(plugin, state, reason)
    if plugin and plugin.novel_prefetch == state then
        plugin.novel_prefetch = nil
    end
    state.status = STATUS_CANCELED
    if state.check then
        UIManager:unschedule(state.check)
    end
    if state.pid then
        if ffiutil.isSubProcessDone(state.pid) then
            if state.read_fd then
                ffiutil.readAllFromFD(state.read_fd)
                state.read_fd = nil
            end
        else
            ffiutil.terminateSubProcess(state.pid)
            collectLater(state.pid, state.read_fd)
            state.read_fd = nil
        end
    end
    notify(state, false, reason or "closed")
end

local function checkTimedOut(state)
    local timeout = tonumber(state.timeout_seconds) or DEFAULT_TIMEOUT
    return timeout > 0 and state.started_at
        and now() - state.started_at >= timeout
end

local function scheduleCheck(plugin, state)
    state.check = function()
        if plugin.novel_prefetch ~= state then
            return
        end
        if checkTimedOut(state) then
            logger.warn("novel prefetch timed out:", state.book_id, state.position)
            cancelRunning(plugin, state, "timeout")
            return
        end

        local has_data = state.read_fd
            and ffiutil.getNonBlockingReadSize(state.read_fd) ~= 0
        local done = ffiutil.isSubProcessDone(state.pid)
        if has_data then
            local encoded = ffiutil.readAllFromFD(state.read_fd)
            state.read_fd = nil
            if not done then
                collectLater(state.pid)
            end
            finish(plugin, state, encoded)
            return
        end
        if done then
            if state.read_fd then
                ffiutil.readAllFromFD(state.read_fd)
                state.read_fd = nil
            end
            if plugin.novel_prefetch == state then
                plugin.novel_prefetch = nil
            end
            state.status = STATUS_FAILED
            notify(state, false, "failed")
            return
        end

        UIManager:scheduleIn(DEFAULT_POLL_INTERVAL, state.check)
    end
    UIManager:scheduleIn(DEFAULT_POLL_INTERVAL, state.check)
end

local function start(plugin, state, manifest, position)
    local chapter = manifest.chapters[position]
    local source = manifest.source
    local book = manifest.book
    local next_chapter_url = nextContentUrl(manifest, position)
    local plugin_settings = plugin.app and plugin.app.settings

    local pid, read_fd = ffiutil.runInSubProcess(function(_pid, write_fd)
        local ChapterContent = require("novel.catalog.reading.chaptercontent")
        local result = ChapterContent.run(source, book, chapter, {
            next_chapter_url = next_chapter_url,
            settings = plugin_settings,
        })
        local ok, encoded = pcall(buffer.encode, result or {})
        if not ok then
            encoded = buffer.encode({
                ok = false,
                error = {
                    message = tostring(encoded),
                },
            })
        end
        ffiutil.writeToFD(write_fd, encoded, true)
    end, true)
    if not pid then
        logger.warn("novel prefetch start failed:", read_fd)
        if plugin.novel_prefetch == state then
            plugin.novel_prefetch = nil
        end
        state.status = STATUS_FAILED
        notify(state, false, "failed")
        return false
    end

    state.status = STATUS_RUNNING
    state.pid = pid
    state.read_fd = read_fd
    state.book_id = manifest.book_id
    state.position = position
    state.started_at = now()
    scheduleCheck(plugin, state)
    return true
end

local function run(plugin, current_chapter, state)
    if plugin.novel_prefetch ~= state then
        return
    end
    if not plugin.app or not plugin.ui or not plugin.ui.document then
        plugin.novel_prefetch = nil
        state.status = STATUS_CANCELED
        notify(state, false, "closed")
        return
    end
    if current_chapter.chapter and current_chapter.chapter.file_path
        and plugin.ui.document.file ~= current_chapter.chapter.file_path then
        plugin.novel_prefetch = nil
        state.status = STATUS_CANCELED
        notify(state, false, "closed")
        return
    end
    if not networkAvailable() then
        plugin.novel_prefetch = nil
        state.status = STATUS_FAILED
        notify(state, false, "offline")
        return
    end

    local manifest = Manifest:new():load(current_chapter.book_id)
        or current_chapter.manifest
    if not manifest then
        plugin.novel_prefetch = nil
        state.status = STATUS_FAILED
        notify(state, false, "failed")
        return
    end

    local position = findTarget(manifest, current_chapter.position,
        state.lookahead)
    if not position then
        plugin.novel_prefetch = nil
        state.status = STATUS_DONE
        notify(state, true, "done")
        return
    end
    start(plugin, state, manifest, position)
end

function Prefetch.setup(plugin)
    Prefetch.close(plugin)
    local current_chapter = plugin and plugin.novel_reader_chapter
    if not current_chapter then
        return false
    end

    local settings = prefetchSettings(plugin)
    if settings.enabled == false then
        return false
    end

    local state = {
        status = STATUS_SCHEDULED,
        lookahead = settings.lookahead or DEFAULT_LOOKAHEAD,
        timeout_seconds = settings.timeout_seconds or DEFAULT_TIMEOUT,
    }
    state.scheduled = function()
        if plugin.novel_prefetch ~= state then
            return
        end
        state.scheduled = nil
        run(plugin, current_chapter, state)
    end
    plugin.novel_prefetch = state
    UIManager:scheduleIn(settings.initial_delay or DEFAULT_INITIAL_DELAY,
        state.scheduled)
    return true
end

function Prefetch.close(plugin)
    local state = plugin and plugin.novel_prefetch
    if not state then
        return
    end
    plugin.novel_prefetch = nil
    if state.scheduled then
        UIManager:unschedule(state.scheduled)
        state.scheduled = nil
    end
    if state.check then
        UIManager:unschedule(state.check)
    end
    if state.pid then
        cancelRunning(plugin, state, "closed")
    else
        state.status = STATUS_CANCELED
        notify(state, false, "closed")
    end
end

function Prefetch.isPending(plugin, manifest, position)
    local state = plugin and plugin.novel_prefetch
    return state and state.status == STATUS_RUNNING and state.pid
        and state.book_id == (manifest and manifest.book_id)
        and state.position == position
        or false
end

function Prefetch.await(plugin, manifest, position, callback)
    local state = plugin and plugin.novel_prefetch
    if not Prefetch.isPending(plugin, manifest, position)
        or type(callback) ~= "function" then
        return false
    end
    state.callbacks = state.callbacks or {}
    table.insert(state.callbacks, callback)
    return true
end

return Prefetch
