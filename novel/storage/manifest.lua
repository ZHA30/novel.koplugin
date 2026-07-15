local Cache = require("novel.storage.cache")
local DataStorage = require("datastorage")
local dump = require("dump")
local FileLock = require("novel.storage.filelock")
local ffiUtil = require("ffi/util")
local LuaSettings = require("luasettings")
local util = require("util")

local Manifest = {
    root_dir = DataStorage:getDataDir() .. "/novel/books",
    schema_version = 1,
}
Manifest.__index = Manifest
local write_serial = 0

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
    local sanitized = tostring(value or ""):gsub("[^%w._-]", "_")
    return sanitized
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

local function chapterTitleKey(chapter)
    local title = clean(chapter and chapter.title)
    if title == "" then
        return ""
    end
    return title:lower()
end

local function buildChapterIndexes(chapters)
    local by_identity = {}
    local by_title = {}
    local title_counts = {}
    for position = 1, #(chapters or {}) do
        local chapter = chapters[position]
        by_identity[chapterIdentity(chapter, position)] = chapter
        local title_key = chapterTitleKey(chapter)
        if title_key ~= "" then
            title_counts[title_key] = (title_counts[title_key] or 0) + 1
            by_title[title_key] = chapter
        end
    end
    return by_identity, by_title, title_counts
end

local function oldChapterFor(chapter, position, by_identity, by_title, title_counts)
    local old = by_identity[chapterIdentity(chapter, position)]
    if old then
        return old
    end
    local title_key = chapterTitleKey(chapter)
    if title_key ~= "" and title_counts[title_key] == 1 then
        return by_title[title_key]
    end
    return nil
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
        chapter.downloaded = chapter.downloaded == true
    end
    return manifest
end

function Manifest:load(book_id)
    if not book_id or book_id == "" then
        return nil
    end
    local path = self.manifestPath(book_id)
    if not util.pathExists(path) and not util.pathExists(path .. ".old") then
        return nil
    end
    local settings = LuaSettings:open(path)
    return self.normalizeManifest(settings:readSetting("manifest"))
end

function Manifest:loadByBook(source, book)
    return self:load(Manifest.bookId(source, book))
end

function Manifest:saveUnlocked(manifest)
    if type(manifest) ~= "table" or not manifest.book_id then
        return nil, "manifest is required"
    end
    local ok, err = util.makePath(self.bookDir(manifest.book_id))
    if not ok then
        return nil, err
    end
    manifest.schema_version = Manifest.schema_version
    manifest.updated_at = now()
    local path = self.manifestPath(manifest.book_id)
    write_serial = write_serial + 1
    local temporary_path = path .. ".tmp." .. tostring(os.time())
        .. "." .. tostring(write_serial)
    local written, write_err = util.writeToFile(dump({
        manifest = stripRuntimeFields(manifest),
    }, nil, true), temporary_path, true, true)
    if not written then
        return nil, write_err
    end
    local backup_path = path .. ".old"
    local had_manifest = util.pathExists(path)
    if had_manifest then
        os.remove(backup_path)
        local backed_up, backup_err = os.rename(path, backup_path)
        if not backed_up then
            os.remove(temporary_path)
            return nil, backup_err
        end
    end
    local renamed, rename_err = os.rename(temporary_path, path)
    if not renamed then
        os.remove(temporary_path)
        if had_manifest then
            os.rename(backup_path, path)
        end
        return nil, rename_err
    end
    ffiUtil.fsyncDirectory(path)
    return self.normalizeManifest(manifest)
end

function Manifest:save(manifest)
    if type(manifest) ~= "table" or not manifest.book_id then
        return nil, "manifest is required"
    end
    local made, make_err = util.makePath(self.bookDir(manifest.book_id))
    if not made then
        return nil, make_err
    end
    return FileLock.with(self.manifestPath(manifest.book_id) .. ".lock", function()
        return self:saveUnlocked(manifest)
    end)
end

function Manifest:update(book_id, callback)
    if not book_id or book_id == "" then
        return nil, "book id is required"
    end
    return FileLock.with(self.manifestPath(book_id) .. ".lock", function()
        local manifest = self:load(book_id)
        if not manifest then
            return nil, "manifest is missing"
        end
        local ok, err = callback(manifest)
        if ok == false then
            return nil, err
        end
        return self:saveUnlocked(manifest)
    end)
end

function Manifest:ensureBook(source, book, chapters)
    chapters = chapters or {}
    local book_id = Manifest.bookId(source, book)
    local made, make_err = util.makePath(self.bookDir(book_id))
    if not made then
        return nil, make_err
    end
    return FileLock.with(self.manifestPath(book_id) .. ".lock", function()
    local existing = self:load(book_id) or {}
    local by_identity, by_title, title_counts = buildChapterIndexes(existing.chapters)

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
        local old = oldChapterFor(
            chapter,
            position,
            by_identity,
            by_title,
            title_counts
        )
        chapter.file_name = old and old.file_name
            or (chapterId(chapter, position) .. ".html")
        if old then
            chapter.read = old.read == true
            chapter.read_at = old.read_at
            chapter.last_opened_at = old.last_opened_at
            chapter.content_type = old.content_type
            chapter.image_style = old.image_style
        end
        chapter.file_path = Manifest.chapterPath(book_id, chapter)
        chapter.downloaded = old and old.downloaded == true or false
        table.insert(manifest.chapters, chapter)
    end

        return self:saveUnlocked(manifest)
    end)
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
    local tmp_path = chapter.file_path .. ".tmp." .. tostring(os.time())
        .. "." .. tostring(position)
    local written, write_err = util.writeToFile(html, tmp_path, true)
    if not written then
        return nil, write_err
    end
    local renamed, rename_err = os.rename(tmp_path, chapter.file_path)
    if not renamed then
        os.remove(tmp_path)
        return nil, rename_err
    end

    local saved, save_err = self:update(manifest.book_id, function(latest)
        local latest_chapter = latest.chapters and latest.chapters[position]
        if not latest_chapter or latest_chapter.file_name ~= chapter.file_name then
            return false, "chapter changed while saving content"
        end
        latest_chapter.downloaded = true
        latest_chapter.downloaded_at = now()
        latest_chapter.content_type = options.content_type or "text"
        latest_chapter.image_style = options.image_style or "default"
    end)
    if not saved then
        return nil, save_err
    end
    return chapter.file_path, nil, saved
end

function Manifest:updateCurrent(manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return false
    end
    local saved, err = self:update(manifest.book_id, function(latest)
        local latest_chapter = latest.chapters and latest.chapters[position]
        if not latest_chapter then
            return false, "chapter is missing"
        end
        latest.current_position = position
        latest_chapter.last_opened_at = now()
    end)
    return saved ~= nil, err, saved
end

function Manifest:markRead(manifest, position, read)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return false
    end
    local saved, err = self:update(manifest.book_id, function(latest)
        local latest_chapter = latest.chapters and latest.chapters[position]
        if not latest_chapter then
            return false, "chapter is missing"
        end
        latest_chapter.read = read ~= false
        latest_chapter.read_at = latest_chapter.read and now() or nil
    end)
    return saved ~= nil, err, saved
end

function Manifest:markReadMany(manifest, positions, read)
    if type(manifest) ~= "table" or not manifest.book_id then
        return nil, "manifest is required", 0
    end

    local changed = 0
    local saved, err = self:update(manifest.book_id, function(latest)
        local seen = {}
        local read_value = read ~= false
        local timestamp = now()
        for position_index = 1, #(positions or {}) do
            local position = tonumber(positions[position_index])
            if position and not seen[position] then
                seen[position] = true
                local chapter = latest.chapters and latest.chapters[position]
                if chapter then
                    chapter.read = read_value
                    chapter.read_at = read_value and timestamp or nil
                    changed = changed + 1
                end
            end
        end
    end)
    if not saved then
        return nil, err, changed
    end
    return saved, nil, changed
end

function Manifest.deleteStorage()
    local ok, ffi_util = pcall(require, "ffi/util")
    if ok and ffi_util and ffi_util.purgeDir then
        ffi_util.purgeDir(Manifest.root_dir)
    end
end

return Manifest
