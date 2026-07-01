local BookList = require("novel.service.booklist")
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

local function activeRule(source)
    if type(source.ruleExplore) == "table" and not isBlank(source.ruleExplore.bookList) then
        return source.ruleExplore, "ruleExplore"
    end
    return source.ruleSearch, "ruleSearch"
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

    local parsed = BookList.parse(source, rule, prefix, response, {
        parse_event = "parse_explore_list",
        size_event = "explore_list_size",
    })
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
