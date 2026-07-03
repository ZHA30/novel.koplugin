local Cache = require("novel.storage.cache")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local util = require("util")

local Manifest = {
    root_dir = DataStorage:getDataDir() .. "/novel/books",
    schema_version = 1,
}
Manifest.__index = Manifest

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

local function clean(value)
    value = tostring(value or ""):gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function safeId(value)
    return tostring(value or ""):gsub("[^%w._-]", "_")
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

local function bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return bookUrl(book)
end

local function chapterIdentity(chapter, position)
    chapter = chapter or {}
    local url = clean(chapter.url)
    if url ~= "" then
        return "url:" .. url
    end
    return "title:" .. clean(chapter.title) .. ":" .. tostring(position or 0)
end

local function chapterId(chapter, position)
    chapter = chapter or {}
    local url = clean(chapter.url)
    local key = Cache.makeKey("chapter", {
        url = url,
        base = clean(chapter.baseUrl),
        title = url == "" and clean(chapter.title) or nil,
        fallback_position = url == "" and position or nil,
    })
    return safeId((key:match("^[^:]+:(.+)$") or key))
end

local function stripRuntimeFields(manifest)
    local copy = clone(manifest or {})
    for chapter_index = 1, #(copy.chapters or {}) do
        copy.chapters[chapter_index].file_path = nil
    end
    return copy
end

function Manifest:new()
    return setmetatable({}, self)
end

function Manifest.bookId(source, book)
    local url = bookUrl(book)
    local key = Cache.makeKey("book", {
        source = sourceUrl(source),
        book = url,
        title = url == "" and bookTitle(book) or nil,
    })
    return safeId(key)
end

function Manifest.bookDir(book_id)
    return Manifest.root_dir .. "/" .. book_id
end

function Manifest.chaptersDir(book_id)
    return Manifest.bookDir(book_id) .. "/chapters"
end

function Manifest.manifestPath(book_id)
    return Manifest.bookDir(book_id) .. "/manifest.lua"
end

function Manifest.chapterPath(book_id, chapter)
    return Manifest.chaptersDir(book_id) .. "/" .. chapter.file_name
end

function Manifest.normalizeManifest(manifest)
    if type(manifest) ~= "table" or manifest.book_id == nil then
        return nil
    end

    manifest.schema_version = manifest.schema_version or Manifest.schema_version
    manifest.chapters = manifest.chapters or {}
    for position = 1, #manifest.chapters do
        local chapter = manifest.chapters[position]
        chapter.position = position
        chapter.file_name = chapter.file_name
            or (chapterId(chapter, position) .. ".html")
        chapter.file_path = Manifest.chapterPath(manifest.book_id, chapter)
        chapter.downloaded = util.pathExists(chapter.file_path) or false
    end
    return manifest
end

function Manifest:load(book_id)
    if not book_id or book_id == "" then
        return nil
    end
    local path = self.manifestPath(book_id)
    if not util.pathExists(path) then
        return nil
    end
    local settings = LuaSettings:open(path)
    return self.normalizeManifest(settings:readSetting("manifest"))
end

function Manifest:loadByBook(source, book)
    return self:load(Manifest.bookId(source, book))
end

function Manifest:save(manifest)
    if type(manifest) ~= "table" or not manifest.book_id then
        return nil, "manifest is required"
    end
    local ok, err = util.makePath(self.bookDir(manifest.book_id))
    if not ok then
        return nil, err
    end
    manifest.schema_version = Manifest.schema_version
    manifest.updated_at = now()
    local settings = LuaSettings:open(self.manifestPath(manifest.book_id))
    settings:saveSetting("manifest", stripRuntimeFields(manifest))
    settings:flush()
    return self.normalizeManifest(manifest)
end

function Manifest:ensureBook(source, book, chapters)
    chapters = chapters or {}
    local book_id = Manifest.bookId(source, book)
    local existing = self:load(book_id) or {}
    local by_identity = {}
    for position = 1, #(existing.chapters or {}) do
        local chapter = existing.chapters[position]
        by_identity[chapterIdentity(chapter, position)] = chapter
    end

    local manifest = {
        schema_version = Manifest.schema_version,
        book_id = book_id,
        source = clone(source or existing.source or {}),
        source_url = sourceUrl(source or existing.source),
        source_name = sourceName(source or existing.source),
        book = clone(book or existing.book or {}),
        book_url = bookUrl(book or existing.book),
        book_title = bookTitle(book or existing.book),
        chapters = {},
        current_position = existing.current_position,
        created_at = existing.created_at or now(),
        updated_at = now(),
    }

    for position = 1, #chapters do
        local chapter = clone(chapters[position])
        chapter.position = position
        chapter.file_name = chapterId(chapter, position) .. ".html"
        local old = by_identity[chapterIdentity(chapter, position)]
        if old then
            chapter.read = old.read == true
            chapter.read_at = old.read_at
            chapter.last_opened_at = old.last_opened_at
            chapter.content_type = old.content_type
        end
        chapter.file_path = Manifest.chapterPath(book_id, chapter)
        chapter.downloaded = util.pathExists(chapter.file_path) or false
        table.insert(manifest.chapters, chapter)
    end

    return self:save(manifest)
end

function Manifest:findChapterByFile(file)
    file = tostring(file or "")
    local prefix = Manifest.root_dir .. "/"
    if file:sub(1, #prefix) ~= prefix then
        return nil
    end

    local rest = file:sub(#prefix + 1)
    local book_id, file_name = rest:match("^([^/]+)/chapters/([^/]+%.html)$")
    if not book_id or not file_name then
        return nil
    end

    local manifest = self:load(book_id)
    if not manifest then
        return nil
    end
    for position = 1, #(manifest.chapters or {}) do
        local chapter = manifest.chapters[position]
        if chapter.file_name == file_name then
            return {
                book_id = book_id,
                manifest = manifest,
                position = position,
                chapter = chapter,
            }
        end
    end
    return nil
end

function Manifest.chapterFileExists(manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    return chapter and chapter.file_path and util.pathExists(chapter.file_path) or false
end

function Manifest:saveChapter(manifest, position, html, options)
    options = options or {}
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return nil, "chapter is missing"
    end

    local ok, err = util.makePath(Manifest.chaptersDir(manifest.book_id))
    if not ok then
        return nil, err
    end
    local written, write_err = util.writeToFile(html, chapter.file_path, true)
    if not written then
        return nil, write_err
    end

    chapter.downloaded = true
    chapter.downloaded_at = now()
    chapter.content_type = options.content_type or "text"
    self:save(manifest)
    return chapter.file_path
end

function Manifest:updateCurrent(manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return false
    end
    manifest.current_position = position
    chapter.last_opened_at = now()
    self:save(manifest)
    return true
end

function Manifest:markRead(manifest, position, read)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return false
    end
    chapter.read = read ~= false
    chapter.read_at = now()
    self:save(manifest)
    return true
end

function Manifest.deleteStorage()
    local ok, ffi_util = pcall(require, "ffi/util")
    if ok and ffi_util and ffi_util.purgeDir then
        ffi_util.purgeDir(Manifest.root_dir)
    end
end

return Manifest
