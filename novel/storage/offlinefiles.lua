local Manifest = require("novel.storage.manifest")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local OfflineFiles = {}

local function newSummary()
    return {
        ok = true,
        book_id = nil,
        removed_book_ids = {},
        book_dirs_removed = 0,
        book_dirs_kept = 0,
        chapter_files_removed = 0,
        chapter_files_failed = 0,
        chapter_files_kept = 0,
        chapter_bytes_removed = 0,
        unsafe_paths_skipped = 0,
    }
end

local function currentReaderFile()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader_ui = ok and ReaderUI.instance
    return reader_ui and reader_ui.document and reader_ui.document.file
end

local function bookIdFromPath(path)
    path = tostring(path or "")
    local prefix = Manifest.root_dir .. "/"
    if path:sub(1, #prefix) ~= prefix then
        return nil
    end
    return path:sub(#prefix + 1):match("^([^/]+)")
end

local function isFile(path)
    return lfs.attributes(path, "mode") == "file"
end

local function isDirectory(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function safeDir(path)
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then
        return nil
    end
    return iter, dir_obj
end

local function fileSize(path)
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then
        return 0
    end
    return tonumber(attr.size) or 0
end

local function chapterFile(entry)
    return entry:match("%.html$") or entry:match("%.html%.tmp%.") ~= nil
end

local function pathForBook(path, book_id)
    local prefix = Manifest.chaptersDir(book_id) .. "/"
    return type(path) == "string" and path:sub(1, #prefix) == prefix
end

local function removeChapterFile(path, book_id, keep_file, summary)
    if path == keep_file then
        summary.chapter_files_kept = summary.chapter_files_kept + 1
        return false
    end
    if not pathForBook(path, book_id) then
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

local function purgeBookDir(book_id, summary)
    local book_dir = Manifest.bookDir(book_id)
    if not isDirectory(book_dir) then
        return summary
    end

    local ok, err = ffiUtil.purgeDir(book_dir)
    if ok then
        summary.book_dirs_removed = summary.book_dirs_removed + 1
        table.insert(summary.removed_book_ids, book_id)
    else
        summary.ok = false
        summary.error = {
            kind = "filesystem",
            message = err or "failed to delete offline book files",
        }
    end
    return summary
end

local function deleteChapterFiles(manifest, keep_file, summary)
    local seen_paths = {}
    local removed_files = {}

    for position = 1, #(manifest.chapters or {}) do
        local chapter = manifest.chapters[position]
        local path = chapter and chapter.file_path
        if path then
            seen_paths[path] = true
            if removeChapterFile(path, manifest.book_id, keep_file, summary) then
                removed_files[chapter.file_name] = true
            end
        end
    end

    local chapters_dir = Manifest.chaptersDir(manifest.book_id)
    if isDirectory(chapters_dir) then
        local iter, dir_obj = safeDir(chapters_dir)
        if iter then
            for entry in iter, dir_obj do
                if entry ~= "." and entry ~= ".." and chapterFile(entry) then
                    local path = chapters_dir .. "/" .. entry
                    if not seen_paths[path] then
                        removeChapterFile(path, manifest.book_id, keep_file, summary)
                    end
                end
            end
        end
    end

    if next(removed_files) ~= nil then
        local saved, err = Manifest:new():update(manifest.book_id, function(latest)
            for position = 1, #(latest.chapters or {}) do
                local chapter = latest.chapters[position]
                if removed_files[chapter.file_name] then
                    chapter.downloaded = false
                    chapter.downloaded_at = nil
                    chapter.content_type = nil
                    chapter.image_style = nil
                end
            end
        end)
        if saved then
            summary.manifest = saved
        else
            summary.ok = false
            summary.error = {
                kind = "manifest",
                message = err,
            }
        end
    else
        summary.manifest = manifest
    end
    return summary
end

local function shelfBookIds(bookshelf_store)
    local ids = {}
    local records = bookshelf_store and bookshelf_store:list() or {}
    for index = 1, #records do
        local record = records[index]
        if record and record.source and record.book then
            ids[Manifest.bookId(record.source, record.book)] = true
        end
    end
    return ids
end

function OfflineFiles.bookId(source, book)
    return Manifest.bookId(source, book)
end

function OfflineFiles.currentReaderFile()
    return currentReaderFile()
end

function OfflineFiles.deleteManifest(manifest, options)
    options = options or {}
    local summary = newSummary()
    manifest = Manifest.normalizeManifest(manifest)
    if not manifest or not manifest.book_id then
        return summary
    end

    summary.book_id = manifest.book_id
    local keep_file = options.keep_file
    if keep_file == nil and options.keep_current ~= false then
        keep_file = currentReaderFile()
    end

    if bookIdFromPath(keep_file) == manifest.book_id then
        return deleteChapterFiles(manifest, keep_file, summary)
    end

    return purgeBookDir(manifest.book_id, summary)
end

function OfflineFiles.deleteBook(source, book, options)
    options = options or {}
    local manifest = options.manifest
    if not manifest and options.book_id then
        manifest = Manifest:new():load(options.book_id)
    end
    if not manifest then
        manifest = Manifest:new():loadByBook(source, book)
    end
    return OfflineFiles.deleteManifest(manifest, options)
end

function OfflineFiles.pruneOrphans(bookshelf_store, options)
    options = options or {}
    local summary = newSummary()
    if not isDirectory(Manifest.root_dir) then
        return summary
    end

    local keep_file = options.keep_file
    if keep_file == nil and options.keep_current ~= false then
        keep_file = currentReaderFile()
    end
    local keep_book_id = bookIdFromPath(keep_file)
    local kept_ids = shelfBookIds(bookshelf_store)
    local iter, dir_obj = safeDir(Manifest.root_dir)
    if not iter then
        return summary
    end

    for entry in iter, dir_obj do
        local book_dir = Manifest.bookDir(entry)
        if entry ~= "." and entry ~= ".." and isDirectory(book_dir)
            and not kept_ids[entry] then
            if entry == keep_book_id then
                summary.book_dirs_kept = summary.book_dirs_kept + 1
            else
                purgeBookDir(entry, summary)
            end
        end
    end

    if #summary.removed_book_ids > 0 then
        logger.dbg("novel orphan offline files pruned:",
            table.concat(summary.removed_book_ids, ","))
    end
    return summary
end

return OfflineFiles
