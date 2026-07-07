local _ = require("novel.i18n")
local BookshelfFlow = require("novel.ui.bookshelf.flow")
local ChaptersFlow = require("novel.ui.chapters.flow")
local ContentBuilder = require("novel.ui.contentbuilder")
local Manifest = require("novel.storage.manifest")

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

local function findCurrentSource(plugin, record)
    local source_url = record.source_url or ""
    local sources = plugin.app:getSourceStore():list()
    for index = 1, #sources do
        local source = sources[index]
        if source.bookSourceUrl == source_url then
            return source
        end
    end
    return record.source
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

local function readChapterCount(record, manifest)
    local current = record and record.current or nil
    local position = wholeNumber(current and current.chapter_position)
    if position > 0 then
        return position
    end

    position = wholeNumber(manifest and manifest.current_position)
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

local function totalChapterCount(record, manifest)
    local book = record and record.book or {}
    local total = wholeNumber(book.totalChapterNum)
    if total > 0 then
        return total
    end

    total = wholeNumber(record and record.last_refresh_count)
    if total > 0 then
        return total
    end
    total = #(manifest and manifest.chapters or {})
    if total > 0 then
        return total
    end
    return 0
end

local function subtitleParts(record, manifest)
    local total = totalChapterCount(record, manifest)
    local read = readChapterCount(record, manifest)
    if total > 0 and read > total then
        read = total
    end
    local parts = {
        tostring(read) .. "/" .. tostring(total),
    }
    local source = sourceTitle(record)
    if source ~= "" then
        table.insert(parts, source)
    end
    return parts
end

function BookshelfPage.build(shell, plugin)
    local records_list = records(plugin)
    if #records_list == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    local manifest_store = Manifest:new()
    local items = {}
    for index = 1, #records_list do
        local record = records_list[index]
        local source = findCurrentSource(plugin, record)
        local manifest = manifest_store:loadByBook(source, record.book)
        items[index] = {
            text = title(record.book),
            book = record.book,
            source_title = record.source_name,
            book_subtitle_parts = subtitleParts(record, manifest),
            book_subtitle_parts_only = true,
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
