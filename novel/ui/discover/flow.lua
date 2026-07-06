local _ = require("novel.i18n")
local DiscoverResultSet = require("novel.ui.discover.resultset")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local DiscoverService = require("novel.catalog.listing.discoverservice")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local ShellRoutes = require("novel.ui.shellroutes")
local Shell = require("novel.ui.shell")
local Trapper = require("ui/trapper")

local DiscoverFlow = {}

local function invalidate(plugin)
    plugin.discover_request_id = (plugin.discover_request_id or 0) + 1
end

local function sourceTitle(source)
    return DiscoverResultSet.sourceTitle(source)
end

function DiscoverFlow.close(plugin)
    invalidate(plugin)
    Loading.close(plugin, "discover_loading")
    DetailFlow.close(plugin)
end

local function currentResultsRoute(plugin)
    local route = Shell.currentRoute(plugin)
    if route and route.key == "discover_results" then
        return route
    end
    return nil
end

local function resultRoute(source, group, page, result, options)
    options = options or {}
    return ShellRoutes.discoverResults{
        tab = options.tab or "discover",
        source = source,
        source_name = sourceTitle(source),
        group = group,
        books = result and result.books or {},
        unsupported = result and result.unsupported or {},
        first_page = options.first_page or page,
        current_page = page,
        no_more_source_pages = not DiscoverService.canRequestNextPage(source, group, page),
        loading = options.loading == true,
        loading_more = options.loading_more == true,
        error = options.error,
    }
end

function DiscoverFlow.loadNextPage(plugin)
    local route = currentResultsRoute(plugin)
    if not route then
        return false
    end
    return DiscoverFlow.loadPage(plugin, (tonumber(route.current_page) or 1) + 1)
end

function DiscoverFlow.loadPage(plugin, page)
    if not plugin.app then
        return false
    end

    local route = currentResultsRoute(plugin)
    if not route or route.loading or route.loading_more then
        return false
    end

    local source = route.source
    local group = route.group
    local current_page = tonumber(route.current_page) or 1
    page = tonumber(page) or current_page
    if not source or not group then
        return false
    end
    if page < 1 or page == current_page then
        return false
    end
    if page > current_page
        and not DiscoverService.canRequestNextPage(source, group, current_page) then
        Shell.replace(plugin, resultRoute(source, group, current_page, {
            books = route.books,
            unsupported = route.unsupported,
        }, {
            first_page = route.first_page,
            no_more_source_pages = true,
        }))
        return false
    end

    if NetworkMgr:willRerunWhenOnline(function()
        DiscoverFlow.loadPage(plugin, page)
    end) then
        return false
    end

    Shell.replace(plugin, ShellRoutes.discoverResults{
        tab = route.tab,
        source = source,
        source_name = route.source_name,
        group = group,
        first_page = page,
        current_page = page,
        loading = true,
    })

    invalidate(plugin)
    local request_id = plugin.discover_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "discover_loading")
        local completed, encoded_result = Trapper:dismissableRunInSubprocess(function()
            return DiscoverService.runEncoded(source, group, page)
        end, loading_widget, true)
        Loading.close(plugin, "discover_loading", loading_widget)

        local current = currentResultsRoute(plugin)
        if not plugin.app
            or plugin.discover_request_id ~= request_id
            or not DiscoverResultSet.sameRoute(current, source, group) then
            return
        end

        if not completed then
            Shell.replace(plugin, ShellRoutes.discoverResults{
                tab = current.tab,
                source = current.source,
                source_name = current.source_name,
                group = current.group,
                first_page = page,
                current_page = page,
                error = _("Discover canceled."),
            })
            return
        end

        local result = DiscoverService.decodeResult(encoded_result)
        if not result then
            result = DiscoverService.run(source, group, page)
        end
        if not result or not result.ok then
            Shell.replace(plugin, ShellRoutes.discoverResults{
                tab = current.tab,
                source = current.source,
                source_name = current.source_name,
                group = current.group,
                first_page = page,
                current_page = page,
                error = _("Discover failed: ") .. Dialog.errorText(result),
            })
            return
        end

        Shell.replace(plugin, ShellRoutes.discoverResults{
            tab = current.tab,
            source = current.source,
            source_name = current.source_name,
            group = current.group,
            books = result.books or {},
            unsupported = result.unsupported or {},
            first_page = page,
            current_page = page,
            no_more_source_pages = #(result.books or {}) == 0
                or not DiscoverService.canRequestNextPage(source, group, page),
        })
    end)
    return true
end

function DiscoverFlow.showResults(plugin, source, group, page, result, options)
    options = options or {}
    if not result or not result.ok then
        Shell.replace(plugin, ShellRoutes.discoverResults{
            tab = options.tab or "discover",
            source = source,
            source_name = sourceTitle(source),
            group = group,
            first_page = page,
            current_page = page,
            error = _("Discover failed: ") .. Dialog.errorText(result),
        })
        return
    end

    local route = resultRoute(source, group, page, result, {
        tab = options.tab or "discover",
    })
    local current = currentResultsRoute(plugin)
    if DiscoverResultSet.sameRoute(current, source, group) then
        Shell.replace(plugin, route)
    else
        Shell.push(plugin, route)
    end
end

function DiscoverFlow.start(plugin, source, group, page, options)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    options = options or {}
    page = page or 1
    if NetworkMgr:willRerunWhenOnline(function()
        DiscoverFlow.start(plugin, source, group, page, options)
    end) then
        return
    end

    local loading_route = ShellRoutes.discoverResults{
        tab = options.tab or "discover",
        source = source,
        source_name = sourceTitle(source),
        group = group,
        first_page = page,
        current_page = page,
        loading = true,
    }
    local current = currentResultsRoute(plugin)
    if DiscoverResultSet.sameRoute(current, source, group) then
        Shell.replace(plugin, loading_route)
    else
        Shell.push(plugin, loading_route)
    end

    invalidate(plugin)
    local request_id = plugin.discover_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "discover_loading")
        local completed, encoded_result = Trapper:dismissableRunInSubprocess(function()
            return DiscoverService.runEncoded(source, group, page)
        end, loading_widget, true)
        Loading.close(plugin, "discover_loading", loading_widget)

        if not plugin.app or plugin.discover_request_id ~= request_id then
            return
        end
        if not completed then
            Shell.replace(plugin, ShellRoutes.discoverResults{
                tab = options.tab or "discover",
                source = source,
                source_name = sourceTitle(source),
                group = group,
                first_page = page,
                current_page = page,
                error = _("Discover canceled."),
            })
            return
        end
        local result = DiscoverService.decodeResult(encoded_result)
        if not result then
            result = DiscoverService.run(source, group, page)
        end
        DiscoverFlow.showResults(plugin, source, group, page, result, options)
    end)
end

function DiscoverFlow.show(plugin)
    Shell.show(plugin, {
        active_tab = "discover",
    })
end

return DiscoverFlow
