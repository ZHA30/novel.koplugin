local _ = require("novel.i18n")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
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

local function showError(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

local function bookTitle(book)
    if book.name and book.name ~= "" then
        return book.name
    end
    return book.bookUrl or _("Book")
end

local function detailText(book)
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

function Detail.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "detail_menu")
    closeWidget(plugin, "detail_viewer")
    Toc.close(plugin)
end

local function showDetailViewer(plugin, book)
    closeWidget(plugin, "detail_viewer")
    local viewer
    viewer = TextViewer:new{
        title = bookTitle(book),
        text = detailText(book),
        text_type = "book_info",
        close_callback = function()
            if plugin.detail_viewer == viewer then
                plugin.detail_viewer = nil
            end
        end,
    }
    plugin.detail_viewer = viewer
    UIManager:show(viewer)
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

local function buildItems(plugin, source, book, result)
    local item_table = {
        {
            text = _("Book info"),
            callback = function()
                showDetailViewer(plugin, book)
            end,
        },
        {
            text = _("Chapters"),
            callback = function()
                Toc.show(plugin, source, book)
            end,
        },
    }

    if result.unsupported and #result.unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#result.unsupported),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = unsupportedText(result),
                })
            end,
        })
    end

    return item_table
end

function Detail.showLoaded(plugin, source, result)
    closeWidget(plugin, "detail_menu")
    closeWidget(plugin, "detail_viewer")
    Toc.close(plugin)
    if not result or not result.ok then
        local error_message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Detail failed.")
        showError(_("Detail failed: ") .. tostring(error_message))
        return
    end

    local book = result.book
    local detail_menu
    detail_menu = Menu:new{
        title = bookTitle(book),
        item_table = buildItems(plugin, source, book, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(detail_menu)
            if plugin.detail_menu == detail_menu then
                plugin.detail_menu = nil
            end
        end,
    }
    plugin.detail_menu = detail_menu
    UIManager:show(detail_menu)
end

function Detail.show(plugin, source, book)
    if not plugin.app then
        return
    end
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
            showError(_("Detail loading canceled."))
            return
        end
        Detail.showLoaded(plugin, source, result)
    end)
end

return Detail
