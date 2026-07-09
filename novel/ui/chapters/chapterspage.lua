local _ = require("novel.i18n")
local ChapterCache = require("novel.reader.chaptercache")
local ChapterDownload = require("novel.reader.chapterdownload")
local ChapterActionDialog = require("novel.ui.chapters.actiondialog")
local ChapterListing = require("novel.ui.chapters.listing")
local ContentBuilder = require("novel.ui.contentbuilder")
local ChapterOpen = require("novel.reader.chapteropen")
local Dialog = require("novel.ui.widget.dialog")
local DownloadQueue = require("novel.reader.downloadqueue")
local Manifest = require("novel.storage.manifest")
local ShellRoutes = require("novel.ui.shellroutes")
local UIManager = require("ui/uimanager")

local ChaptersPage = {}

local function chapterRoute(route, manifest)
    return ShellRoutes.chapters{
        tab = route.tab,
        source = route.source or manifest.source,
        book = route.book or manifest.book,
        manifest = manifest,
        filter = route.filter,
        sort = route.sort,
    }
end

local function refresh(runtime, plugin, route, manifest)
    if runtime and type(runtime.replace) == "function" then
        runtime.replace(plugin, manifest and chapterRoute(route, manifest) or route)
    end
end

local function markReadState(plugin, manifest, row, runtime, route, read)
    local manifest_store = Manifest:new()
    local current_manifest = manifest_store:load(manifest.book_id) or manifest
    local updated_manifest, err = manifest_store:markReadMany(
        current_manifest,
        { row.position },
        read
    )
    if not updated_manifest then
        Dialog.message(Dialog.failureMessage(err))
        return
    end
    ChapterListing.setSelected(plugin, updated_manifest, row.position, false)
    refresh(runtime, plugin, route, updated_manifest)
end

local function finishOfflineChapterAction(plugin, route, runtime, manifest, row,
    updated_manifest)
    updated_manifest = updated_manifest or manifest
    ChapterListing.setSelected(plugin, updated_manifest, row.position, false)
    refresh(runtime, plugin, route, updated_manifest)
end

local function downloadOfflineChapter(plugin, route, runtime, manifest, row, positions)
    ChapterDownload.enqueue(plugin, manifest, positions, {
        on_done = function(_summary, updated_manifest)
            finishOfflineChapterAction(
                plugin,
                route,
                runtime,
                manifest,
                row,
                updated_manifest
            )
        end,
    })
end

local function deleteOfflineChapter(plugin, route, runtime, manifest, row,
    positions)
    ChapterCache.delete(plugin, manifest, positions, {
        on_done = function(_summary, updated_manifest)
            finishOfflineChapterAction(
                plugin,
                route,
                runtime,
                manifest,
                row,
                updated_manifest
            )
        end,
    })
end

local function toggleSelected(plugin, manifest, row, runtime, route)
    local selected = ChapterListing.toggleSelected(plugin, manifest, row.position)
    if selected then
        ChapterListing.setSelectionMode(plugin, manifest, true)
    end
    refresh(runtime, plugin, route)
end

local function showActions(plugin, route, runtime, manifest, row)
    local row_positions = { row.position }
    local download_positions = ChapterCache.cacheablePositions(manifest,
        row_positions)
    local offline_positions = ChapterCache.cachedPositions(manifest,
        row_positions, {
            keep_file = ChapterCache.currentFile(),
        })
    UIManager:show(ChapterActionDialog:new{
        title = row.title,
        actions = {
            {
                icon = "arrow-down-to-line",
                text = _("Download selected"),
                enabled = row.openable and #download_positions > 0,
                callback = function()
                    downloadOfflineChapter(
                        plugin,
                        route,
                        runtime,
                        manifest,
                        row,
                        download_positions
                    )
                end,
            },
            {
                icon = "trash-2",
                text = _("Delete offline chapter"),
                enabled = row.openable and #offline_positions > 0,
                callback = function()
                    deleteOfflineChapter(
                        plugin,
                        route,
                        runtime,
                        manifest,
                        row,
                        offline_positions
                    )
                end,
            },
            {
                icon = "check-check",
                text = _("Mark selected as read"),
                enabled = row.openable,
                callback = function()
                    markReadState(plugin, manifest, row, runtime, route, true)
                end,
            },
            {
                icon = "check-check-off",
                text = _("Mark selected as unread"),
                enabled = row.openable,
                callback = function()
                    markReadState(plugin, manifest, row, runtime, route, false)
                end,
            },
        },
    })
end

local function trailingActions(plugin, route, runtime, manifest, row, selection_mode)
    if selection_mode then
        return {
            {
                icon = ChapterListing.isSelected(plugin, manifest, row.position)
                    and "square-check" or "square",
                dim = not row.openable,
                callback = row.openable and function()
                    toggleSelected(plugin, manifest, row, runtime, route)
                end or nil,
            },
        }
    end
    return {
        {
            icon = "ellipsis-vertical",
            dim = not row.openable,
            callback = row.openable and function()
                showActions(plugin, route, runtime, manifest, row)
            end or nil,
        },
    }
end

function ChaptersPage.build(shell, plugin, route, runtime)
    if route.error then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), tostring(route.error))
    end

    local manifest = route.manifest
    if not manifest then
        return ContentBuilder.buildEmptyState(shell)
    end

    local filter, sort = ChapterListing.resolveState(plugin, manifest, {
        filter = route.filter,
        sort = route.sort,
    })
    local model = ChapterListing.buildModel(manifest, filter, sort, {
        download_label_at = function(position)
            return DownloadQueue.chapterStatusLabel(
                plugin,
                manifest.book_id,
                position
            )
        end,
    })
    if model.count == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    local selection_mode = ChapterListing.isSelectionMode(plugin, manifest)

    return ContentBuilder.buildList(shell, nil, {
        item_count = model.count,
        fixed_item = true,
        item_at = function(index)
            local row = model.rowAt(index)
            return {
                title = row.title,
                mandatory = row.downloaded_label,
                dim = row.dim,
                trailing_actions = trailingActions(
                    plugin,
                    route,
                    runtime,
                    manifest,
                    row,
                    selection_mode
                ),
                callback = row.openable and function()
                    ChapterOpen.open(plugin, manifest, row.position, {
                        from_reader = plugin.ui and plugin.ui.document ~= nil,
                        jump = "start",
                    })
                end or nil,
            }
        end,
    })
end

return ChaptersPage
