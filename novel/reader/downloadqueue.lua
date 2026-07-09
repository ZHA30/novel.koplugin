local _ = require("novel.i18n")
local ChapterDoc = require("novel.reader.chapterdoc")
local ChapterRecord = require("novel.reader.chapterrecord")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Manifest = require("novel.storage.manifest")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local buffer = require("string.buffer")
local ffiutil = require("ffi/util")
local util = require("util")

local DownloadQueue = {}

DownloadQueue.path = DataStorage:getDataDir() .. "/novel/downloadqueue.lua"
DownloadQueue.max_retries = 3
DownloadQueue.poll_interval = 0.25
DownloadQueue.collect_interval = 1
DownloadQueue.retry_delays = { 2, 5, 15 }

local STATUS_QUEUED = "queued"
local STATUS_RUNNING = "running"
local STATUS_PAUSED = "paused"
local STATUS_DONE = "done"
local STATUS_ERROR = "error"

local function now()
    return os.time()
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function clean(value)
    value = tostring(value or ""):gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function titleForChapter(chapter, position)
    local title = clean(chapter and (chapter.title or chapter.name))
    if title ~= "" then
        return title
    end
    return string.format(_("Chapter %d"), tonumber(position) or 0)
end

local function itemKey(book_id, position)
    return tostring(book_id or "") .. ":" .. tostring(position or 0)
end

local function storageDir()
    return DownloadQueue.path:match("^(.*)/[^/]+$") or DataStorage:getDataDir()
end

local function savedItems(items)
    local result = {}
    for index = 1, #(items or {}) do
        local item = clone(items[index])
        if item.status ~= STATUS_DONE then
            item.pid = nil
            item.read_fd = nil
            item.check = nil
            item.started_at = nil
            if item.status == STATUS_RUNNING then
                item.status = STATUS_QUEUED
            end
            table.insert(result, item)
        end
    end
    return result
end

local function loadState()
    if not util.pathExists(DownloadQueue.path) then
        return {
            paused = false,
            waiting_network = false,
            items = {},
        }
    end
    local settings = LuaSettings:open(DownloadQueue.path)
    local state = settings:readSetting("download_queue")
    if type(state) ~= "table" then
        return {
            paused = false,
            waiting_network = false,
            items = {},
        }
    end
    state.waiting_network = state.waiting_network == true
    local loaded_items = state.items or {}
    state.items = {}
    local removed_done = false
    for index = 1, #loaded_items do
        local item = loaded_items[index]
        if item.status ~= STATUS_DONE then
            item.key = item.key or itemKey(item.book_id, item.position)
            item.status = item.status == STATUS_RUNNING and STATUS_QUEUED
                or (item.status or STATUS_QUEUED)
            item.tries = tonumber(item.tries) or 0
            item.progress = tonumber(item.progress) or 0
            table.insert(state.items, item)
        else
            removed_done = true
        end
    end
    state.needs_save = removed_done
    return state
end

local function saveState(state)
    util.makePath(storageDir())
    local settings = LuaSettings:open(DownloadQueue.path)
    settings:saveSetting("download_queue", {
        paused = state.paused == true,
        waiting_network = state.waiting_network == true,
        items = savedItems(state.items),
    })
    settings:flush()
end

local function queue(plugin)
    if not plugin.novel_download_queue then
        plugin.novel_download_queue = loadState()
    end
    return plugin.novel_download_queue
end

local function nextContentUrl(manifest, position)
    local next_chapter = ChapterRecord.nextOpenable(
        manifest and manifest.chapters,
        position,
        1
    )
    return next_chapter and next_chapter.url or nil
end

local function saveResult(manifest_store, manifest, position, result)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return nil, "chapter is missing"
    end
    local image_style = result.image_style
        or ChapterDoc.expectedImageStyle(manifest)
    local html = ChapterDoc.html(chapter, result.text, result.content_type, {
        image_style = image_style,
    })
    return manifest_store:saveChapter(manifest, position, html, {
        content_type = result.content_type,
        image_style = image_style,
    })
end

local function networkAvailable()
    if NetworkMgr.isOnline then
        return NetworkMgr:isOnline()
    end
    if NetworkMgr.getConnectionState then
        return NetworkMgr:getConnectionState()
    end
    return true
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
        UIManager:scheduleIn(DownloadQueue.collect_interval, collect)
    end
    UIManager:scheduleIn(DownloadQueue.collect_interval, collect)
end

local function refreshShell(plugin, book_id)
    if not plugin or not plugin.app then
        return
    end
    local ok, Shell = pcall(require, "novel.ui.shell")
    if ok and Shell and type(Shell.refreshDownloadState) == "function" then
        Shell.refreshDownloadState(plugin, book_id)
    end
end

local function notify(plugin, item)
    local state = queue(plugin)
    saveState(state)
    state.notify_token = (state.notify_token or 0) + 1
    local token = state.notify_token
    UIManager:scheduleIn(0.5, function()
        if not plugin or not plugin.app or not plugin.novel_download_queue then
            return
        end
        if plugin.novel_download_queue.notify_token ~= token then
            return
        end
        refreshShell(plugin, item and item.book_id)
    end)
end

local function retryDelay(tries)
    return DownloadQueue.retry_delays[tries] or DownloadQueue.retry_delays[#DownloadQueue.retry_delays]
end

local function removeItem(state, item)
    for index = 1, #(state.items or {}) do
        if state.items[index] == item
            or state.items[index].key == item.key then
            table.remove(state.items, index)
            return true
        end
    end
    return false
end

local function finishItem(plugin, item, ok, result_or_err)
    local state = queue(plugin)
    local book_id = item.book_id
    item.pid = nil
    item.read_fd = nil
    item.check = nil
    item.waiting_network = nil
    item.progress = ok and 1 or item.progress
    item.updated_at = now()
    if ok then
        state.waiting_network = false
        state.running_key = nil
        removeItem(state, item)
        notify(plugin, {
            book_id = book_id,
        })
        DownloadQueue.start(plugin)
        return
    end

    item.tries = (tonumber(item.tries) or 0) + 1
    item.error = tostring(result_or_err or _("Download failed"))
    state.waiting_network = false
    if item.tries < DownloadQueue.max_retries then
        item.status = STATUS_QUEUED
        item.next_retry_at = now() + retryDelay(item.tries)
    else
        item.status = STATUS_ERROR
        item.next_retry_at = nil
    end
    state.running_key = nil
    notify(plugin, item)
    DownloadQueue.start(plugin)
end

local function readResult(plugin, item, encoded)
    local decoded, result = pcall(buffer.decode, encoded or "")
    if not decoded or type(result) ~= "table" then
        finishItem(plugin, item, false, result or "cannot decode result")
        return
    end
    if not result.ok then
        finishItem(plugin, item, false, result.error
            and result.error.message or "download failed")
        return
    end

    local manifest_store = Manifest:new()
    local manifest = manifest_store:load(item.book_id)
    if not manifest then
        finishItem(plugin, item, false, "manifest is missing")
        return
    end
    local file, err = saveResult(manifest_store, manifest, item.position, result)
    if not file then
        finishItem(plugin, item, false, err)
        return
    end
    finishItem(plugin, item, true)
end

local function scheduleCheck(plugin, item)
    item.check = function()
        if not plugin or not plugin.app then
            return
        end
        if item.status ~= STATUS_RUNNING or not item.pid then
            return
        end

        local has_data = item.read_fd
            and ffiutil.getNonBlockingReadSize(item.read_fd) ~= 0
        local done = ffiutil.isSubProcessDone(item.pid)
        if has_data then
            local encoded = ffiutil.readAllFromFD(item.read_fd)
            item.read_fd = nil
            if not done then
                collectLater(item.pid)
            end
            readResult(plugin, item, encoded)
            return
        end
        if done then
            if item.read_fd then
                ffiutil.readAllFromFD(item.read_fd)
                item.read_fd = nil
            end
            finishItem(plugin, item, false, "subprocess exited without result")
            return
        end
        UIManager:scheduleIn(DownloadQueue.poll_interval, item.check)
    end
    UIManager:scheduleIn(DownloadQueue.poll_interval, item.check)
end

local function startItem(plugin, item)
    local manifest_store = Manifest:new()
    local manifest = manifest_store:load(item.book_id)
    local chapter = manifest and manifest.chapters and manifest.chapters[item.position]
    if not manifest or not chapter then
        item.status = STATUS_ERROR
        item.error = "chapter is missing"
        item.updated_at = now()
        notify(plugin, item)
        DownloadQueue.start(plugin)
        return false
    end
    if Manifest.chapterFileExists(manifest, item.position)
        and ChapterDoc.contentIsCurrent(manifest, chapter) then
        finishItem(plugin, item, true)
        return true
    end

    local source = manifest.source
    local book = manifest.book
    local next_chapter_url = nextContentUrl(manifest, item.position)
    local settings = plugin.app and plugin.app.settings
    local pid, read_fd = ffiutil.runInSubProcess(function(_pid, write_fd)
        local ChapterContent = require("novel.catalog.reading.chaptercontent")
        local result = ChapterContent.run(source, book, chapter, {
            next_chapter_url = next_chapter_url,
            settings = settings,
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
        finishItem(plugin, item, false, read_fd)
        return false
    end

    item.status = STATUS_RUNNING
    item.pid = pid
    item.read_fd = read_fd
    item.progress = 0
    item.started_at = now()
    item.updated_at = item.started_at
    queue(plugin).running_key = item.key
    notify(plugin, item)
    scheduleCheck(plugin, item)
    return true
end

local function runnableItem(state)
    local timestamp = now()
    for index = 1, #state.items do
        local item = state.items[index]
        if item.status == STATUS_QUEUED
            and ((tonumber(item.next_retry_at) or 0) <= timestamp) then
            return item
        end
    end
end

local function nextRetryAt(state)
    local next_at
    for index = 1, #state.items do
        local item = state.items[index]
        local retry_at = tonumber(item.next_retry_at)
        if item.status == STATUS_QUEUED and retry_at then
            next_at = next_at and math.min(next_at, retry_at) or retry_at
        end
    end
    return next_at
end

local function scheduleWake(plugin, state)
    if state.paused == true or state.wake_action then
        return
    end
    local retry_at = nextRetryAt(state)
    if not retry_at then
        return
    end
    local delay = math.max(1, retry_at - now())
    state.wake_action = function()
        state.wake_action = nil
        DownloadQueue.start(plugin)
    end
    UIManager:scheduleIn(delay, state.wake_action)
end

function DownloadQueue.init(plugin)
    if not plugin then
        return
    end
    local state = queue(plugin)
    if state.needs_save == true then
        state.needs_save = nil
        saveState(state)
    end
    DownloadQueue.start(plugin)
end

function DownloadQueue.close(plugin)
    local state = plugin and plugin.novel_download_queue
    if not state then
        return
    end
    state.notify_token = (state.notify_token or 0) + 1
    if state.wake_action then
        UIManager:unschedule(state.wake_action)
        state.wake_action = nil
    end
    for index = 1, #state.items do
        local item = state.items[index]
        if item.check then
            UIManager:unschedule(item.check)
            item.check = nil
        end
        if item.pid then
            if ffiutil.isSubProcessDone(item.pid) then
                if item.read_fd then
                    ffiutil.readAllFromFD(item.read_fd)
                end
            else
                ffiutil.terminateSubProcess(item.pid)
                collectLater(item.pid, item.read_fd)
            end
            item.pid = nil
            item.read_fd = nil
            if item.status == STATUS_RUNNING then
                item.status = STATUS_QUEUED
            end
        end
    end
    state.running_key = nil
    saveState(state)
end

function DownloadQueue.start(plugin)
    if not plugin or not plugin.app then
        return false
    end
    local state = queue(plugin)
    if state.paused == true or state.running_key then
        return false
    end
    local item = runnableItem(state)
    if not item then
        scheduleWake(plugin, state)
        return false
    end
    if not networkAvailable() then
        state.waiting_network = true
        item.waiting_network = true
        item.error = _("Waiting for network")
        notify(plugin, item)
        return false
    end
    state.waiting_network = false
    item.waiting_network = nil
    return startItem(plugin, item)
end

function DownloadQueue.pause(plugin)
    local state = queue(plugin)
    state.paused = true
    state.waiting_network = false
    for index = 1, #state.items do
        state.items[index].waiting_network = nil
    end
    if state.wake_action then
        UIManager:unschedule(state.wake_action)
        state.wake_action = nil
    end
    notify(plugin)
end

function DownloadQueue.resume(plugin)
    local state = queue(plugin)
    state.paused = false
    notify(plugin)
    DownloadQueue.start(plugin)
end

function DownloadQueue.enqueue(plugin, manifest, positions, options)
    options = options or {}
    if not plugin or not plugin.app or not manifest then
        return {
            queued = 0,
            skipped = 0,
        }
    end
    local state = queue(plugin)
    local manifest_store = Manifest:new()
    manifest = manifest_store:load(manifest.book_id) or manifest
    local queued, skipped = 0, 0
    for index = 1, #(positions or {}) do
        local position = tonumber(positions[index])
        local chapter = position and manifest.chapters and manifest.chapters[position]
        if chapter then
            local key = itemKey(manifest.book_id, position)
            local existing
            for item_index = 1, #state.items do
                if state.items[item_index].key == key then
                    existing = state.items[item_index]
                    break
                end
            end
            if existing and existing.status ~= STATUS_DONE then
                skipped = skipped + 1
            else
                if existing and existing.status == STATUS_DONE then
                    existing.status = STATUS_QUEUED
                    existing.tries = 0
                    existing.error = nil
                    existing.progress = 0
                    existing.waiting_network = nil
                    existing.next_retry_at = nil
                    existing.updated_at = now()
                else
                    table.insert(state.items, {
                        key = key,
                        book_id = manifest.book_id,
                        book_title = clean(manifest.book_title),
                        source_name = clean(manifest.source_name),
                        position = position,
                        title = titleForChapter(chapter, position),
                        status = STATUS_QUEUED,
                        tries = 0,
                        progress = 0,
                        created_at = now(),
                        updated_at = now(),
                    })
                end
                queued = queued + 1
            end
        end
    end
    notify(plugin)
    if type(options.on_done) == "function" then
        options.on_done({
            queued = queued,
            skipped = skipped,
        }, manifest)
    end
    DownloadQueue.start(plugin)
    return {
        queued = queued,
        skipped = skipped,
    }
end

function DownloadQueue.items(plugin)
    local result = {}
    local items = queue(plugin).items
    for index = 1, #items do
        if items[index].status ~= STATUS_DONE then
            table.insert(result, clone(items[index]))
        end
    end
    return result
end

function DownloadQueue.summary(plugin)
    local state = queue(plugin)
    local summary = {
        total = 0,
        queued = 0,
        running = 0,
        done = 0,
        error = 0,
        paused = state.paused == true,
        waiting_network = state.waiting_network == true,
    }
    for index = 1, #state.items do
        local status = state.items[index].status
        if status ~= STATUS_DONE then
            summary.total = summary.total + 1
        end
        if status == STATUS_QUEUED then
            summary.queued = summary.queued + 1
        elseif status == STATUS_RUNNING then
            summary.running = summary.running + 1
        elseif status == STATUS_DONE then
            summary.done = summary.done + 1
        elseif status == STATUS_ERROR then
            summary.error = summary.error + 1
        elseif status == STATUS_PAUSED then
            summary.queued = summary.queued + 1
        end
    end
    return summary
end

function DownloadQueue.networkReady(plugin)
    local state = queue(plugin)
    if state.paused == true then
        return false
    end
    if state.waiting_network ~= true then
        return false
    end
    state.waiting_network = false
    notify(plugin)
    return DownloadQueue.start(plugin)
end

function DownloadQueue.statusLabel(item)
    local status = item and item.status
    if status == STATUS_RUNNING then
        return _("Downloading")
    end
    if status == STATUS_DONE then
        return _("Downloaded")
    end
    if status == STATUS_ERROR then
        return _("Failed")
    end
    if item and item.waiting_network == true then
        return _("Waiting for network")
    end
    return _("Queued")
end

function DownloadQueue.find(plugin, key)
    local state = queue(plugin)
    for index = 1, #state.items do
        if state.items[index].key == key then
            return state.items[index], index
        end
    end
end

function DownloadQueue.remove(plugin, key)
    local state = queue(plugin)
    local item, index = DownloadQueue.find(plugin, key)
    if not item then
        return false
    end
    if item.check then
        UIManager:unschedule(item.check)
    end
    if item.pid then
        if ffiutil.isSubProcessDone(item.pid) then
            if item.read_fd then
                ffiutil.readAllFromFD(item.read_fd)
            end
        else
            ffiutil.terminateSubProcess(item.pid)
            collectLater(item.pid, item.read_fd)
        end
        state.running_key = nil
    end
    table.remove(state.items, index)
    notify(plugin, item)
    DownloadQueue.start(plugin)
    return true
end

function DownloadQueue.retry(plugin, key)
    local item = DownloadQueue.find(plugin, key)
    if not item then
        return false
    end
    item.status = STATUS_QUEUED
    item.tries = 0
    item.progress = 0
    item.error = nil
    item.waiting_network = nil
    item.next_retry_at = nil
    item.updated_at = now()
    notify(plugin, item)
    DownloadQueue.start(plugin)
    return true
end

function DownloadQueue.clearDone(plugin)
    local state = queue(plugin)
    local kept = {}
    for index = 1, #state.items do
        local item = state.items[index]
        if item.status ~= STATUS_DONE then
            table.insert(kept, item)
        end
    end
    state.items = kept
    notify(plugin)
end

function DownloadQueue.deleteStorage()
    os.remove(DownloadQueue.path)
end

DownloadQueue.STATUS_QUEUED = STATUS_QUEUED
DownloadQueue.STATUS_RUNNING = STATUS_RUNNING
DownloadQueue.STATUS_PAUSED = STATUS_PAUSED
DownloadQueue.STATUS_DONE = STATUS_DONE
DownloadQueue.STATUS_ERROR = STATUS_ERROR

return DownloadQueue
