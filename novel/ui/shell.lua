local ChapterListing = require("novel.ui.chapters.listing")
local Dialog = require("novel.ui.widget.dialog")
local HomeShell = require("novel.ui.widget.homeshell")
local Manifest = require("novel.storage.manifest")
local ShellActions = require("novel.ui.shell.actions")
local ShellPages = require("novel.ui.shellpages")
local ShellRoutes = require("novel.ui.shellroutes")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local Shell = {}

local function actionCallbacks(plugin)
    return {
        show_tab = function(tab)
            Shell.showTab(plugin, tab)
        end,
        close = function()
            Shell.close(plugin)
        end,
        previous_page = function()
            Shell.previousPage(plugin)
        end,
        next_page = function()
            Shell.nextPage(plugin)
        end,
        pop = function()
            Shell.pop(plugin)
        end,
        replace = function(route)
            Shell.replace(plugin, route)
        end,
    }
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
    local callbacks = actionCallbacks(plugin)
    local home = HomeShell:new{
        title = ShellRoutes.title(page),
        active_tab = ShellSession.activeTab(plugin),
        tabs = ShellActions.home(plugin, callbacks),
        list_page = ShellSession.listPage(plugin),
        paginate_lists = not ShellRoutes.isTopLevel(page),
        previous_page_callback = function()
            return Shell.previousPage(plugin)
        end,
        next_page_callback = function()
            return Shell.nextPage(plugin)
        end,
        bottom_actions_builder = function(shell_widget)
            return ShellActions.bottom(plugin, page, shell_widget, callbacks)
        end,
        top_actions_builder = function()
            return ShellActions.top(plugin, page, callbacks)
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
            ShellSession.listInfo(plugin) or {}
        ) then
            route.manifest = Manifest:new():load(book_id) or route.manifest
            return
        end
        local manifest = Manifest:new():load(book_id) or route.manifest
        Shell.replace(
            plugin,
            ShellActions.chapterRoute(route, manifest, route.filter, route.sort)
        )
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
    local info = ShellSession.listInfo(plugin) or {}
    if info.has_previous then
        ShellSession.setListPage(plugin, (tonumber(info.current_page) or 1) - 1)
        scheduleRender(plugin)
        return true
    end
    if not ShellActions.canRemotePreviousPage(route) then
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
    local info = ShellSession.listInfo(plugin) or {}
    if info.has_next then
        ShellSession.setListPage(plugin, (tonumber(info.current_page) or 1) + 1)
        scheduleRender(plugin)
        return true
    end
    if not ShellActions.canRemoteNextPage(route) then
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
