local _ = require("novel.i18n")
local BookshelfLifecycle = require("novel.bookshelflifecycle")
local BookRefresh = require("novel.bookshelfrefresh")
local BookshelfSelection = require("novel.ui.bookshelf.selection")
local ActionDialog = require("novel.ui.widget.actiondialog")
local BookActions = require("novel.ui.bookactions")
local ChapterCache = require("novel.reader.chaptercache")
local DownloadQueue = require("novel.reader.downloadqueue")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local ChaptersFlow = require("novel.ui.chapters.flow")
local Manifest = require("novel.storage.manifest")
local RefreshFlow = require("novel.ui.refreshflow")
local Shell = require("novel.ui.shell")
local UIManager = require("ui/uimanager")

local BookshelfFlow = {}

local function selectedRecords(plugin)
    local records = plugin and plugin.app
        and plugin.app:getBookshelfStore():list() or {}
    return BookshelfSelection.records(plugin, records)
end

local function leaveSelection(plugin)
    BookshelfSelection.setMode(plugin, false)
end

local function refreshSelected(plugin, records)
    RefreshFlow.refreshBookshelf(plugin, records, {
        on_done = function()
            leaveSelection(plugin)
            BookshelfFlow.show(plugin)
        end,
    })
end

local function manifestForRecord(plugin, record)
    local source = BookRefresh.findCurrentSource(plugin, record)
    return Manifest:new():loadByBook(source, record.book)
end

local function recordsMissingManifest(plugin, records)
    local missing = {}
    for index = 1, #records do
        local record = records[index]
        local manifest = manifestForRecord(plugin, record)
        if not manifest or #(manifest.chapters or {}) == 0 then
            table.insert(missing, record)
        end
    end
    return missing
end

local function enqueueSelectedDownloads(plugin, records)
    local queued = 0
    for index = 1, #records do
        local record = records[index]
        local manifest = manifestForRecord(plugin, record)
        local positions = {}
        for position = 1, #(manifest and manifest.chapters or {}) do
            table.insert(positions, position)
        end
        local download_positions = ChapterCache.cacheablePositions(manifest, positions)
        if #download_positions > 0 then
            local summary = DownloadQueue.enqueue(plugin, manifest, download_positions)
            queued = queued + (summary.queued or 0)
        end
    end
    if queued > 0 then
        Dialog.message(string.format(_("Queued %d chapters for download."), queued))
    else
        Dialog.message(_("Selected chapters are already in the download queue."))
    end
end

local function downloadSelected(plugin, records)
    local function finishDownload()
        enqueueSelectedDownloads(plugin, records)
        leaveSelection(plugin)
        BookshelfFlow.show(plugin)
    end

    local missing_records = recordsMissingManifest(plugin, records)
    if #missing_records == 0 then
        finishDownload()
        return
    end
    RefreshFlow.refreshBookshelf(plugin, missing_records, {
        message = false,
        on_done = finishDownload,
    })
end

local function removeSelected(plugin, records)
    Dialog.confirm(
        string.format(_("Remove %d books from bookshelf?"), #records),
        _("Remove"),
        function()
            local removed = BookshelfLifecycle.removeMany(plugin, records)
            leaveSelection(plugin)
            BookshelfFlow.show(plugin)
            if removed > 0 then
                Dialog.message(string.format(_("Removed %d books from bookshelf."), removed))
            else
                Dialog.message(Dialog.failureMessage())
            end
        end
    )
end

local function resumeRecord(plugin, record)
    local source = BookRefresh.findCurrentSource(plugin, record)
    local current = record.current
    if not current or not current.chapter then
        ChaptersFlow.resume(plugin, source, record.book, 1)
        return
    end
    local chapter_position = current.chapter_position or 1
    ChaptersFlow.resume(plugin, source, record.book, chapter_position)
end

function BookshelfFlow.showDetails(plugin, record)
    if not plugin or not record then
        return
    end
    local source = BookRefresh.findCurrentSource(plugin, record)
    BookActions.showMenu(plugin, source, record.book, record, {
        tab = "bookshelf",
        on_bookshelf_changed = function()
            BookshelfFlow.show(plugin)
        end,
    })
end

function BookshelfFlow.resume(plugin, record)
    if not plugin or not record then
        return
    end
    resumeRecord(plugin, record)
end

function BookshelfFlow.toggleSelected(plugin, record)
    if not plugin or not record then
        return
    end
    BookshelfSelection.toggle(plugin, record)
    BookshelfFlow.show(plugin)
end

function BookshelfFlow.showSelectedActions(plugin)
    local records = selectedRecords(plugin)
    if #records == 0 then
        return
    end
    UIManager:show(ActionDialog:new{
        title = string.format(_("Selected %d books"), #records),
        actions = {
            {
                icon = "rotate-cw",
                text = _("Refresh"),
                callback = function()
                    refreshSelected(plugin, records)
                end,
            },
            {
                icon = "arrow-down-to-line",
                text = _("Download"),
                callback = function()
                    downloadSelected(plugin, records)
                end,
            },
            {
                icon = "trash-2",
                text = _("Remove"),
                callback = function()
                    removeSelected(plugin, records)
                end,
            },
        },
    })
end

function BookshelfFlow.close(plugin)
    RefreshFlow.close(plugin)
    Dialog.closeKeys(plugin, {
        "bookshelf_confirm_dialog",
    })
    DetailFlow.close(plugin)
    BookshelfSelection.setMode(plugin, false)
end

function BookshelfFlow.show(plugin)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    Shell.show(plugin, {
        active_tab = "bookshelf",
    })
end

return BookshelfFlow
