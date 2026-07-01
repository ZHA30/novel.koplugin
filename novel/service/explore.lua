local Analyzer = require("novel.rule.analyzer")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")
local rapidjson = require("rapidjson")

local Explore = {}
Explore.__index = Explore

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

local function addUnsupported(target, source, field, kind, snippet)
    table.insert(target, {
        source = sourceName(source),
        field = field,
        kind = kind,
        snippet = tostring(snippet or ""):sub(1, 120),
    })
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
            field = item.field == "url" and "exploreUrl" or item.field,
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

local function activeRule(source)
    if type(source.ruleExplore) == "table" and not isBlank(source.ruleExplore.bookList) then
        return source.ruleExplore, "ruleExplore"
    end
    return source.ruleSearch, "ruleSearch"
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

local function parseBooks(source, rule, prefix, response)
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

    addDebug(debug, "parse_explore_list", {
        rule = book_list_rule,
    })
    local items = analyzeElements(analyzer, unsupported, source,
        prefix .. ".bookList", book_list_rule)
    addDebug(debug, "explore_list_size", {
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

local function responseSummary(response)
    return {
        request_url = response.request_url,
        final_url = response.final_url or response.url,
        status = response.status,
        bytes = #(response.body or ""),
        redirects = response.redirects or {},
    }
end

local function parseJsonGroups(source, groups, decoded)
    for index = 1, #decoded do
        local item = decoded[index]
        if type(item) == "table" and not isBlank(item.url) then
            table.insert(groups, {
                title = trim(item.title or item.name or item.url),
                url = trim(item.url),
                source = source,
            })
        end
    end
end

local function parseTextGroups(source, groups, text)
    text = tostring(text or ""):gsub("\r\n", "\n")
    for raw_line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local start_index = 1
        while start_index <= #raw_line do
            local delimiter_start = raw_line:find("&&", start_index, true)
            local part = delimiter_start
                and raw_line:sub(start_index, delimiter_start - 1)
                or raw_line:sub(start_index)
            local line = trim(part)
            if line ~= "" then
                local title, url = line:match("^(.-)::(.+)$")
                if title and url then
                    table.insert(groups, {
                        title = trim(title),
                        url = trim(url),
                        source = source,
                    })
                end
            end
            if not delimiter_start then
                break
            end
            start_index = delimiter_start + 2
        end
    end
end

function Explore.groups(source)
    local groups, unsupported = {}, {}
    if type(source) ~= "table" or isBlank(source.exploreUrl) then
        return groups, unsupported
    end
    local text = trim(source.exploreUrl)
    if text:match("^<js>") or text:match("^@js:") or text:match("^%{%{") then
        addUnsupported(unsupported, source, "exploreUrl", "js", text)
        return groups, unsupported
    end

    local ok, decoded = pcall(rapidjson.decode, text)
    if ok and type(decoded) == "table" then
        parseJsonGroups(source, groups, decoded)
    else
        parseTextGroups(source, groups, text .. "\n")
    end
    return groups, unsupported
end

function Explore:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function Explore:explore(source, group, options)
    options = options or {}
    local debug, unsupported = {}, {}

    if type(source) ~= "table" then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source is required"),
        }
    end
    if source.enabled == false or source.enabledExplore == false then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source explore is disabled"),
        }
    end
    if type(group) ~= "table" or isBlank(group.url) then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("explore", "exploreUrl is required"),
        }
    end

    local rule, prefix = activeRule(source)
    if type(rule) ~= "table" then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "ruleExplore or ruleSearch is required"),
        }
    end

    local spec = Url.parse(group.url, {
        base_url = source.bookSourceUrl,
        headers = source.header,
        page = options.page or 1,
    })
    spec.timeout = options.timeout or spec.timeout
    spec.total_timeout = options.total_timeout or spec.total_timeout
        or (tonumber(source.respondTime) and tonumber(source.respondTime) / 1000)
    spec.max_redirects = options.max_redirects or spec.max_redirects
    copyUrlUnsupported(unsupported, source, spec.unsupported)

    addDebug(debug, "request", {
        url = spec.url,
        method = spec.method,
        title = group.title,
        page = options.page or 1,
    })

    if #spec.errors > 0 then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("url", spec.errors[1].error, spec.errors[1]),
        }
    end

    local token, wait_ms = self.throttle:acquire(source, source.concurrentRate)
    if not token then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("throttle", "source request is rate limited", {
                wait_ms = wait_ms,
            }),
        }
    end

    local ok, response = pcall(function()
        return self.request.execute(spec)
    end)
    self.throttle:release(token)

    if not ok then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("request", tostring(response)),
        }
    end

    addDebug(debug, "response", responseSummary(response))
    if not response.ok then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = response.error or addError("request", "request failed"),
            response = responseSummary(response),
        }
    end

    local parsed = parseBooks(source, rule, prefix, response)
    for index = 1, #parsed.debug do
        table.insert(debug, parsed.debug[index])
    end
    for index = 1, #parsed.unsupported do
        table.insert(unsupported, parsed.unsupported[index])
    end
    parsed.debug = debug
    parsed.unsupported = unsupported
    parsed.response = responseSummary(response)
    parsed.group = {
        title = group.title,
        url = group.url,
        page = options.page or 1,
    }
    return parsed
end

function Explore.run(source, group, options)
    return Explore:new(options):explore(source, group, options)
end

return Explore
