local _ = require("novel.i18n")
local ChapterCache = require("novel.reader.chaptercache")
local ChapterDownload = require("novel.reader.chapterdownload")
local ChapterListing = require("novel.ui.chapters.listing")
local Dialog = require("novel.ui.widget.dialog")
local DownloadQueue = require("novel.reader.downloadqueue")
local Manifest = require("novel.storage.manifest")
local ShellRoutes = require("novel.ui.shellroutes")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local ShellActions = {}

local function listInfo(plugin)
    return ShellSession.listInfo(plugin) or {}
end

local function canRemotePage(route)
    if not route or route.loading == true or route.loading_more == true then
        return false
    end
    if route.key == "discover_results" then
        return route.source ~= nil and route.group ~= nil
    end
    if route.key == "search_results" then
        return route.source ~= nil and route.keyword ~= nil
    end
    return false
end

function ShellActions.canRemotePreviousPage(route)
    return canRemotePage(route) and (tonumber(route.current_page) or 1) > 1
end

function ShellActions.canRemoteNextPage(route)
    return canRemotePage(route) and route.no_more_source_pages ~= true
end

local function canPreviousPage(plugin, route)
    local info = listInfo(plugin)
    return info.has_previous == true or ShellActions.canRemotePreviousPage(route)
end

local function canNextPage(plugin, route)
    local info = listInfo(plugin)
    return info.has_next == true or ShellActions.canRemoteNextPage(route)
end

local function previousAction(plugin, route, callbacks)
    return {
        key = "previous",
        text = _("Previous page"),
        icon = "arrow-left",
        enabled = canPreviousPage(plugin, route),
        callback = function()
            callbacks.previous_page()
        end,
    }
end

local function nextAction(plugin, route, callbacks)
    return {
        key = "next",
        text = _("Next page"),
        icon = "arrow-right",
        enabled = canNextPage(plugin, route),
        callback = function()
            callbacks.next_page()
        end,
    }
end

local function backAction(callbacks)
    return {
        key = "back",
        text = _("Back"),
        icon = "undo-2",
        callback = function()
            callbacks.pop()
        end,
    }
end

function ShellActions.chapterRoute(route, manifest, filter, sort)
    return ShellRoutes.chapters{
        tab = route.tab,
        source = route.source or manifest.source,
        book = route.book or manifest.book,
        manifest = manifest,
        filter = filter,
        sort = sort,
    }
end

local function replaceChapterManifest(callbacks, route, manifest, filter, sort)
    if not manifest then
        return
    end
    callbacks.replace(ShellActions.chapterRoute(route, manifest, filter, sort))
end

local function replaceChapterState(callbacks, route, filter, sort)
    replaceChapterManifest(callbacks, route, route and route.manifest, filter, sort)
end

local function chapterState(plugin, route)
    local manifest = route and route.manifest
    local filter, sort = ChapterListing.resolveState(plugin, manifest, {
        filter = route and route.filter,
        sort = route and route.sort,
    })
    return manifest, filter, sort
end

local function resumeChapter(plugin, route)
    local manifest = route and route.manifest
    if not manifest then
        return
    end
    local position = tonumber(manifest.current_position) or 1
    local ChapterOpen = require("novel.reader.chapteropen")
    ChapterOpen.open(plugin, manifest, position, {
        from_reader = plugin.ui and plugin.ui.document ~= nil,
    })
end

local function markReadState(plugin, callbacks, route, manifest, filter, sort,
    positions, read)
    if #positions == 0 then
        return
    end
    local manifest_store = Manifest:new()
    local current_manifest = manifest_store:load(manifest.book_id) or manifest
    local updated_manifest, err = manifest_store:markReadMany(
        current_manifest,
        positions,
        read
    )
    if not updated_manifest then
        Dialog.message(Dialog.failureMessage(err))
        return
    end
    ChapterListing.setSelectionMode(plugin, updated_manifest, false)
    replaceChapterManifest(callbacks, route, updated_manifest, filter, sort)
end

local function finishChapterCacheAction(plugin, callbacks, route, manifest, filter,
    sort, updated_manifest)
    updated_manifest = updated_manifest or manifest
    ChapterListing.setSelectionMode(plugin, updated_manifest, false)
    replaceChapterManifest(callbacks, route, updated_manifest, filter, sort)
end

local function confirmChapterAction(message_template, count, ok_text, callback)
    if count <= 0 then
        return
    end
    Dialog.confirm(string.format(message_template, count), ok_text, callback)
end

local function chapterTopActions(plugin, route, callbacks)
    local manifest, filter, sort = chapterState(plugin, route)
    if not manifest then
        return {}
    end
    local rows = ChapterListing.buildRows(manifest, filter, sort)
    local selection = ChapterListing.selectionStateForRows(plugin, manifest, rows)
    local selection_mode = ChapterListing.isSelectionMode(plugin, manifest)
    local action_positions = selection_mode
        and ChapterListing.selectedPositionsForRows(plugin, manifest, rows)
        or ChapterListing.positionsForRows(manifest, rows)
    local has_action_scope = #action_positions > 0
    local cache_positions = ChapterCache.cacheablePositions(
        manifest,
        action_positions
    )
    local delete_cache_positions = ChapterCache.cachedPositions(
        manifest,
        action_positions,
        {
            keep_file = ChapterCache.currentFile(),
        }
    )
    return {
        {
            key = "mark_read",
            text = _("Mark as read"),
            icon = "check-check",
            enabled = has_action_scope,
            callback = function()
                confirmChapterAction(
                    _("Mark %d chapters as read?"),
                    #action_positions,
                    _("Mark as read"),
                    function()
                        markReadState(
                            plugin,
                            callbacks,
                            route,
                            manifest,
                            filter,
                            sort,
                            action_positions,
                            true
                        )
                    end
                )
            end,
        },
        {
            key = "mark_unread",
            text = _("Mark as unread"),
            icon = "check-check-off",
            enabled = has_action_scope,
            callback = function()
                confirmChapterAction(
                    _("Mark %d chapters as unread?"),
                    #action_positions,
                    _("Mark as unread"),
                    function()
                        markReadState(
                            plugin,
                            callbacks,
                            route,
                            manifest,
                            filter,
                            sort,
                            action_positions,
                            false
                        )
                    end
                )
            end,
        },
        {
            key = "cache",
            text = _("Download"),
            icon = "arrow-down-to-line",
            enabled = #cache_positions > 0,
            callback = function()
                confirmChapterAction(
                    _("Download %d chapters?"),
                    #cache_positions,
                    _("Download"),
                    function()
                        ChapterDownload.enqueue(plugin, manifest, cache_positions, {
                            on_done = function(_summary, updated_manifest)
                                finishChapterCacheAction(
                                    plugin,
                                    callbacks,
                                    route,
                                    manifest,
                                    filter,
                                    sort,
                                    updated_manifest
                                )
                            end,
                        })
                    end
                )
            end,
        },
        {
            key = "delete_cache",
            text = _("Delete"),
            icon = "trash-2",
            enabled = #delete_cache_positions > 0,
            callback = function()
                confirmChapterAction(
                    _("Delete %d chapters?"),
                    #delete_cache_positions,
                    _("Delete"),
                    function()
                        ChapterCache.delete(plugin, manifest, delete_cache_positions, {
                            on_done = function(_summary, updated_manifest)
                                finishChapterCacheAction(
                                    plugin,
                                    callbacks,
                                    route,
                                    manifest,
                                    filter,
                                    sort,
                                    updated_manifest
                                )
                            end,
                        })
                    end
                )
            end,
        },
        {
            key = "select",
            text = _("Select"),
            icon = selection_mode and "square-check" or "square",
            active = selection_mode,
            enabled = selection.selectable_count > 0,
            callback = function()
                ChapterListing.setSelectionMode(
                    plugin,
                    manifest,
                    not selection_mode
                )
                callbacks.replace(route)
            end,
            hold_callback = function()
                ChapterListing.setSelectionMode(plugin, manifest, true)
                ChapterListing.setRowsSelected(
                    plugin,
                    manifest,
                    rows,
                    not selection.all_selected
                )
                callbacks.replace(route)
            end,
        },
    }
end

local function chapterActions(plugin, route, callbacks)
    local manifest, filter, sort = chapterState(plugin, route)
    local filter_active = ChapterListing.hasActiveFilter(filter)
    local descending = sort == ChapterListing.SORT_DESCENDING
    return {
        previousAction(plugin, route, callbacks),
        nextAction(plugin, route, callbacks),
        {
            key = "filter",
            text = ChapterListing.filterLabel(filter),
            icon = filter_active and "funnel" or "funnel-x",
            active = filter_active,
            callback = function()
                local ChapterFilterDialog = require("novel.ui.chapters.filterdialog")
                UIManager:show(ChapterFilterDialog:new{
                    filter = filter,
                    on_apply = function(next_filter)
                        replaceChapterState(callbacks, route, next_filter, sort)
                    end,
                })
            end,
        },
        {
            key = "sort",
            text = ChapterListing.sortLabel(sort),
            icon = descending
                and "arrow-down-wide-narrow"
                or "arrow-up-narrow-wide",
            active = descending,
            callback = function()
                local next_sort = descending
                    and ChapterListing.SORT_ASCENDING
                    or ChapterListing.SORT_DESCENDING
                replaceChapterState(callbacks, route, filter, next_sort)
            end,
        },
        {
            key = "continue",
            text = _("Continue"),
            icon = "circle-play",
            enabled = manifest ~= nil and #(manifest.chapters or {}) > 0,
            callback = function()
                resumeChapter(plugin, route)
            end,
        },
        backAction(callbacks),
    }
end

local function listActions(plugin, route, callbacks)
    return {
        previousAction(plugin, route, callbacks),
        nextAction(plugin, route, callbacks),
        backAction(callbacks),
    }
end

local function homeActions(plugin, callbacks)
    local active_tab = ShellSession.activeTab(plugin)
    return {
        {
            key = "bookshelf",
            text = _("Bookshelf"),
            icon = "bookshelf",
            active = active_tab == "bookshelf",
            callback = function()
                callbacks.show_tab("bookshelf")
            end,
        },
        {
            key = "discover",
            text = _("Discover"),
            icon = "discover",
            active = active_tab == "discover",
            callback = function()
                callbacks.show_tab("discover")
            end,
        },
        {
            key = "settings",
            text = _("More"),
            icon = "circle-ellipsis",
            active = active_tab == "settings",
            callback = function()
                callbacks.show_tab("settings")
            end,
        },
        {
            key = "exit",
            text = _("Exit"),
            icon = "log-out",
            callback = function()
                callbacks.close()
            end,
        },
    }
end

local function downloadTopActions(plugin)
    local summary = DownloadQueue.summary(plugin)
    return {
        {
            key = "download_clear",
            text = _("Clear queue"),
            icon = "trash-2",
            enabled = summary.total > 0,
            callback = function()
                Dialog.confirm(
                    _("Clear all downloads?"),
                    _("Clear queue"),
                    function()
                        DownloadQueue.clear(plugin)
                    end
                )
            end,
        },
        {
            key = "download_toggle",
            text = summary.paused and _("Resume") or _("Pause"),
            icon = summary.paused and "play" or "pause",
            enabled = summary.total > 0,
            callback = function()
                if summary.paused then
                    DownloadQueue.resume(plugin)
                else
                    DownloadQueue.pause(plugin)
                end
            end,
        },
    }
end

local function searchResultsActions(plugin, route, callbacks)
    return {
        previousAction(plugin, route, callbacks),
        nextAction(plugin, route, callbacks),
        {
            key = "search",
            text = _("Search"),
            icon = "search",
            enabled = route and route.source ~= nil and route.loading ~= true,
            callback = function()
                local SearchFlow = require("novel.ui.search.flow")
                SearchFlow.showInput(plugin, route.source, route.keyword, {
                    tab = route.tab,
                })
            end,
        },
        backAction(callbacks),
    }
end

function ShellActions.home(plugin, callbacks)
    return homeActions(plugin, callbacks)
end

function ShellActions.bottom(plugin, route, shell_widget, callbacks)
    ShellSession.setListInfo(plugin, shell_widget and shell_widget.list_page_info)
    if ShellRoutes.isTopLevel(route) then
        return homeActions(plugin, callbacks)
    end
    if route and route.key == "chapters" and route.manifest then
        return chapterActions(plugin, route, callbacks)
    end
    if route and route.key == "search_results" then
        return searchResultsActions(plugin, route, callbacks)
    end
    return listActions(plugin, route, callbacks)
end

function ShellActions.top(plugin, route, callbacks)
    if route and route.key == "chapters" and route.manifest then
        return chapterTopActions(plugin, route, callbacks)
    end
    if route and route.key == "downloads" then
        return downloadTopActions(plugin)
    end
    return {}
end

return ShellActions
