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
            record.book = normalized
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

return Bookshelf
