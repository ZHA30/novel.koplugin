local Analyzer = require("novel.rule.analyzer")
local Chapter = require("novel.model.chapter")
local Cache = require("novel.storage.cache")
local HtmlFormat = require("novel.support.htmlformat")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local Toc = {}
Toc.__index = Toc

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

local function analyzeString(analyzer, unsupported, source, field, rule, content)
    if isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local value = analyzer:getString(rule, content)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)
    return trim(value)
end

local function analyzeText(analyzer, unsupported, source, field, rule, content)
    return HtmlFormat.text(analyzeString(analyzer, unsupported, source, field, rule, content))
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

local function analyzeUrlList(analyzer, unsupported, source, field, rule)
    if isBlank(rule) then
        return {}
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, nil, true)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)
    return values
end

local function asBoolean(value)
    value = trim(value):lower()
    return value == "true" or value == "1" or value == "yes"
        or value == "y" or value == "on" or value == "vip"
end

local function listRule(rule)
    local value = trim(rule and rule.chapterList or "")
    local reverse = false
    if value:sub(1, 1) == "-" then
        reverse = true
        value = trim(value:sub(2))
    elseif value:sub(1, 1) == "+" then
        value = trim(value:sub(2))
    end
    return value, reverse
end

local function cacheKey(source, book, toc_url, rule, options)
    return Cache.makeKey("toc", {
        source = source.bookSourceUrl,
        book = book.bookUrl,
        toc = toc_url,
        rule = rule,
        max_pages = options.max_pages or DEFAULT_MAX_PAGES,
    })
end

local function cachedResult(cache, key, options)
    local value, meta = cache:get("toc", key, options)
    if not value then
        return nil
    end
    value.cached = true
    value.cache = meta
    value.debug = value.debug or {}
    table.insert(value.debug, 1, {
        event = "cache_hit",
        data = {
            kind = "toc",
            key = key,
            stored_at = meta.stored_at,
        },
    })
    return value
end

local function enqueue(queue, queued, visited, url)
    if url and url ~= "" and not visited[url] and not queued[url] then
        queued[url] = true
        table.insert(queue, url)
    end
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

local function syntheticResponse(book, url)
    return {
        ok = true,
        request_url = url,
        final_url = url,
        status = nil,
        headers = {},
        body = book.tocHtml,
        redirects = {},
    }
end

function Toc:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function Toc:fetchPage(source, book, url, options, unsupported)
    if book.tocHtml and url == book.tocUrl and options.use_toc_html ~= false then
        return syntheticResponse(book, url)
    end

    local spec = requestSpec(source, url, options)
    copyUrlUnsupported(unsupported, source, spec.unsupported, "tocUrl")
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

function Toc.parsePage(source, book, rule, list_rule, response, get_next)
    local debug, unsupported, chapters, next_urls = {}, {}, {}, {}
    local final_url = response.final_url or response.url or response.request_url
        or book.tocUrl or book.bookUrl or ""
    local base_url = response.request_url or final_url
    local analyzer = Analyzer:new({
        content = response.body or "",
        base_url = base_url,
        redirect_url = final_url,
    })

    addDebug(debug, "parse_chapter_list", {
        rule = list_rule,
    })
    local start_index = #analyzer.unsupported + 1
    local elements = analyzer:getElements(list_rule)
    copyUnsupported(unsupported, source, "ruleToc.chapterList",
        analyzer.unsupported, start_index)
    addDebug(debug, "chapter_list_size", {
        count = #elements,
    })

    if get_next and not isBlank(rule.nextTocUrl) then
        local values = analyzeUrlList(analyzer, unsupported, source,
            "ruleToc.nextTocUrl", rule.nextTocUrl)
        for value_index = 1, #values do
            local next_url = values[value_index]
            if next_url ~= "" and next_url ~= final_url and next_url ~= base_url then
                table.insert(next_urls, next_url)
            end
        end
    end

    for element_index = 1, #elements do
        local element = elements[element_index]
        analyzer:setContent(element)
        local title = analyzeText(analyzer, unsupported, source,
            "ruleToc.chapterName", rule.chapterName, element)
        if title ~= "" then
            local is_volume = asBoolean(analyzeText(analyzer, unsupported, source,
                "ruleToc.isVolume", rule.isVolume, element))
            local chapter_url = analyzeUrl(analyzer, unsupported, source,
                "ruleToc.chapterUrl", rule.chapterUrl, element)
            if chapter_url == "" then
                if is_volume then
                    chapter_url = title .. tostring(element_index)
                else
                    chapter_url = base_url
                end
            end
            local is_vip = asBoolean(analyzeText(analyzer, unsupported, source,
                "ruleToc.isVip", rule.isVip, element))
            table.insert(chapters, Chapter.new{
                url = chapter_url,
                title = title,
                isVolume = is_volume,
                isVip = is_vip,
                baseUrl = final_url,
                bookUrl = book.bookUrl,
                tag = analyzeText(analyzer, unsupported, source,
                    "ruleToc.updateTime", rule.updateTime, element),
            })
        end
    end

    return {
        chapters = chapters,
        next_urls = next_urls,
        debug = debug,
        unsupported = unsupported,
        response = responseSummary(response),
    }
end

local function dedupeChapters(chapters, reverse_rule)
    local deduped, seen = {}, {}
    for chapter_index = 1, #chapters do
        local chapter = chapters[chapter_index]
        if not seen[chapter.url] then
            seen[chapter.url] = true
            table.insert(deduped, chapter)
        end
    end

    if reverse_rule then
        local left, right = 1, #deduped
        while left < right do
            deduped[left], deduped[right] = deduped[right], deduped[left]
            left = left + 1
            right = right - 1
        end
    end

    for index = 1, #deduped do
        deduped[index].index = index - 1
    end
    return deduped
end

function Toc:get(source, book, options)
    options = options or {}
    local debug, unsupported, pages = {}, {}, {}
    if type(source) ~= "table" then
        return {
            ok = false,
            chapters = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source is required"),
        }
    end
    if type(book) ~= "table" then
        return {
            ok = false,
            chapters = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("book", "book is required"),
        }
    end
    if type(source.ruleToc) ~= "table" then
        return {
            ok = false,
            chapters = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "ruleToc is required"),
        }
    end

    local toc_url = Url.absolute(source.bookSourceUrl,
        not isBlank(book.tocUrl) and book.tocUrl or book.bookUrl)
    if toc_url == "" then
        return {
            ok = false,
            chapters = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("book", "tocUrl is required"),
        }
    end
    book.tocUrl = toc_url

    local rule, reverse_rule = listRule(source.ruleToc)
    if rule == "" then
        return {
            ok = false,
            chapters = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("rule", "ruleToc.chapterList is required"),
        }
    end
    if not isBlank(source.ruleToc.preUpdateJs) then
        table.insert(unsupported, {
            source = sourceName(source),
            field = "ruleToc.preUpdateJs",
            kind = "js",
            snippet = tostring(source.ruleToc.preUpdateJs):sub(1, 120),
        })
    end

    local cache = options.cache or Cache:new()
    local key = cacheKey(source, book, toc_url, source.ruleToc, options)
    local cached = cachedResult(cache, key, options)
    if cached then
        return cached
    end

    local queue, queued, visited = {}, {}, {}
    enqueue(queue, queued, visited, toc_url)
    local chapters = {}
    local max_pages = options.max_pages or DEFAULT_MAX_PAGES

    while #queue > 0 and #pages < max_pages do
        local current_url = table.remove(queue, 1)
        queued[current_url] = nil
        if not visited[current_url] then
            visited[current_url] = true
            addDebug(debug, "request", {
                url = current_url,
            })
            local response, err = self:fetchPage(source, book, current_url,
                options, unsupported)
            if not response then
                return {
                    ok = false,
                    chapters = {},
                    debug = debug,
                    unsupported = unsupported,
                    error = err,
                    pages = pages,
                }
            end

            local parsed = Toc.parsePage(source, book, source.ruleToc,
                rule, response, true)
            table.insert(pages, parsed.response)
            for index = 1, #parsed.debug do
                table.insert(debug, parsed.debug[index])
            end
            for index = 1, #parsed.unsupported do
                table.insert(unsupported, parsed.unsupported[index])
            end
            for index = 1, #parsed.chapters do
                table.insert(chapters, parsed.chapters[index])
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

    chapters = dedupeChapters(chapters, reverse_rule)
    if #chapters == 0 then
        return {
            ok = false,
            chapters = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("toc_empty", "table of contents is empty"),
            pages = pages,
        }
    end

    book.latestChapterTitle = chapters[#chapters].title
    if (book.totalChapterNum or 0) < #chapters then
        book.lastCheckCount = #chapters - (book.totalChapterNum or 0)
    end
    book.totalChapterNum = #chapters

    local result = {
        ok = true,
        chapters = chapters,
        book = book,
        debug = debug,
        unsupported = unsupported,
        pages = pages,
    }
    cache:set("toc", key, result, options)
    return result
end

function Toc.run(source, book, options)
    return Toc:new(options):get(source, book, options)
end

return Toc
