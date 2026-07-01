local Search = require("novel.service.search")

local SourceCheck = {}

local DEFAULT_TIMEOUT_MS = 5000
local DEFAULT_CONCURRENCY = 5

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function sourceName(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source and source.bookSourceUrl or ""
end

local function isSearchable(source)
    return type(source) == "table"
        and source.enabled ~= false
        and source.searchUrl ~= nil
        and source.searchUrl ~= ""
        and type(source.ruleSearch) == "table"
end

local function milliseconds(value, fallback)
    local number = tonumber(value)
    if not number or number <= 0 then
        return fallback
    end
    return number
end

local function secondsFromMilliseconds(value)
    return math.max(1, milliseconds(value, DEFAULT_TIMEOUT_MS) / 1000)
end

local function clampInteger(value, fallback, minimum, maximum)
    local number = math.floor(tonumber(value) or fallback)
    if number < minimum then
        return minimum
    end
    if number > maximum then
        return maximum
    end
    return number
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

local function errorSummary(result)
    if not result or not result.error then
        return nil
    end
    return {
        kind = result.error.kind or "unknown",
        message = result.error.message or tostring(result.error.kind or ""),
        data = result.error.data,
    }
end

local function checkedSource(source, result)
    local status = statusFromResult(result)
    return {
        source = sourceName(source),
        source_url = source.bookSourceUrl,
        status = status,
        ok = status == "ok",
        books_count = result and result.books and #result.books or 0,
        error = errorSummary(result),
        response = result and result.response or nil,
        unsupported = result and result.unsupported or {},
        debug = result and result.debug or {},
    }
end

local function skippedSource(source, reason)
    return {
        source = sourceName(source),
        source_url = source and source.bookSourceUrl or "",
        status = "skipped",
        ok = false,
        books_count = 0,
        error = {
            kind = "source",
            message = reason,
        },
        response = nil,
        unsupported = {},
        debug = {},
    }
end

local function updateSummary(summary, status)
    if status == "ok" then
        summary.ok_count = summary.ok_count + 1
    elseif status == "empty" then
        summary.empty_count = summary.empty_count + 1
    elseif status == "failed" then
        summary.failed_count = summary.failed_count + 1
    else
        summary.skipped_count = summary.skipped_count + 1
    end
end

function SourceCheck.run(sources, options)
    options = options or {}
    local keyword = trim(options.keyword)
    if keyword == "" then
        return {
            ok = false,
            error = {
                kind = "input",
                message = "keyword is required",
            },
            results = {},
        }
    end

    local timeout_ms = milliseconds(options.timeout_ms, DEFAULT_TIMEOUT_MS)
    local max_concurrency = clampInteger(options.concurrent,
        DEFAULT_CONCURRENCY, 1, 15)
    local timeout_seconds = secondsFromMilliseconds(timeout_ms)
    local max_sources = tonumber(options.max_sources)
    local search = options.search or Search
    local results = {}
    local summary = {
        ok = true,
        keyword = keyword,
        total = #(sources or {}),
        checked = 0,
        ok_count = 0,
        empty_count = 0,
        failed_count = 0,
        skipped_count = 0,
        timeout_ms = timeout_ms,
        max_concurrency = max_concurrency,
        effective_concurrency = 1,
        results = results,
    }

    for source_index = 1, #(sources or {}) do
        if max_sources and summary.checked >= max_sources then
            break
        end

        local source = sources[source_index]
        local item
        if isSearchable(source) then
            local result = search.run(source, keyword, {
                page = 1,
                timeout = timeout_seconds,
                total_timeout = timeout_seconds,
            })
            item = checkedSource(source, result)
            summary.checked = summary.checked + 1
        else
            item = skippedSource(source, "source is not enabled or searchable")
        end
        updateSummary(summary, item.status)
        table.insert(results, item)
    end

    return summary
end

return SourceCheck
