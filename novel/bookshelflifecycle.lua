local DownloadQueue = require("novel.reader.downloadqueue")
local OfflineFiles = require("novel.storage.offlinefiles")
local logger = require("logger")

local BookshelfLifecycle = {}

function BookshelfLifecycle.remove(plugin, source, book)
    if not plugin or not plugin.app then
        return false
    end

    local removed = plugin.app:getBookshelfStore():remove(source, book)
    if not removed then
        return false
    end

    local book_id = OfflineFiles.bookId(source, book)
    DownloadQueue.removeBook(plugin, book_id, {
        restart = false,
    })
    local summary = OfflineFiles.deleteBook(source, book, {
        book_id = book_id,
    })
    if summary and summary.ok == false then
        logger.warn("Novel: failed to delete offline files for removed book:",
            book_id, summary.error and summary.error.message)
    end
    DownloadQueue.start(plugin)
    return true
end

return BookshelfLifecycle
