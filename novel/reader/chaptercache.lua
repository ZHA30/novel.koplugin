local _ = require("novel.i18n")
local CacheCleanup = require("novel.storage.cachecleanup")
local ChapterDoc = require("novel.reader.chapterdoc")
local ChapterRecord = require("novel.reader.chapterrecord")
local DownloadQueue = require("novel.reader.downloadqueue")
local Dialog = require("novel.ui.widget.dialog")
local Manifest = require("novel.storage.manifest")

local ChapterCache = {}

local function uniqueOpenablePositions(manifest, positions)
    local result = {}
    local seen = {}
    local chapters = manifest and manifest.chapters or {}
    for position_index = 1, #(positions or {}) do
        local position = tonumber(positions[position_index])
        local chapter = position and chapters[position]
        if position and not seen[position] and ChapterRecord.isOpenable(chapter) then
            seen[position] = true
            table.insert(result, position)
        end
    end
    table.sort(result)
    return result
end

local function currentFile()
    return ChapterDoc.currentReaderFile()
end

local function isChapterCurrent(manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    return Manifest.chapterFileExists(manifest, position)
        and ChapterDoc.contentIsCurrent(manifest, chapter)
end

local function deleteSummaryMessage(summary)
    if not summary.ok then
        return Dialog.failureMessage(summary)
    end

    local lines = {}
    if summary.chapter_files_removed > 0 then
        table.insert(lines, string.format(
            _("Deleted cache for %d chapters."),
            summary.chapter_files_removed
        ))
    end
    if summary.chapter_files_kept > 0 then
        table.insert(lines, _("Current chapter cache was kept."))
    end
    if summary.chapter_files_failed > 0 then
        table.insert(lines, string.format(
            _("Failed to delete cache for %d chapters."),
            summary.chapter_files_failed
        ))
    end
    if #lines == 0 then
        table.insert(lines, _("No cached chapters to delete."))
    end
    return table.concat(lines, "\n")
end

function ChapterCache.cacheablePositions(manifest, positions)
    manifest = Manifest.normalizeManifest(manifest)
    local result = {}
    local openable_positions = uniqueOpenablePositions(manifest, positions)
    for position_index = 1, #openable_positions do
        local position = openable_positions[position_index]
        if not isChapterCurrent(manifest, position) then
            table.insert(result, position)
        end
    end
    return result
end

function ChapterCache.cachedPositions(manifest, positions, options)
    options = options or {}
    manifest = Manifest.normalizeManifest(manifest)
    local keep_file = options.keep_file
    local result = {}
    local openable_positions = uniqueOpenablePositions(manifest, positions)
    for position_index = 1, #openable_positions do
        local position = openable_positions[position_index]
        local chapter = manifest and manifest.chapters and manifest.chapters[position]
        if Manifest.chapterFileExists(manifest, position)
            and chapter.file_path ~= keep_file then
            table.insert(result, position)
        end
    end
    return result
end

function ChapterCache.cache(plugin, manifest, positions, options)
    options = options or {}
    if not plugin or not plugin.app then
        return
    end
    local manifest_store = Manifest:new()
    manifest = manifest_store:load(manifest and manifest.book_id) or manifest
    local target_positions = ChapterCache.cacheablePositions(manifest, positions)
    if #target_positions == 0 then
        Dialog.message(_("No chapters to download."))
        return
    end

    local summary = DownloadQueue.enqueue(plugin, manifest, target_positions, options)
    if summary.queued > 0 then
        Dialog.message(string.format(
            _("Queued %d chapters for download."),
            summary.queued
        ))
    else
        Dialog.message(_("Selected chapters are already in the download queue."))
    end
end

function ChapterCache.delete(plugin, manifest, positions, options)
    options = options or {}
    if not plugin or not plugin.app then
        return
    end
    local manifest_store = Manifest:new()
    manifest = manifest_store:load(manifest and manifest.book_id) or manifest
    local target_positions = ChapterCache.cachedPositions(manifest, positions, {
        keep_file = currentFile(),
    })
    if #target_positions == 0 then
        Dialog.message(_("No cached chapters to delete."))
        return
    end

    local summary = CacheCleanup.deleteChapterCache(manifest, target_positions, {
        keep_file = currentFile(),
    })
    local updated_manifest = summary.manifest
        or manifest_store:load(manifest.book_id)
        or manifest
    if type(options.on_done) == "function" then
        options.on_done(summary, updated_manifest)
    end
    Dialog.message(deleteSummaryMessage(summary))
end

function ChapterCache.currentFile()
    return currentFile()
end

return ChapterCache
