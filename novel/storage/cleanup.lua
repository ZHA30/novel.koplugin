-- luacheck: globals lfs

local Cache = require("novel.storage.cache")
local Manifest = require("novel.books.manifest")
local logger = require("logger")

local Cleanup = {}

local function sourceUrl(source)
    return source and source.bookSourceUrl or ""
end

local function bookUrl(book)
    return book and book.bookUrl or ""
end

local function isFile(path)
    return lfs and lfs.attributes(path, "mode") == "file"
end

local function isDirectory(path)
    return lfs and lfs.attributes(path, "mode") == "directory"
end

local function safeDir(path)
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then
        return nil
    end
    return iter, dir_obj
end

local function fileSize(path)
    local attr = lfs and lfs.attributes(path)
    if not attr or attr.mode ~= "file" then
        return 0
    end
    return tonumber(attr.size) or 0
end

local function chapterCacheFile(entry)
    return entry:match("%.html$") or entry:match("%.html%.tmp%.") ~= nil
end

local function cachePathForBook(path, book_id)
    local prefix = Manifest.chaptersDir(book_id) .. "/"
    return type(path) == "string" and path:sub(1, #prefix) == prefix
end

local function newSummary(book_id)
    return {
        ok = true,
        book_id = book_id,
        chapter_files_removed = 0,
        chapter_files_failed = 0,
        chapter_files_kept = 0,
        chapter_bytes_removed = 0,
        metadata_content_removed = 0,
        unsafe_paths_skipped = 0,
    }
end

local function removeChapterFile(path, book_id, keep_file, summary)
    if path == keep_file then
        summary.chapter_files_kept = summary.chapter_files_kept + 1
        return false
    end
    if not cachePathForBook(path, book_id) then
        summary.unsafe_paths_skipped = summary.unsafe_paths_skipped + 1
        return false
    end
    if not isFile(path) then
        return false
    end

    local size = fileSize(path)
    if os.remove(path) == true then
        summary.chapter_files_removed = summary.chapter_files_removed + 1
        summary.chapter_bytes_removed = summary.chapter_bytes_removed + size
        return true
    end
    summary.chapter_files_failed = summary.chapter_files_failed + 1
    return false
end

local function invalidateContentCache(manifest)
    local source_url = manifest.source_url or sourceUrl(manifest.source)
    local book_url = manifest.book_url or bookUrl(manifest.book)
    if source_url == "" or book_url == "" then
        return 0
    end

    local cache = Cache:new()
    return cache:invalidateByOwner({
        source = source_url,
        book = book_url,
    }, "content")
end

local function deleteChapterFiles(manifest, options, summary)
    local keep_file = options and options.keep_file
    local seen_paths = {}
    local changed = false

    for position = 1, #(manifest.chapters or {}) do
        local chapter = manifest.chapters[position]
        local path = chapter and chapter.file_path
        if path then
            seen_paths[path] = true
            if removeChapterFile(path, manifest.book_id, keep_file, summary) then
                chapter.downloaded = false
                chapter.content_type = nil
                changed = true
            end
        end
    end

    local chapters_dir = Manifest.chaptersDir(manifest.book_id)
    if isDirectory(chapters_dir) then
        local iter, dir_obj = safeDir(chapters_dir)
        if iter then
            for entry in iter, dir_obj do
                if entry ~= "." and entry ~= ".." and chapterCacheFile(entry) then
                    local path = chapters_dir .. "/" .. entry
                    if not seen_paths[path] then
                        removeChapterFile(path, manifest.book_id, keep_file, summary)
                    end
                end
            end
        end
    end

    if changed then
        Manifest:new():save(manifest)
    end
end

function Cleanup.deleteManifestCache(manifest, options)
    options = options or {}
    manifest = Manifest.normalizeManifest(manifest)
    if not manifest or not manifest.book_id then
        return {
            ok = false,
            error = {
                kind = "manifest",
                message = "book cache not found",
            },
        }
    end

    local summary = newSummary(manifest.book_id)
    if not lfs then
        summary.ok = false
        summary.error = {
            kind = "filesystem",
            message = "filesystem module is not available",
        }
        return summary
    end

    deleteChapterFiles(manifest, options, summary)
    summary.metadata_content_removed = invalidateContentCache(manifest)

    logger.dbg("novel book cache deleted:", manifest.book_id,
        "chapter_files", summary.chapter_files_removed,
        "content_records", summary.metadata_content_removed)
    return summary
end

function Cleanup.deleteBookCache(source, book, options)
    options = options or {}
    local manifest_store = Manifest:new()
    local manifest = options.manifest
    if not manifest and options.book_id then
        manifest = manifest_store:load(options.book_id)
    end
    if not manifest then
        manifest = manifest_store:loadByBook(source, book)
    end
    return Cleanup.deleteManifestCache(manifest, options)
end

function Cleanup.pruneMetadata(settings)
    settings = settings or {}
    local cache_settings = settings.cache or settings
    local cache = Cache:new()
    return {
        ok = true,
        metadata_expired_removed = cache:pruneExpired(),
        metadata_lru_removed = cache:pruneLRU(cache_settings.max_metadata_records),
    }
end

return Cleanup
