local BookList = require("novel.catalog.listing.booklist")
local Cache = require("novel.storage.cache")
local RequestSupport = require("novel.catalog.shared.requestsupport")
local HttpRequest = require("novel.catalog.shared.httprequest")
local Text = require("novel.catalog.shared.text")
local Throttle = require("novel.catalog.shared.throttle")

local SearchService = {}
SearchService.__index = SearchService

local isBlank = Text.isBlank
local addDebug = RequestSupport.addDebug
local addError = RequestSupport.error
local copyUrlUnsupported = RequestSupport.copyUrlUnsupported
local responseSummary = RequestSupport.responseSummary

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
    return Cache.instance(options)
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

function SearchService:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or HttpRequest,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function SearchService:search(source, keyword, options)
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

    local spec = RequestSupport.requestSpec(source, source.searchUrl, options, {
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

    local response, request_err, failed_response = RequestSupport.execute(self, source, spec)
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
        cache:set("search", key, parsed, {
            owner = {
                source = source.bookSourceUrl,
            },
            tags = {
                kind = "search",
                keyword = keyword or "",
            },
            settings = options.settings,
            ttl = options.ttl,
            flush = options.flush,
        })
    end
    return parsed
end

function SearchService.run(source, keyword, options)
    return SearchService:new(options):search(source, keyword, options)
end

return SearchService
