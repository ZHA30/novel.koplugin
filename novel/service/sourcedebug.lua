local Search = require("novel.service.search")

local SourceDebug = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function sourceName(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source and source.bookSourceUrl or ""
end

local function sourceUrl(source)
    return source and source.bookSourceUrl or ""
end

local function compactError(error)
    if type(error) ~= "table" then
        return nil
    end
    return {
        kind = error.kind or "unknown",
        message = error.message or tostring(error.kind or ""),
        data = error.data,
    }
end

local function statusFromResult(result)
    if not result or not result.ok then
        return "failed"
    end
    if not result.books or #result.books == 0 then
        return "empty"
    end
    return "ok"
end

local function runSearch(search, source, keyword, options)
    local debug_source = clone(source or {})
    if options.allow_disabled ~= false then
        debug_source.enabled = true
    end
    return search.run(debug_source, keyword, {
        page = options.page or 1,
        timeout = options.timeout,
        total_timeout = options.total_timeout,
        max_redirects = options.max_redirects,
    })
end

function SourceDebug.run(source, keyword, options)
    options = options or {}
    keyword = trim(keyword)
    if keyword == "" then
        return {
            ok = false,
            error = {
                kind = "input",
                message = "keyword is required",
            },
            books = {},
            debug = {},
            unsupported = {},
        }
    end

    local search = options.search or Search
    local ok, result = pcall(runSearch, search, source, keyword, options)
    if not ok then
        result = {
            ok = false,
            books = {},
            debug = {},
            unsupported = {},
            error = {
                kind = "exception",
                message = tostring(result),
            },
        }
    end

    local status = statusFromResult(result)
    return {
        ok = true,
        source = sourceName(source),
        source_url = sourceUrl(source),
        source_enabled = source and source.enabled ~= false,
        keyword = keyword,
        status = status,
        result_ok = result and result.ok == true,
        books = result and result.books or {},
        books_count = result and result.books and #result.books or 0,
        error = compactError(result and result.error),
        response = result and result.response or nil,
        debug = result and result.debug or {},
        unsupported = result and result.unsupported or {},
    }
end

return SourceDebug
