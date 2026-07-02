local _ = require("novel.i18n")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("novel.ui.menu")
local NetworkMgr = require("ui/network/manager")
local TextViewer = require("ui/widget/textviewer")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Toc = {}

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function invalidate(plugin)
    plugin.toc_request_id = (plugin.toc_request_id or 0) + 1
    plugin.content_request_id = (plugin.content_request_id or 0) + 1
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

local function chapterTitle(chapter)
    if chapter.isVip then
        return _("Locked: ") .. chapter.title
    end
    return chapter.title
end

function Toc.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "toc_menu")
    closeWidget(plugin, "content_viewer")
end

local function showContentViewer(plugin, chapter, result)
    closeWidget(plugin, "content_viewer")
    if not result or not result.ok then
        local error_message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Content failed.")
        showError(_("Content failed: ") .. tostring(error_message))
        return
    end

    local viewer
    viewer = TextViewer:new{
        title = chapter.title,
        text = result.text,
        text_type = "book_info",
        close_callback = function()
            if plugin.content_viewer == viewer then
                plugin.content_viewer = nil
            end
        end,
    }
    plugin.content_viewer = viewer
    UIManager:show(viewer)
end

function Toc.showContent(plugin, source, book, chapters, position)
    if not plugin.app then
        return
    end
    local chapter = chapters[position]
    if not chapter then
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        Toc.showContent(plugin, source, book, chapters, position)
    end) then
        return
    end

    plugin.content_request_id = (plugin.content_request_id or 0) + 1
    local request_id = plugin.content_request_id
    local next_chapter = chapters[position + 1]

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ContentService = require("novel.service.content")
            return ContentService.run(source, book, chapter, {
                next_chapter_url = next_chapter and next_chapter.url or nil,
            })
        end, _("Loading chapter... (tap to cancel)"))

        if not plugin.app or plugin.content_request_id ~= request_id then
            return
        end
        if not completed then
            showError(_("Chapter loading canceled."))
            return
        end
        if result and result.ok and plugin.app then
            plugin.app:getBookshelfService():updateProgress(source, book, chapter, position, 0)
        end
        showContentViewer(plugin, chapter, result)
    end)
end

local function chapterActions(plugin, source, book, chapters, position)
    local chapter = chapters[position]
    return {
        {
            text = _("Read"),
            callback = function()
                Toc.showContent(plugin, source, book, chapters, position)
            end,
        },
        {
            text = _("Details"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = table.concat({
                        chapter.title,
                        chapter.url,
                        chapter.tag or "",
                    }, "\n"),
                })
            end,
        },
    }
end

local function buildChapterItems(plugin, source, book, chapters)
    local item_table = {}
    for position = 1, #chapters do
        local chapter = chapters[position]
        table.insert(item_table, {
            text = chapterTitle(chapter),
            mandatory = chapter.isVolume and _("Volume") or nil,
            sub_item_table = chapterActions(plugin, source, book, chapters, position),
        })
    end
    return item_table
end

function Toc.showList(plugin, source, book, result)
    closeWidget(plugin, "toc_menu")
    if not result or not result.ok then
        local error_message = result and result.error
            and (result.error.message or result.error.kind)
            or _("TOC failed.")
        showError(_("TOC failed: ") .. tostring(error_message))
        return
    end

    local toc_menu
    toc_menu = Menu:new{
        title = bookTitle(result.book or book) .. " (" .. tostring(#result.chapters) .. ")",
        item_table = buildChapterItems(plugin, source, result.book or book, result.chapters),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.toc_menu == toc_menu then
                plugin.toc_menu = nil
            end
        end,
    }
    plugin.toc_menu = toc_menu
    UIManager:show(toc_menu)
end

function Toc.show(plugin, source, book)
    if not plugin.app then
        return
    end
    local has_toc_html = book.tocHtml ~= nil and book.tocHtml ~= ""
    if not has_toc_html and NetworkMgr:willRerunWhenOnline(function()
        Toc.show(plugin, source, book)
    end) then
        return
    end

    plugin.toc_request_id = (plugin.toc_request_id or 0) + 1
    local request_id = plugin.toc_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local TocService = require("novel.service.toc")
            return TocService.run(source, book)
        end, _("Loading chapters... (tap to cancel)"))

        if not plugin.app or plugin.toc_request_id ~= request_id then
            return
        end
        if not completed then
            showError(_("Chapter list loading canceled."))
            return
        end
        Toc.showList(plugin, source, book, result)
    end)
end

return Toc
