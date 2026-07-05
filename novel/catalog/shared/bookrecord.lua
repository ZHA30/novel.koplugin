local BookRecord = {}

local SearchBook = {}

BookRecord.fields = {
    "bookUrl",
    "tocUrl",
    "origin",
    "originName",
    "name",
    "author",
    "kind",
    "customTag",
    "coverUrl",
    "customCoverUrl",
    "intro",
    "customIntro",
    "charset",
    "type",
    "group",
    "latestChapterTitle",
    "updateTime",
    "latestChapterTime",
    "lastCheckTime",
    "lastCheckCount",
    "totalChapterNum",
    "durChapterTitle",
    "durChapterIndex",
    "durChapterPos",
    "durChapterTime",
    "wordCount",
    "canUpdate",
    "order",
    "originOrder",
    "useReplaceRule",
    "variable",
    "infoHtml",
    "tocHtml",
}

local function now()
    return os.time()
end

BookRecord.defaults = {
    bookUrl = "",
    tocUrl = "",
    origin = "",
    originName = "",
    name = "",
    author = "",
    kind = "",
    customTag = nil,
    coverUrl = "",
    customCoverUrl = nil,
    intro = "",
    customIntro = nil,
    charset = nil,
    type = 0,
    group = 0,
    latestChapterTitle = "",
    updateTime = "",
    latestChapterTime = 0,
    lastCheckTime = 0,
    lastCheckCount = 0,
    totalChapterNum = 0,
    durChapterTitle = "",
    durChapterIndex = 0,
    durChapterPos = 0,
    durChapterTime = 0,
    wordCount = "",
    canUpdate = true,
    order = 0,
    originOrder = 0,
    useReplaceRule = true,
    variable = nil,
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

local function applyValues(target, values)
    values = values or {}
    for field_index = 1, #BookRecord.fields do
        local field = BookRecord.fields[field_index]
        if values[field] ~= nil then
            target[field] = values[field]
        end
    end
    return target
end

function BookRecord.new(values)
    local book = clone(BookRecord.defaults)
    local timestamp = now()
    book.latestChapterTime = timestamp
    book.lastCheckTime = timestamp
    book.durChapterTime = timestamp
    return applyValues(book, values)
end

function BookRecord.fromSearchBook(search_book)
    search_book = search_book or {}
    return BookRecord.new{
        bookUrl = search_book.bookUrl,
        tocUrl = search_book.tocUrl,
        origin = search_book.origin,
        originName = search_book.originName,
        name = search_book.name,
        author = search_book.author,
        kind = search_book.kind,
        coverUrl = search_book.coverUrl,
        intro = search_book.intro,
        type = search_book.type,
        latestChapterTitle = search_book.latestChapterTitle or search_book.latestChapter,
        updateTime = search_book.updateTime,
        wordCount = search_book.wordCount,
        originOrder = search_book.originOrder,
        variable = search_book.variable,
        infoHtml = search_book.infoHtml,
        tocHtml = search_book.tocHtml,
    }
end

function BookRecord.toSearchBook(book)
    return SearchBook.new{
        bookUrl = book.bookUrl,
        tocUrl = book.tocUrl,
        origin = book.origin,
        originName = book.originName,
        name = book.name,
        author = book.author,
        kind = book.kind,
        coverUrl = book.coverUrl,
        intro = book.intro,
        type = book.type,
        latestChapterTitle = book.latestChapterTitle,
        updateTime = book.updateTime,
        wordCount = book.wordCount,
        originOrder = book.originOrder,
        variable = book.variable,
        infoHtml = book.infoHtml,
        tocHtml = book.tocHtml,
    }
end

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

return BookRecord
