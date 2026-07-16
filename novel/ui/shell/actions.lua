local _ = require("novel.i18n")
local BookshelfLifecycle = require("novel.bookshelflifecycle")
local ActionDialog = require("novel.ui.widget.actiondialog")
local BookshelfSelection = require("novel.ui.bookshelf.selection")
local ChapterCache = require("novel.reader.chaptercache")
local ChapterDownload = require("novel.reader.chapterdownload")
local ChapterListing = require("novel.ui.chapters.listing")
local Dialog = require("novel.ui.widget.dialog")
local DownloadQueue = require("novel.reader.downloadqueue")
local Manifest = require("novel.storage.manifest")
local RefreshFlow = require("novel.ui.refreshflow")
local ShellRoutes = require("novel.ui.shellroutes")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local ShellActions = {}

local function detailFlow()
    return require("novel.ui.detail.flow")
end

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
        hold_callback = function()
            callbacks.first_page()
        end,
    }
end

local function nextAction(plugin, route, callbacks)
    if route and route.error
        and (route.key == "search_results" or route.key == "discover_results") then
        return {
            key = "retry",
            text = _("Retry"),
            icon = "rotate-ccw",
            enabled = canRemotePage(route),
            callback = function()
                if route.key == "search_results" then
                    local SearchFlow = require("novel.ui.search.flow")
                    SearchFlow.retry(plugin)
                else
                    local DiscoverFlow = require("novel.ui.discover.flow")
                    DiscoverFlow.retry(plugin)
                end
            end,
        }
    end
    return {
        key = "next",
        text = _("Next page"),
        icon = "arrow-right",
        enabled = canNextPage(plugin, route),
        callback = function()
            callbacks.next_page()
        end,
        hold_callback = function()
            callbacks.last_page()
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

local function finishOfflineChapterAction(plugin, callbacks, route, manifest, filter,
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

local function countedText(label, count)
    return string.format("%s (%d)", label, count)
end

local function showBookIntro(plugin, route, manifest)
    if not manifest then
        return
    end
    detailFlow().show(plugin, manifest.source, manifest.book, {
        tab = route and route.tab,
    })
end

local function refreshChapterBook(plugin, route, callbacks, manifest, filter, sort)
    RefreshFlow.refreshBook(
        plugin,
        route.source or manifest.source,
        route.book or manifest.book,
        {
            on_done = function(applied)
                replaceChapterManifest(
                    callbacks,
                    route,
                    applied.manifest,
                    filter,
                    sort
                )
            end,
        }
    )
end

local function replaceSelectionMode(plugin, callbacks, route, manifest, enabled)
    ChapterListing.setSelectionMode(plugin, manifest, enabled)
    callbacks.replace(route)
end

local function showSelectedChapterActions(plugin, route, callbacks, manifest, filter, sort,
    selected_positions)
    local download_positions = ChapterCache.cacheablePositions(
        manifest,
        selected_positions
    )
    local offline_positions = ChapterCache.cachedPositions(
        manifest,
        selected_positions,
        {
            keep_file = ChapterCache.currentFile(),
        }
    )
    UIManager:show(ActionDialog:new{
        title = string.format(_("Selected %d items"), #selected_positions),
        actions = {
            {
                icon = "arrow-down-to-line",
                text = countedText(_("Download selected"), #download_positions),
                enabled = #download_positions > 0,
                callback = function()
                    ChapterDownload.enqueue(plugin, manifest, download_positions, {
                        on_done = function(_summary, updated_manifest)
                            finishOfflineChapterAction(
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
                end,
            },
            {
                icon = "trash-2",
                text = countedText(_("Delete offline chapters"), #offline_positions),
                enabled = #offline_positions > 0,
                callback = function()
                    ChapterCache.delete(plugin, manifest, offline_positions, {
                        on_done = function(_summary, updated_manifest)
                            finishOfflineChapterAction(
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
                end,
            },
            {
                icon = "check-check",
                text = countedText(_("Mark selected as read"), #selected_positions),
                enabled = #selected_positions > 0,
                callback = function()
                    markReadState(
                        plugin,
                        callbacks,
                        route,
                        manifest,
                        filter,
                        sort,
                        selected_positions,
                        true
                    )
                end,
            },
            {
                icon = "check-check-off",
                text = countedText(_("Mark selected as unread"), #selected_positions),
                enabled = #selected_positions > 0,
                callback = function()
                    markReadState(
                        plugin,
                        callbacks,
                        route,
                        manifest,
                        filter,
                        sort,
                        selected_positions,
                        false
                    )
                end,
            },
        },
    })
end

local function chapterTopActions(plugin, route, callbacks)
    local manifest, filter, sort = chapterState(plugin, route)
    if not manifest then
        return {}
    end
    local rows = ChapterListing.buildRows(manifest, filter, sort)
    local selection = ChapterListing.selectionStateForRows(plugin, manifest, rows)
    local selection_mode = ChapterListing.isSelectionMode(plugin, manifest)
    local filtered_positions = ChapterListing.positionsForRows(manifest, rows)
    local selected_positions = ChapterListing.selectedPositionsForRows(
        plugin,
        manifest,
        rows
    )
    if selection_mode then
        return {
            {
                key = "selected_actions",
                icon = "check",
                enabled = #selected_positions > 0,
                callback = function()
                    showSelectedChapterActions(
                        plugin,
                        route,
                        callbacks,
                        manifest,
                        filter,
                        sort,
                        selected_positions
                    )
                end,
            },
            {
                key = "cancel_selection",
                icon = "x",
                callback = function()
                    replaceSelectionMode(plugin, callbacks, route, manifest, false)
                end,
            },
            {
                key = "select_all",
                icon = selection.all_selected and "square-check" or "square",
                enabled = selection.selectable_count > 0,
                callback = function()
                    ChapterListing.setRowsSelected(
                        plugin,
                        manifest,
                        rows,
                        not selection.all_selected
                    )
                    callbacks.replace(route)
                end,
                hold_callback = function()
                    ChapterListing.setRowsSelected(plugin, manifest, rows, true)
                    callbacks.replace(route)
                end,
            },
        }
    end
    local action_positions = filtered_positions
    local has_action_scope = #action_positions > 0
    local download_positions = ChapterCache.cacheablePositions(
        manifest,
        action_positions
    )
    return {
        {
            key = "refresh",
            icon = "rotate-cw",
            callback = function()
                refreshChapterBook(
                    plugin,
                    route,
                    callbacks,
                    manifest,
                    filter,
                    sort
                )
            end,
        },
        {
            key = "intro",
            icon = "info",
            callback = function()
                showBookIntro(plugin, route, manifest)
            end,
        },
        {
            key = "mark_all_read",
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
            key = "download_all",
            icon = "arrow-down-to-line",
            enabled = #download_positions > 0,
            callback = function()
                confirmChapterAction(
                    _("Download %d chapters?"),
                    #download_positions,
                    _("Download"),
                    function()
                        ChapterDownload.enqueue(plugin, manifest, download_positions, {
                            on_done = function(_summary, updated_manifest)
                                finishOfflineChapterAction(
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
            icon = "square",
            enabled = selection.selectable_count > 0,
            callback = function()
                ChapterListing.setSelectionMode(plugin, manifest, true)
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

local function bookshelfTopActions(plugin, route, callbacks)
    local records = plugin and plugin.app
        and plugin.app:getBookshelfStore():list() or {}
    local selection_mode = BookshelfSelection.isMode(plugin)
    local selection = BookshelfSelection.state(plugin, records)
    if selection_mode then
        return {
            {
                key = "selected_actions",
                icon = "check",
                enabled = selection.selected_count > 0,
                callback = function()
                    require("novel.ui.bookshelf.flow").showSelectedActions(plugin)
                end,
            },
            {
                key = "cancel_selection",
                icon = "x",
                callback = function()
                    BookshelfSelection.setMode(plugin, false)
                    callbacks.replace(route or ShellRoutes.bookshelf())
                end,
            },
            {
                key = "select_all",
                icon = selection.all_selected and "square-check" or "square",
                enabled = #records > 0,
                callback = function()
                    BookshelfSelection.setAll(plugin, records, not selection.all_selected)
                    callbacks.replace(route or ShellRoutes.bookshelf())
                end,
                hold_callback = function()
                    BookshelfSelection.setAll(plugin, records, true)
                    callbacks.replace(route or ShellRoutes.bookshelf())
                end,
            },
        }
    end
    return {
        {
            key = "refresh_bookshelf",
            icon = "rotate-cw",
            enabled = #records > 0,
            callback = function()
                local current_records = plugin and plugin.app
                    and plugin.app:getBookshelfStore():list() or {}
                Dialog.confirm(
                    string.format(_("Refresh %d books?"), #current_records),
                    _("Refresh"),
                    function()
                        RefreshFlow.refreshBookshelf(plugin, current_records, {
                            on_done = function()
                                callbacks.replace(route or ShellRoutes.bookshelf())
                            end,
                        })
                    end
                )
            end,
        },
        {
            key = "select",
            icon = "square",
            enabled = #records > 0,
            callback = function()
                BookshelfSelection.setMode(plugin, true)
                callbacks.replace(route or ShellRoutes.bookshelf())
            end,
            hold_callback = function()
                BookshelfSelection.setMode(plugin, true)
                BookshelfSelection.setAll(plugin, records, true)
                callbacks.replace(route or ShellRoutes.bookshelf())
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
            text = _("Continue reading"),
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
            text = summary.paused and _("Resume downloads") or _("Pause"),
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

local function detailRouteWithPage(route, page)
    return detailFlow().withPage(route, page)
end

local function detailActions(plugin, route, shell_widget, callbacks)
    local info = shell_widget and shell_widget.detail_page_info or {}
    local store = plugin and plugin.app and plugin.app:getBookshelfStore()
    local in_bookshelf = store and store:has(route.source, route.book)
    return {
        {
            key = "previous",
            text = _("Previous page"),
            icon = "arrow-left",
            enabled = info.has_previous == true,
            callback = function()
                callbacks.replace(detailRouteWithPage(route, (route.detail_page or 1) - 1))
            end,
        },
        {
            key = "next",
            text = _("Next page"),
            icon = "arrow-right",
            enabled = info.has_next == true,
            callback = function()
                callbacks.replace(detailRouteWithPage(route, (route.detail_page or 1) + 1))
            end,
        },
        {
            key = "chapters",
            text = _("Chapters"),
            icon = "list",
            enabled = route.loading ~= true,
            callback = function()
                local ChaptersFlow = require("novel.ui.chapters.flow")
                ChaptersFlow.show(plugin, route.source, route.book, {
                    tab = route.tab,
                })
            end,
        },
        {
            key = "bookshelf",
            text = in_bookshelf and _("Remove") or _("Add to bookshelf"),
            icon = in_bookshelf and "book-check" or "book",
            enabled = store ~= nil and route.loading ~= true,
            callback = function()
                if in_bookshelf then
                    if BookshelfLifecycle.remove(plugin, route.source, route.book) then
                        callbacks.replace(detailFlow().withBook(route, route.book))
                        Dialog.message(_("Removed from bookshelf."))
                    else
                        Dialog.message(Dialog.failureMessage())
                    end
                    return
                end
                local record, err = store:add(route.source, route.book)
                if record then
                    callbacks.replace(detailFlow().withBook(route, record.book or route.book))
                    Dialog.message(_("Added to bookshelf."))
                else
                    Dialog.message(Dialog.failureMessage(err))
                end
            end,
        },
        backAction(callbacks),
    }
end

local function detailTopActions(route)
    local actions = {}
    if #(route.unsupported or {}) > 0 then
        actions[#actions + 1] = {
            key = "unsupported",
            icon = "funnel",
            callback = function()
                Dialog.showUnsupported(route.unsupported)
            end,
        }
    end
    return actions
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
    if route and route.key == "detail" then
        return detailActions(plugin, route, shell_widget, callbacks)
    end
    if route and route.key == "search_results" then
        return searchResultsActions(plugin, route, callbacks)
    end
    return listActions(plugin, route, callbacks)
end

function ShellActions.top(plugin, route, callbacks)
    if route and route.key == "bookshelf" then
        return bookshelfTopActions(plugin, route, callbacks)
    end
    if route and route.key == "chapters" and route.manifest then
        return chapterTopActions(plugin, route, callbacks)
    end
    if route and route.key == "detail" then
        return detailTopActions(route)
    end
    if route and route.key == "downloads" then
        return downloadTopActions(plugin)
    end
    return {}
end

return ShellActions
