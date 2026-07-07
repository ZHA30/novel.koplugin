local _ = require("novel.i18n")
local BookshelfFlow = require("novel.ui.bookshelf.flow")
local ChaptersFlow = require("novel.ui.chapters.flow")
local ContentBuilder = require("novel.ui.contentbuilder")

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

local function sourceTitle(record)
    record = record or {}
    local book = record.book or {}
    local source_title = clean(book.originName)
    if source_title == "" then
        source_title = clean(record.source_name)
    end
    if source_title == "" then
        source_title = clean(book.origin)
    end
    if source_title == "" then
        source_title = clean(record.source_url)
    end
    return source_title
end

local function readChapterCount(record)
    local current = record and record.current or nil
    local position = wholeNumber(current and current.chapter_position)
    if position > 0 then
        return position
    end

    local book = record and record.book or {}
    local index = wholeNumber(book.durChapterIndex)
    if index > 0 or clean(book.durChapterTitle) ~= "" then
        return index + 1
    end
    return 0
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

local function subtitleSegments(record)
    local total = totalChapterCount(record)
    local read = readChapterCount(record)
    if total > 0 and read > total then
        read = total
    end
    local segments = {
        {
            icon = "circle-check",
            text = tostring(read),
        },
        {
            icon = "list",
            text = tostring(total),
        },
    }
    local source = sourceTitle(record)
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
    local items = {}
    for index = 1, #records_list do
        local record = records_list[index]
        local source = findCurrentSource(sources, record)
        items[index] = {
            text = title(record.book),
            book = record.book,
            source_title = record.source_name,
            book_subtitle_segments = subtitleSegments(record),
            action_buttons = {
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
                ChaptersFlow.show(plugin, source, record.book)
            end,
        }
    end

    return ContentBuilder.buildList(shell, items)
end

return BookshelfPage
