local Analyzer = require("novel.rule.analyzer")
local Book = require("novel.model.book")
local HtmlFormat = require("novel.support.htmlformat")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local BookInfo = {}
BookInfo.__index = BookInfo

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

local function copyUrlUnsupported(target, source, items)
    for index = 1, #(items or {}) do
        local item = items[index]
        table.insert(target, {
            source = sourceName(source),
            field = item.field == "url" and "bookUrl" or item.field,
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

local function analyzeList(analyzer, unsupported, source, field, rule, content)
    if isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, content)
    copyUnsupported(unsupported, source, field, analyzer.unsupported, start_index)

    local output = {}
    for index = 1, #values do
        local value = HtmlFormat.text(values[index])
        if value ~= "" then
            table.insert(output, value)
        end
    end
    return table.concat(output, ",")
end

local function applyIfPresent(target, field, value, replace)
    if value ~= "" and (replace or isBlank(target[field])) then
        target[field] = value
    end
end

local function allowsRename(analyzer, unsupported, source, rule, can_rename)
    if not can_rename or isBlank(rule.canReName) then
        return false
    end
    local value = analyzeText(analyzer, unsupported, source,
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
    applyIfPresent(book, "name", analyzeText(analyzer, unsupported, source,
        "ruleBookInfo.name", rule.name), can_rename)
    applyIfPresent(book, "author", analyzeText(analyzer, unsupported, source,
        "ruleBookInfo.author", rule.author), can_rename)
    applyIfPresent(book, "kind", analyzeList(analyzer, unsupported, source,
        "ruleBookInfo.kind", rule.kind), true)
    applyIfPresent(book, "wordCount", analyzeText(analyzer, unsupported, source,
        "ruleBookInfo.wordCount", rule.wordCount), true)

    local latest_chapter = analyzeText(analyzer, unsupported, source,
        "ruleBookInfo.lastChapter", rule.lastChapter)
    applyIfPresent(book, "latestChapterTitle", latest_chapter, true)
    book.latestChapter = book.latestChapterTitle

    applyIfPresent(book, "intro", analyzeText(analyzer, unsupported, source,
        "ruleBookInfo.intro", rule.intro), true)
    applyIfPresent(book, "coverUrl", analyzeUrl(analyzer, unsupported, source,
        "ruleBookInfo.coverUrl", rule.coverUrl), true)

    local toc_url = analyzeUrl(analyzer, unsupported, source,
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

function BookInfo:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function BookInfo:get(source, search_book, options)
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

    local response
    if search_book.infoHtml and options.use_info_html ~= false then
        response = syntheticResponse(search_book)
        addDebug(debug, "response", responseSummary(response))
    else
        local spec = Url.parse(search_book.bookUrl, {
            base_url = source.bookSourceUrl,
            headers = source.header,
        })
        spec.timeout = options.timeout or spec.timeout
        spec.total_timeout = options.total_timeout or spec.total_timeout
            or (tonumber(source.respondTime) and tonumber(source.respondTime) / 1000)
        spec.max_redirects = options.max_redirects or spec.max_redirects
        copyUrlUnsupported(unsupported, source, spec.unsupported)

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

        local token, wait_ms = self.throttle:acquire(source, source.concurrentRate)
        if not token then
            return {
                ok = false,
                book = nil,
                debug = debug,
                unsupported = unsupported,
                error = addError("throttle", "source request is rate limited", {
                    wait_ms = wait_ms,
                }),
            }
        end

        local ok, request_response = pcall(function()
            return self.request.execute(spec)
        end)
        self.throttle:release(token)

        if not ok then
            return {
                ok = false,
                book = nil,
                debug = debug,
                unsupported = unsupported,
                error = addError("request", tostring(request_response)),
            }
        end

        response = request_response
        addDebug(debug, "response", responseSummary(response))
        if not response.ok then
            return {
                ok = false,
                book = nil,
                debug = debug,
                unsupported = unsupported,
                error = response.error or addError("request", "request failed"),
                response = responseSummary(response),
            }
        end
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
    return parsed
end

function BookInfo.run(source, book, options)
    return BookInfo:new(options):get(source, book, options)
end

return BookInfo
