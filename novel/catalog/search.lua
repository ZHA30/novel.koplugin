local BookList = require("novel.catalog.books")
local Cache = require("novel.storage.cache")
local Context = require("novel.catalog.client")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")

local Search = {}
Search.__index = Search

local isBlank = Context.isBlank
local addDebug = Context.addDebug
local addError = Context.error
local copyUrlUnsupported = Context.copyUrlUnsupported
local responseSummary = Context.responseSummary

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

    local spec = Context.requestSpec(source, source.searchUrl, options, {
        key = keyword or "",
        page = options.page or 1,
    })
    copyUrlUnsupported(unsupported, source, spec.unsupported, "searchUrl")

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

    local response, request_err, failed_response = Context.execute(self, source, spec)
    if not response then
        if failed_response then
            addDebug(debug, "response", responseSummary(failed_response))
        end
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = request_err,
            response = failed_response and responseSummary(failed_response) or nil,
        }
    end

    addDebug(debug, "response", responseSummary(response))

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
