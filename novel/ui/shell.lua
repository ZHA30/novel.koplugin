local _ = require("novel.i18n")
local ChapterCache = require("novel.reader.chaptercache")
local ChapterListing = require("novel.ui.chapters.listing")
local Dialog = require("novel.ui.widget.dialog")
local DownloadQueue = require("novel.reader.downloadqueue")
local HomeShell = require("novel.ui.widget.homeshell")
local Manifest = require("novel.storage.manifest")
local ShellPages = require("novel.ui.shellpages")
local ShellRoutes = require("novel.ui.shellroutes")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local Shell = {}

local function homeActions(plugin)
    local active_tab = ShellSession.activeTab(plugin)
    return {
        {
            key = "bookshelf",
            text = _("Bookshelf"),
            icon = "bookshelf",
            active = active_tab == "bookshelf",
            callback = function()
                Shell.showTab(plugin, "bookshelf")
            end,
        },
        {
            key = "discover",
            text = _("Discover"),
            icon = "discover",
            active = active_tab == "discover",
            callback = function()
                Shell.showTab(plugin, "discover")
            end,
        },
        {
            key = "settings",
            text = _("More"),
            icon = "circle-ellipsis",
            active = active_tab == "settings",
            callback = function()
                Shell.showTab(plugin, "settings")
            end,
        },
        {
            key = "exit",
            text = _("Exit"),
            icon = "log-out",
            callback = function()
                Shell.close(plugin)
            end,
        },
    }
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

local function canRemotePreviousPage(route)
    return canRemotePage(route) and (tonumber(route.current_page) or 1) > 1
end

local function canRemoteNextPage(route)
    return canRemotePage(route) and route.no_more_source_pages ~= true
end

local function listInfo(plugin)
    return ShellSession.listInfo(plugin) or {}
end

local function canPreviousPage(plugin, route)
    local info = listInfo(plugin)
    return info.has_previous == true or canRemotePreviousPage(route)
end

local function canNextPage(plugin, route)
    local info = listInfo(plugin)
    return info.has_next == true or canRemoteNextPage(route)
end

local function previousAction(plugin, route)
    return {
        key = "previous",
        text = _("Previous page"),
        icon = "arrow-left",
        enabled = canPreviousPage(plugin, route),
        callback = function()
            Shell.previousPage(plugin)
        end,
    }
end

local function nextAction(plugin, route)
    return {
        key = "next",
        text = _("Next page"),
        icon = "arrow-right",
        enabled = canNextPage(plugin, route),
        callback = function()
            Shell.nextPage(plugin)
        end,
    }
end

local function backAction(plugin)
    return {
        key = "back",
        text = _("Back"),
        icon = "undo-2",
        callback = function()
            Shell.pop(plugin)
        end,
    }
end

local function chapterRoute(route, manifest, filter, sort)
    return ShellRoutes.chapters{
        tab = route.tab,
        source = route.source or manifest.source,
        book = route.book or manifest.book,
        manifest = manifest,
        filter = filter,
        sort = sort,
    }
end

local function replaceChapterManifest(plugin, route, manifest, filter, sort)
    if not manifest then
        return
    end
    Shell.replace(plugin, chapterRoute(route, manifest, filter, sort))
end

local function replaceChapterState(plugin, route, filter, sort)
    replaceChapterManifest(plugin, route, route and route.manifest, filter, sort)
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

local function markReadState(plugin, route, manifest, filter, sort, positions,
    read)
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
    replaceChapterManifest(plugin, route, updated_manifest, filter, sort)
end

local function finishChapterCacheAction(plugin, route, manifest, filter, sort,
    updated_manifest)
    updated_manifest = updated_manifest or manifest
    ChapterListing.setSelectionMode(plugin, updated_manifest, false)
    replaceChapterManifest(plugin, route, updated_manifest, filter, sort)
end

local function confirmChapterAction(message_template, count, ok_text, callback)
    if count <= 0 then
        return
    end
    Dialog.confirm(string.format(message_template, count), ok_text, callback)
end

local function chapterTopActions(plugin, route)
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
                        ChapterCache.cache(plugin, manifest, cache_positions, {
                            on_done = function(_summary, updated_manifest)
                                finishChapterCacheAction(
                                    plugin,
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
            text = _("Delete cache"),
            icon = "trash-2",
            enabled = #delete_cache_positions > 0,
            callback = function()
                confirmChapterAction(
                    _("Delete cache for %d chapters?"),
                    #delete_cache_positions,
                    _("Delete cache"),
                    function()
                        ChapterCache.delete(plugin, manifest, delete_cache_positions, {
                            on_done = function(_summary, updated_manifest)
                                finishChapterCacheAction(
                                    plugin,
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
                Shell.replace(plugin, route)
            end,
            hold_callback = function()
                ChapterListing.setSelectionMode(plugin, manifest, true)
                ChapterListing.setRowsSelected(
                    plugin,
                    manifest,
                    rows,
                    not selection.all_selected
                )
                Shell.replace(plugin, route)
            end,
        },
    }
end

local function chapterActions(plugin, route)
    local manifest, filter, sort = chapterState(plugin, route)
    local filter_active = ChapterListing.hasActiveFilter(filter)
    local descending = sort == ChapterListing.SORT_DESCENDING
    return {
        previousAction(plugin, route),
        nextAction(plugin, route),
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
                        replaceChapterState(plugin, route, next_filter, sort)
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
                replaceChapterState(plugin, route, filter, next_sort)
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
        backAction(plugin),
    }
end

local function listActions(plugin, route)
    return {
        previousAction(plugin, route),
        nextAction(plugin, route),
        backAction(plugin),
    }
end

local function downloadTopActions(plugin)
    local summary = DownloadQueue.summary(plugin)
    return {
        {
            key = "download_toggle",
            text = summary.paused and _("Resume") or _("Pause"),
            icon = summary.paused and "circle-play" or "square",
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

local function searchResultsActions(plugin, route)
    local actions = {
        previousAction(plugin, route),
        nextAction(plugin, route),
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
        backAction(plugin),
    }
    return actions
end

local function bottomActions(plugin, route, shell_widget)
    ShellSession.setListInfo(plugin, shell_widget and shell_widget.list_page_info)
    if ShellRoutes.isTopLevel(route) then
        return homeActions(plugin)
    end
    if route and route.key == "chapters" and route.manifest then
        return chapterActions(plugin, route)
    end
    if route and route.key == "search_results" then
        return searchResultsActions(plugin, route)
    end
    return listActions(plugin, route)
end

local function topActions(plugin, route)
    if route and route.key == "chapters" and route.manifest then
        return chapterTopActions(plugin, route)
    end
    if route and route.key == "downloads" then
        return downloadTopActions(plugin)
    end
    return {}
end

local function currentPage(plugin)
    local route = ShellSession.currentRoute(plugin)
    if route then
        return route
    end
    return ShellPages.defaultRouteForTab(ShellSession.activeTab(plugin))
end

local function scheduleRender(plugin)
    if not plugin then
        return
    end
    plugin.novel_shell_render_token = (plugin.novel_shell_render_token or 0) + 1
    plugin.novel_shell_render_scheduled = true
    local render_token = plugin.novel_shell_render_token
    UIManager:nextTick(function()
        if plugin.novel_shell_render_token ~= render_token then
            return
        end
        plugin.novel_shell_render_scheduled = nil
        if plugin and plugin.app then
            if plugin.detail_viewer and UIManager:isWidgetShown(plugin.detail_viewer) then
                plugin.novel_shell_render_pending = true
                return
            end
            plugin.novel_shell_render_pending = nil
            Shell.show(plugin)
        end
    end)
end

local function cancelScheduledRender(plugin)
    plugin.novel_shell_render_scheduled = nil
    plugin.novel_shell_render_token = (plugin.novel_shell_render_token or 0) + 1
end

local function buildContent(shell, plugin, page)
    return ShellPages.build(shell, plugin, page, Shell)
end

function Shell.show(plugin, options)
    if not plugin or not plugin.app then
        return
    end
    cancelScheduledRender(plugin)
    options = options or {}
    if options.active_tab then
        ShellSession.setActiveTab(plugin, options.active_tab)
        if options.reset_stack ~= false then
            ShellSession.resetStack(plugin)
        end
    elseif options.reset_stack then
        ShellSession.resetStack(plugin)
    end

    local page = currentPage(plugin)
    ShellSession.setListInfo(plugin, nil)
    local home = HomeShell:new{
        title = ShellRoutes.title(page),
        active_tab = ShellSession.activeTab(plugin),
        tabs = homeActions(plugin),
        list_page = ShellSession.listPage(plugin),
        paginate_lists = not ShellRoutes.isTopLevel(page),
        previous_page_callback = function()
            return Shell.previousPage(plugin)
        end,
        next_page_callback = function()
            return Shell.nextPage(plugin)
        end,
        bottom_actions_builder = function(shell_widget)
            return bottomActions(plugin, page, shell_widget)
        end,
        top_actions_builder = function()
            return topActions(plugin, page)
        end,
        content_builder = function(shell_widget)
            return buildContent(shell_widget, plugin, page)
        end,
        close_request_callback = function()
            Shell.close(plugin)
            return true
        end,
    }
    Dialog.showWidget(plugin, "novel_home", home)
    if options.force_repaint then
        UIManager:forceRePaint()
    end
end

function Shell.close(plugin)
    plugin.novel_shell_render_pending = nil
    cancelScheduledRender(plugin)
    ShellSession.resetStack(plugin)
    Dialog.closeWidget(plugin, "novel_home")
end

function Shell.flushPendingRender(plugin)
    if not plugin or not plugin.novel_shell_render_pending then
        return
    end
    scheduleRender(plugin)
end

function Shell.reshow(plugin)
    scheduleRender(plugin)
end

function Shell.refreshDownloadState(plugin, book_id, position)
    local route = Shell.currentRoute(plugin)
    if route and route.key == "chapters" and route.manifest
        and route.manifest.book_id == book_id then
        if position and not ChapterListing.isPositionVisible(
            route.manifest,
            route.filter,
            route.sort,
            position,
            listInfo(plugin)
        ) then
            route.manifest = Manifest:new():load(book_id) or route.manifest
            return
        end
        local manifest = Manifest:new():load(book_id) or route.manifest
        Shell.replace(plugin, chapterRoute(route, manifest, route.filter, route.sort))
        return
    end
    if route and (route.key == "downloads" or route.key == "settings") then
        scheduleRender(plugin)
    end
end

function Shell.showTab(plugin, active_tab)
    ShellSession.setActiveTab(plugin, active_tab)
    ShellSession.resetStack(plugin)
    cancelScheduledRender(plugin)
    Shell.show(plugin)
end

function Shell.push(plugin, route)
    if route and route.tab then
        ShellSession.setActiveTab(plugin, route.tab)
    end
    ShellSession.push(plugin, route)
    scheduleRender(plugin)
end

function Shell.pushNow(plugin, route)
    if route and route.tab then
        ShellSession.setActiveTab(plugin, route.tab)
    end
    ShellSession.push(plugin, route)
    Shell.show(plugin)
end

function Shell.replace(plugin, route)
    if route and route.tab then
        ShellSession.setActiveTab(plugin, route.tab)
    end
    ShellSession.replace(plugin, route)
    scheduleRender(plugin)
end

function Shell.replaceNow(plugin, route)
    if route and route.tab then
        ShellSession.setActiveTab(plugin, route.tab)
    end
    ShellSession.replace(plugin, route)
    Shell.show(plugin)
end

function Shell.pop(plugin)
    ShellSession.pop(plugin)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 and plugin and plugin.ui and plugin.ui.document then
        Shell.close(plugin)
    else
        scheduleRender(plugin)
    end
end

function Shell.previousPage(plugin)
    local route = Shell.currentRoute(plugin)
    local info = listInfo(plugin)
    if info.has_previous then
        ShellSession.setListPage(plugin, (tonumber(info.current_page) or 1) - 1)
        scheduleRender(plugin)
        return true
    end
    if not canRemotePreviousPage(route) then
        return false
    end
    local page = (tonumber(route.current_page) or 1) - 1
    local options = {
        list_page_anchor = "last",
    }
    if route.key == "search_results" then
        local SearchFlow = require("novel.ui.search.flow")
        return SearchFlow.loadPage(plugin, page, options)
    end
    local DiscoverFlow = require("novel.ui.discover.flow")
    return DiscoverFlow.loadPage(plugin, page, options)
end

function Shell.nextPage(plugin)
    local route = Shell.currentRoute(plugin)
    local info = listInfo(plugin)
    if info.has_next then
        ShellSession.setListPage(plugin, (tonumber(info.current_page) or 1) + 1)
        scheduleRender(plugin)
        return true
    end
    if not canRemoteNextPage(route) then
        return false
    end
    local page = (tonumber(route.current_page) or 1) + 1
    local options = {
        list_page = tonumber(info.current_page) or ShellSession.listPage(plugin),
    }
    if route.key == "search_results" then
        local SearchFlow = require("novel.ui.search.flow")
        return SearchFlow.loadPage(plugin, page, options)
    end
    local DiscoverFlow = require("novel.ui.discover.flow")
    return DiscoverFlow.loadPage(plugin, page, options)
end

function Shell.currentRoute(plugin)
    return ShellSession.currentRoute(plugin)
end

return Shell
