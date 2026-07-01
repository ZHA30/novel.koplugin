local Analyzer = require("novel.rule.analyzer")

local BookList = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function isBlank(value)
    return value == nil or trim(value) == ""
end

local function sourceName(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source and source.bookSourceUrl or ""
end

local function sourceKey(source)
    return source and source.bookSourceUrl or ""
end

local function cleanText(value)
    value = trim(value)
    value = value:gsub("<br%s*/?>", "\n")
    value = value:gsub("</p%s*>", "\n")
    value = value:gsub("<[^>]+>", "")
    value = value:gsub("&nbsp;", " ")
    value = value:gsub("&amp;", "&")
    value = value:gsub("&lt;", "<")
    value = value:gsub("&gt;", ">")
    value = value:gsub("[ \t\r\n]+", " ")
    return trim(value)
end

local function stringListText(values)
    local output = {}
    for index = 1, #(values or {}) do
        local value = cleanText(values[index])
        if value ~= "" then
            table.insert(output, value)
        end
    end
    return table.concat(output, ",")
end

local function addDebug(debug, event, data)
    table.insert(debug, {
        event = event,
        data = data,
    })
end

local function addError(kind, message, data)
    return {
        kind = kind,
        message = message,
        data = data,
    }
end

local function copyUnsupported(target, source, field, items, start_index)
    for index = start_index, #items do
        local item = items[index]
        table.insert(target, {
            source = sourceName(source),
            field = field or item.field or "rule",
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        })
    end
end

local function analyzeString(analyzer, unsupported, source, field, rule, content)
    if isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local value = analyzer:getString(rule, content)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)
    return cleanText(value)
end

local function analyzeUrl(analyzer, unsupported, source, field, rule, content)
    if isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local value = analyzer:getString(rule, content, true)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)
    return trim(value)
end

local function analyzeList(analyzer, unsupported, source, field, rule, content)
    if isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, content)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)
    return stringListText(values)
end

local function analyzeElements(analyzer, unsupported, source, field, rule)
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getElements(rule)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)
    return values
end

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
    local name = analyzeString(analyzer, unsupported, source, prefix .. ".name", rule.name, item)
    if name == "" then
        return nil
    end

    local book_url = analyzeUrl(analyzer, unsupported, source, prefix .. ".bookUrl", rule.bookUrl, item)
    if book_url == "" then
        book_url = final_url
    end

    local latest_chapter = analyzeString(analyzer, unsupported, source,
        prefix .. ".lastChapter", rule.lastChapter, item)

    return {
        name = name,
        author = analyzeString(analyzer, unsupported, source, prefix .. ".author", rule.author, item),
        intro = analyzeString(analyzer, unsupported, source, prefix .. ".intro", rule.intro, item),
        kind = analyzeList(analyzer, unsupported, source, prefix .. ".kind", rule.kind, item),
        latestChapter = latest_chapter,
        latestChapterTitle = latest_chapter,
        bookUrl = book_url,
        coverUrl = analyzeUrl(analyzer, unsupported, source, prefix .. ".coverUrl", rule.coverUrl, item),
        wordCount = analyzeString(analyzer, unsupported, source, prefix .. ".wordCount", rule.wordCount, item),
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
    local items = analyzeElements(analyzer, unsupported, source,
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
