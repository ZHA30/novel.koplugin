local Analyzer = require("novel.rule.analyzer")
local Chapter = require("novel.model.chapter")
local Cache = require("novel.storage.cache")
local Runtime = require("novel.catalog.runtime")
local Extract = require("novel.catalog.extract")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local Chapters = {}
Chapters.__index = Chapters

local DEFAULT_MAX_PAGES = 20

local trim = Runtime.trim
local isBlank = Runtime.isBlank
local addDebug = Runtime.addDebug
local addError = Runtime.error
local responseSummary = Runtime.responseSummary
local copyUnsupported = Runtime.copyUnsupported
local copyUrlUnsupported = Runtime.copyUrlUnsupported
local addUnsupported = Runtime.addUnsupported
local requestSpec = Runtime.requestSpec

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
    if not cache then
        return nil
    end

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

function Chapters:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function Chapters:fetchPage(source, book, url, options, unsupported)
    if book.tocHtml and url == book.tocUrl and options.use_toc_html ~= false then
        return syntheticResponse(book, url)
    end

    local spec = requestSpec(source, url, options)
    copyUrlUnsupported(unsupported, source, spec.unsupported, "tocUrl")
    if #spec.errors > 0 then
        return nil, addError("url", spec.errors[1].error, spec.errors[1])
    end

    return Runtime.execute(self, source, spec)
end

function Chapters.parsePage(source, book, rule, list_rule, response, get_next)
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
        local values = Extract.urlList(analyzer, unsupported, source,
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
        local title = Extract.text(analyzer, unsupported, source,
            "ruleToc.chapterName", rule.chapterName, element)
        if title ~= "" then
            local is_volume = Extract.boolean(Extract.text(analyzer, unsupported, source,
                "ruleToc.isVolume", rule.isVolume, element))
            local chapter_url = Extract.url(analyzer, unsupported, source,
                "ruleToc.chapterUrl", rule.chapterUrl, element)
            if chapter_url == "" then
                if is_volume then
                    chapter_url = title .. tostring(element_index)
                else
                    chapter_url = base_url
                end
            end
            local is_vip = Extract.boolean(Extract.text(analyzer, unsupported, source,
                "ruleToc.isVip", rule.isVip, element))
            table.insert(chapters, Chapter.new{
                url = chapter_url,
                title = title,
                isVolume = is_volume,
                isVip = is_vip,
                baseUrl = final_url,
                bookUrl = book.bookUrl,
                tag = Extract.text(analyzer, unsupported, source,
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

function Chapters:get(source, book, options)
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
        addUnsupported(unsupported, source, "ruleToc.preUpdateJs",
            "js", source.ruleToc.preUpdateJs)
    end

    local cache = Cache.instance(options)
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

            local parsed = Chapters.parsePage(source, book, source.ruleToc,
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
    if cache then
        cache:set("toc", key, result, {
            owner = {
                source = source.bookSourceUrl,
                book = book.bookUrl,
            },
            tags = {
                kind = "toc",
            },
            settings = options.settings,
            ttl = options.ttl,
            flush = options.flush,
        })
    end
    return result
end

function Chapters.run(source, book, options)
    return Chapters:new(options):get(source, book, options)
end

return Chapters
