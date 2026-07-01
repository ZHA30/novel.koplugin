local _ = require("novel.i18n")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local SourceCheck = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function invalidate(plugin)
    plugin.sources_check_request_id = (plugin.sources_check_request_id or 0) + 1
end

local function showMessage(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
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

local function statusLabel(status)
    if status == "ok" then
        return _("OK")
    end
    if status == "empty" then
        return _("Empty")
    end
    if status == "failed" then
        return _("Failed")
    end
    return _("Skipped")
end

local function checkSummary(result)
    return table.concat({
        _("Keyword: ") .. tostring(result.keyword or ""),
        _("Checked: ") .. tostring(result.checked or 0)
            .. "/" .. tostring(result.total or 0),
        _("OK: ") .. tostring(result.ok_count or 0),
        _("Empty: ") .. tostring(result.empty_count or 0),
        _("Failed: ") .. tostring(result.failed_count or 0),
        _("Skipped: ") .. tostring(result.skipped_count or 0),
        _("Timeout: ") .. tostring(result.timeout_ms or 0) .. "ms",
    }, "\n")
end

local function checkDetails(item)
    local lines = {
        item.source or "",
        item.source_url or "",
        _("Status: ") .. statusLabel(item.status),
        _("Books: ") .. tostring(item.books_count or 0),
    }
    if item.error then
        table.insert(lines, _("Error: ")
            .. tostring(item.error.kind or "")
            .. " "
            .. tostring(item.error.message or ""))
    end
    if item.response then
        table.insert(lines, _("Request: ") .. tostring(item.response.request_url or ""))
        table.insert(lines, _("Final: ") .. tostring(item.response.final_url or ""))
        table.insert(lines, _("HTTP: ") .. tostring(item.response.status or ""))
        table.insert(lines, _("Bytes: ") .. tostring(item.response.bytes or 0))
    end
    if item.unsupported and #item.unsupported > 0 then
        table.insert(lines, _("Unsupported: ") .. tostring(#item.unsupported))
    end
    if item.debug and #item.debug > 0 then
        table.insert(lines, _("Debug events: ") .. tostring(#item.debug))
        local limit = math.min(#item.debug, 8)
        for debug_index = 1, limit do
            local event = item.debug[debug_index]
            table.insert(lines, tostring(event.event or ""))
        end
    end
    return table.concat(lines, "\n")
end

local function showUnsupported(items)
    local lines = {}
    for item_index = 1, #(items or {}) do
        local item = items[item_index]
        table.insert(lines, table.concat({
            item.source or "",
            item.field or "",
            item.kind or "",
            item.snippet or "",
        }, "\n"))
    end
    showMessage(table.concat(lines, "\n\n"))
end

local function checkActions(item)
    local actions = {
        {
            text = _("Details"),
            callback = function()
                showMessage(checkDetails(item))
            end,
        },
    }
    if item.unsupported and #item.unsupported > 0 then
        table.insert(actions, {
            text = _("Unsupported rules"),
            mandatory = tostring(#item.unsupported),
            callback = function()
                showUnsupported(item.unsupported)
            end,
        })
    end
    return actions
end

local function resultItems(result)
    local item_table = {
        {
            text = _("Summary"),
            mandatory = tostring(result.failed_count or 0) .. " "
                .. _("failed"),
            callback = function()
                showMessage(checkSummary(result))
            end,
            separator = true,
        },
    }

    for item_index = 1, #(result.results or {}) do
        local item = result.results[item_index]
        table.insert(item_table, {
            text = item.source or item.source_url or _("Unknown source"),
            mandatory = statusLabel(item.status),
            sub_item_table = checkActions(item),
        })
    end
    return item_table
end

function SourceCheck.hasSources(plugin)
    return plugin.app and #searchableSources(plugin) > 0
end

function SourceCheck.showResults(plugin, result)
    closeWidget(plugin, "sources_check_results_menu")

    if not result or not result.ok then
        local message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Source check failed.")
        showMessage(_("Source check failed: ") .. tostring(message))
        return
    end

    local results_menu
    results_menu = Menu:new{
        title = _("Source check"),
        item_table = resultItems(result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(results_menu)
            if plugin.sources_check_results_menu == results_menu then
                plugin.sources_check_results_menu = nil
            end
        end,
    }
    plugin.sources_check_results_menu = results_menu
    UIManager:show(results_menu)
end

function SourceCheck.start(plugin, keyword)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        SourceCheck.start(plugin, keyword)
    end) then
        return
    end

    local sources = searchableSources(plugin)
    if #sources == 0 then
        showMessage(_("No enabled searchable sources."))
        return
    end

    invalidate(plugin)
    local request_id = plugin.sources_check_request_id
    plugin.sources_check_keyword = keyword

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SourceCheckService = require("novel.service.sourcecheck")
            return SourceCheckService.run(sources, {
                keyword = keyword,
                timeout_ms = 5000,
                concurrent = 5,
            })
        end, _("Checking sources... (tap to cancel)"))

        if not plugin.app or plugin.sources_check_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Source check canceled."))
            return
        end
        SourceCheck.showResults(plugin, result)
    end)
end

function SourceCheck.show(plugin)
    closeWidget(plugin, "sources_check_input_dialog")

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Check sources"),
        input = plugin.sources_check_keyword or "",
        input_hint = _("Keyword"),
        description = _("Search enabled sources with this keyword."),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    closeWidget(plugin, "sources_check_input_dialog")
                end,
            },
            {
                text = _("Check"),
                is_enter_default = true,
                callback = function()
                    local keyword = trim(input_dialog:getInputText())
                    if keyword == "" then
                        return
                    end
                    closeWidget(plugin, "sources_check_input_dialog")
                    SourceCheck.start(plugin, keyword)
                end,
            },
        }},
    }
    plugin.sources_check_input_dialog = input_dialog
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

return SourceCheck
