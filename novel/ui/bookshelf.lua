local _ = require("novel.i18n")
local BookList = require("novel.ui.booklist")
local ConfirmBox = require("ui/widget/confirmbox")
local Detail = require("novel.ui.detail")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local Toc = require("novel.ui.toc")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Bookshelf = {}

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function showMessage(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

local function invalidateRefresh(plugin)
    plugin.bookshelf_refresh_request_id = (plugin.bookshelf_refresh_request_id or 0) + 1
end

local function invalidateSwitch(plugin)
    plugin.bookshelf_switch_request_id = (plugin.bookshelf_switch_request_id or 0) + 1
end

local function bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function errorText(result, fallback)
    if not result or not result.error then
        return fallback
    end
    return result.error.message or result.error.kind or fallback
end

local function sourceTitle(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source and source.bookSourceUrl or ""
end

local function findCurrentSource(plugin, record)
    local source_url = record.source_url or ""
    local sources = plugin.app:getSourceRepo():list()
    for source_index = 1, #sources do
        local source = sources[source_index]
        if source.bookSourceUrl == source_url then
            return source
        end
    end
    return record.source
end

local function recordCurrentChapter(record)
    if record.current and record.current.chapter and record.current.chapter.title then
        return record.current.chapter.title
    elseif record.current and record.current.chapter_title then
        return record.current.chapter_title
    end
    return nil
end

local function showBookInfo(record)
    local book = record.book or {}
    local lines = {
        bookTitle(book),
    }
    if book.author and book.author ~= "" then
        table.insert(lines, _("Author: ") .. book.author)
    end
    if record.source_name and record.source_name ~= "" then
        table.insert(lines, _("Source: ") .. record.source_name)
    end
    if record.current and record.current.chapter and record.current.chapter.title then
        table.insert(lines, _("Current chapter: ") .. record.current.chapter.title)
    elseif record.current and record.current.chapter_title then
        table.insert(lines, _("Current chapter: ") .. record.current.chapter_title)
    end
    if book.bookUrl and book.bookUrl ~= "" then
        table.insert(lines, "")
        table.insert(lines, book.bookUrl)
    end
    showMessage(table.concat(lines, "\n"))
end

local function switchSummary(result)
    return table.concat({
        _("Keyword: ") .. tostring(result.keyword or ""),
        _("Candidates: ") .. tostring(#(result.candidates or {})),
        _("Checked: ") .. tostring(result.checked or 0),
        _("Skipped: ") .. tostring(result.skipped or 0),
        _("Failed: ") .. tostring(result.failed or 0),
    }, "\n")
end

local function closeSwitchResults(plugin)
    closeWidget(plugin, "bookshelf_switch_confirm_dialog")
    closeWidget(plugin, "bookshelf_switch_results_menu")
end

local function applySwitch(plugin, record, candidate)
    closeWidget(plugin, "bookshelf_switch_confirm_dialog")
    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Switch this book to source?")
            .. "\n\n" .. sourceTitle(candidate.source),
        ok_text = _("Switch"),
        ok_callback = function()
            if plugin.bookshelf_switch_confirm_dialog == confirm_dialog then
                plugin.bookshelf_switch_confirm_dialog = nil
            end
            if not plugin.app then
                showMessage(_("Novel is not ready."))
                return
            end
            local updated_record, err = plugin.app:getBookshelfService()
                :applySwitch(record, candidate.source, candidate.book)
            if not updated_record then
                showMessage(_("Switch failed: ") .. tostring(err))
                return
            end
            closeSwitchResults(plugin)
            showMessage(_("Source switched."))
            Bookshelf.show(plugin)
        end,
        cancel_callback = function()
            if plugin.bookshelf_switch_confirm_dialog == confirm_dialog then
                plugin.bookshelf_switch_confirm_dialog = nil
            end
        end,
    }
    plugin.bookshelf_switch_confirm_dialog = confirm_dialog
    UIManager:show(confirm_dialog)
end

local function candidateActions(plugin, record, candidate)
    return {
        {
            text = _("Apply switch"),
            callback = function()
                applySwitch(plugin, record, candidate)
            end,
        },
        {
            text = _("Details"),
            callback = function()
                Detail.show(plugin, candidate.source, candidate.book)
            end,
        },
    }
end

local function switchResultItems(plugin, record, result)
    local item_table = {
        {
            text = _("Summary"),
            mandatory = tostring(#(result.candidates or {})),
            callback = function()
                showMessage(switchSummary(result))
            end,
            separator = true,
        },
    }

    if not result.candidates or #result.candidates == 0 then
        table.insert(item_table, {
            text = _("No matching books."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for candidate_index = 1, #result.candidates do
        local candidate = result.candidates[candidate_index]
        table.insert(item_table, {
            text = bookTitle(candidate.book),
            book = candidate.book,
            source_title = candidate.source_name,
            book_extra_metadata = candidate.reason,
            sub_item_table = candidateActions(plugin, record, candidate),
        })
    end
    return item_table
end

local function showSwitchResults(plugin, record, result)
    closeWidget(plugin, "bookshelf_switch_results_menu")

    if not result or not result.ok then
        showMessage(_("Switch failed: ")
            .. tostring(errorText(result, _("Switch failed."))))
        return
    end

    local results_menu
    results_menu = BookList:new{
        title = _("Switch source"),
        item_table = switchResultItems(plugin, record, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.bookshelf_switch_results_menu == results_menu then
                plugin.bookshelf_switch_results_menu = nil
            end
        end,
    }
    plugin.bookshelf_switch_results_menu = results_menu
    UIManager:show(results_menu)
end

local function confirmRemove(plugin, record)
    closeWidget(plugin, "bookshelf_confirm_dialog")
    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Remove book from bookshelf?"),
        ok_text = _("Remove"),
        ok_callback = function()
            plugin.app:getBookshelfService():remove(record.source, record.book)
            if plugin.bookshelf_confirm_dialog == confirm_dialog then
                plugin.bookshelf_confirm_dialog = nil
            end
            Bookshelf.show(plugin)
        end,
        cancel_callback = function()
            if plugin.bookshelf_confirm_dialog == confirm_dialog then
                plugin.bookshelf_confirm_dialog = nil
            end
        end,
    }
    plugin.bookshelf_confirm_dialog = confirm_dialog
    UIManager:show(confirm_dialog)
end

local function resumeRecord(plugin, record)
    local source = findCurrentSource(plugin, record)
    local current = record.current
    if not current or not current.chapter then
        Toc.show(plugin, source, record.book)
        return
    end
    local chapter_position = current.chapter_position or 1
    local chapters = {}
    chapters[chapter_position] = current.chapter
    Toc.showContent(plugin, source, record.book, chapters, chapter_position)
end

local function refreshRecord(plugin, record)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end
    local source = findCurrentSource(plugin, record)
    if NetworkMgr:willRerunWhenOnline(function()
        refreshRecord(plugin, record)
    end) then
        return
    end

    invalidateRefresh(plugin)
    local request_id = plugin.bookshelf_refresh_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookshelfService = require("novel.service.bookshelf")
            return BookshelfService.fetchRefresh(source, record.book)
        end, _("Refreshing... (tap to cancel)"))

        if not plugin.app or plugin.bookshelf_refresh_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Refresh canceled."))
            return
        end
        if not result or not result.ok then
            showMessage(_("Refresh failed: ") .. tostring(errorText(result, _("Refresh failed."))))
            return
        end

        local updated_record, err = plugin.app:getBookshelfService()
            :applyRefresh(source, record.book, result)
        if not updated_record then
            showMessage(_("Refresh failed: ") .. tostring(err))
            return
        end
        showMessage(_("Book refreshed.") .. "\n" .. _("Chapters: ") .. tostring(#(result.chapters or {})))
        Bookshelf.show(plugin)
    end)
end

local function switchRecord(plugin, record)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        switchRecord(plugin, record)
    end) then
        return
    end

    local sources = plugin.app:getSourceRepo():list()
    invalidateSwitch(plugin)
    local request_id = plugin.bookshelf_switch_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SwitchService = require("novel.service.switch")
            return SwitchService.find(record, sources, {
                timeout = 5,
            })
        end, _("Searching sources... (tap to cancel)"))

        if not plugin.app or plugin.bookshelf_switch_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Source switch canceled."))
            return
        end
        showSwitchResults(plugin, record, result)
    end)
end

local function recordActions(plugin, record)
    return {
        {
            text = _("Resume"),
            callback = function()
                resumeRecord(plugin, record)
            end,
        },
        {
            text = _("Refresh"),
            callback = function()
                refreshRecord(plugin, record)
            end,
        },
        {
            text = _("Switch source"),
            callback = function()
                switchRecord(plugin, record)
            end,
        },
        {
            text = _("Chapters"),
            callback = function()
                Toc.show(plugin, findCurrentSource(plugin, record), record.book)
            end,
        },
        {
            text = _("Details"),
            callback = function()
                Detail.show(plugin, findCurrentSource(plugin, record), record.book)
            end,
        },
        {
            text = _("Book info"),
            callback = function()
                showBookInfo(record)
            end,
        },
        {
            text = _("Remove from bookshelf"),
            callback = function()
                confirmRemove(plugin, record)
            end,
        },
    }
end

local function buildItems(plugin, records)
    if #records == 0 then
        return {{
            text = _("No books in bookshelf."),
            select_enabled = false,
            dim = true,
        }}
    end

    local item_table = {}
    for record_index = 1, #records do
        local record = records[record_index]
        table.insert(item_table, {
            text = bookTitle(record.book),
            book = record.book,
            source_title = record.source_name,
            book_subtitle_parts = {
                recordCurrentChapter(record),
            },
            sub_item_table = recordActions(plugin, record),
        })
    end
    return item_table
end

function Bookshelf.close(plugin)
    invalidateRefresh(plugin)
    invalidateSwitch(plugin)
    closeWidget(plugin, "bookshelf_confirm_dialog")
    closeSwitchResults(plugin)
    closeWidget(plugin, "bookshelf_menu")
end

function Bookshelf.show(plugin)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end

    closeWidget(plugin, "bookshelf_menu")
    local records = plugin.app:getBookshelfService():list()
    local bookshelf_menu
    bookshelf_menu = BookList:new{
        title = _("Bookshelf"),
        item_table = buildItems(plugin, records),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.bookshelf_menu == bookshelf_menu then
                plugin.bookshelf_menu = nil
            end
        end,
    }
    plugin.bookshelf_menu = bookshelf_menu
    UIManager:show(bookshelf_menu)
end

return Bookshelf
