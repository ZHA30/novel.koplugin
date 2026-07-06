local _ = require("novel.i18n")
local ChapterRecord = require("novel.reader.chapterrecord")

local ChapterListing = {}

ChapterListing.FILTER_ALL = "all"
ChapterListing.FILTER_UNREAD = "unread"

ChapterListing.SORT_ASCENDING = "ascending"
ChapterListing.SORT_DESCENDING = "descending"

function ChapterListing.refreshManifest(manifest_store, manifest, source, book)
    if not manifest or not source then
        return manifest
    end
    local refreshed = manifest_store:ensureBook(source, book or manifest.book,
        manifest.chapters or {})
    return refreshed or manifest
end

function ChapterListing.bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

function ChapterListing.manifestTitle(manifest)
    return ChapterListing.bookTitle(manifest and manifest.book)
end

function ChapterListing.filterLabel(filter)
    if filter == ChapterListing.FILTER_UNREAD then
        return _("Unread")
    end
    return _("All")
end

function ChapterListing.sortLabel(sort)
    if sort == ChapterListing.SORT_DESCENDING then
        return _("Descending")
    end
    return _("Ascending")
end

local function chapterTitle(chapter)
    return tostring(chapter.title or "")
end

local function matchesFilter(filter, chapter)
    if filter == ChapterListing.FILTER_UNREAD then
        return chapter.read ~= true and ChapterRecord.isOpenable(chapter)
    end
    return true
end

function ChapterListing.normalizeFilter(filter)
    if filter == ChapterListing.FILTER_UNREAD then
        return ChapterListing.FILTER_UNREAD
    end
    return ChapterListing.FILTER_ALL
end

function ChapterListing.normalizeSort(sort)
    if sort == ChapterListing.SORT_DESCENDING then
        return ChapterListing.SORT_DESCENDING
    end
    return ChapterListing.SORT_ASCENDING
end

local function chapterListBooks(plugin)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil
    end
    if type(settings.chapter_list) ~= "table" then
        settings.chapter_list = {}
    end
    if type(settings.chapter_list.books) ~= "table" then
        settings.chapter_list.books = {}
    end
    return settings.chapter_list.books
end

local function chapterListBookState(plugin, book_id, create)
    if not book_id or book_id == "" then
        return nil
    end

    local books = chapterListBooks(plugin)
    if not books then
        return nil
    end

    local state = books[book_id]
    if type(state) ~= "table" then
        if not create then
            return nil
        end
        state = {}
        books[book_id] = state
    end
    return state
end

local function saveBookState(plugin, book_id, filter, sort)
    local state = chapterListBookState(plugin, book_id, true)
    if not state then
        return
    end

    local changed = false
    if state.filter ~= filter then
        state.filter = filter
        changed = true
    end
    if state.sort ~= sort then
        state.sort = sort
        changed = true
    end

    if changed and plugin and plugin.app then
        plugin.app:saveSettings()
    end
end

function ChapterListing.resolveState(plugin, manifest, options)
    options = options or {}
    local book_id = manifest and manifest.book_id or nil
    local book_state = chapterListBookState(plugin, book_id)
    plugin.novel_chapters_filter = plugin.novel_chapters_filter or {}
    plugin.novel_chapters_sort = plugin.novel_chapters_sort or {}

    local filter = options.filter
        or (book_id and plugin.novel_chapters_filter[book_id])
        or (book_state and book_state.filter)
        or ChapterListing.FILTER_ALL
    filter = ChapterListing.normalizeFilter(filter)
    if book_id then
        plugin.novel_chapters_filter[book_id] = filter
    end

    local sort = options.sort
        or (book_id and plugin.novel_chapters_sort[book_id])
        or (book_state and book_state.sort)
        or ChapterListing.SORT_ASCENDING
    sort = ChapterListing.normalizeSort(sort)
    if book_id then
        plugin.novel_chapters_sort[book_id] = sort
    end

    if options.filter ~= nil or options.sort ~= nil
        or (book_state and (book_state.filter ~= filter
            or book_state.sort ~= sort)) then
        saveBookState(plugin, book_id, filter, sort)
    end

    return filter, sort
end

function ChapterListing.buildRows(manifest, filter, sort)
    local rows = {}
    local chapters = manifest and manifest.chapters or {}
    local shown_count = 0
    local start_position = sort == ChapterListing.SORT_DESCENDING and #chapters or 1
    local end_position = sort == ChapterListing.SORT_DESCENDING and 1 or #chapters
    local step = sort == ChapterListing.SORT_DESCENDING and -1 or 1

    for position = start_position, end_position, step do
        local chapter = chapters[position]
        if matchesFilter(filter, chapter) then
            local openable = ChapterRecord.isOpenable(chapter)
            shown_count = shown_count + 1
            table.insert(rows, {
                position = position,
                title = chapterTitle(chapter),
                openable = openable,
                dim = chapter.read == true or not openable,
            })
        end
    end

    if shown_count == 0 then
        table.insert(rows, {
            title = _("No chapters."),
            openable = false,
            dim = true,
            empty = true,
        })
    end

    return rows, shown_count
end

return ChapterListing
