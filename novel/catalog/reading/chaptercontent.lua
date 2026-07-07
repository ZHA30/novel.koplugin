local Analyzer = require("novel.catalog.shared.analyzer")
local Cache = require("novel.storage.cache")
local ContentType = require("novel.catalog.shared.contenttype")
local Extract = require("novel.catalog.shared.extract")
local RequestSupport = require("novel.catalog.shared.requestsupport")
local HttpRequest = require("novel.catalog.shared.httprequest")
local Text = require("novel.catalog.shared.text")
local Throttle = require("novel.catalog.shared.throttle")
local Url = require("novel.catalog.shared.url")

local ChapterContent = {}
ChapterContent.__index = ChapterContent

local DEFAULT_MAX_PAGES = 20

local isBlank = Text.isBlank
local addDebug = RequestSupport.addDebug
local addError = RequestSupport.error
local responseSummary = RequestSupport.responseSummary
local copyUnsupported = RequestSupport.copyUnsupported
local copyUrlUnsupported = RequestSupport.copyUrlUnsupported
local addUnsupported = RequestSupport.addUnsupported
local requestSpec = RequestSupport.requestSpec

local function enqueue(queue, queued, visited, url)
    if url and url ~= "" and not visited[url] and not queued[url] then
        queued[url] = true
        table.insert(queue, url)
    end
end

local function sameUrl(left, right)
    return left ~= "" and right ~= "" and left == right
end

local function cacheKey(source, book, chapter, first_url, next_chapter_url, rule, options)
    return Cache.makeKey("content", {
        source = source.bookSourceUrl,
        book = book.bookUrl,
        chapter = chapter.url,
        first = first_url,
        next_chapter = next_chapter_url,
        rule = rule,
        max_pages = options.max_pages or DEFAULT_MAX_PAGES,
    })
end

local function cachedResult(cache, key, options)
    if not cache then
        return nil
    end

    local value, meta = cache:get("content", key, options)
    if not value then
        return nil
    end
    value.cached = true
    value.cache = meta
    value.debug = value.debug or {}
    table.insert(value.debug, 1, {
        event = "cache_hit",
        data = {
            kind = "content",
            key = key,
            stored_at = meta.stored_at,
        },
    })
    return value
end

function ChapterContent:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or HttpRequest,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function ChapterContent:fetchPage(source, url, options, unsupported)
    local spec = requestSpec(source, url, options)
    copyUrlUnsupported(unsupported, source, spec.unsupported, "chapter.url")
    if #spec.errors > 0 then
        return nil, addError("url", spec.errors[1].error, spec.errors[1])
    end

    return RequestSupport.execute(self, source, spec)
end

local function applySourceRegex(source, rule, body, base_url, redirect_url, unsupported)
    if isBlank(rule.sourceRegex) then
        return body
    end
    local analyzer = Analyzer:new({
        content = body,
        base_url = base_url,
        redirect_url = redirect_url,
    })
    local start_index = #analyzer.unsupported + 1
    local filtered = analyzer:getString(rule.sourceRegex)
    copyUnsupported(unsupported, source, "ruleContent.sourceRegex",
        analyzer.unsupported, start_index)
    if filtered ~= "" then
        return filtered
    end
    return body
end

function ChapterContent.parsePage(source, book, chapter, rule, response, next_chapter_url)
    local debug, unsupported = {}, {}
    local final_url = response.final_url or response.url or response.request_url
        or chapter.url or ""
    local base_url = response.request_url or final_url
    local body = applySourceRegex(source, rule, response.body or "",
        base_url, final_url, unsupported)
    local analyzer = Analyzer:new({
        content = body,
        base_url = base_url,
        redirect_url = final_url,
    })
    analyzer.nextChapterUrl = next_chapter_url
    analyzer.chapter = chapter
    analyzer.book = book

    addDebug(debug, "parse_content", {
        rule = rule.content,
    })
    local content_type = ContentType.typeForRule(rule.content)
    local raw_content = Extract.raw(analyzer, unsupported, source,
        "ruleContent.content", rule.content)
    local text = ContentType.format(raw_content, content_type)

    local next_urls = {}
    if not isBlank(rule.nextContentUrl) then
        local start_index = #analyzer.unsupported + 1
        local values = analyzer:getStringList(rule.nextContentUrl, nil, true)
        copyUnsupported(unsupported, source, "ruleContent.nextContentUrl",
            analyzer.unsupported, start_index)
        for value_index = 1, #values do
            local next_url = values[value_index]
            if not sameUrl(next_url, final_url)
                and not sameUrl(next_url, base_url)
                and not sameUrl(next_url, next_chapter_url or "") then
                table.insert(next_urls, next_url)
            end
        end
    end

    return {
        text = text,
        content_type = content_type,
        next_urls = next_urls,
        debug = debug,
        unsupported = unsupported,
        response = responseSummary(response),
    }
end

local function applyReplaceRule(source, rule, text, unsupported, content_type)
    if isBlank(rule.replaceRegex) then
        return text
    end
    local analyzer = Analyzer:new({
        content = text,
    })
    local start_index = #analyzer.unsupported + 1
    local replaced = analyzer:getString(rule.replaceRegex)
    copyUnsupported(unsupported, source, "ruleContent.replaceRegex",
        analyzer.unsupported, start_index)
    if replaced ~= "" then
        return ContentType.format(replaced, content_type)
    end
    return text
end

local function initialChapterUrl(source, book, chapter)
    local base_url = chapter.baseUrl or book.tocUrl or book.bookUrl
        or source.bookSourceUrl
    return Url.absolute(base_url, chapter.url)
end

function ChapterContent:get(source, book, chapter, options)
    options = options or {}
    local debug, unsupported, pages = {}, {}, {}
    if type(source) ~= "table" then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source is required"),
        }
    end
    if type(book) ~= "table" then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("book", "book is required"),
        }
    end
    if type(chapter) ~= "table" then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("chapter", "chapter is required"),
        }
    end
    if type(source.ruleContent) ~= "table" then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "ruleContent is required"),
        }
    end
    if isBlank(source.ruleContent.content) then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("rule", "ruleContent.content is required"),
        }
    end
    if not isBlank(source.ruleContent.webJs) then
        addUnsupported(unsupported, source, "ruleContent.webJs",
            "js", source.ruleContent.webJs)
    end
    if not ContentType.supportsImageStyle(source.ruleContent.imageStyle) then
        addUnsupported(unsupported, source, "ruleContent.imageStyle",
            "unsupported_value", source.ruleContent.imageStyle)
    end

    local first_url = initialChapterUrl(source, book, chapter)
    if first_url == "" then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("chapter", "chapter url is required"),
        }
    end

    local next_chapter_url = options.next_chapter_url
        and Url.absolute(chapter.baseUrl or book.tocUrl or book.bookUrl,
            options.next_chapter_url)
        or ""
    local cache = Cache.isKindEnabled("content", options)
        and Cache.instance(options) or nil
    local key = cacheKey(source, book, chapter, first_url, next_chapter_url,
        source.ruleContent, options)
    local cached = cachedResult(cache, key, options)
    if cached then
        return cached
    end

    local queue, queued, visited = {}, {}, {}
    local parts = {}
    local content_type = ContentType.typeForRule(source.ruleContent.content)
    local image_style = ContentType.normalizeImageStyle(source.ruleContent.imageStyle)
    enqueue(queue, queued, visited, first_url)
    local max_pages = options.max_pages or DEFAULT_MAX_PAGES

    while #queue > 0 and #pages < max_pages do
        local current_url = table.remove(queue, 1)
        queued[current_url] = nil
        if not visited[current_url] then
            visited[current_url] = true
            addDebug(debug, "request", {
                url = current_url,
            })
            local response, err = self:fetchPage(source, current_url,
                options, unsupported)
            if not response then
                return {
                    ok = false,
                    text = "",
                    debug = debug,
                    unsupported = unsupported,
                    error = err,
                    pages = pages,
                }
            end

            local parsed = ChapterContent.parsePage(source, book, chapter,
                source.ruleContent, response, next_chapter_url)
            table.insert(pages, parsed.response)
            for index = 1, #parsed.debug do
                table.insert(debug, parsed.debug[index])
            end
            for index = 1, #parsed.unsupported do
                table.insert(unsupported, parsed.unsupported[index])
            end
            if parsed.text ~= "" then
                table.insert(parts, parsed.text)
            end
            for index = 1, #parsed.next_urls do
                enqueue(queue, queued, visited, parsed.next_urls[index])
            end
        end
    end

    if #queue > 0 then
        addDebug(debug, "max_pages_reached", {
            max_pages = max_pages,
            remaining = #queue,
        })
    end

    local text = ContentType.join(parts, content_type)
    text = applyReplaceRule(source, source.ruleContent, text, unsupported,
        content_type)
    if text == "" then
        return {
            ok = false,
            text = "",
            debug = debug,
            unsupported = unsupported,
            error = addError("content_empty", "chapter content is empty"),
            pages = pages,
        }
    end

    local result = {
        ok = true,
        text = text,
        content_type = content_type,
        image_style = image_style,
        chapter = chapter,
        book = book,
        debug = debug,
        unsupported = unsupported,
        pages = pages,
    }
    if cache then
        cache:set("content", key, result, {
            owner = {
                source = source.bookSourceUrl,
                book = book.bookUrl,
            },
            tags = {
                kind = "content",
                chapter = chapter.url,
            },
            settings = options.settings,
            ttl = options.ttl,
            flush = options.flush,
        })
    end
    return result
end

function ChapterContent.run(source, book, chapter, options)
    return ChapterContent:new(options):get(source, book, chapter, options)
end

return ChapterContent
