local Analyzer = require("novel.rule.analyzer")
local Book = require("novel.model.book")
local Cache = require("novel.storage.cache")
local Runtime = require("novel.catalog.runtime")
local Extract = require("novel.catalog.extract")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local BookDetail = {}
BookDetail.__index = BookDetail

local isBlank = Runtime.isBlank
local sourceName = Runtime.sourceName
local sourceKey = Runtime.sourceKey
local addDebug = Runtime.addDebug
local addError = Runtime.error
local responseSummary = Runtime.responseSummary
local copyUnsupported = Runtime.copyUnsupported
local copyUrlUnsupported = Runtime.copyUrlUnsupported

local function applyIfPresent(target, field, value, replace)
    if value ~= "" and (replace or isBlank(target[field])) then
        target[field] = value
    end
end

local function cacheKey(source, book, options)
    return Cache.makeKey("detail", {
        source = source.bookSourceUrl,
        book = book.bookUrl,
        rule = source.ruleBookInfo,
        use_info_html = options.use_info_html ~= false and book.infoHtml ~= nil,
    })
end

local function cachedResult(cache, key, options)
    if not cache then
        return nil
    end

    local value, meta = cache:get("detail", key, options)
    if not value then
        return nil
    end
    value.cached = true
    value.cache = meta
    value.debug = value.debug or {}
    table.insert(value.debug, 1, {
        event = "cache_hit",
        data = {
            kind = "detail",
            key = key,
            stored_at = meta.stored_at,
        },
    })
    return value
end

local function allowsRename(analyzer, unsupported, source, rule, can_rename)
    if not can_rename or isBlank(rule.canReName) then
        return false
    end
    local value = Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.canReName", rule.canReName)
    if value == "" then
        return false
    end
    local lowered = value:lower()
    return lowered ~= "false" and lowered ~= "0" and lowered ~= "no"
end

local function applyInit(analyzer, unsupported, source, rule, debug)
    if isBlank(rule.init) then
        return
    end
    addDebug(debug, "parse_init", {
        rule = rule.init,
    })
    local start_index = #analyzer.unsupported + 1
    local content = analyzer:getElement(rule.init)
    copyUnsupported(unsupported, source, "ruleBookInfo.init",
        analyzer.unsupported, start_index)
    if content then
        analyzer:setContent(content)
    end
end

local function parseBook(source, input_book, rule, response, options)
    local debug, unsupported = {}, {}
    local final_url = response.final_url or response.url or response.request_url
        or input_book.bookUrl or ""
    local base_url = response.request_url or input_book.bookUrl or final_url
    local book = Book.fromSearchBook(input_book)
    book.bookUrl = Url.absolute(source.bookSourceUrl,
        book.bookUrl ~= "" and book.bookUrl or final_url)
    book.origin = book.origin ~= "" and book.origin or sourceKey(source)
    book.originName = book.originName ~= "" and book.originName or sourceName(source)
    book.originOrder = book.originOrder or source.customOrder or 0
    book.type = book.type or source.bookSourceType or 0
    book.infoHtml = response.body

    local analyzer = Analyzer:new({
        content = response.body or "",
        base_url = base_url,
        redirect_url = final_url,
    })

    applyInit(analyzer, unsupported, source, rule, debug)

    local can_rename = allowsRename(analyzer, unsupported, source, rule,
        options.can_rename == true)
    applyIfPresent(book, "name", Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.name", rule.name), can_rename)
    applyIfPresent(book, "author", Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.author", rule.author), can_rename)
    applyIfPresent(book, "kind", Extract.listText(analyzer, unsupported, source,
        "ruleBookInfo.kind", rule.kind), true)
    applyIfPresent(book, "wordCount", Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.wordCount", rule.wordCount), true)

    local latest_chapter = Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.lastChapter", rule.lastChapter)
    applyIfPresent(book, "latestChapterTitle", latest_chapter, true)
    book.latestChapter = book.latestChapterTitle
    applyIfPresent(book, "updateTime", Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.updateTime", rule.updateTime), true)

    applyIfPresent(book, "intro", Extract.text(analyzer, unsupported, source,
        "ruleBookInfo.intro", rule.intro), true)
    applyIfPresent(book, "coverUrl", Extract.url(analyzer, unsupported, source,
        "ruleBookInfo.coverUrl", rule.coverUrl), true)

    local toc_url = Extract.url(analyzer, unsupported, source,
        "ruleBookInfo.tocUrl", rule.tocUrl)
    if toc_url == "" then
        toc_url = base_url
    end
    book.tocUrl = toc_url
    if book.tocUrl == base_url or book.tocUrl == final_url then
        book.tocHtml = response.body
    end

    addDebug(debug, "parsed_book", {
        name = book.name,
        author = book.author,
        toc_url = book.tocUrl,
    })

    return {
        ok = true,
        book = book,
        debug = debug,
        unsupported = unsupported,
    }
end

local function syntheticResponse(book)
    return {
        ok = true,
        request_url = book.bookUrl,
        final_url = book.bookUrl,
        status = nil,
        headers = {},
        body = book.infoHtml,
        redirects = {},
    }
end

function BookDetail:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function BookDetail:get(source, search_book, options)
    options = options or {}
    local debug, unsupported = {}, {}

    if type(source) ~= "table" then
        return {
            ok = false,
            book = nil,
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source is required"),
        }
    end
    if type(search_book) ~= "table" then
        return {
            ok = false,
            book = nil,
            debug = debug,
            unsupported = unsupported,
            error = addError("book", "book is required"),
        }
    end
    if isBlank(search_book.bookUrl) then
        return {
            ok = false,
            book = nil,
            debug = debug,
            unsupported = unsupported,
            error = addError("book", "bookUrl is required"),
        }
    end
    if type(source.ruleBookInfo) ~= "table" then
        return {
            ok = false,
            book = nil,
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "ruleBookInfo is required"),
        }
    end

    local cache = Cache.instance(options)
    local key = cacheKey(source, search_book, options)
    local cached = cachedResult(cache, key, options)
    if cached then
        return cached
    end

    local response
    if search_book.infoHtml and options.use_info_html ~= false then
        response = syntheticResponse(search_book)
        addDebug(debug, "response", responseSummary(response))
    else
        local spec = Runtime.requestSpec(source, search_book.bookUrl, options)
        copyUrlUnsupported(unsupported, source, spec.unsupported, "bookUrl")

        addDebug(debug, "request", {
            url = spec.url,
            method = spec.method,
        })

        if #spec.errors > 0 then
            return {
                ok = false,
                book = nil,
                debug = debug,
                unsupported = unsupported,
                error = addError("url", spec.errors[1].error, spec.errors[1]),
            }
        end

        local request_response, request_err, failed_response = Runtime.execute(self, source, spec)
        if not request_response then
            if failed_response then
                addDebug(debug, "response", responseSummary(failed_response))
            end
            return {
                ok = false,
                book = nil,
                debug = debug,
                unsupported = unsupported,
                error = request_err,
                response = failed_response and responseSummary(failed_response) or nil,
            }
        end

        response = request_response
        addDebug(debug, "response", responseSummary(response))
    end

    local parsed = parseBook(source, search_book, source.ruleBookInfo,
        response, options)
    for index = 1, #parsed.debug do
        table.insert(debug, parsed.debug[index])
    end
    for index = 1, #parsed.unsupported do
        table.insert(unsupported, parsed.unsupported[index])
    end
    parsed.debug = debug
    parsed.unsupported = unsupported
    parsed.response = responseSummary(response)
    if parsed.ok and parsed.book and cache then
        cache:set("detail", key, parsed, {
            owner = {
                source = source.bookSourceUrl,
                book = parsed.book.bookUrl or search_book.bookUrl,
            },
            tags = {
                kind = "detail",
            },
            settings = options.settings,
            ttl = options.ttl,
            flush = options.flush,
        })
    end
    return parsed
end

function BookDetail.run(source, book, options)
    return BookDetail:new(options):get(source, book, options)
end

return BookDetail
