local SearchBook = {}

SearchBook.fields = {
    "bookUrl",
    "origin",
    "originName",
    "type",
    "name",
    "author",
    "kind",
    "coverUrl",
    "intro",
    "wordCount",
    "latestChapterTitle",
    "latestChapter",
    "updateTime",
    "tocUrl",
    "time",
    "variable",
    "originOrder",
    "infoHtml",
    "tocHtml",
}

SearchBook.defaults = {
    bookUrl = "",
    origin = "",
    originName = "",
    type = 0,
    name = "",
    author = "",
    kind = "",
    coverUrl = "",
    intro = "",
    wordCount = "",
    latestChapterTitle = "",
    latestChapter = "",
    updateTime = "",
    tocUrl = "",
    time = 0,
    variable = nil,
    originOrder = 0,
    infoHtml = nil,
    tocHtml = nil,
}

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

function SearchBook.new(values)
    values = values or {}
    local search_book = clone(SearchBook.defaults)
    search_book.time = os.time()
    for field_index = 1, #SearchBook.fields do
        local field = SearchBook.fields[field_index]
        if values[field] ~= nil then
            search_book[field] = values[field]
        end
    end
    if search_book.latestChapterTitle == "" and search_book.latestChapter ~= "" then
        search_book.latestChapterTitle = search_book.latestChapter
    elseif search_book.latestChapter == "" and search_book.latestChapterTitle ~= "" then
        search_book.latestChapter = search_book.latestChapterTitle
    end
    return search_book
end

function SearchBook.toBook(search_book)
    local Book = require("novel.model.book")
    return Book.fromSearchBook(search_book)
end

return SearchBook
