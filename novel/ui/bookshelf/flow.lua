local _ = require("novel.i18n")
local BookshelfSupport = require("novel.ui.bookshelf.bookshelfsupport")
local ButtonDialog = require("ui/widget/buttondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local ChaptersFlow = require("novel.ui.chapters.flow")
local ShellRoutes = require("novel.ui.shellroutes")
local Shell = require("novel.ui.shell")
local Trapper = require("ui/trapper")

local BookshelfFlow = {}

local function invalidateRefresh(plugin)
    plugin.bookshelf_refresh_request_id = (plugin.bookshelf_refresh_request_id or 0) + 1
end

local function invalidateSwitch(plugin)
    plugin.bookshelf_switch_request_id = (plugin.bookshelf_switch_request_id or 0) + 1
end

local function bookTitle(book)
    return BookshelfSupport.bookTitle(book)
end

local function sourceTitle(source)
    return BookshelfSupport.sourceTitle(source)
end

local function findCurrentSource(plugin, record)
    local source_url = record.source_url or ""
    local sources = plugin.app:getSourceStore():list()
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

local function applySwitch(plugin, record, candidate)
    Dialog.closeWidget(plugin, "bookshelf_switch_confirm_dialog")
    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Switch this book to source?")
            .. "\n\n" .. sourceTitle(candidate.source),
        ok_text = _("Switch"),
        ok_callback = function()
            Dialog.clearIfOwned(plugin, "bookshelf_switch_confirm_dialog", confirm_dialog)
            if not plugin.app then
                Dialog.message(_("Novel is not ready."))
                return
            end
            local updated_record, err = plugin.app:getBookshelfStore()
                :applySwitch(record, candidate.source, candidate.book)
            if not updated_record then
                Dialog.message(_("Switch failed: ") .. tostring(err))
                return
            end
            Dialog.closeWidget(plugin, "bookshelf_switch_confirm_dialog")
            Dialog.message(_("Source switched."))
            BookshelfFlow.show(plugin)
        end,
        cancel_callback = function()
            Dialog.clearIfOwned(plugin, "bookshelf_switch_confirm_dialog", confirm_dialog)
        end,
    }
    Dialog.showWidget(plugin, "bookshelf_switch_confirm_dialog", confirm_dialog)
end

local function showSwitchResults(plugin, record, result)
    if not result or not result.ok then
        Dialog.message(_("Switch failed: ")
            .. tostring(Dialog.errorText(result, _("Switch failed."))))
        return
    end

    Shell.push(plugin, ShellRoutes.bookshelfSwitchResults{
        record = record,
        keyword = result.keyword,
        checked = result.checked,
        skipped = result.skipped,
        failed = result.failed,
        candidates = result.candidates,
        apply_callback = function(candidate)
            applySwitch(plugin, record, candidate)
        end,
    })
end

local function confirmRemove(plugin, record)
    Dialog.closeWidget(plugin, "bookshelf_confirm_dialog")
    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Remove book from bookshelf?"),
        ok_text = _("Remove"),
        ok_callback = function()
            local removed = plugin.app:getBookshelfStore():remove(record.source, record.book)
            Dialog.clearIfOwned(plugin, "bookshelf_confirm_dialog", confirm_dialog)
            if not removed then
                Dialog.message(_("Remove from bookshelf failed."))
                return
            end
            BookshelfFlow.show(plugin)
            Dialog.message(_("Removed from bookshelf."))
        end,
        cancel_callback = function()
            Dialog.clearIfOwned(plugin, "bookshelf_confirm_dialog", confirm_dialog)
        end,
    }
    Dialog.showWidget(plugin, "bookshelf_confirm_dialog", confirm_dialog)
end

local function resumeRecord(plugin, record)
    local source = findCurrentSource(plugin, record)
    local current = record.current
    if not current or not current.chapter then
        ChaptersFlow.show(plugin, source, record.book)
        return
    end
    local chapter_position = current.chapter_position or 1
    ChaptersFlow.resume(plugin, source, record.book, chapter_position)
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
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookshelfStore = require("novel.storage.bookshelfstore")
            return BookshelfStore.fetchRefresh(source, record.book, {
                settings = settings,
            })
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

        local updated_record, err = plugin.app:getBookshelfStore()
            :applyRefresh(source, record.book, result)
        if not updated_record then
            Dialog.message(_("Refresh failed: ") .. tostring(err))
            return
        end
        Dialog.message(_("Book refreshed.") .. "\n"
            .. _("Chapters: ") .. tostring(#(result.chapters or {})))
        BookshelfFlow.show(plugin)
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

    local sources = plugin.app:getSourceStore():list()
    invalidateSwitch(plugin)
    local request_id = plugin.bookshelf_switch_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "bookshelf_switch_loading")
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local SourceFinder = require("novel.catalog.listing.sourcefinder")
            return SourceFinder.find(record, sources, {
                settings = settings,
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
                ChaptersFlow.show(plugin, findCurrentSource(plugin, record), record.book)
            end,
        },
        {
            text = _("Details"),
            callback = function()
                DetailFlow.show(plugin, findCurrentSource(plugin, record), record.book)
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
    Dialog.closeWidget(plugin, "bookshelf_actions_dialog")
    local actions = recordActions(plugin, record)
    local actions_dialog

    local function actionButton(action)
        return {
            text = action.text,
            callback = function()
                Dialog.closeWidget(plugin, "bookshelf_actions_dialog")
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
            Dialog.clearIfOwned(plugin, "bookshelf_actions_dialog", actions_dialog)
        end,
    }
    Dialog.showWidget(plugin, "bookshelf_actions_dialog", actions_dialog)
end

function BookshelfFlow.showActions(plugin, record)
    if not plugin or not record then
        return
    end
    showActions(plugin, record)
end

function BookshelfFlow.close(plugin)
    invalidateRefresh(plugin)
    invalidateSwitch(plugin)
    Loading.close(plugin, "bookshelf_refresh_loading")
    Loading.close(plugin, "bookshelf_switch_loading")
    Dialog.closeKeys(plugin, {
        "bookshelf_actions_dialog",
        "bookshelf_confirm_dialog",
        "bookshelf_switch_confirm_dialog",
    })
    DetailFlow.close(plugin)
end

function BookshelfFlow.show(plugin)
    if not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    Shell.show(plugin, {
        active_tab = "bookshelf",
    })
end

return BookshelfFlow
