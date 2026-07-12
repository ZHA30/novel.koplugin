local _ = require("novel.i18n")
local ChapterDoc = require("novel.reader.chapterdoc")
local DownloadItem = require("novel.reader.downloaditem")
local DownloadPolicy = require("novel.reader.downloadpolicy")
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
DownloadQueue.max_attempts = DownloadPolicy.max_attempts
DownloadQueue.poll_interval = 0.25
DownloadQueue.collect_interval = 1
DownloadQueue.checkpoint_changes = DownloadPolicy.checkpoint_changes
DownloadQueue.min_workers = 1
DownloadQueue.max_workers = 3

local BACKGROUND_NOVEL_ONLY = "novel_only"
local BACKGROUND_PAUSE_WHILE_READING = "pause_while_reading"
local BACKGROUND_ALWAYS = "always"

local STATUS_QUEUED = "queued"
local STATUS_RUNNING = "running"
local STATUS_PAUSED = "paused"
local STATUS_DONE = "done"
local STATUS_ERROR = "error"

local VALID_BACKGROUND_MODES = {
    [BACKGROUND_NOVEL_ONLY] = true,
    [BACKGROUND_PAUSE_WHILE_READING] = true,
    [BACKGROUND_ALWAYS] = true,
}

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

local function storageDir()
    return DownloadQueue.path:match("^(.*)/[^/]+$") or DataStorage:getDataDir()
end

local function emptyState()
    return {
        paused = false,
        waiting_network = false,
        items = {},
        running_keys = {},
    }
end

local function savedItems(items)
    local result = {}
    for index = 1, #(items or {}) do
        local item = type(items[index]) == "table" and clone(items[index]) or nil
        if item and item.status ~= STATUS_DONE then
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

local function normalizedLoadedItem(item, manifest_store, manifests)
    if type(item) ~= "table" then
        return nil, true
    end
    if item.status == STATUS_DONE then
        return nil, true
    end
    local changed = item.status == STATUS_RUNNING
        or item.chapter_file_name == nil
    item.status = item.status == STATUS_RUNNING and STATUS_QUEUED
        or (item.status or STATUS_QUEUED)
    item.tries = tonumber(item.tries) or 0
    item.progress = tonumber(item.progress) or 0
    local book_id = tostring(item.book_id or "")
    if book_id ~= "" then
        local manifest = manifests[book_id]
        if manifest == nil then
            manifest = manifest_store:load(book_id) or false
            manifests[book_id] = manifest
        end
        if manifest then
            local chapter, position = DownloadItem.resolve(manifest, item)
            if chapter then
                local old_key = item.key
                DownloadItem.bind(item, chapter, position)
                changed = changed or old_key ~= item.key
            end
        end
    end
    return item, changed
end

local function loadState()
    if not util.pathExists(DownloadQueue.path) then
        return emptyState()
    end
    local settings = LuaSettings:open(DownloadQueue.path)
    local state = settings:readSetting("download_queue")
    if type(state) ~= "table" then
        return emptyState()
    end
    state.waiting_network = state.waiting_network == true
    state.running_key = nil
    state.running_keys = {}
    local loaded_items = state.items or {}
    state.items = {}
    local needs_save = false
    local manifest_store = Manifest:new()
    local manifests = {}
    for index = 1, #loaded_items do
        local item, changed = normalizedLoadedItem(
            loaded_items[index],
            manifest_store,
            manifests
        )
        if item then
            table.insert(state.items, item)
        end
        needs_save = needs_save or changed
    end
    state.needs_save = needs_save
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
    state.dirty_changes = 0
end

local function checkpointState(state)
    -- Manifests are authoritative, so a crash can safely replay a bounded
    -- number of completed queue entries as local cache hits.
    state.dirty_changes = (state.dirty_changes or 0) + 1
    if DownloadPolicy.shouldCheckpoint(state.dirty_changes) then
        saveState(state)
    end
end

local function queue(plugin)
    if not plugin.novel_download_queue then
        plugin.novel_download_queue = loadState()
    end
    return plugin.novel_download_queue
end

local function downloadSettings(plugin)
    local settings = plugin and plugin.app and plugin.app.settings
    local download = settings and settings.download
    return type(download) == "table" and download or {}
end

local function backgroundMode(plugin)
    local mode = downloadSettings(plugin).background_mode
    if VALID_BACKGROUND_MODES[mode] then
        return mode
    end
    return BACKGROUND_PAUSE_WHILE_READING
end

local function workerCount(plugin)
    local workers = math.floor(tonumber(downloadSettings(plugin).workers) or 1)
    return math.max(DownloadQueue.min_workers,
        math.min(DownloadQueue.max_workers, workers))
end

local function runtimeAllowsDownloads(plugin)
    if not plugin or not plugin.app or plugin.novel_closing then
        return false
    end
    if plugin.novel_shell_visible == true then
        return true
    end
    local mode = backgroundMode(plugin)
    if mode == BACKGROUND_NOVEL_ONLY then
        return false
    end
    if mode == BACKGROUND_PAUSE_WHILE_READING then
        return ChapterDoc.currentChapter(plugin) == nil
    end
    return true
end

local function runningKeys(state)
    state.running_keys = state.running_keys or {}
    return state.running_keys
end

local function runningCount(state)
    local count = 0
    for running_key in pairs(runningKeys(state)) do
        if running_key ~= nil then
            count = count + 1
        end
    end
    return count
end

local function markRunning(state, item)
    runningKeys(state)[item.key] = true
end

local function unmarkRunning(state, item)
    if state and item then
        runningKeys(state)[item.key] = nil
    end
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

local function notify(plugin, item, save_mode)
    local state = queue(plugin)
    if save_mode == "immediate" then
        saveState(state)
    elseif save_mode ~= "none" then
        checkpointState(state)
    end
    state.pending_changes = state.pending_changes or {}
    if item and item.book_id then
        local change_key = tostring(item.book_id) .. ":"
            .. tostring(item.position or "")
        state.pending_changes[change_key] = {
            book_id = item.book_id,
            position = item.position,
        }
    else
        state.pending_general_change = true
    end
    if state.notify_action then
        return
    end
    state.notify_token = state.notify_token or 0
    local token = state.notify_token
    state.notify_action = function()
        if plugin and plugin.novel_download_queue then
            plugin.novel_download_queue.notify_action = nil
        end
        if not plugin or not plugin.app or not plugin.novel_download_queue then
            return
        end
        if plugin.novel_download_queue.notify_token ~= token then
            return
        end
        local current_state = plugin.novel_download_queue
        local listener = current_state.change_listener
        if type(listener) == "function" then
            if current_state.pending_general_change then
                pcall(listener, plugin)
            end
            for change_key, change in pairs(current_state.pending_changes or {}) do
                current_state.pending_changes[change_key] = nil
                pcall(listener, plugin, change.book_id, change.position)
            end
        end
        current_state.pending_changes = {}
        current_state.pending_general_change = nil
    end
    UIManager:scheduleIn(0.5, state.notify_action)
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

local function stopRunningItem(item)
    if item.check then
        UIManager:unschedule(item.check)
        item.check = nil
    end
    if not item.pid then
        return false
    end
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
    return true
end

local function stopRunningItems(state)
    local stopped = false
    for item_index = 1, #(state.items or {}) do
        local item = state.items[item_index]
        if item.status == STATUS_RUNNING then
            stopRunningItem(item)
            item.status = STATUS_QUEUED
            item.started_at = nil
            item.updated_at = now()
            stopped = true
        end
    end
    state.running_keys = {}
    return stopped
end

local function stopWake(state)
    if state and state.wake_action then
        UIManager:unschedule(state.wake_action)
        state.wake_action = nil
    end
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
    unmarkRunning(state, item)
    if ok then
        state.waiting_network = false
        removeItem(state, item)
        notify(plugin, {
            book_id = book_id,
            position = item.position,
        })
        DownloadQueue.start(plugin)
        return
    end

    item.tries = (tonumber(item.tries) or 0) + 1
    item.error = tostring(result_or_err or _("Download failed"))
    state.waiting_network = false
    local retry_at = DownloadPolicy.retryAt(item.tries, now())
    if retry_at then
        item.status = STATUS_QUEUED
        item.next_retry_at = retry_at
    else
        item.status = STATUS_ERROR
        item.next_retry_at = nil
    end
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
    local chapter, position = DownloadItem.resolve(manifest, item)
    if not chapter then
        finishItem(plugin, item, false, "chapter is missing")
        return
    end
    DownloadItem.bind(item, chapter, position)
    local file, err = saveResult(manifest_store, manifest, position, result)
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
    local chapter, position = DownloadItem.resolve(manifest, item)
    if not manifest or not chapter then
        item.status = STATUS_ERROR
        item.error = "chapter is missing"
        item.updated_at = now()
        notify(plugin, item)
        DownloadQueue.start(plugin)
        return false
    end
    DownloadItem.bind(item, chapter, position)
    if Manifest.chapterFileExists(manifest, position)
        and ChapterDoc.contentIsCurrent(manifest, chapter) then
        finishItem(plugin, item, true)
        return true
    end

    local source = manifest.source
    local book = manifest.book
    local next_chapter_url = nextContentUrl(manifest, position)
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
    markRunning(queue(plugin), item)
    notify(plugin, item, "none")
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

function DownloadQueue.setChangeListener(plugin, listener)
    if not plugin then
        return
    end
    queue(plugin).change_listener = type(listener) == "function"
        and listener or nil
end

function DownloadQueue.close(plugin)
    local state = plugin and plugin.novel_download_queue
    if not state then
        return
    end
    state.notify_token = (state.notify_token or 0) + 1
    if state.notify_action then
        UIManager:unschedule(state.notify_action)
        state.notify_action = nil
    end
    state.pending_changes = {}
    state.pending_general_change = nil
    stopWake(state)
    stopRunningItems(state)
    state.change_listener = nil
    saveState(state)
end

function DownloadQueue.start(plugin)
    if not plugin or not plugin.app then
        return false
    end
    local state = queue(plugin)
    if state.starting then
        state.start_requested = true
        return false
    end
    if state.paused == true or not runtimeAllowsDownloads(plugin) then
        stopWake(state)
        return false
    end
    state.starting = true
    local started = false
    repeat
        state.start_requested = nil
        while runningCount(state) < workerCount(plugin) do
            local item = runnableItem(state)
            if not item then
                break
            end
            if not networkAvailable() then
                state.waiting_network = true
                item.waiting_network = true
                item.error = _("Waiting for network")
                notify(plugin, item, "none")
                break
            end
            state.waiting_network = false
            item.waiting_network = nil
            if startItem(plugin, item) then
                started = true
            end
        end
    until not state.start_requested
    state.starting = nil
    if runningCount(state) < workerCount(plugin) then
        scheduleWake(plugin, state)
    end
    return started
end

function DownloadQueue.pause(plugin)
    local state = queue(plugin)
    state.paused = true
    state.waiting_network = false
    for index = 1, #state.items do
        state.items[index].waiting_network = nil
    end
    stopWake(state)
    stopRunningItems(state)
    notify(plugin, nil, "immediate")
end

function DownloadQueue.resume(plugin)
    local state = queue(plugin)
    state.paused = false
    notify(plugin, nil, "immediate")
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
            local key = DownloadItem.key(manifest.book_id, chapter, position)
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
                    local item = {
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
                    }
                    DownloadItem.bind(item, chapter, position)
                    table.insert(state.items, item)
                end
                queued = queued + 1
            end
        end
    end
    notify(plugin, nil, "immediate")
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
    notify(plugin, nil, "none")
    return DownloadQueue.start(plugin)
end

function DownloadQueue.runtimeChanged(plugin)
    if not plugin or not plugin.app then
        return false
    end
    local state = queue(plugin)
    if runtimeAllowsDownloads(plugin) then
        return DownloadQueue.start(plugin)
    end
    stopWake(state)
    local changed = state.waiting_network == true
    state.waiting_network = false
    for item_index = 1, #state.items do
        changed = changed or state.items[item_index].waiting_network == true
        state.items[item_index].waiting_network = nil
    end
    changed = stopRunningItems(state) or changed
    if changed then
        notify(plugin, nil, "immediate")
        return true
    end
    return false
end

function DownloadQueue.settingsChanged(plugin)
    return DownloadQueue.runtimeChanged(plugin)
end

function DownloadQueue.backgroundMode(plugin)
    return backgroundMode(plugin)
end

function DownloadQueue.workerCount(plugin)
    return workerCount(plugin)
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
    if status == STATUS_PAUSED then
        return _("Paused")
    end
    if item and item.waiting_network == true then
        return _("Waiting for network")
    end
    return _("Queued")
end

function DownloadQueue.chapterStatusLabel(plugin, manifest, position)
    if not plugin or not manifest or not position then
        return nil
    end
    if type(manifest) ~= "table" then
        manifest = Manifest:new():load(manifest)
    end
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return nil
    end
    local key = DownloadItem.key(manifest.book_id, chapter, position)
    local item = DownloadQueue.find(plugin, key)
    if not item or item.status == STATUS_DONE then
        return nil
    end
    return DownloadQueue.statusLabel(item)
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
    if stopRunningItem(item) then
        unmarkRunning(state, item)
    end
    table.remove(state.items, index)
    notify(plugin, item, "immediate")
    DownloadQueue.start(plugin)
    return true
end

local function removeBookItems(state, book_id)
    local removed = false
    for index = #state.items, 1, -1 do
        local item = state.items[index]
        if item.book_id == book_id then
            if stopRunningItem(item) or runningKeys(state)[item.key] then
                unmarkRunning(state, item)
            end
            table.remove(state.items, index)
            removed = true
        end
    end
    if removed then
        state.waiting_network = false
    end
    return removed
end

function DownloadQueue.removeBook(plugin, book_id, options)
    options = options or {}
    book_id = tostring(book_id or "")
    if book_id == "" then
        return false
    end

    local state = queue(plugin)
    if not removeBookItems(state, book_id) then
        return false
    end

    if options.notify == false then
        saveState(state)
    else
        notify(plugin, nil, "immediate")
    end
    if options.restart ~= false then
        DownloadQueue.start(plugin)
    end
    return true
end

function DownloadQueue.removeBooks(plugin, book_ids, options)
    local state = queue(plugin)
    local removed = false
    for index = 1, #(book_ids or {}) do
        local book_id = tostring(book_ids[index] or "")
        if book_id ~= "" and removeBookItems(state, book_id) then
            removed = true
        end
    end
    if not removed then
        return false
    end

    if options and options.notify == false then
        saveState(state)
    else
        notify(plugin, nil, "immediate")
    end
    if not options or options.restart ~= false then
        DownloadQueue.start(plugin)
    end
    return true
end

function DownloadQueue.pauseItem(plugin, key)
    local state = queue(plugin)
    local item = DownloadQueue.find(plugin, key)
    if not item or item.status == STATUS_ERROR or item.status == STATUS_DONE then
        return false
    end
    if stopRunningItem(item) then
        unmarkRunning(state, item)
    end
    item.status = STATUS_PAUSED
    item.waiting_network = nil
    state.waiting_network = false
    item.next_retry_at = nil
    item.updated_at = now()
    notify(plugin, item, "immediate")
    DownloadQueue.start(plugin)
    return true
end

function DownloadQueue.resumeItem(plugin, key)
    local item = DownloadQueue.find(plugin, key)
    if not item or item.status ~= STATUS_PAUSED then
        return false
    end
    item.status = STATUS_QUEUED
    item.error = nil
    item.waiting_network = nil
    item.next_retry_at = nil
    item.updated_at = now()
    notify(plugin, item, "immediate")
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
    notify(plugin, item, "immediate")
    DownloadQueue.start(plugin)
    return true
end

function DownloadQueue.clear(plugin)
    local state = queue(plugin)
    for index = 1, #state.items do
        local item = state.items[index]
        if stopRunningItem(item) then
            unmarkRunning(state, item)
        end
    end
    state.items = {}
    state.waiting_network = false
    state.running_keys = {}
    stopWake(state)
    notify(plugin, nil, "immediate")
end

function DownloadQueue.deleteStorage()
    os.remove(DownloadQueue.path)
end

DownloadQueue.STATUS_QUEUED = STATUS_QUEUED
DownloadQueue.STATUS_RUNNING = STATUS_RUNNING
DownloadQueue.STATUS_PAUSED = STATUS_PAUSED
DownloadQueue.STATUS_DONE = STATUS_DONE
DownloadQueue.STATUS_ERROR = STATUS_ERROR
DownloadQueue.BACKGROUND_NOVEL_ONLY = BACKGROUND_NOVEL_ONLY
DownloadQueue.BACKGROUND_PAUSE_WHILE_READING = BACKGROUND_PAUSE_WHILE_READING
DownloadQueue.BACKGROUND_ALWAYS = BACKGROUND_ALWAYS

return DownloadQueue
