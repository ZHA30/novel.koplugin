local _ = require("novel.i18n")
local ChaptersFlow = require("novel.ui.chapters.flow")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailFlow = require("novel.ui.detail.flow")
local DetailVisits = require("novel.ui.detail.detailvisits")
local Dialog = require("novel.ui.widget.dialog")
local ShellRoutes = require("novel.ui.shellroutes")
local SourceInfo = require("novel.catalog.shared.sourceinfo")

local DiscoverResultsPage = {}

local function copiedBooks(books)
    local copied = {}
    for index = 1, #(books or {}) do
        copied[index] = books[index]
    end
    return copied
end

local function routeWith(route, patch)
    local copied = ShellRoutes.discoverResults(route)
    for key, value in pairs(patch or {}) do
        copied[key] = value
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

local function updateBook(runtime, plugin, route, index, book)
    local books = copiedBooks(route.books)
    books[index] = book or books[index]
    runtime.replace(plugin, routeWith(route, {
        books = books,
    }))
end

local function showDetail(runtime, plugin, route, index, book)
    DetailFlow.show(plugin, route.source, book, {
        on_visited = function(visited_book)
            updateBook(runtime, plugin, route, index, visited_book)
        end,
        on_bookshelf_changed = function(changed_book)
            updateBook(runtime, plugin, route, index, changed_book)
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

local function toggleBookshelf(runtime, plugin, route, index, book, record, store)
    if not store then
        return
    end
    if record then
        if store:remove(record.source or route.source, record.book or book) then
            updateBook(runtime, plugin, route, index, book)
            Dialog.message(_("Removed from bookshelf."))
        else
            Dialog.message(_("Remove from bookshelf failed."))
        end
        return
    end

    local updated_record, err = store:add(route.source, book)
    if updated_record then
        updateBook(runtime, plugin, route, index, updated_record.book or book)
        Dialog.message(_("Added to bookshelf."))
        return
    end
    Dialog.message(_("Add to bookshelf failed: ") .. tostring(err))
end

local function bookActions(runtime, plugin, route, index, book, store, records)
    local record = records and records[bookKey(route.source, book)] or nil
    return {
        {
            id = "add",
            icon = record and "book-check" or "book",
            callback = function()
                toggleBookshelf(runtime, plugin, route, index, book, record, store)
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
                showDetail(runtime, plugin, route, index, book)
            end,
        },
    }
end

function DiscoverResultsPage.build(shell, plugin, route, runtime)
    if route.loading and #(route.books or {}) == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Loading"), _("Loading results..."))
    end

    if route.error and #(route.books or {}) == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), tostring(route.error))
    end

    local items = {}
    local store = bookshelf(plugin)
    local records = bookshelfIndex(store)
    if route.unsupported and #route.unsupported > 0 then
        table.insert(items, {
            title = _("Unsupported rules"),
            mandatory = tostring(#route.unsupported),
            callback = function()
                Dialog.showUnsupported(route.unsupported)
            end,
        })
    end

    for index = 1, #(route.books or {}) do
        local book = route.books[index]
        table.insert(items, {
            text = book.name,
            book = book,
            source_title = route.source_name,
            dim = DetailVisits.isVisited(plugin, route.source, book),
            action_buttons = bookActions(runtime, plugin, route, index, book,
                store, records),
            callback = function()
                showDetail(runtime, plugin, route, index, book)
            end,
        })
    end

    if #items == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Empty"), _("No results."))
    end

    if route.error then
        table.insert(items, {
            title = _("Last request failed"),
            subtitle = tostring(route.error),
            dim = true,
        })
    end

    return ContentBuilder.buildList(shell, items)
end

return DiscoverResultsPage
