local _ = require("novel.i18n")
local BookshelfStore = require("novel.storage.bookshelfstore")
local DetailVisits = require("novel.ui.detail.detailvisits")
local Dialog = require("novel.ui.widget.dialog")
local DetailViewer = require("novel.ui.widget.detailviewer")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local ChaptersFlow = require("novel.ui.chapters.flow")
local Trapper = require("ui/trapper")

local DetailFlow = {}

local function invalidate(plugin)
    plugin.detail_request_id = (plugin.detail_request_id or 0) + 1
end

local function bookTitle(book)
    book = book or {}
    if book.name and book.name ~= "" then
        return book.name
    end
    return book.bookUrl or _("Book")
end

local function detailText(book)
    book = book or {}
    return book.intro or ""
end

local function showUnsupported(result)
    Dialog.showUnsupported(result and result.unsupported)
end

local function buildButtons(plugin, source, result, options)
    if options and type(options.buttons_builder) == "function" then
        local buttons = options.buttons_builder(plugin, source, result)
        if type(buttons) == "table" and #buttons > 0 then
            return buttons
        end
    end

    local book = result.book or {}
    local bookshelf = plugin.app and plugin.app:getBookshelfStore()
        or BookshelfStore:new()
    local in_bookshelf = bookshelf:has(source, book)
    local row = {
        {
            text = _("Chapters"),
            callback = function()
                Dialog.closeWidget(plugin, "detail_viewer")
                ChaptersFlow.show(plugin, source, book)
            end,
        },
        {
            text = in_bookshelf and _("Update") or _("Add"),
            callback = function()
                local updated_record, err = bookshelf:add(source, book)
                if updated_record then
                    result.book = updated_record.book or book
                    DetailFlow.showLoaded(plugin, source, result)
                    Dialog.message(in_bookshelf
                        and _("Bookshelf info updated.")
                        or _("Added to bookshelf."))
                else
                    Dialog.message(in_bookshelf
                        and (_("Update bookshelf failed: ") .. tostring(err))
                        or (_("Add to bookshelf failed: ") .. tostring(err)))
                end
            end,
        },
    }

    if in_bookshelf then
        table.insert(row, {
            text = _("Remove"),
            callback = function()
                bookshelf:remove(source, book)
                DetailFlow.showLoaded(plugin, source, result)
                Dialog.message(_("Removed from bookshelf."))
            end,
        })
    end

    if result.unsupported and #result.unsupported > 0 then
        table.insert(row, {
            text = _("Rules") .. " (" .. tostring(#result.unsupported) .. ")",
            callback = function()
                showUnsupported(result)
            end,
        })
    end

    table.insert(row, {
        text = _("Close"),
        callback = function()
            Dialog.closeWidget(plugin, "detail_viewer")
        end,
    })

    return { row }
end

local function showDetailViewer(plugin, source, result, options)
    local book = result.book or {}
    options = options or {}
    options.state = options.state or {}
    Dialog.closeWidget(plugin, "detail_viewer")
    local viewer
    viewer = DetailViewer:new{
        title = bookTitle(book),
        text = detailText(book),
        buttons_table = buildButtons(plugin, source, result, options),
        text_font_size = tonumber(options.state.font_size) or 22,
        on_font_size_change = function(size)
            options.state.font_size = tonumber(size) or 22
            DetailFlow.showLoaded(plugin, source, result, options)
        end,
        close_callback = function()
            Dialog.clearIfOwned(plugin, "detail_viewer", viewer)
        end,
    }
    Dialog.showWidget(plugin, "detail_viewer", viewer)
end

function DetailFlow.close(plugin)
    invalidate(plugin)
    Loading.close(plugin, "detail_loading")
    Dialog.closeKeys(plugin, {
        "detail_menu",
        "detail_viewer",
    })
end

function DetailFlow.showLoaded(plugin, source, result, options)
    Dialog.closeKeys(plugin, {
        "detail_menu",
        "detail_viewer",
    })
    if not result or not result.ok then
        Dialog.message(_("Detail failed: ")
            .. tostring(Dialog.errorText(result, _("Detail failed."))))
        return
    end

    local visited_book = result.book or {}
    DetailVisits.markVisited(plugin, source, visited_book)
    if options and type(options.on_visited) == "function" then
        options.on_visited(visited_book)
    end

    showDetailViewer(plugin, source, result, options)
end

function DetailFlow.show(plugin, source, book, options)
    if not plugin.app then
        return
    end
    book = book or {}
    local has_info_html = book.infoHtml ~= nil and book.infoHtml ~= ""
    if not has_info_html and NetworkMgr:willRerunWhenOnline(function()
        DetailFlow.show(plugin, source, book)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.detail_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "detail_loading")
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookInfo = require("novel.catalog.reading.bookinfo")
            return BookInfo.run(source, book, {
                settings = settings,
            })
        end, loading_widget)
        Loading.close(plugin, "detail_loading", loading_widget)

        if not plugin.app or plugin.detail_request_id ~= request_id then
            return
        end
        if not completed then
            Dialog.message(_("Detail loading canceled."))
            return
        end
        DetailFlow.showLoaded(plugin, source, result, options)
    end)
end

return DetailFlow
