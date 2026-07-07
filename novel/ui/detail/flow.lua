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
local DEFAULT_FONT_SIZE = 22
local FONT_SIZE_OPTIONS = { 18, 20, 22, 24, 26, 28 }

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

local function normalizeFontSize(size)
    size = tonumber(size)
    if not size then
        return DEFAULT_FONT_SIZE
    end

    for index = 1, #FONT_SIZE_OPTIONS do
        if size == FONT_SIZE_OPTIONS[index] then
            return size
        end
    end
    return DEFAULT_FONT_SIZE
end

local function detailSettings(plugin, create)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil
    end

    if type(settings.ui) ~= "table" then
        if not create then
            return nil
        end
        settings.ui = {}
    end
    if type(settings.ui.detail) ~= "table" then
        if not create then
            return nil
        end
        settings.ui.detail = {}
    end

    return settings.ui.detail
end

local function currentFontSize(plugin, options)
    if options and options.state and options.state.font_size ~= nil then
        return normalizeFontSize(options.state.font_size)
    end

    local detail = detailSettings(plugin, false)
    if detail then
        return normalizeFontSize(detail.font_size)
    end
    return DEFAULT_FONT_SIZE
end

local function saveFontSize(plugin, options, size)
    size = normalizeFontSize(size)
    options.state.font_size = size

    local detail = detailSettings(plugin, true)
    if not detail then
        return size
    end
    if detail.font_size ~= size then
        detail.font_size = size
        plugin.app:saveSettings()
    end
    return size
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
    local function notifyBookshelfChanged(changed_book, added)
        if options and type(options.on_bookshelf_changed) == "function" then
            options.on_bookshelf_changed(changed_book or book, added)
        end
    end
    local row = {
        {
            icon = "list",
            callback = function()
                Dialog.closeWidget(plugin, "detail_viewer")
                ChaptersFlow.show(plugin, source, book)
            end,
        },
        {
            icon = in_bookshelf and "book-check" or "book",
            callback = function()
                if in_bookshelf then
                    if bookshelf:remove(source, book) then
                        notifyBookshelfChanged(book, false)
                        DetailFlow.showLoaded(plugin, source, result, options)
                        Dialog.message(_("Removed from bookshelf."))
                    else
                        Dialog.message(Dialog.failureMessage())
                    end
                    return
                end

                local updated_record, err = bookshelf:add(source, book)
                if updated_record then
                    result.book = updated_record.book or book
                    notifyBookshelfChanged(result.book, true)
                    DetailFlow.showLoaded(plugin, source, result, options)
                    Dialog.message(_("Added to bookshelf."))
                else
                    Dialog.message(Dialog.failureMessage(err))
                end
            end,
        },
    }

    if result.unsupported and #result.unsupported > 0 then
        table.insert(row, {
            icon = "funnel",
            callback = function()
                showUnsupported(result)
            end,
        })
    end

    table.insert(row, {
        icon = "x",
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
        text_font_size = currentFontSize(plugin, options),
        on_font_size_change = function(size, owner)
            if not plugin.app or plugin.detail_viewer ~= owner then
                return
            end
            saveFontSize(plugin, options, size)
            DetailFlow.showLoaded(plugin, source, result, options)
        end,
        close_callback = function()
            Dialog.clearIfOwned(plugin, "detail_viewer", viewer)
            local Shell = require("novel.ui.shell")
            Shell.flushPendingRender(plugin)
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
        Dialog.message(Dialog.failureMessage(result))
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
            Dialog.message(Dialog.canceledMessage())
            return
        end
        DetailFlow.showLoaded(plugin, source, result, options)
    end)
end

return DetailFlow
