local _ = require("novel.i18n")
local BookshelfLifecycle = require("novel.bookshelflifecycle")
local BookRefresh = require("novel.bookshelfrefresh")
local ChapterActionDialog = require("novel.ui.chapters.actiondialog")
local ConfirmBox = require("ui/widget/confirmbox")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local ChaptersFlow = require("novel.ui.chapters.flow")
local RefreshFlow = require("novel.ui.refreshflow")
local Shell = require("novel.ui.shell")
local UIManager = require("ui/uimanager")

local BookshelfFlow = {}

local function bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function confirmRemove(plugin, record)
    Dialog.closeWidget(plugin, "bookshelf_confirm_dialog")
    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Remove book from bookshelf?"),
        ok_text = _("Remove"),
        ok_callback = function()
            local removed = BookshelfLifecycle.remove(plugin, record.source,
                record.book)
            Dialog.clearIfOwned(plugin, "bookshelf_confirm_dialog", confirm_dialog)
            if not removed then
                Dialog.message(Dialog.failureMessage())
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
    local source = BookRefresh.findCurrentSource(plugin, record)
    local current = record.current
    if not current or not current.chapter then
        ChaptersFlow.resume(plugin, source, record.book, 1)
        return
    end
    local chapter_position = current.chapter_position or 1
    ChaptersFlow.resume(plugin, source, record.book, chapter_position)
end

local function refreshRecord(plugin, record)
    local source = BookRefresh.findCurrentSource(plugin, record)
    RefreshFlow.refreshBook(plugin, source, record.book, {
        require_bookshelf = true,
        on_done = function()
            BookshelfFlow.show(plugin)
        end,
    })
end

local function showActions(plugin, record)
    UIManager:show(ChapterActionDialog:new{
        title = bookTitle(record and record.book),
        actions = {
            {
                icon = "rotate-cw",
                text = _("Refresh"),
                callback = function()
                    refreshRecord(plugin, record)
                end,
            },
            {
                icon = "trash-2",
                text = _("Remove"),
                callback = function()
                    confirmRemove(plugin, record)
                end,
            },
            {
                icon = "x",
                text = _("Close"),
                callback = function()
                end,
            },
        },
    })
end

function BookshelfFlow.showDetails(plugin, record)
    if not plugin or not record then
        return
    end
    showActions(plugin, record)
end

function BookshelfFlow.resume(plugin, record)
    if not plugin or not record then
        return
    end
    resumeRecord(plugin, record)
end

function BookshelfFlow.close(plugin)
    RefreshFlow.close(plugin)
    Dialog.closeKeys(plugin, {
        "bookshelf_confirm_dialog",
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
