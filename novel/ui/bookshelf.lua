local _ = require("novel.i18n")
local MatchReason = require("novel.books.reason")
local BookMenu = require("novel.widget.bookmenu")
local ButtonDialog = require("ui/widget/buttondialog")
local Capability = require("novel.source.capability")
local ConfirmBox = require("ui/widget/confirmbox")
local Detail = require("novel.ui.detail")
local Dialog = require("novel.widget.dialog")
local Loading = require("novel.widget.loading")
local NetworkMgr = require("ui/network/manager")
local Chapters = require("novel.ui.chapters")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Bookshelf = {}

local RETURN_TO_BOOKSHELF = "bookshelf"

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

local function sourceTitle(source)
    return Capability.title(source)
end

local function findCurrentSource(plugin, record)
    local source_url = record.source_url or ""
    local sources = plugin.app:getSourceRepository():list()
    for source_index = 1, #sources do
        local source = sources[source_index]
        if source.bookSourceUrl == source_url then
            return source
        end
    end
    return record.source
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
    Dialog.message(table.concat(lines, "\n"))
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

local function switchReasonText(reason)
    if reason == MatchReason.MATCH_NAME_AUTHOR then
        return _("Name and author match")
    elseif reason == MatchReason.MATCH_NAME then
        return _("Name matches")
    end
    return reason
end

local function closeSwitchResults(plugin)
    Dialog.closeWidget(plugin, "bookshelf_switch_confirm_dialog")
    Dialog.closeWidget(plugin, "bookshelf_switch_results_menu")
end

local function closeActions(plugin)
    Dialog.closeWidget(plugin, "bookshelf_actions_dialog")
end

local function applySwitch(plugin, record, candidate)
    Dialog.closeWidget(plugin, "bookshelf_switch_confirm_dialog")
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
                Dialog.message(_("Novel is not ready."))
                return
            end
            local updated_record, err = plugin.app:getBookshelfRecords()
                :applySwitch(record, candidate.source, candidate.book)
            if not updated_record then
                Dialog.message(_("Switch failed: ") .. tostring(err))
                return
            end
            closeSwitchResults(plugin)
            Dialog.message(_("Source switched."))
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
                Dialog.message(switchSummary(result))
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
            book_extra_metadata = switchReasonText(candidate.reason),
            sub_item_table = candidateActions(plugin, record, candidate),
        })
    end
    return item_table
end

local function showSwitchResults(plugin, record, result)
    Dialog.closeWidget(plugin, "bookshelf_switch_results_menu")

    if not result or not result.ok then
        Dialog.message(_("Switch failed: ")
            .. tostring(Dialog.errorText(result, _("Switch failed."))))
        return
    end

    local results_menu
    results_menu = BookMenu:new{
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
    Dialog.closeWidget(plugin, "bookshelf_confirm_dialog")
    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Remove book from bookshelf?"),
        ok_text = _("Remove"),
        ok_callback = function()
            local removed = plugin.app:getBookshelfRecords():remove(record.source, record.book)
            if plugin.bookshelf_confirm_dialog == confirm_dialog then
                plugin.bookshelf_confirm_dialog = nil
            end
            if not removed then
                Dialog.message(_("Remove from bookshelf failed."))
                return
            end
            Bookshelf.show(plugin)
            Dialog.message(_("Removed from bookshelf."))
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
        Chapters.show(plugin, source, record.book, {
            return_to = RETURN_TO_BOOKSHELF,
        })
        return
    end
    local chapter_position = current.chapter_position or 1
    Chapters.resume(plugin, source, record.book, chapter_position, {
        return_to = RETURN_TO_BOOKSHELF,
    })
end

local function refreshRecord(plugin, record)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
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
        local loading_widget = Loading.show(plugin, "bookshelf_refresh_loading")
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookshelfRecords = require("novel.books.records")
            return BookshelfRecords.fetchRefresh(source, record.book)
        end, loading_widget)
        Loading.close(plugin, "bookshelf_refresh_loading", loading_widget)

        if not plugin.app or plugin.bookshelf_refresh_request_id ~= request_id then
            return
        end
        if not completed then
            Dialog.message(_("Refresh canceled."))
            return
        end
        if not result or not result.ok then
            Dialog.message(_("Refresh failed: ")
                .. tostring(Dialog.errorText(result, _("Refresh failed."))))
            return
        end

        local updated_record, err = plugin.app:getBookshelfRecords()
            :applyRefresh(source, record.book, result)
        if not updated_record then
            Dialog.message(_("Refresh failed: ") .. tostring(err))
            return
        end
        Dialog.message(_("Book refreshed.") .. "\n"
            .. _("Chapters: ") .. tostring(#(result.chapters or {})))
        Bookshelf.show(plugin)
    end)
end

local function switchRecord(plugin, record)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        switchRecord(plugin, record)
    end) then
        return
    end

    local sources = plugin.app:getSourceRepository():list()
    invalidateSwitch(plugin)
    local request_id = plugin.bookshelf_switch_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "bookshelf_switch_loading")
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookMatcher = require("novel.books.matcher")
            return BookMatcher.find(record, sources, {
                timeout = 5,
            })
        end, loading_widget)
        Loading.close(plugin, "bookshelf_switch_loading", loading_widget)

        if not plugin.app or plugin.bookshelf_switch_request_id ~= request_id then
            return
        end
        if not completed then
            Dialog.message(_("Source switch canceled."))
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
                Chapters.show(plugin, findCurrentSource(plugin, record), record.book, {
                    return_to = RETURN_TO_BOOKSHELF,
                })
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

local function showActions(plugin, record)
    closeActions(plugin)
    local actions = recordActions(plugin, record)
    local actions_dialog

    local function actionButton(action)
        return {
            text = action.text,
            callback = function()
                if plugin.bookshelf_actions_dialog == actions_dialog then
                    plugin.bookshelf_actions_dialog = nil
                end
                UIManager:close(actions_dialog)
                action.callback()
            end,
        }
    end

    actions_dialog = ButtonDialog:new{
        title = _("Book actions") .. "\n" .. bookTitle(record.book),
        title_align = "center",
        buttons = {
            {
                actionButton(actions[1]),
                actionButton(actions[4]),
            },
            {
                actionButton(actions[2]),
                actionButton(actions[3]),
            },
            {
                actionButton(actions[5]),
                actionButton(actions[6]),
            },
            {},
            {
                actionButton(actions[7]),
            },
        },
        tap_close_callback = function()
            if plugin.bookshelf_actions_dialog == actions_dialog then
                plugin.bookshelf_actions_dialog = nil
            end
        end,
    }
    plugin.bookshelf_actions_dialog = actions_dialog
    UIManager:show(actions_dialog)
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
            callback = function()
                Chapters.show(plugin, findCurrentSource(plugin, record), record.book, {
                    return_to = RETURN_TO_BOOKSHELF,
                })
            end,
            hold_callback = function()
                showActions(plugin, record)
            end,
        })
    end
    return item_table
end

function Bookshelf.close(plugin)
    invalidateRefresh(plugin)
    invalidateSwitch(plugin)
    Loading.close(plugin, "bookshelf_refresh_loading")
    Loading.close(plugin, "bookshelf_switch_loading")
    closeActions(plugin)
    Dialog.closeWidget(plugin, "bookshelf_confirm_dialog")
    closeSwitchResults(plugin)
    Detail.close(plugin)
    Dialog.closeWidget(plugin, "bookshelf_menu")
end

function Bookshelf.show(plugin)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end

    Dialog.closeWidget(plugin, "bookshelf_menu")
    local records = plugin.app:getBookshelfRecords():list()
    local bookshelf_menu
    bookshelf_menu = BookMenu:new{
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
