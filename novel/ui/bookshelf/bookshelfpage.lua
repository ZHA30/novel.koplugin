local _ = require("novel.i18n")
local BookshelfFlow = require("novel.ui.bookshelf.flow")
local BookshelfSelection = require("novel.ui.bookshelf.selection")
local ChapterRecord = require("novel.reader.chapterrecord")
local ChaptersFlow = require("novel.ui.chapters.flow")
local ContentBuilder = require("novel.ui.contentbuilder")
local Manifest = require("novel.storage.manifest")
local SourceStore = require("novel.storage.sourcestore")

local BookshelfPage = {}

local function records(plugin)
    if not plugin or not plugin.app then
        return {}
    end
    return plugin.app:getBookshelfStore():list()
end

local function title(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function clean(value)
    value = tostring(value or "")
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function wholeNumber(value)
    value = tonumber(value)
    if not value or value < 0 then
        return 0
    end
    return math.floor(value)
end

local function sourceIndex(plugin)
    local index = {}
    local sources = plugin.app:getSourceStore():list()
    for source_index = 1, #sources do
        local source = sources[source_index]
        index[source.bookSourceUrl or ""] = source
    end
    return index
end

local function findCurrentSource(sources, record)
    local source_url = record.source_url or ""
    return sources[source_url] or record.source
end

local function sourceTitle(record, current_source)
    record = record or {}
    local book = record.book or {}
    local source_title = clean(SourceStore.title(current_source))
    if source_title == "" then
        source_title = clean(record.source_name)
    end
    if source_title == "" then
        source_title = clean(SourceStore.title(record.source))
    end
    if source_title == "" then
        source_title = clean(book.originName)
    end
    if source_title == "" then
        source_title = clean(book.origin)
    end
    if source_title == "" then
        source_title = clean(record.source_url)
    end
    return source_title
end

local function totalChapterCount(record)
    local book = record and record.book or {}
    local total = wholeNumber(book.totalChapterNum)
    if total > 0 then
        return total
    end

    total = wholeNumber(record and record.last_refresh_count)
    if total > 0 then
        return total
    end
    return 0
end

local function chapterStats(record)
    local stats = {
        downloaded = 0,
        total = 0,
        unread = nil,
    }
    if not record or not record.source or not record.book then
        return stats
    end
    local manifest = Manifest:loadByBook(record.source, record.book)
    if not manifest or not manifest.chapters then
        return stats
    end
    stats.unread = 0
    for position = 1, #manifest.chapters do
        local chapter = manifest.chapters[position]
        stats.total = stats.total + 1
        if chapter.downloaded then
            stats.downloaded = stats.downloaded + 1
        end
        if ChapterRecord.isOpenable(chapter) and chapter.read ~= true then
            stats.unread = stats.unread + 1
        end
    end
    return stats
end

local function subtitleSegments(record, current_source)
    local stats = chapterStats(record)
    local total = stats.total > 0 and stats.total or totalChapterCount(record)
    local segments = {}
    if stats.unread ~= nil then
        table.insert(segments, {
            icon = "check-check-off",
            text = tostring(stats.unread),
        })
    end
    if stats.downloaded > 0 then
        table.insert(segments, {
            icon = "arrow-down-to-line",
            text = tostring(stats.downloaded),
        })
    end
    if total > 0 then
        table.insert(segments, {
            icon = "list",
            text = tostring(total),
        })
    end
    local source = sourceTitle(record, current_source)
    if source ~= "" then
        table.insert(segments, {
            icon = "sources",
            text = source,
        })
    end
    return segments
end

function BookshelfPage.build(shell, plugin)
    local records_list = records(plugin)
    if #records_list == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    local sources = sourceIndex(plugin)
    local selection_mode = BookshelfSelection.isMode(plugin)
    local items = {}
    for index = 1, #records_list do
        local record = records_list[index]
        local source = findCurrentSource(sources, record)
        items[index] = {
            text = title(record.book),
            book = record.book,
            source_title = record.source_name,
            book_subtitle_segments = subtitleSegments(record, source),
            action_buttons = selection_mode and {
                {
                    id = "select",
                    icon = BookshelfSelection.isSelected(plugin, record)
                        and "square-check" or "square",
                    callback = function()
                        BookshelfFlow.toggleSelected(plugin, record)
                    end,
                },
            } or {
                {
                    id = "resume",
                    icon = "circle-play",
                    callback = function()
                        BookshelfFlow.resume(plugin, record)
                    end,
                },
                {
                    id = "more",
                    icon = "ellipsis-vertical",
                    callback = function()
                        if type(BookshelfFlow.showDetails) == "function" then
                            BookshelfFlow.showDetails(plugin, record)
                        end
                    end,
                },
            },
            callback = function()
                if selection_mode then
                    BookshelfFlow.toggleSelected(plugin, record)
                else
                    ChaptersFlow.show(plugin, source, record.book)
                end
            end,
        }
    end

    return ContentBuilder.buildList(shell, items)
end

return BookshelfPage
