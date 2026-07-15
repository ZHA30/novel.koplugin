local _ = require("novel.i18n")
local BookshelfLifecycle = require("novel.bookshelflifecycle")
local ActionDialog = require("novel.ui.widget.actiondialog")
local ChapterCache = require("novel.reader.chaptercache")
local ChapterDownload = require("novel.reader.chapterdownload")
local ChaptersFlow = require("novel.ui.chapters.flow")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")
local Manifest = require("novel.storage.manifest")
local RefreshFlow = require("novel.ui.refreshflow")
local SourceInfo = require("novel.catalog.shared.sourceinfo")
local UIManager = require("ui/uimanager")

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

local function bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function notifyBookshelfChanged(options, book, added)
    if options and type(options.on_bookshelf_changed) == "function" then
        options.on_bookshelf_changed(book, added)
    end
end

local function showMenuIntro(plugin, source, book, options)
    DetailFlow.show(plugin, source, book, {
        tab = options and options.tab,
        on_visited = function(visited_book)
            if options and type(options.on_book_changed) == "function" then
                options.on_book_changed(visited_book or book)
            end
        end,
    })
end

local function downloadBook(plugin, source, book, options)
    local manifest = Manifest:new():loadByBook(source, book)
    local function enqueue(current_manifest)
        local positions = {}
        for position = 1, #(current_manifest and current_manifest.chapters or {}) do
            table.insert(positions, position)
        end
        local download_positions = ChapterCache.cacheablePositions(current_manifest, positions)
        if #download_positions == 0 then
            Dialog.message(_("No chapters to download."))
            return
        end
        Dialog.confirm(
            string.format(_("Download %d chapters?"), #download_positions),
            _("Download"),
            function()
                ChapterDownload.enqueue(plugin, current_manifest, download_positions, {
                    on_done = function()
                        notifyBookshelfChanged(options, book, true)
                    end,
                })
            end
        )
    end

    if manifest and #(manifest.chapters or {}) > 0 then
        enqueue(manifest)
        return
    end

    RefreshFlow.refreshBook(plugin, source, book, {
        message = false,
        require_bookshelf = true,
        on_done = function(applied)
            notifyBookshelfChanged(options,
                applied.record and applied.record.book or book, true)
            enqueue(applied.manifest)
        end,
    })
end

local function toggleMenuBookshelf(plugin, source, book, record, options)
    if not plugin or not plugin.app then
        return
    end
    if record then
        Dialog.confirm(
            _("Remove book from bookshelf?"),
            _("Remove"),
            function()
                if BookshelfLifecycle.remove(plugin, record.source or source,
                    record.book or book) then
                    notifyBookshelfChanged(options, book, false)
                    Dialog.message(_("Removed from bookshelf."))
                else
                    Dialog.message(Dialog.failureMessage())
                end
            end
        )
        return
    end

    local added_record, err = plugin.app:getBookshelfStore():add(source, book)
    if added_record then
        notifyBookshelfChanged(options, added_record.book or book, true)
        Dialog.message(_("Added to bookshelf."))
    else
        Dialog.message(Dialog.failureMessage(err))
    end
end

local function updateBook(runtime, plugin, route, index, book, route_with)
    local books = copiedBooks(route.books)
    books[index] = book or books[index]
    local updated_route = route_with(route, {
        books = books,
    })
    local current = runtime.currentRoute and runtime.currentRoute(plugin)
    if current and current.key == "detail"
        and type(runtime.replacePrevious) == "function" then
        runtime.replacePrevious(plugin, updated_route)
        return
    end
    runtime.replace(plugin, updated_route)
end

local function showDetail(runtime, plugin, route, index, book, route_with)
    DetailFlow.show(plugin, route.source, book, {
        tab = route.tab,
        on_visited = function(visited_book)
            updateBook(runtime, plugin, route, index, visited_book, route_with)
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
        if BookshelfLifecycle.remove(plugin, record.source or route.source,
            record.book or book) then
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

function BookActions.showMenu(plugin, source, book, record, options)
    if not plugin or not source or not book then
        return
    end
    options = options or {}
    local in_bookshelf = record ~= nil
    UIManager:show(ActionDialog:new{
        title = bookTitle(book),
        actions = {
            {
                icon = "info",
                text = _("Intro"),
                callback = function()
                    showMenuIntro(plugin, source, book, options)
                end,
            },
            {
                icon = "list",
                text = _("Table of contents"),
                callback = function()
                    ChaptersFlow.show(plugin, source, book, {
                        tab = options.tab,
                    })
                end,
            },
            {
                icon = "rotate-cw",
                text = _("Refresh"),
                enabled = in_bookshelf,
                callback = function()
                    RefreshFlow.refreshBook(plugin, source, book, {
                        require_bookshelf = true,
                        on_done = function(applied)
                            notifyBookshelfChanged(options,
                                applied.record and applied.record.book or book, true)
                        end,
                    })
                end,
            },
            {
                icon = "arrow-down-to-line",
                text = _("Download"),
                enabled = in_bookshelf,
                callback = function()
                    downloadBook(plugin, source, book, options)
                end,
            },
            {
                icon = in_bookshelf and "trash-2" or "book",
                text = in_bookshelf and _("Remove") or _("Add to bookshelf"),
                callback = function()
                    toggleMenuBookshelf(plugin, source, book, record, options)
                end,
            },
        },
    })
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
                BookActions.showMenu(plugin,
                    record and (record.source or route.source) or route.source,
                    record and (record.book or book) or book, record, {
                        tab = route.tab,
                        on_book_changed = function(changed_book)
                            updateBook(runtime, plugin, route, index, changed_book,
                                route_with)
                        end,
                        on_bookshelf_changed = function(changed_book)
                            updateBook(runtime, plugin, route, index, changed_book,
                                route_with)
                        end,
                    })
            end,
        },
    }
end

return BookActions
