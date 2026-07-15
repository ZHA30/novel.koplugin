local DetailVisits = require("novel.ui.detail.detailvisits")
local Dialog = require("novel.ui.widget.dialog")
local NetworkMgr = require("ui/network/manager")
local ShellRoutes = require("novel.ui.shellroutes")
local Trapper = require("ui/trapper")

local DetailFlow = {}

local function invalidate(plugin)
    plugin.detail_request_id = (plugin.detail_request_id or 0) + 1
end

local function detailText(book)
    book = book or {}
    return book.intro or ""
end

local function copyTable(value)
    local copy = {}
    for key, item in pairs(value or {}) do
        copy[key] = item
    end
    return copy
end

local function hasDetailText(book)
    return tostring(detailText(book)):match("%S") ~= nil
end

local function persistBookshelfBook(plugin, source, book)
    if not plugin or not plugin.app or type(book) ~= "table" then
        return
    end
    plugin.app:getBookshelfStore():updateExisting(source, book)
end

local function routeFor(source, book, text, options)
    options = options or {}
    return ShellRoutes.detail{
        tab = options.tab,
        source = source,
        book = book,
        text = text,
        unsupported = options.unsupported,
        loading = options.loading,
        error = options.error,
        detail_page = options.detail_page,
    }
end

local function sameBook(route, source, book)
    return route and route.key == "detail" and route.source == source
        and route.book and book and route.book.bookUrl == book.bookUrl
end

local function shell()
    return require("novel.ui.shell")
end

local function showRoute(plugin, route, replace)
    if replace then
        shell().replaceNow(plugin, route)
    else
        shell().pushNow(plugin, route)
    end
end

local function showResolvedDetail(plugin, source, result, detail_text, options)
    local visited_book = result.book or {}
    persistBookshelfBook(plugin, source, visited_book)
    DetailVisits.markVisited(plugin, source, visited_book)
    if options and type(options.on_visited) == "function" then
        options.on_visited(visited_book)
    end

    showRoute(plugin, routeFor(source, visited_book, detail_text or detailText(visited_book), {
        tab = options and options.tab,
        unsupported = result.unsupported,
    }), true)
end

local function fallbackDetailText(book, reason)
    if hasDetailText(book) then
        return detailText(book)
    end
    return Dialog.failureMessage(reason)
end

local function showFallbackDetail(plugin, source, book, reason, options)
    options = options or {}
    local fallback_book = copyTable(book)
    options.fallback_detail_text = fallbackDetailText(fallback_book, reason)
    local fallback_result = {
        ok = true,
        book = fallback_book,
        unsupported = type(reason) == "table" and reason.unsupported or nil,
    }
    showResolvedDetail(plugin, source, fallback_result,
        options.fallback_detail_text, options)
end

function DetailFlow.close(plugin)
    invalidate(plugin)
end

function DetailFlow.showLoaded(plugin, source, result, options)
    if not result or not result.ok then
        showFallbackDetail(plugin, source,
            (options and options.fallback_book) or (result and result.book) or {},
            result, options)
        return
    end
    if hasDetailText(result.book) and options then
        options.fallback_detail_text = nil
    end
    showResolvedDetail(plugin, source, result,
        options and options.fallback_detail_text or nil, options)
end

function DetailFlow.withPage(route, page)
    return routeFor(route.source, route.book, route.text, {
        tab = route.tab,
        unsupported = route.unsupported,
        loading = route.loading,
        error = route.error,
        detail_page = math.max(1, tonumber(page) or 1),
    })
end

function DetailFlow.withBook(route, book)
    return routeFor(route.source, book, route.text, {
        tab = route.tab,
        unsupported = route.unsupported,
        loading = route.loading,
        error = route.error,
        detail_page = route.detail_page,
    })
end

function DetailFlow.show(plugin, source, book, options)
    if not plugin.app then
        return
    end
    book = book or {}
    options = options or {}
    options.fallback_book = options.fallback_book or book
    local current = shell().currentRoute(plugin)
    local replace = sameBook(current, source, book)
    showRoute(plugin, routeFor(source, book, detailText(book), {
        tab = options.tab,
        loading = true,
    }), replace)
    local has_info_html = book.infoHtml ~= nil and book.infoHtml ~= ""
    if not has_info_html and NetworkMgr:willRerunWhenOnline(function()
        DetailFlow.show(plugin, source, book, options)
    end) then
        showFallbackDetail(plugin, source, book, nil, options)
        return
    end

    invalidate(plugin)
    local request_id = plugin.detail_request_id

    Trapper:wrap(function()
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookInfo = require("novel.catalog.reading.bookinfo")
            return BookInfo.run(source, book, {
                settings = settings,
            })
        end)

        if not plugin.app or plugin.detail_request_id ~= request_id
            or not sameBook(shell().currentRoute(plugin), source, book) then
            return
        end
        if not completed then
            showFallbackDetail(plugin, source,
                options.fallback_book or book, Dialog.canceledMessage(), options)
            return
        end
        DetailFlow.showLoaded(plugin, source, result, options)
    end)
end

return DetailFlow
