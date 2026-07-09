local _ = require("novel.i18n")
local BookshelfStore = require("novel.storage.bookshelfstore")
local Manifest = require("novel.storage.manifest")
local SourceInfo = require("novel.catalog.shared.sourceinfo")

local BookRefresh = {}

local function sourceKey(source)
    return SourceInfo.key(source)
end

function BookRefresh.findCurrentSource(plugin, record)
    local source_url = record and record.source_url or ""
    if plugin and plugin.app then
        local sources = plugin.app:getSourceStore():list()
        for source_index = 1, #sources do
            local source = sources[source_index]
            if sourceKey(source) == source_url then
                return source
            end
        end
    end
    return record and record.source
end

function BookRefresh.fetch(source, book, options)
    return BookshelfStore.fetchRefresh(source, book, options)
end

function BookRefresh.apply(plugin, source, book, refresh, options)
    options = options or {}
    if not refresh or not refresh.ok then
        return nil, "invalid refresh result"
    end

    local refreshed_book = refresh.book or book
    local manifest, manifest_err = Manifest:new():ensureBook(
        source,
        refreshed_book,
        refresh.chapters or {}
    )
    if not manifest then
        return nil, manifest_err
    end

    local record
    if plugin and plugin.app then
        local store = plugin.app:getBookshelfStore()
        record = store:applyRefresh(source, book, refresh)
        if not record and options.require_bookshelf then
            return nil, _("Book is not in bookshelf.")
        end
        if not record then
            store:updateExisting(source, refreshed_book)
        end
    end

    return {
        record = record,
        manifest = manifest,
        chapters = refresh.chapters or {},
    }
end

return BookRefresh
