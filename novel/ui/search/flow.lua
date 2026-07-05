local _ = require("novel.i18n")
local Dialog = require("novel.ui.widget.dialog")
local InputDialog = require("ui/widget/inputdialog")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local ShellRoutes = require("novel.ui.shellroutes")
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

function SearchFlow.showResults(plugin, source, keyword, result, options)
    options = options or {}
    if not result or not result.ok then
        Shell.replace(plugin, ShellRoutes.searchResults{
            tab = options.tab or "discover",
            source = source,
            source_name = SearchSupport.sourceTitle(source),
            keyword = keyword,
            error = _("Search failed: ")
                .. tostring(Dialog.errorText(result, _("Search failed."))),
        })
        return
    end

    local route = ShellRoutes.searchResults{
        tab = options.tab or "discover",
        source = source,
        source_name = SearchSupport.sourceTitle(source),
        keyword = keyword,
        books = result.books or {},
        unsupported = result.unsupported or {},
    }
    local current = Shell.currentRoute(plugin)
    if SearchSupport.sameResultRoute(current, source, keyword) then
        Shell.replace(plugin, route)
    else
        Shell.push(plugin, route)
    end
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

    local loading_route = ShellRoutes.searchResults{
        tab = options.tab or "discover",
        source = source,
        source_name = SearchSupport.sourceTitle(source),
        keyword = keyword,
        loading = true,
    }
    local current = Shell.currentRoute(plugin)
    if SearchSupport.sameResultRoute(current, source, keyword) then
        Shell.replace(plugin, loading_route)
    else
        Shell.push(plugin, loading_route)
    end

    invalidate(plugin)
    local request_id = plugin.search_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "search_loading")
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SearchService = require("novel.catalog.listing.searchservice")
            return SearchService.run(source, keyword, {
                page = 1,
                settings = settings,
            })
        end, loading_widget)
        Loading.close(plugin, "search_loading", loading_widget)

        if not plugin.app or plugin.search_request_id ~= request_id then
            return
        end
        if not completed then
            Shell.replace(plugin, ShellRoutes.searchResults{
                tab = options.tab or "discover",
                source = source,
                source_name = SearchSupport.sourceTitle(source),
                keyword = keyword,
                error = _("Search canceled."),
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
