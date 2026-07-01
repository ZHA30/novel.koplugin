local _ = require("novel.i18n")
local Detail = require("novel.ui.detail")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Search = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function sourceTitle(source)
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl
end

local function sourceSubtitle(source)
    local parts = {}
    if source.bookSourceGroup and source.bookSourceGroup ~= "" then
        table.insert(parts, source.bookSourceGroup)
    end
    if source.concurrentRate and source.concurrentRate ~= "" then
        table.insert(parts, _("Rate: ") .. source.concurrentRate)
    end
    return table.concat(parts, " / ")
end

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function invalidate(plugin)
    plugin.search_request_id = (plugin.search_request_id or 0) + 1
end

local function isSearchable(source)
    return source.enabled ~= false
        and source.searchUrl ~= nil
        and source.searchUrl ~= ""
        and type(source.ruleSearch) == "table"
end

local function searchableSources(plugin)
    local sources = plugin.app:getSourceRepo():list()
    local searchable = {}
    for source_index = 1, #sources do
        local source = sources[source_index]
        if isSearchable(source) then
            table.insert(searchable, source)
        end
    end
    return searchable
end

local function showError(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

function Search.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "search_source_menu")
    closeWidget(plugin, "search_input_dialog")
    closeWidget(plugin, "search_results_menu")
    Detail.close(plugin)
end

local function showUnsupported(result)
    local lines = {}
    for item_index = 1, #(result.unsupported or {}) do
        local item = result.unsupported[item_index]
        table.insert(lines, table.concat({
            item.source or "",
            item.field or "",
            item.kind or "",
            item.snippet or "",
        }, "\n"))
    end
    UIManager:show(InfoMessage:new{
        text = table.concat(lines, "\n\n"),
    })
end

local function resultActions(plugin, source, book)
    return {
        {
            text = _("Details"),
            callback = function()
                Detail.show(plugin, source, book)
            end,
        },
    }
end

local function buildResultItems(plugin, source, keyword, result)
    local item_table = {
        {
            text = _("Search again"),
            callback = function()
                closeWidget(plugin, "search_results_menu")
                Search.showInput(plugin, source, keyword)
            end,
        },
    }

    if result.unsupported and #result.unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#result.unsupported),
            callback = function()
                showUnsupported(result)
            end,
            separator = true,
        })
    else
        item_table[1].separator = true
    end

    if not result.books or #result.books == 0 then
        table.insert(item_table, {
            text = _("No results."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for book_index = 1, #result.books do
        local book = result.books[book_index]
        table.insert(item_table, {
            text = book.name,
            mandatory = book.author ~= "" and book.author or nil,
            sub_item_table = resultActions(plugin, source, book),
        })
    end
    return item_table
end

function Search.showResults(plugin, source, keyword, result)
    closeWidget(plugin, "search_results_menu")

    if not result or not result.ok then
        local error_message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Search failed.")
        showError(_("Search failed: ") .. tostring(error_message))
        return
    end

    local results_menu
    results_menu = Menu:new{
        title = _("Search") .. ": " .. keyword,
        item_table = buildResultItems(plugin, source, keyword, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(results_menu)
            if plugin.search_results_menu == results_menu then
                plugin.search_results_menu = nil
            end
        end,
    }
    plugin.search_results_menu = results_menu
    UIManager:show(results_menu)
end

function Search.start(plugin, source, keyword)
    if not plugin.app then
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        Search.start(plugin, source, keyword)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.search_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SearchService = require("novel.service.search")
            return SearchService.run(source, keyword, {
                page = 1,
            })
        end, _("Searching... (tap to cancel)"))

        if not plugin.app or plugin.search_request_id ~= request_id then
            return
        end
        if not completed then
            showError(_("Search canceled."))
            return
        end
        Search.showResults(plugin, source, keyword, result)
    end)
end

function Search.showInput(plugin, source, previous_keyword)
    closeWidget(plugin, "search_input_dialog")

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Search"),
        input = previous_keyword or "",
        input_hint = _("Keyword"),
        description = sourceTitle(source),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    closeWidget(plugin, "search_input_dialog")
                end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    local keyword = trim(input_dialog:getInputText())
                    if keyword == "" then
                        return
                    end
                    closeWidget(plugin, "search_input_dialog")
                    Search.start(plugin, source, keyword)
                end,
            },
        }},
    }
    plugin.search_input_dialog = input_dialog
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

local function buildSourceItems(plugin, sources)
    local item_table = {}
    for source_index = 1, #sources do
        local source = sources[source_index]
        table.insert(item_table, {
            text = sourceTitle(source),
            mandatory = sourceSubtitle(source) ~= "" and sourceSubtitle(source) or nil,
            callback = function()
                closeWidget(plugin, "search_source_menu")
                Search.showInput(plugin, source)
            end,
        })
    end
    return item_table
end

function Search.show(plugin)
    if not plugin.app then
        showError(_("Novel is not ready."))
        return
    end

    local sources = searchableSources(plugin)
    if #sources == 0 then
        showError(_("No enabled searchable sources."))
        return
    end
    if #sources == 1 then
        Search.showInput(plugin, sources[1])
        return
    end

    closeWidget(plugin, "search_source_menu")
    local source_menu
    source_menu = Menu:new{
        title = _("Search source"),
        item_table = buildSourceItems(plugin, sources),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(source_menu)
            if plugin.search_source_menu == source_menu then
                plugin.search_source_menu = nil
            end
        end,
    }
    plugin.search_source_menu = source_menu
    UIManager:show(source_menu)
end

return Search
