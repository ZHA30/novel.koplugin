local _ = require("novel.i18n")
local ConfirmBox = require("ui/widget/confirmbox")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local ChaptersFlow = require("novel.ui.chapters.flow")
local Shell = require("novel.ui.shell")
local Trapper = require("ui/trapper")

local BookshelfFlow = {}

local function invalidateRefresh(plugin)
    plugin.bookshelf_refresh_request_id = (plugin.bookshelf_refresh_request_id or 0) + 1
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
                Dialog.message(Dialog.failureMessage())
                return
            end
            Dialog.closeWidget(plugin, "detail_viewer")
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
        ChaptersFlow.resume(plugin, source, record.book, 1)
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
            Dialog.message(Dialog.canceledMessage())
            return
        end
        if not result or not result.ok then
            Dialog.message(Dialog.failureMessage(result))
            return
        end

        local updated_record, err = plugin.app:getBookshelfStore()
            :applyRefresh(source, record.book, result)
        if not updated_record then
            Dialog.message(Dialog.failureMessage(err))
            return
        end
        Dialog.message(_("Book refreshed.") .. "\n"
            .. _("Chapters: ") .. tostring(#(result.chapters or {})))
        BookshelfFlow.show(plugin)
    end)
end

local function bookshelfDetailButtons(plugin, record)
    return {
        {
            {
                icon = "rotate-cw",
                callback = function()
                    refreshRecord(plugin, record)
                end,
            },
            {
                icon = "trash-2",
                callback = function()
                    confirmRemove(plugin, record)
                end,
            },
            {
                icon = "x",
                callback = function()
                    Dialog.closeWidget(plugin, "detail_viewer")
                end,
            },
        },
    }
end

local function showDetails(plugin, record)
    DetailFlow.show(plugin, findCurrentSource(plugin, record), record.book, {
        buttons_builder = function()
            return bookshelfDetailButtons(plugin, record)
        end,
    })
end

function BookshelfFlow.showDetails(plugin, record)
    if not plugin or not record then
        return
    end
    showDetails(plugin, record)
end

function BookshelfFlow.resume(plugin, record)
    if not plugin or not record then
        return
    end
    resumeRecord(plugin, record)
end

function BookshelfFlow.close(plugin)
    invalidateRefresh(plugin)
    Loading.close(plugin, "bookshelf_refresh_loading")
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
