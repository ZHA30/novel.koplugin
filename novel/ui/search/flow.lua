local _ = require("novel.i18n")
local Dialog = require("novel.ui.widget.dialog")
local InputDialog = require("ui/widget/inputdialog")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local ResultSet = require("novel.ui.resultset")
local ShellRoutes = require("novel.ui.shellroutes")
local SearchService = require("novel.catalog.listing.searchservice")
local SearchSupport = require("novel.ui.search.searchsupport")
local Shell = require("novel.ui.shell")
local Trapper = require("ui/trapper")

local SearchFlow = {}

local function invalidate(plugin)
    plugin.search_request_id = (plugin.search_request_id or 0) + 1
end

function SearchFlow.close(plugin)
    invalidate(plugin)
    Loading.close(plugin, "search_loading")
    Dialog.closeKeys(plugin, {
        "search_input_dialog",
    })
end

local function currentResultsRoute(plugin)
    local route = Shell.currentRoute(plugin)
    if route and route.key == "search_results" then
        return route
    end
    return nil
end

local function resultRoute(source, keyword, page, result, options)
    options = options or {}
    return ShellRoutes.searchResults{
        tab = options.tab or "discover",
        source = source,
        source_name = SearchSupport.sourceTitle(source),
        keyword = keyword,
        books = result and result.books or {},
        unsupported = result and result.unsupported or {},
        first_page = options.first_page or page,
        current_page = page,
        no_more_source_pages = options.no_more_source_pages == true
            or not SearchService.canRequestNextPage(source, keyword, page),
        loading = options.loading == true,
        loading_more = options.loading_more == true,
        error = options.error,
        list_page = options.list_page,
        list_page_anchor = options.list_page_anchor,
        list_item_anchor = options.list_item_anchor,
    }
end

local function showResultRoute(plugin, source, keyword, route)
    local current = Shell.currentRoute(plugin)
    if SearchSupport.sameResultRoute(current, source, keyword) then
        Shell.replace(plugin, route)
    else
        Shell.push(plugin, route)
    end
end

function SearchFlow.showResults(plugin, source, keyword, result, options)
    options = options or {}
    local page = tonumber(options.page) or 1
    if not result or not result.ok then
        showResultRoute(plugin, source, keyword, ShellRoutes.searchResults{
            tab = options.tab or "discover",
            source = source,
            source_name = SearchSupport.sourceTitle(source),
            keyword = keyword,
            first_page = page,
            current_page = page,
            no_more_source_pages = true,
            error = Dialog.failureMessage(result),
        })
        return
    end

    local route = resultRoute(source, keyword, page, result, {
        tab = options.tab or "discover",
    })
    showResultRoute(plugin, source, keyword, route)
end

function SearchFlow.loadNextPage(plugin)
    local route = currentResultsRoute(plugin)
    if not route then
        return false
    end
    return SearchFlow.loadPage(plugin, (tonumber(route.current_page) or 1) + 1)
end

function SearchFlow.loadPage(plugin, page, options)
    if not plugin.app then
        return false
    end
    options = options or {}

    local route = currentResultsRoute(plugin)
    if not route or route.loading or route.loading_more then
        return false
    end

    local source = route.source
    local keyword = route.keyword
    local current_page = tonumber(route.current_page) or 1
    page = tonumber(page) or current_page
    local append_next_page = page > current_page
    local current_books = route.books or {}
    local current_unsupported = route.unsupported or {}
    local first_page = tonumber(route.first_page) or current_page
    if not source or keyword == nil then
        return false
    end
    if page < 1 or page == current_page then
        return false
    end
    if page > current_page
        and not SearchService.canRequestNextPage(source, keyword, current_page) then
        Shell.replace(plugin, resultRoute(source, keyword, current_page, {
            books = route.books,
            unsupported = route.unsupported,
        }, {
            tab = route.tab,
            first_page = route.first_page,
            no_more_source_pages = true,
            list_page = route.list_page,
        }))
        return false
    end

    if NetworkMgr:willRerunWhenOnline(function()
        SearchFlow.loadPage(plugin, page, options)
    end) then
        return false
    end

    if append_next_page then
        route.loading_more = true
    end

    invalidate(plugin)
    local request_id = plugin.search_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "search_loading")
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local WorkerSearchService = require("novel.catalog.listing.searchservice")
            return WorkerSearchService.run(source, keyword, {
                page = page,
                settings = settings,
            })
        end, loading_widget)
        Loading.close(plugin, "search_loading", loading_widget)

        local current = currentResultsRoute(plugin)
        if not plugin.app
            or plugin.search_request_id ~= request_id
            or not SearchSupport.sameResultRoute(current, source, keyword) then
            return
        end
        if not completed then
            Shell.replace(plugin, ShellRoutes.searchResults{
                tab = current.tab,
                source = current.source,
                source_name = current.source_name,
                keyword = current.keyword,
                books = current.books or current_books,
                unsupported = current.unsupported or current_unsupported,
                first_page = first_page,
                current_page = current_page,
                no_more_source_pages = current.no_more_source_pages == true,
                error = Dialog.canceledMessage(),
            })
            return
        end

        if not result or not result.ok then
            Shell.replace(plugin, ShellRoutes.searchResults{
                tab = current.tab,
                source = current.source,
                source_name = current.source_name,
                keyword = current.keyword,
                books = current.books or current_books,
                unsupported = current.unsupported or current_unsupported,
                first_page = first_page,
                current_page = current_page,
                no_more_source_pages = current.no_more_source_pages == true,
                error = Dialog.failureMessage(result),
            })
            return
        end

        if append_next_page then
            local merged_books, appended = ResultSet.mergeBooks(
                current.books or current_books,
                result.books or {}
            )
            Shell.replace(plugin, ShellRoutes.searchResults{
                tab = current.tab,
                source = current.source,
                source_name = current.source_name,
                keyword = current.keyword,
                books = merged_books,
                unsupported = ResultSet.appendUnsupported(
                    current.unsupported or current_unsupported,
                    result.unsupported
                ),
                first_page = first_page,
                current_page = page,
                no_more_source_pages = appended == 0
                    or not SearchService.canRequestNextPage(source, keyword, page),
                list_page = options.list_page,
                list_page_anchor = options.list_page_anchor,
                list_item_anchor = options.list_item_anchor,
            })
            return
        end

        Shell.replace(plugin, ShellRoutes.searchResults{
            tab = current.tab,
            source = current.source,
            source_name = current.source_name,
            keyword = current.keyword,
            books = result.books or {},
            unsupported = result.unsupported or {},
            first_page = page,
            current_page = page,
            no_more_source_pages = #(result.books or {}) == 0
                or not SearchService.canRequestNextPage(source, keyword, page),
            list_page = options.list_page,
            list_page_anchor = options.list_page_anchor,
            list_item_anchor = options.list_item_anchor,
        })
    end)
    return true
end

function SearchFlow.start(plugin, source, keyword, options)
    if not plugin.app then
        return
    end
    options = options or {}
    if NetworkMgr:willRerunWhenOnline(function()
        SearchFlow.start(plugin, source, keyword, options)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.search_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "search_loading")
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local WorkerSearchService = require("novel.catalog.listing.searchservice")
            return WorkerSearchService.run(source, keyword, {
                page = 1,
                settings = settings,
            })
        end, loading_widget)
        Loading.close(plugin, "search_loading", loading_widget)

        if not plugin.app or plugin.search_request_id ~= request_id then
            return
        end
        if not completed then
            showResultRoute(plugin, source, keyword, ShellRoutes.searchResults{
                tab = options.tab or "discover",
                source = source,
                source_name = SearchSupport.sourceTitle(source),
                keyword = keyword,
                no_more_source_pages = true,
                error = Dialog.canceledMessage(),
            })
            return
        end
        SearchFlow.showResults(plugin, source, keyword, result, options)
    end)
end

function SearchFlow.showInput(plugin, source, previous_keyword, options)
    Dialog.closeWidget(plugin, "search_input_dialog")
    options = options or {}

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Search"),
        input = previous_keyword or "",
        input_hint = _("Keyword"),
        description = SearchSupport.sourceTitle(source),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    Dialog.closeWidget(plugin, "search_input_dialog")
                end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    local keyword = SearchSupport.trim(input_dialog:getInputText())
                    if keyword == "" then
                        return
                    end
                    Dialog.closeWidget(plugin, "search_input_dialog")
                    SearchFlow.start(plugin, source, keyword, {
                        tab = options.tab or "discover",
                    })
                end,
            },
        }},
    }
    Dialog.showWidget(plugin, "search_input_dialog", input_dialog)
    input_dialog:onShowKeyboard()
end

function SearchFlow.show(plugin, options)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    options = options or {}

    local sources = SearchSupport.searchableSources(plugin)
    if #sources == 0 then
        Dialog.message(_("No enabled searchable sources."))
        return
    end
    if #sources == 1 then
        SearchFlow.showInput(plugin, sources[1], nil, {
            tab = options.tab or "discover",
        })
        return
    end

    Shell.push(plugin, ShellRoutes.searchSources{
        tab = options.tab or "discover",
        sources = sources,
    })
end

return SearchFlow
