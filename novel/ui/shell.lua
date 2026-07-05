local _ = require("novel.i18n")
local Dialog = require("novel.ui.widget.dialog")
local HomeShell = require("novel.ui.widget.homeshell")
local ShellPages = require("novel.ui.shellpages")
local ShellRoutes = require("novel.ui.shellroutes")
local ShellSession = require("novel.ui.shellsession")
local UIManager = require("ui/uimanager")

local Shell = {}

local function tabs(plugin)
    return {
        {
            key = "bookshelf",
            text = _("Bookshelf"),
            icon = "bookshelf",
            callback = function()
                Shell.showTab(plugin, "bookshelf")
            end,
        },
        {
            key = "discover",
            text = _("Discover"),
            icon = "discover",
            callback = function()
                Shell.showTab(plugin, "discover")
            end,
        },
        {
            key = "sources",
            text = _("Sources"),
            icon = "sources",
            callback = function()
                Shell.showTab(plugin, "sources")
            end,
        },
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
    UIManager:nextTick(function()
        if plugin and plugin.app then
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
    local home = HomeShell:new{
        title = ShellRoutes.title(page),
        subtitle = ShellRoutes.subtitle(page),
        active_tab = ShellSession.activeTab(plugin),
        tabs = tabs(plugin),
        left_icon = ShellRoutes.isTopLevel(page) and nil or "back.top",
        left_callback = ShellRoutes.isTopLevel(page) and nil or function()
            Shell.pop(plugin)
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
    ShellSession.resetStack(plugin)
    Dialog.closeWidget(plugin, "novel_home")
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

function Shell.replace(plugin, route)
    if route and route.tab then
        ShellSession.setActiveTab(plugin, route.tab)
    end
    ShellSession.replace(plugin, route)
    scheduleRender(plugin)
end

function Shell.pop(plugin)
    ShellSession.pop(plugin)
    scheduleRender(plugin)
end

function Shell.currentRoute(plugin)
    return ShellSession.currentRoute(plugin)
end

return Shell
