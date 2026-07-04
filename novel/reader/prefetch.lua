local Chapter = require("novel.model.chapter")
local ChapterDocument = require("novel.books.document")
local Manifest = require("novel.books.manifest")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local buffer = require("string.buffer")
local ffiutil = require("ffi/util")
local logger = require("logger")

local Prefetch = {}

local INITIAL_DELAY = 0.8
local POLL_INTERVAL = 0.25
local COLLECT_INTERVAL = 1
local LOOKAHEAD_LIMIT = 2

local function isChapterCurrent(manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    return Manifest.chapterFileExists(manifest, position)
        and ChapterDocument.contentIsCurrent(manifest, chapter)
end

local function networkAvailable()
    if NetworkMgr.getConnectionState then
        return NetworkMgr:getConnectionState()
    end
    return true
end

local function nextContentUrl(manifest, position)
    local next_chapter = Chapter.nextOpenable(manifest.chapters, position, 1)
    return next_chapter and next_chapter.url or nil
end

local function findTarget(manifest, current_position)
    local position = current_position
    local checked = 0
    while checked < LOOKAHEAD_LIMIT do
        checked = checked + 1
        local chapter, target_position = Chapter.nextOpenable(
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
        UIManager:scheduleIn(COLLECT_INTERVAL, collect)
    end
    UIManager:scheduleIn(COLLECT_INTERVAL, collect)
end

local function notify(state, ok, reason)
    local callbacks = state and state.callbacks
    state.callbacks = nil
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
    local ok = false
    if not plugin.app then
        notify(state, ok, "closed")
        return
    end

    local decoded, result = pcall(buffer.decode, encoded or "")
    if not decoded or type(result) ~= "table" then
        logger.warn("novel prefetch: cannot decode result:", result)
        notify(state, ok, "failed")
        return
    end
    if not result.ok then
        logger.dbg("novel prefetch failed:", result.error
            and result.error.message or "unknown")
        notify(state, ok, "failed")
        return
    end

    local manifest_store = Manifest:new()
    local manifest = manifest_store:load(state.book_id)
    local chapter = manifest and manifest.chapters
        and manifest.chapters[state.position]
    if not chapter or isChapterCurrent(manifest, state.position) then
        notify(state, chapter ~= nil, chapter and "done" or "failed")
        return
    end

    local html = ChapterDocument.html(chapter, result.text, result.content_type)
    local file, err = manifest_store:saveChapter(manifest, state.position, html, {
        content_type = result.content_type,
    })
    if file then
        logger.dbg("novel prefetch saved:", file)
        ok = true
    else
        logger.warn("novel prefetch save failed:", err)
    end
    notify(state, ok, ok and "done" or "failed")
end

local function scheduleCheck(plugin, state)
    state.check = function()
        if plugin.novel_prefetch ~= state then
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
            notify(state, false, "failed")
            return
        end

        UIManager:scheduleIn(POLL_INTERVAL, state.check)
    end
    UIManager:scheduleIn(POLL_INTERVAL, state.check)
end

local function start(plugin, manifest, position)
    local chapter = manifest.chapters[position]
    local source = manifest.source
    local book = manifest.book
    local next_chapter_url = nextContentUrl(manifest, position)

    local pid, read_fd = ffiutil.runInSubProcess(function(_pid, write_fd)
        local ContentService = require("novel.catalog.content")
        local result = ContentService.run(source, book, chapter, {
            next_chapter_url = next_chapter_url,
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
        plugin.novel_prefetch = nil
        return false
    end

    local state = {
        pid = pid,
        read_fd = read_fd,
        book_id = manifest.book_id,
        position = position,
    }
    plugin.novel_prefetch = state
    scheduleCheck(plugin, state)
    return true
end

local function run(plugin, current_chapter)
    if not plugin.app or not plugin.ui or not plugin.ui.document then
        plugin.novel_prefetch = nil
        return
    end
    if current_chapter.chapter and current_chapter.chapter.file_path
        and plugin.ui.document.file ~= current_chapter.chapter.file_path then
        plugin.novel_prefetch = nil
        return
    end
    if not networkAvailable() then
        plugin.novel_prefetch = nil
        return
    end

    local manifest = Manifest:new():load(current_chapter.book_id)
        or current_chapter.manifest
    if not manifest then
        plugin.novel_prefetch = nil
        return
    end

    local position = findTarget(manifest, current_chapter.position)
    if not position then
        plugin.novel_prefetch = nil
        return
    end
    start(plugin, manifest, position)
end

function Prefetch.setup(plugin)
    Prefetch.close(plugin)
    local current_chapter = plugin and plugin.novel_reader_chapter
    if not current_chapter then
        return false
    end

    local state = {}
    state.scheduled = function()
        if plugin.novel_prefetch ~= state then
            return
        end
        state.scheduled = nil
        run(plugin, current_chapter)
    end
    plugin.novel_prefetch = state
    UIManager:scheduleIn(INITIAL_DELAY, state.scheduled)
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
    end
    if state.check then
        UIManager:unschedule(state.check)
    end
    if state.pid then
        if ffiutil.isSubProcessDone(state.pid) then
            if state.read_fd then
                ffiutil.readAllFromFD(state.read_fd)
            end
        else
            ffiutil.terminateSubProcess(state.pid)
            collectLater(state.pid, state.read_fd)
        end
    end
    notify(state, false, "closed")
end

function Prefetch.isPending(plugin, manifest, position)
    local state = plugin and plugin.novel_prefetch
    return state and state.pid
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
