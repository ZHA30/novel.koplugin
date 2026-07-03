local Analyzer = require("novel.rule.analyzer")
local Context = require("novel.catalog.client")
local Fields = require("novel.catalog.extract")

local BookList = {}

local trim = Context.trim
local sourceName = Context.sourceName
local sourceKey = Context.sourceKey
local addDebug = Context.addDebug
local addError = Context.error

local function listRule(rule)
    local value = trim(rule and rule.bookList or "")
    local reverse = false
    if value:sub(1, 1) == "-" then
        reverse = true
        value = trim(value:sub(2))
    elseif value:sub(1, 1) == "+" then
        value = trim(value:sub(2))
    end
    return value, reverse
end

local function parseBook(analyzer, unsupported, source, rule, prefix, item, final_url)
    local name = Fields.cleanString(analyzer, unsupported, source,
        prefix .. ".name", rule.name, item)
    if name == "" then
        return nil
    end

    local book_url = Fields.url(analyzer, unsupported, source,
        prefix .. ".bookUrl", rule.bookUrl, item)
    if book_url == "" then
        book_url = final_url
    end

    local latest_chapter = Fields.cleanString(analyzer, unsupported, source,
        prefix .. ".lastChapter", rule.lastChapter, item)

    return {
        name = name,
        author = Fields.cleanString(analyzer, unsupported, source,
            prefix .. ".author", rule.author, item),
        intro = Fields.cleanString(analyzer, unsupported, source,
            prefix .. ".intro", rule.intro, item),
        kind = Fields.listText(analyzer, unsupported, source,
            prefix .. ".kind", rule.kind, item),
        latestChapter = latest_chapter,
        latestChapterTitle = latest_chapter,
        updateTime = Fields.cleanString(analyzer, unsupported, source,
            prefix .. ".updateTime", rule.updateTime, item),
        bookUrl = book_url,
        coverUrl = Fields.url(analyzer, unsupported, source,
            prefix .. ".coverUrl", rule.coverUrl, item),
        wordCount = Fields.cleanString(analyzer, unsupported, source,
            prefix .. ".wordCount", rule.wordCount, item),
        origin = sourceKey(source),
        originName = sourceName(source),
        originOrder = source.customOrder or 0,
        type = source.bookSourceType or 0,
    }
end

function BookList.parse(source, rule, prefix, response, options)
    options = options or {}
    prefix = prefix or "ruleSearch"
    local debug, unsupported, books = {}, {}, {}
    local final_url = response.final_url or response.url or response.request_url or ""
    local analyzer = Analyzer:new({
        content = response.body or "",
        base_url = final_url,
        redirect_url = final_url,
    })

    local book_list_rule, reverse = listRule(rule)
    if book_list_rule == "" then
        return {
            ok = false,
            books = books,
            debug = debug,
            unsupported = unsupported,
            error = addError("rule", prefix .. ".bookList is required"),
        }
    end

    addDebug(debug, options.parse_event or "parse_list", {
        rule = book_list_rule,
    })
    local items = Fields.elements(analyzer, unsupported, source,
        prefix .. ".bookList", book_list_rule)
    addDebug(debug, options.size_event or "list_size", {
        count = #items,
    })

    for item_index = 1, #items do
        analyzer:setContent(items[item_index])
        local book = parseBook(analyzer, unsupported, source, rule, prefix,
            items[item_index], final_url)
        if book then
            table.insert(books, book)
        end
    end

    if reverse then
        local left, right = 1, #books
        while left < right do
            books[left], books[right] = books[right], books[left]
            left = left + 1
            right = right - 1
        end
    end

    return {
        ok = true,
        books = books,
        debug = debug,
        unsupported = unsupported,
    }
end

return BookList
