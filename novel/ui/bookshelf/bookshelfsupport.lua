local _ = require("novel.i18n")
local SourceFinder = require("novel.catalog.listing.sourcefinder")
local SourceStore = require("novel.storage.sourcestore")

local BookshelfSupport = {}

function BookshelfSupport.bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

function BookshelfSupport.sourceTitle(source)
    return SourceStore.title(source)
end

function BookshelfSupport.switchSummary(result)
    return table.concat({
        _("Keyword: ") .. tostring(result.keyword or ""),
        _("Candidates: ") .. tostring(#(result.candidates or {})),
        _("Checked: ") .. tostring(result.checked or 0),
        _("Skipped: ") .. tostring(result.skipped or 0),
        _("Failed: ") .. tostring(result.failed or 0),
    }, "\n")
end

function BookshelfSupport.switchReasonText(reason)
    if reason == SourceFinder.MATCH_NAME_AUTHOR then
        return _("Name and author match")
    elseif reason == SourceFinder.MATCH_NAME then
        return _("Name matches")
    end
    return reason
end

return BookshelfSupport
