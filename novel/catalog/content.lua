local Analyzer = require("novel.rule.analyzer")
local Cache = require("novel.storage.cache")
local ContentRule = require("novel.rule.content")
local Context = require("novel.catalog.client")
local Fields = require("novel.catalog.extract")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local Content = {}
Content.__index = Content

local DEFAULT_MAX_PAGES = 20

local isBlank = Context.isBlank
local addDebug = Context.addDebug
local addError = Context.error
local responseSummary = Context.responseSummary
local copyUnsupported = Context.copyUnsupported
local copyUrlUnsupported = Context.copyUrlUnsupported
local addUnsupported = Context.addUnsupported
local requestSpec = Context.requestSpec

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

function Content:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function Content:fetchPage(source, url, options, unsupported)
    local spec = requestSpec(source, url, options)
    copyUrlUnsupported(unsupported, source, spec.unsupported, "chapter.url")
    if #spec.errors > 0 then
        return nil, addError("url", spec.errors[1].error, spec.errors[1])
    end

    return Context.execute(self, source, spec)
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

function Content.parsePage(source, book, chapter, rule, response, next_chapter_url)
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
    local content_type = ContentRule.typeForRule(rule.content)
    local raw_content = Fields.raw(analyzer, unsupported, source,
        "ruleContent.content", rule.content)
    local text = ContentRule.format(raw_content, content_type)

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
        return ContentRule.format(replaced, content_type)
    end
    return text
end

local function initialChapterUrl(source, book, chapter)
    local base_url = chapter.baseUrl or book.tocUrl or book.bookUrl
        or source.bookSourceUrl
    return Url.absolute(base_url, chapter.url)
end

function Content:get(source, book, chapter, options)
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
    local cache = options.cache or Cache:new()
    local key = cacheKey(source, book, chapter, first_url, next_chapter_url,
        source.ruleContent, options)
    local cached = cachedResult(cache, key, options)
    if cached then
        return cached
    end

    local queue, queued, visited = {}, {}, {}
    local parts = {}
    local content_type = ContentRule.typeForRule(source.ruleContent.content)
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

            local parsed = Content.parsePage(source, book, chapter,
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

    local text = ContentRule.join(parts, content_type)
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
        chapter = chapter,
        book = book,
        debug = debug,
        unsupported = unsupported,
        pages = pages,
    }
    cache:set("content", key, result, options)
    return result
end

function Content.run(source, book, chapter, options)
    return Content:new(options):get(source, book, chapter, options)
end

return Content
