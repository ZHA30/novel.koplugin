local BookList = require("novel.service.booklist")
local Cache = require("novel.storage.cache")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local Url = require("novel.net.url")

local Search = {}
Search.__index = Search

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

local function copyUrlUnsupported(target, source, items)
    for index = 1, #(items or {}) do
        local item = items[index]
        table.insert(target, {
            source = sourceName(source),
            field = item.field == "url" and "searchUrl" or item.field,
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        })
    end
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

local function cacheKey(source, spec, keyword, options)
    return Cache.makeKey("search", {
        source = source.bookSourceUrl,
        search = source.searchUrl,
        keyword = keyword or "",
        page = options.page or 1,
        method = spec.method,
        url = spec.url,
        url_no_query = spec.url_no_query,
        body = spec.body,
        fields = spec.fields,
        headers = spec.headers,
        rule = source.ruleSearch,
    })
end

local function cacheInstance(options)
    if options.cache == false then
        return nil
    end
    return options.cache or Cache:new()
end

local function cachedResult(cache, key, options)
    if not cache then
        return nil
    end

    local value, meta = cache:get("search", key, options)
    if not value then
        return nil
    end
    value.cached = true
    value.cache = meta
    value.debug = value.debug or {}
    table.insert(value.debug, 1, {
        event = "cache_hit",
        data = {
            kind = "search",
            key = key,
            stored_at = meta.stored_at,
        },
    })
    return value
end

function Search:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function Search:search(source, keyword, options)
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
    if source.enabled == false then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source is disabled"),
        }
    end
    if isBlank(source.searchUrl) then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "searchUrl is required"),
        }
    end
    if type(source.ruleSearch) ~= "table" then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "ruleSearch is required"),
        }
    end

    local spec = Url.parse(source.searchUrl, {
        base_url = source.bookSourceUrl,
        headers = source.header,
        key = keyword or "",
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

    local cache = cacheInstance(options)
    local key = cacheKey(source, spec, keyword, options)
    local cached = cachedResult(cache, key, options)
    if cached then
        return cached
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

    local parsed = BookList.parse(source, source.ruleSearch, "ruleSearch",
        response)
    for index = 1, #parsed.debug do
        table.insert(debug, parsed.debug[index])
    end
    for index = 1, #parsed.unsupported do
        table.insert(unsupported, parsed.unsupported[index])
    end
    parsed.debug = debug
    parsed.unsupported = unsupported
    parsed.response = responseSummary(response)
    if parsed.ok and parsed.books and #parsed.books > 0 and cache then
        cache:set("search", key, parsed, options)
    end
    return parsed
end

function Search.run(source, keyword, options)
    return Search:new(options):search(source, keyword, options)
end

return Search
