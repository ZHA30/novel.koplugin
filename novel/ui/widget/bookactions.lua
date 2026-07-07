local _ = require("novel.i18n")
local ChaptersFlow = require("novel.ui.chapters.flow")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local SourceInfo = require("novel.catalog.shared.sourceinfo")

local BookActions = {}

local function copiedBooks(books)
    local copied = {}
    for index = 1, #(books or {}) do
        copied[index] = books[index]
    end
    return copied
end

local function bookshelf(plugin)
    if plugin and plugin.app then
        return plugin.app:getBookshelfStore()
    end
    return nil
end

local function bookKey(source, book)
    return SourceInfo.key(source) .. "\n" .. tostring(book and book.bookUrl or "")
end

local function bookshelfIndex(store)
    local records = {}
    if not store then
        return records
    end
    local list = store:list()
    for index = 1, #list do
        local record = list[index]
        if record.key then
            records[record.key] = record
        end
    end
    return records
end

local function updateBook(runtime, plugin, route, index, book, route_with)
    local books = copiedBooks(route.books)
    books[index] = book or books[index]
    runtime.replace(plugin, route_with(route, {
        books = books,
    }))
end

local function showDetail(runtime, plugin, route, index, book, route_with)
    DetailFlow.show(plugin, route.source, book, {
        on_visited = function(visited_book)
            updateBook(runtime, plugin, route, index, visited_book, route_with)
        end,
        on_bookshelf_changed = function(changed_book)
            updateBook(runtime, plugin, route, index, changed_book, route_with)
        end,
    })
end

local function resumeBook(plugin, route, book, record)
    local source = record and (record.source or route.source) or route.source
    local target_book = record and (record.book or book) or book
    local current = record and record.current or nil
    local position = current and (current.chapter_position
        or (current.chapter and 1)) or nil
    if position then
        ChaptersFlow.resume(plugin, source, target_book, position, {
            tab = route.tab,
        })
        return
    end
    ChaptersFlow.show(plugin, source, target_book, {
        tab = route.tab,
    })
end

local function toggleBookshelf(runtime, plugin, route, index, book, record, store, route_with)
    if not store then
        return
    end
    if record then
        if store:remove(record.source or route.source, record.book or book) then
            updateBook(runtime, plugin, route, index, book, route_with)
            Dialog.message(_("Removed from bookshelf."))
        else
            Dialog.message(Dialog.failureMessage())
        end
        return
    end

    local updated_record, err = store:add(route.source, book)
    if updated_record then
        updateBook(runtime, plugin, route, index, updated_record.book or book, route_with)
        Dialog.message(_("Added to bookshelf."))
        return
    end
    Dialog.message(Dialog.failureMessage(err))
end

function BookActions.context(plugin)
    local store = bookshelf(plugin)
    return {
        store = store,
        records = bookshelfIndex(store),
    }
end

function BookActions.detailCallback(runtime, plugin, route, index, book, route_with)
    return function()
        showDetail(runtime, plugin, route, index, book, route_with)
    end
end

function BookActions.buttons(runtime, plugin, route, index, book, context, route_with)
    context = context or BookActions.context(plugin)
    local record = context.records and context.records[bookKey(route.source, book)] or nil
    return {
        {
            id = "add",
            icon = record and "book-check" or "book",
            callback = function()
                toggleBookshelf(runtime, plugin, route, index, book, record,
                    context.store, route_with)
            end,
        },
        {
            id = "resume",
            icon = "circle-play",
            callback = function()
                resumeBook(plugin, route, book, record)
            end,
        },
        {
            id = "more",
            icon = "ellipsis-vertical",
            callback = function()
                showDetail(runtime, plugin, route, index, book, route_with)
            end,
        },
    }
end

return BookActions
