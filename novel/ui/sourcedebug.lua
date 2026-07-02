local _ = require("novel.i18n")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Log = require("novel.support.log")
local Menu = require("novel.ui.menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local SourceDebug = {}

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
    plugin.sources_debug_request_id = (plugin.sources_debug_request_id or 0) + 1
end

local function showMessage(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

local function sourceTitle(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source and source.bookSourceUrl or ""
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
    return tostring(status or "")
end

local function bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function summaryText(result)
    local lines = {
        result.source or "",
        result.source_url or "",
        _("Keyword: ") .. tostring(result.keyword or ""),
        _("Status: ") .. statusLabel(result.status),
        _("Books: ") .. tostring(result.books_count or 0),
    }
    if result.source_enabled == false then
        table.insert(lines, _("Source is disabled; debug ran without changing stored state."))
    end
    if result.error then
        table.insert(lines, _("Error: ")
            .. tostring(result.error.kind or "")
            .. " "
            .. tostring(result.error.message or ""))
    end
    return table.concat(lines, "\n")
end

local function detailSummaryText(result)
    local book = result.book or {}
    local lines = {
        result.source or "",
        result.source_url or "",
        _("Book: ") .. bookTitle(book),
        _("Book URL: ") .. tostring(book.bookUrl or ""),
        _("Status: ") .. statusLabel(result.status),
    }
    if result.source_enabled == false then
        table.insert(lines, _("Source is disabled; debug ran without changing stored state."))
    end
    if result.error then
        table.insert(lines, _("Error: ")
            .. tostring(result.error.kind or "")
            .. " "
            .. tostring(result.error.message or ""))
    end
    return table.concat(lines, "\n")
end

local function diagnosticText(result)
    local diagnostics = Log.formatDiagnostic(result, {
        response_title = _("Response"),
        debug_title = _("Debug events"),
        unsupported_title = _("Unsupported"),
    })
    if diagnostics == "" then
        return _("No diagnostic events.")
    end
    return diagnostics
end

local function bookText(book)
    local fields = {
        { _("Name"), book.name },
        { _("Author"), book.author },
        { _("Kind"), book.kind },
        { _("Latest chapter"), book.latestChapterTitle or book.latestChapter },
        { _("Word count"), book.wordCount },
        { _("Book URL"), book.bookUrl },
        { _("TOC URL"), book.tocUrl },
        { _("Cover URL"), book.coverUrl },
        { _("Intro"), book.intro },
    }
    local lines = {}
    for field_index = 1, #fields do
        local field = fields[field_index]
        if field[2] ~= nil and field[2] ~= "" then
            table.insert(lines, field[1] .. ": " .. tostring(field[2]))
        end
    end
    return table.concat(lines, "\n")
end

local function detailItems(result)
    local item_table = {
        {
            text = _("Summary"),
            mandatory = statusLabel(result.status),
            callback = function()
                showMessage(detailSummaryText(result))
            end,
        },
        {
            text = _("Diagnostics"),
            mandatory = tostring(#(result.debug or {})),
            callback = function()
                showMessage(diagnosticText(result))
            end,
        },
    }

    if result.unsupported and #result.unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#result.unsupported),
            callback = function()
                showMessage(Log.formatUnsupported(result.unsupported))
            end,
            separator = true,
        })
    else
        item_table[#item_table].separator = true
    end

    table.insert(item_table, {
        text = _("Book fields"),
        callback = function()
            showMessage(bookText(result.book or {}))
        end,
    })
    return item_table
end

local function bookActions(plugin, source, book)
    return {
        {
            text = _("Debug details"),
            callback = function()
                SourceDebug.startDetail(plugin, source, book)
            end,
        },
        {
            text = _("Book fields"),
            callback = function()
                showMessage(bookText(book))
            end,
        },
    }
end

local function resultItems(plugin, source, result)
    local item_table = {
        {
            text = _("Summary"),
            mandatory = statusLabel(result.status),
            callback = function()
                showMessage(summaryText(result))
            end,
        },
        {
            text = _("Diagnostics"),
            mandatory = tostring(#(result.debug or {})),
            callback = function()
                showMessage(diagnosticText(result))
            end,
        },
    }

    if result.unsupported and #result.unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#result.unsupported),
            callback = function()
                showMessage(Log.formatUnsupported(result.unsupported))
            end,
            separator = true,
        })
    else
        item_table[#item_table].separator = true
    end

    if not result.books or #result.books == 0 then
        table.insert(item_table, {
            text = _("No books parsed."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for book_index = 1, #result.books do
        local book = result.books[book_index]
        table.insert(item_table, {
            text = bookTitle(book),
            mandatory = book.author ~= "" and book.author or nil,
            sub_item_table = bookActions(plugin, source, book),
        })
    end
    return item_table
end

function SourceDebug.hasSource(source)
    return type(source) == "table"
end

function SourceDebug.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "sources_debug_input_dialog")
    closeWidget(plugin, "sources_debug_results_menu")
    closeWidget(plugin, "sources_debug_detail_menu")
end

function SourceDebug.showDetailResults(plugin, book, result)
    closeWidget(plugin, "sources_debug_detail_menu")

    if not result or not result.ok then
        local message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Source detail debug failed.")
        showMessage(_("Source detail debug failed: ") .. tostring(message))
        return
    end

    local detail_menu
    detail_menu = Menu:new{
        title = _("Source debug") .. ": " .. bookTitle(result.book or book),
        item_table = detailItems(result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.sources_debug_detail_menu == detail_menu then
                plugin.sources_debug_detail_menu = nil
            end
        end,
    }
    plugin.sources_debug_detail_menu = detail_menu
    UIManager:show(detail_menu)
end

function SourceDebug.showResults(plugin, source, result)
    closeWidget(plugin, "sources_debug_results_menu")

    if not result or not result.ok then
        local message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Source debug failed.")
        showMessage(_("Source debug failed: ") .. tostring(message))
        return
    end

    local results_menu
    results_menu = Menu:new{
        title = _("Source debug") .. ": " .. sourceTitle(source),
        item_table = resultItems(plugin, source, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.sources_debug_results_menu == results_menu then
                plugin.sources_debug_results_menu = nil
            end
        end,
    }
    plugin.sources_debug_results_menu = results_menu
    UIManager:show(results_menu)
end

function SourceDebug.startDetail(plugin, source, book)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        SourceDebug.startDetail(plugin, source, book)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.sources_debug_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SourceDebugService = require("novel.service.sourcedebug")
            return SourceDebugService.detail(source, book, {
                timeout = 5,
                total_timeout = 5,
            })
        end, _("Debugging details... (tap to cancel)"))

        if not plugin.app or plugin.sources_debug_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Source detail debug canceled."))
            return
        end
        SourceDebug.showDetailResults(plugin, book, result)
    end)
end

function SourceDebug.start(plugin, source, keyword)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        SourceDebug.start(plugin, source, keyword)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.sources_debug_request_id
    plugin.sources_debug_keyword = keyword

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SourceDebugService = require("novel.service.sourcedebug")
            return SourceDebugService.run(source, keyword, {
                timeout = 5,
                total_timeout = 5,
            })
        end, _("Debugging source... (tap to cancel)"))

        if not plugin.app or plugin.sources_debug_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Source debug canceled."))
            return
        end
        SourceDebug.showResults(plugin, source, result)
    end)
end

function SourceDebug.show(plugin, source)
    closeWidget(plugin, "sources_debug_input_dialog")

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Source debug"),
        input = plugin.sources_debug_keyword or "",
        input_hint = _("Keyword"),
        description = sourceTitle(source),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    closeWidget(plugin, "sources_debug_input_dialog")
                end,
            },
            {
                text = _("Debug"),
                is_enter_default = true,
                callback = function()
                    local keyword = trim(input_dialog:getInputText())
                    if keyword == "" then
                        return
                    end
                    closeWidget(plugin, "sources_debug_input_dialog")
                    SourceDebug.start(plugin, source, keyword)
                end,
            },
        }},
    }
    plugin.sources_debug_input_dialog = input_dialog
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

return SourceDebug
