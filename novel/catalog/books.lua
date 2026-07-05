local Analyzer = require("novel.rule.analyzer")
local Runtime = require("novel.catalog.runtime")
local Extract = require("novel.catalog.extract")
local Url = require("novel.net.url")

local Books = {}

local trim = Runtime.trim
local sourceName = Runtime.sourceName
local sourceKey = Runtime.sourceKey
local addDebug = Runtime.addDebug
local addError = Runtime.error

local function looksMalformedKind(kind)
    kind = trim(kind)
    return kind == ""
        or kind:find("||", 1, true) ~= nil
        or kind:find("&&", 1, true) ~= nil
end

local function bookUrlSlug(book_url)
    local path = tostring(book_url or ""):match("^https?://[^/]+(/[^?#]*)$")
        or tostring(book_url or "")
    return path:match("^/([^/]+)/") or path:match("^([^/]+)/")
end

local function parseExploreKindMap(source)
    if type(source) ~= "table" then
        return {}
    end
    if source._explore_kind_map then
        return source._explore_kind_map
    end

    local map = {}
    local explore_url = trim(source.exploreUrl)
    if explore_url == "" then
        source._explore_kind_map = map
        return map
    end

    local normalized = explore_url:gsub("\r\n", "\n"):gsub("\r", "\n")
    for raw_line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local start_index = 1
        while start_index <= #raw_line do
            local delimiter_start = raw_line:find("&&", start_index, true)
            local part = delimiter_start
                and raw_line:sub(start_index, delimiter_start - 1)
                or raw_line:sub(start_index)
            local title, group_url = trim(part):match("^(.-)::(.+)$")
            if title and group_url then
                local spec = Url.parse(trim(group_url), {
                    base_url = source.bookSourceUrl,
                    page = 1,
                })
                local slug = bookUrlSlug(spec.url_no_query ~= "" and spec.url_no_query or spec.url)
                if slug and slug ~= "" and trim(title) ~= "" and map[slug] == nil then
                    map[slug] = trim(title)
                end
            end
            if not delimiter_start then
                break
            end
            start_index = delimiter_start + 2
        end
    end

    source._explore_kind_map = map
    return map
end

local function normalizeKind(source, book_url, kind)
    kind = trim(kind)
    if not looksMalformedKind(kind) then
        return kind
    end

    local kind_map = parseExploreKindMap(source)
    local cleaned = kind:match("^([%w_%-]+)") or ""
    if cleaned ~= "" and kind_map[cleaned] then
        return kind_map[cleaned]
    end

    local slug = bookUrlSlug(book_url)
    if slug and kind_map[slug] then
        return kind_map[slug]
    end

    return kind
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
    local name = Extract.cleanString(analyzer, unsupported, source,
        prefix .. ".name", rule.name, item)
    if name == "" then
        return nil
    end

    local book_url = Extract.url(analyzer, unsupported, source,
        prefix .. ".bookUrl", rule.bookUrl, item)
    if book_url == "" then
        book_url = final_url
    end

    local latest_chapter = Extract.cleanString(analyzer, unsupported, source,
        prefix .. ".lastChapter", rule.lastChapter, item)
    local kind = Extract.listText(analyzer, unsupported, source,
        prefix .. ".kind", rule.kind, item)
    kind = normalizeKind(source, book_url, kind)

    return {
        name = name,
        author = Extract.cleanString(analyzer, unsupported, source,
            prefix .. ".author", rule.author, item),
        intro = Extract.cleanString(analyzer, unsupported, source,
            prefix .. ".intro", rule.intro, item),
        kind = kind,
        latestChapter = latest_chapter,
        latestChapterTitle = latest_chapter,
        updateTime = Extract.cleanString(analyzer, unsupported, source,
            prefix .. ".updateTime", rule.updateTime, item),
        bookUrl = book_url,
        coverUrl = Extract.url(analyzer, unsupported, source,
            prefix .. ".coverUrl", rule.coverUrl, item),
        wordCount = Extract.cleanString(analyzer, unsupported, source,
            prefix .. ".wordCount", rule.wordCount, item),
        origin = sourceKey(source),
        originName = sourceName(source),
        originOrder = source.customOrder or 0,
        type = source.bookSourceType or 0,
    }
end

function Books.parse(source, rule, prefix, response, options)
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
    local items = Extract.elements(analyzer, unsupported, source,
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

return Books
