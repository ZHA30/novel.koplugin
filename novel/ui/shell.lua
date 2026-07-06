local _ = require("novel.i18n")
local ChapterListing = require("novel.ui.chapters.listing")
local Dialog = require("novel.ui.widget.dialog")
local HomeShell = require("novel.ui.widget.homeshell")
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
            dim = active_tab ~= "bookshelf",
            callback = function()
                Shell.showTab(plugin, "bookshelf")
            end,
        },
        {
            key = "discover",
            text = _("Discover"),
            icon = "discover",
            active = active_tab == "discover",
            dim = active_tab ~= "discover",
            callback = function()
                Shell.showTab(plugin, "discover")
            end,
        },
        {
            key = "sources",
            text = _("Sources"),
            icon = "sources",
            active = active_tab == "sources",
            dim = active_tab ~= "sources",
            callback = function()
                Shell.showTab(plugin, "sources")
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
    return route
        and route.key == "discover_results"
        and route.source ~= nil
        and route.group ~= nil
        and route.loading ~= true
        and route.loading_more ~= true
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

local function replaceChapterState(plugin, route, filter, sort)
    local manifest = route and route.manifest
    if not manifest then
        return
    end
    Shell.replace(plugin, ShellRoutes.chapters{
        tab = route.tab,
        source = route.source or manifest.source,
        book = route.book or manifest.book,
        manifest = manifest,
        filter = filter,
        sort = sort,
    })
end

local function chapterActions(plugin, route)
    local manifest = route and route.manifest
    local filter, sort = ChapterListing.resolveState(plugin, manifest, {
        filter = route and route.filter,
        sort = route and route.sort,
    })
    local unread = filter == ChapterListing.FILTER_UNREAD
    local descending = sort == ChapterListing.SORT_DESCENDING
    return {
        previousAction(plugin, route),
        nextAction(plugin, route),
        {
            key = "filter",
            text = ChapterListing.filterLabel(filter),
            icon = unread and "funnel" or "funnel-x",
            active = unread,
            callback = function()
                local next_filter = unread
                    and ChapterListing.FILTER_ALL
                    or ChapterListing.FILTER_UNREAD
                replaceChapterState(plugin, route, next_filter, sort)
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

local function bottomActions(plugin, route, shell_widget)
    ShellSession.setListInfo(plugin, shell_widget and shell_widget.list_page_info)
    if ShellRoutes.isTopLevel(route) then
        return homeActions(plugin)
    end
    if route and route.key == "chapters" and route.manifest then
        return chapterActions(plugin, route)
    end
    return listActions(plugin, route)
end

local function currentPage(plugin)
    local route = ShellSession.currentRoute(plugin)
    if route then
        return route
    end
    return ShellPages.defaultRouteForTab(ShellSession.activeTab(plugin))
end

local function scheduleRender(plugin)
    UIManager:nextTick(function()
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

local function buildContent(shell, plugin, page)
    return ShellPages.build(shell, plugin, page, Shell)
end

function Shell.show(plugin, options)
    if not plugin or not plugin.app then
        return
    end
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
        content_builder = function(shell_widget)
            return buildContent(shell_widget, plugin, page)
        end,
        close_request_callback = function()
            Shell.close(plugin)
            return true
        end,
    }
    Dialog.showWidget(plugin, "novel_home", home)
end

function Shell.close(plugin)
    plugin.novel_shell_render_pending = nil
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

function Shell.showTab(plugin, active_tab)
    ShellSession.setActiveTab(plugin, active_tab)
    ShellSession.resetStack(plugin)
    scheduleRender(plugin)
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
    scheduleRender(plugin)
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
    local DiscoverFlow = require("novel.ui.discover.flow")
    return DiscoverFlow.loadPage(plugin, (tonumber(route.current_page) or 1) - 1, {
        list_page_anchor = "last",
    })
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
    local DiscoverFlow = require("novel.ui.discover.flow")
    return DiscoverFlow.loadPage(plugin, (tonumber(route.current_page) or 1) + 1, {
        list_page = tonumber(info.current_page) or ShellSession.listPage(plugin),
    })
end

function Shell.currentRoute(plugin)
    return ShellSession.currentRoute(plugin)
end

return Shell
