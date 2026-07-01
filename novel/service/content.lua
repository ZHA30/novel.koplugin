local Analyzer = require("novel.rule.analyzer")
local Cache = require("novel.storage.cache")
local HtmlFormat = require("novel.support.htmlformat")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local Content = {}
Content.__index = Content

local DEFAULT_MAX_PAGES = 20

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

local function responseSummary(response)
    return {
        request_url = response.request_url,
        final_url = response.final_url or response.url,
        status = response.status,
        bytes = #(response.body or ""),
        redirects = response.redirects or {},
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

local function copyUrlUnsupported(target, source, items, field)
    for index = 1, #(items or {}) do
        local item = items[index]
        table.insert(target, {
            source = sourceName(source),
            field = item.field == "url" and field or item.field,
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        })
    end
end

local function addUnsupported(target, source, field, kind, snippet)
    table.insert(target, {
        source = sourceName(source),
        field = field,
        kind = kind,
        snippet = tostring(snippet or ""):sub(1, 120),
    })
end

local function requestSpec(source, url, options)
    local spec = Url.parse(url, {
        base_url = source.bookSourceUrl,
        headers = source.header,
    })
    spec.timeout = options.timeout or spec.timeout
    spec.total_timeout = options.total_timeout or spec.total_timeout
        or (tonumber(source.respondTime) and tonumber(source.respondTime) / 1000)
    spec.max_redirects = options.max_redirects or spec.max_redirects
    return spec
end

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

    local token, wait_ms = self.throttle:acquire(source, source.concurrentRate)
    if not token then
        return nil, addError("throttle", "source request is rate limited", {
            wait_ms = wait_ms,
        })
    end

    local ok, response = pcall(function()
        return self.request.execute(spec)
    end)
    self.throttle:release(token)

    if not ok then
        return nil, addError("request", tostring(response))
    end
    if not response.ok then
        return nil, response.error or addError("request", "request failed")
    end
    return response
end

function Content.parsePage(source, book, chapter, rule, response, next_chapter_url)
    local debug, unsupported = {}, {}
    local final_url = response.final_url or response.url or response.request_url
        or chapter.url or ""
    local base_url = response.request_url or final_url
    local analyzer = Analyzer:new({
        content = response.body or "",
        base_url = base_url,
        redirect_url = final_url,
    })
    analyzer.nextChapterUrl = next_chapter_url
    analyzer.chapter = chapter
    analyzer.book = book

    addDebug(debug, "parse_content", {
        rule = rule.content,
    })
    local start_index = #analyzer.unsupported + 1
    local raw_content = analyzer:getString(rule.content)
    copyUnsupported(unsupported, source, "ruleContent.content",
        analyzer.unsupported, start_index)
    local text = HtmlFormat.text(raw_content)

    local next_urls = {}
    if not isBlank(rule.nextContentUrl) then
        start_index = #analyzer.unsupported + 1
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
        next_urls = next_urls,
        debug = debug,
        unsupported = unsupported,
        response = responseSummary(response),
    }
end

local function applyReplaceRule(source, rule, text, unsupported)
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
        return HtmlFormat.text(replaced)
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
    if not isBlank(source.ruleContent.sourceRegex) then
        addUnsupported(unsupported, source, "ruleContent.sourceRegex",
            "regex", source.ruleContent.sourceRegex)
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

    local text = table.concat(parts, "\n\n")
    text = applyReplaceRule(source, source.ruleContent, text, unsupported)
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
