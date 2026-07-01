local Book = require("novel.model.book")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Bookshelf = {
    path = DataStorage:getSettingsDir() .. "/novel_bookshelf.lua",
}
Bookshelf.__index = Bookshelf

local function now()
    return os.time()
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function sourceUrl(source)
    return source and source.bookSourceUrl or ""
end

local function sourceName(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return sourceUrl(source)
end

local function bookUrl(book)
    return book and book.bookUrl or ""
end

local function bookKey(source, book)
    return sourceUrl(source) .. "\n" .. bookUrl(book)
end

local function sortRecords(records)
    table.sort(records, function(left, right)
        if (left.updated_time or 0) ~= (right.updated_time or 0) then
            return (left.updated_time or 0) > (right.updated_time or 0)
        end
        local left_name = left.book and left.book.name or ""
        local right_name = right.book and right.book.name or ""
        return left_name < right_name
    end)
end

local function normalizeBook(source, book)
    local normalized = Book.new(book)
    if normalized.latestChapterTitle == "" and book and book.latestChapter then
        normalized.latestChapterTitle = book.latestChapter
    end
    if normalized.origin == "" then
        normalized.origin = sourceUrl(source)
    end
    if normalized.originName == "" then
        normalized.originName = sourceName(source)
    end
    return normalized
end

local function normalizeRecord(record)
    record = record or {}
    record.source = clone(record.source or {})
    record.source_url = record.source_url or sourceUrl(record.source)
    record.source_name = record.source_name or sourceName(record.source)
    record.book = normalizeBook(record.source, record.book or {})
    record.key = record.key or bookKey(record.source, record.book)
    record.added_time = record.added_time or now()
    record.updated_time = record.updated_time or record.added_time
    record.current = record.current or nil
    return record
end

local function preserveProgress(book, record)
    record = record or {}
    local old_book = record.book or {}
    book.durChapterTitle = old_book.durChapterTitle or book.durChapterTitle
    book.durChapterIndex = old_book.durChapterIndex or book.durChapterIndex
    book.durChapterPos = old_book.durChapterPos or book.durChapterPos
    book.durChapterTime = old_book.durChapterTime or book.durChapterTime
    return book
end

local function switchProgress(record, timestamp)
    if type(record.current) ~= "table" then
        return nil
    end
    local current = clone(record.current)
    if current.chapter and current.chapter.title then
        current.chapter_title = current.chapter.title
    end
    current.chapter = nil
    current.updated_time = timestamp
    return current
end

local function chapterAt(chapters, position)
    if type(chapters) ~= "table" then
        return nil
    end
    return chapters[tonumber(position) or 1]
end

local function mergeResultLists(left, right)
    local merged = {}
    for index = 1, #(left or {}) do
        table.insert(merged, left[index])
    end
    for index = 1, #(right or {}) do
        table.insert(merged, right[index])
    end
    return merged
end

local function serviceError(stage, result)
    result = result or {}
    return {
        ok = false,
        stage = stage,
        error = result.error or {
            kind = stage,
            message = stage .. " failed",
        },
        debug = result.debug or {},
        unsupported = result.unsupported or {},
    }
end

function Bookshelf:new()
    return setmetatable({
        settings = LuaSettings:open(Bookshelf.path),
    }, self)
end

function Bookshelf:list()
    local records = self.settings:readSetting("books") or {}
    local normalized = {}
    for record_index = 1, #records do
        table.insert(normalized, normalizeRecord(records[record_index]))
    end
    sortRecords(normalized)
    return normalized
end

function Bookshelf:saveAll(records)
    sortRecords(records)
    self.settings:saveSetting("books", records)
    self.settings:flush()
end

function Bookshelf:count()
    return #self:list()
end

function Bookshelf:get(source, book)
    local key = bookKey(source, book)
    for record_index, record in ipairs(self:list()) do
        if record.key == key then
            return record, record_index
        end
    end
    return nil
end

function Bookshelf:has(source, book)
    return self:get(source, book) ~= nil
end

function Bookshelf:add(source, book)
    local records = self:list()
    local key = bookKey(source, book)
    if key == "\n" then
        return nil, "missing book source or URL"
    end

    local timestamp = now()
    local normalized = normalizeBook(source, book)
    for record_index = 1, #records do
        local record = records[record_index]
        if record.key == key then
            record.source = clone(source)
            record.source_url = sourceUrl(source)
            record.source_name = sourceName(source)
            record.book = preserveProgress(normalized, record)
            record.updated_time = timestamp
            self:saveAll(records)
            return record
        end
    end

    local record = {
        key = key,
        source = clone(source),
        source_url = sourceUrl(source),
        source_name = sourceName(source),
        book = normalized,
        added_time = timestamp,
        updated_time = timestamp,
    }
    table.insert(records, record)
    self:saveAll(records)
    return record
end

function Bookshelf:remove(source, book)
    local key = bookKey(source, book)
    local records = self:list()
    local removed = false
    for record_index = #records, 1, -1 do
        if records[record_index].key == key then
            table.remove(records, record_index)
            removed = true
            break
        end
    end
    if removed then
        self:saveAll(records)
    end
    return removed
end

function Bookshelf:applyRefresh(source, book, refresh)
    if not refresh or not refresh.ok or type(refresh.book) ~= "table" then
        return nil, "invalid refresh result"
    end

    local key = bookKey(source, book)
    local records = self:list()
    for record_index = 1, #records do
        local record = records[record_index]
        if record.key == key then
            local timestamp = now()
            local updated_book = preserveProgress(normalizeBook(source, refresh.book), record)
            local current = record.current
            if current and current.chapter_position then
                local chapter = chapterAt(refresh.chapters, current.chapter_position)
                if chapter then
                    current = clone(current)
                    current.chapter = chapter
                    current.updated_time = timestamp
                    updated_book.durChapterTitle = chapter.title or updated_book.durChapterTitle
                    updated_book.durChapterIndex = math.max((tonumber(current.chapter_position) or 1) - 1, 0)
                    updated_book.durChapterPos = tonumber(current.chapter_pos) or 0
                    updated_book.durChapterTime = timestamp
                end
            end
            record.source = clone(source)
            record.source_url = sourceUrl(source)
            record.source_name = sourceName(source)
            record.book = updated_book
            record.current = current
            record.updated_time = timestamp
            record.last_refresh_time = timestamp
            record.last_refresh_count = #(refresh.chapters or {})
            self:saveAll(records)
            return record
        end
    end
    return nil, "book is not in bookshelf"
end

function Bookshelf:applySwitch(record, new_source, new_book)
    if type(record) ~= "table" then
        return nil, "book record is required"
    end
    if type(new_source) ~= "table" or type(new_book) ~= "table" then
        return nil, "target source and book are required"
    end

    local old_key = record.key or bookKey(record.source, record.book)
    local new_key = bookKey(new_source, new_book)
    if old_key == "\n"
        or (record.source_url or sourceUrl(record.source)) == ""
        or bookUrl(record.book) == "" then
        return nil, "source book is missing URL"
    end
    if sourceUrl(new_source) == "" or bookUrl(new_book) == "" then
        return nil, "target book is missing URL"
    end

    local records = self:list()
    local record_position
    for record_index = 1, #records do
        local existing = records[record_index]
        if existing.key == new_key and existing.key ~= old_key then
            return nil, "target book is already in bookshelf"
        end
        if existing.key == old_key then
            record_position = record_index
        end
    end
    if not record_position then
        return nil, "book is not in bookshelf"
    end

    local previous_source = {
        source_url = record.source_url or sourceUrl(record.source),
        source_name = record.source_name or sourceName(record.source),
        book_url = record.book and record.book.bookUrl or "",
    }
    local timestamp = now()
    local stored = records[record_position]
    stored.key = new_key
    stored.source = clone(new_source)
    stored.source_url = sourceUrl(new_source)
    stored.source_name = sourceName(new_source)
    stored.book = preserveProgress(normalizeBook(new_source, new_book), stored)
    stored.current = switchProgress(stored, timestamp)
    stored.updated_time = timestamp
    stored.last_switch_time = timestamp
    stored.previous_source = previous_source
    stored.last_refresh_time = nil
    stored.last_refresh_count = nil
    self:saveAll(records)
    return stored
end

function Bookshelf:updateProgress(source, book, chapter, position, chapter_pos)
    local record = self:get(source, book)
    if not record then
        return false
    end

    local records = self:list()
    local key = bookKey(source, book)
    for record_index = 1, #records do
        if records[record_index].key == key then
            local timestamp = now()
            local updated_book = normalizeBook(source, book)
            local chapter_index = tonumber(position) or 1
            updated_book.durChapterIndex = math.max(chapter_index - 1, 0)
            updated_book.durChapterPos = tonumber(chapter_pos) or 0
            updated_book.durChapterTitle = chapter and chapter.title or ""
            updated_book.durChapterTime = timestamp
            records[record_index].book = updated_book
            records[record_index].source = clone(source)
            records[record_index].source_url = sourceUrl(source)
            records[record_index].source_name = sourceName(source)
            records[record_index].current = {
                chapter = clone(chapter),
                chapter_position = chapter_index,
                chapter_pos = tonumber(chapter_pos) or 0,
                updated_time = timestamp,
            }
            records[record_index].updated_time = timestamp
            self:saveAll(records)
            return true
        end
    end
    return false
end

function Bookshelf:clear()
    self:saveAll({})
end

function Bookshelf.deleteStorage()
    os.remove(Bookshelf.path)
    os.remove(Bookshelf.path .. ".old")
end

function Bookshelf.fetchRefresh(source, book, options)
    options = options or {}
    local BookInfo = options.bookinfo or require("novel.service.bookinfo")
    local Toc = options.toc or require("novel.service.toc")

    local detail = BookInfo.run(source, book, {
        refresh = true,
        use_info_html = false,
        timeout = options.timeout,
        total_timeout = options.total_timeout,
        max_redirects = options.max_redirects,
    })
    if not detail or not detail.ok then
        return serviceError("detail", detail)
    end

    local toc = Toc.run(source, detail.book, {
        refresh = true,
        use_toc_html = false,
        timeout = options.timeout,
        total_timeout = options.total_timeout,
        max_redirects = options.max_redirects,
        max_pages = options.max_pages,
    })
    if not toc or not toc.ok then
        return serviceError("toc", toc)
    end

    return {
        ok = true,
        book = toc.book or detail.book,
        chapters = toc.chapters or {},
        debug = mergeResultLists(detail.debug, toc.debug),
        unsupported = mergeResultLists(detail.unsupported, toc.unsupported),
        detail = detail.response,
        toc = toc.pages,
    }
end

function Bookshelf:refresh(source, book, options)
    local result = Bookshelf.fetchRefresh(source, book, options)
    if not result.ok then
        return result
    end
    local record, err = self:applyRefresh(source, book, result)
    if not record then
        result.ok = false
        result.error = {
            kind = "bookshelf",
            message = err,
        }
        return result
    end
    result.record = record
    return result
end

return Bookshelf
