local _ = require("novel.i18n")
local CacheCleanup = require("novel.storage.cachecleanup")
local ChapterDoc = require("novel.reader.chapterdoc")
local ChapterRecord = require("novel.reader.chapterrecord")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local Manifest = require("novel.storage.manifest")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")

local ChapterCache = {}

local LOADING_KEY = "novel_chapter_cache_loading"

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

local function nextContentUrl(manifest, position)
    local next_chapter = ChapterRecord.nextOpenable(
        manifest and manifest.chapters,
        position,
        1
    )
    return next_chapter and next_chapter.url or nil
end

local function newCacheSummary(book_id, total)
    return {
        ok = true,
        book_id = book_id,
        total = total or 0,
        cached = 0,
        skipped = 0,
        failed = 0,
        canceled = false,
        first_error = nil,
    }
end

local function closeLoading(plugin, widget)
    Loading.close(plugin, LOADING_KEY, widget)
end

local function cacheProgressMessage(current, total)
    if current and total then
        return string.format(_("Caching (%d/%d)..."), current, total)
    end
    return _("Caching...")
end

local function showLoading(plugin)
    return Loading.show(plugin, LOADING_KEY, {
        text = cacheProgressMessage(),
    })
end

local function updateLoading(plugin, widget, current, total)
    Loading.update(plugin, LOADING_KEY,
        cacheProgressMessage(current, total), widget)
end

local function fetchChapter(source, book, chapter, next_chapter_url, settings)
    local ChapterContent = require("novel.catalog.reading.chaptercontent")
    return ChapterContent.run(source, book, chapter, {
        next_chapter_url = next_chapter_url,
        settings = settings,
    })
end

local function saveResult(manifest_store, manifest, position, result)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        return nil, "chapter is missing"
    end
    local image_style = result.image_style
        or ChapterDoc.expectedImageStyle(manifest)
    local html = ChapterDoc.html(chapter, result.text, result.content_type, {
        image_style = image_style,
    })
    return manifest_store:saveChapter(manifest, position, html, {
        content_type = result.content_type,
        image_style = image_style,
    })
end

local function cachePosition(plugin, manifest_store, manifest, position, settings,
    loading_widget, summary)
    if isChapterCurrent(manifest, position) then
        summary.skipped = summary.skipped + 1
        return true
    end

    local chapter = manifest.chapters[position]
    local source = manifest.source
    local book = manifest.book
    local next_chapter_url = nextContentUrl(manifest, position)
    local completed, result = Trapper:dismissableRunInSubprocess(function()
        return fetchChapter(source, book, chapter, next_chapter_url, settings)
    end, loading_widget)

    if not plugin.app then
        summary.canceled = true
        return false
    end
    if not completed then
        summary.canceled = true
        return false
    end
    if not result or not result.ok then
        summary.failed = summary.failed + 1
        summary.first_error = summary.first_error or result
        return true
    end

    local file, err = saveResult(manifest_store, manifest, position, result)
    if not file then
        summary.failed = summary.failed + 1
        summary.first_error = summary.first_error or err
        return true
    end
    summary.cached = summary.cached + 1
    return true
end

local function cacheSummaryMessage(summary)
    if summary.canceled then
        return Dialog.canceledMessage()
    end

    local lines = {}
    if summary.cached > 0 then
        table.insert(lines, string.format(
            _("Cached %d chapters."),
            summary.cached
        ))
    end
    if summary.skipped > 0 then
        table.insert(lines, string.format(
            _("Skipped %d cached chapters."),
            summary.skipped
        ))
    end
    if summary.failed > 0 then
        table.insert(lines, string.format(
            _("Failed to cache %d chapters."),
            summary.failed
        ))
        table.insert(lines, Dialog.failureMessage(summary.first_error))
    end
    if #lines == 0 then
        table.insert(lines, _("No chapters to cache."))
    end
    return table.concat(lines, "\n")
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
        Dialog.message(_("No chapters to cache."))
        return
    end

    if NetworkMgr:willRerunWhenOnline(function()
        ChapterCache.cache(plugin, manifest, target_positions, options)
    end) then
        return
    end

    local loading_widget = showLoading(plugin)
    local settings = plugin.app and plugin.app.settings
    local summary = newCacheSummary(manifest.book_id, #target_positions)

    Trapper:wrap(function()
        for position_index = 1, #target_positions do
            if not plugin.app then
                summary.canceled = true
                break
            end
            updateLoading(plugin, loading_widget, position_index,
                #target_positions)
            manifest = manifest_store:load(manifest.book_id) or manifest
            if not cachePosition(
                plugin,
                manifest_store,
                manifest,
                target_positions[position_index],
                settings,
                loading_widget,
                summary
            ) then
                break
            end
        end

        closeLoading(plugin, loading_widget)
        if not plugin.app then
            return
        end
        local updated_manifest = manifest_store:load(manifest.book_id) or manifest
        if type(options.on_done) == "function" then
            options.on_done(summary, updated_manifest)
        end
        Dialog.message(cacheSummaryMessage(summary))
    end)
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
