local DownloadQueue = require("novel.reader.downloadqueue")
local OfflineFiles = require("novel.storage.offlinefiles")
local logger = require("logger")

local BookshelfLifecycle = {}

function BookshelfLifecycle.remove(plugin, source, book)
    return BookshelfLifecycle.removeMany(plugin, {
        {
            source = source,
            book = book,
        },
    }) > 0
end

function BookshelfLifecycle.removeMany(plugin, records)
    if not plugin or not plugin.app then
        return 0
    end

    local store = plugin.app:getBookshelfStore()
    local removed_count = 0
    local book_ids = {}
    for index = 1, #(records or {}) do
        local record = records[index]
        if record and store:remove(record.source, record.book) then
            removed_count = removed_count + 1
            table.insert(book_ids, OfflineFiles.bookId(record.source, record.book))
            local summary = OfflineFiles.deleteBook(record.source, record.book, {
                book_id = book_ids[#book_ids],
            })
            if summary and summary.ok == false then
                logger.warn("Novel: failed to delete offline files for removed book:",
                    book_ids[#book_ids], summary.error and summary.error.message)
            end
        end
    end

    if removed_count == 0 then
        return 0
    end
    DownloadQueue.removeBooks(plugin, book_ids, {
        restart = false,
    })
    DownloadQueue.start(plugin)
    return removed_count
end

return BookshelfLifecycle
