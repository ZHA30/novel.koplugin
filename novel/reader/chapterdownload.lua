local _ = require("novel.i18n")
local ChapterCache = require("novel.reader.chaptercache")
local Dialog = require("novel.ui.widget.dialog")
local DownloadQueue = require("novel.reader.downloadqueue")
local Manifest = require("novel.storage.manifest")

local ChapterDownload = {}

function ChapterDownload.enqueue(plugin, manifest, positions, options)
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

return ChapterDownload
