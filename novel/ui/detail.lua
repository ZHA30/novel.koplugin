local _ = require("novel.i18n")
local BookshelfService = require("novel.service.bookshelf")
local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local Toc = require("novel.ui.toc")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Detail = {}

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function invalidate(plugin)
    plugin.detail_request_id = (plugin.detail_request_id or 0) + 1
end

local function showMessage(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
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
    local lines = {
        bookTitle(book),
    }
    if book.author and book.author ~= "" then
        table.insert(lines, _("Author: ") .. book.author)
    end
    if book.kind and book.kind ~= "" then
        table.insert(lines, _("Kind: ") .. book.kind)
    end
    if book.latestChapterTitle and book.latestChapterTitle ~= "" then
        table.insert(lines, _("Latest chapter: ") .. book.latestChapterTitle)
    end
    if book.updateTime and book.updateTime ~= "" then
        table.insert(lines, _("Update time: ") .. book.updateTime)
    end
    if book.wordCount and book.wordCount ~= "" then
        table.insert(lines, _("Word count: ") .. book.wordCount)
    end
    if book.intro and book.intro ~= "" then
        table.insert(lines, "")
        table.insert(lines, book.intro)
    end
    if book.bookUrl and book.bookUrl ~= "" then
        table.insert(lines, "")
        table.insert(lines, book.bookUrl)
    end
    if book.tocUrl and book.tocUrl ~= "" then
        table.insert(lines, book.tocUrl)
    end
    return table.concat(lines, "\n")
end

local function unsupportedText(result)
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
    return table.concat(lines, "\n\n")
end

local function showUnsupported(result)
    showMessage(unsupportedText(result))
end

local function buildButtons(plugin, source, result)
    local book = result.book or {}
    local bookshelf = plugin.app and plugin.app:getBookshelfService()
        or BookshelfService:new()
    local in_bookshelf = bookshelf:has(source, book)
    local buttons = {
        {
            {
                text = _("Chapters"),
                callback = function()
                    Toc.show(plugin, source, book)
                end,
            },
            {
                text = in_bookshelf
                    and _("Update bookshelf info")
                    or _("Add to bookshelf"),
                callback = function()
                    local updated_record, err = bookshelf:add(source, book)
                    if updated_record then
                        result.book = updated_record.book or book
                        Detail.showLoaded(plugin, source, result)
                        showMessage(in_bookshelf
                            and _("Bookshelf info updated.")
                            or _("Added to bookshelf."))
                    else
                        showMessage(in_bookshelf
                            and (_("Update bookshelf failed: ") .. tostring(err))
                            or (_("Add to bookshelf failed: ") .. tostring(err)))
                    end
                end,
            },
        },
    }

    if in_bookshelf then
        table.insert(buttons, {{
            text = _("Remove from bookshelf"),
            callback = function()
                bookshelf:remove(source, book)
                Detail.showLoaded(plugin, source, result)
                showMessage(_("Removed from bookshelf."))
            end,
        }})
    end

    if result.unsupported and #result.unsupported > 0 then
        table.insert(buttons, {{
            text = _("Unsupported rules") .. " (" .. tostring(#result.unsupported) .. ")",
            callback = function()
                showUnsupported(result)
            end,
        }})
    end

    table.insert(buttons, {{
        text = _("Close"),
        callback = function()
            if plugin.detail_viewer then
                plugin.detail_viewer:onClose()
            end
        end,
    }})

    return buttons
end

local function showDetailViewer(plugin, source, result)
    local book = result.book or {}
    closeWidget(plugin, "detail_viewer")
    local viewer
    viewer = TextViewer:new{
        title = bookTitle(book),
        text = detailText(book),
        text_type = "book_info",
        buttons_table = buildButtons(plugin, source, result),
        close_callback = function()
            if plugin.detail_viewer == viewer then
                plugin.detail_viewer = nil
            end
        end,
    }
    plugin.detail_viewer = viewer
    UIManager:show(viewer)
end

function Detail.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "detail_menu")
    closeWidget(plugin, "detail_viewer")
    Toc.close(plugin)
end

function Detail.showLoaded(plugin, source, result)
    closeWidget(plugin, "detail_menu")
    closeWidget(plugin, "detail_viewer")
    Toc.close(plugin)
    if not result or not result.ok then
        local error_message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Detail failed.")
        showMessage(_("Detail failed: ") .. tostring(error_message))
        return
    end

    showDetailViewer(plugin, source, result)
end

function Detail.show(plugin, source, book)
    if not plugin.app then
        return
    end
    book = book or {}
    local has_info_html = book.infoHtml ~= nil and book.infoHtml ~= ""
    if not has_info_html and NetworkMgr:willRerunWhenOnline(function()
        Detail.show(plugin, source, book)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.detail_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local BookInfoService = require("novel.service.bookinfo")
            return BookInfoService.run(source, book)
        end, _("Loading details... (tap to cancel)"))

        if not plugin.app or plugin.detail_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Detail loading canceled."))
            return
        end
        Detail.showLoaded(plugin, source, result)
    end)
end

return Detail
