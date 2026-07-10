local SourceInfo = require("novel.catalog.shared.sourceinfo")
local Url = require("novel.catalog.shared.url")
local logger = require("logger")

local RequestSupport = {}

local function logDetail(data)
    if type(data) ~= "table" then
        return ""
    end
    local url = data.url or data.final_url or data.request_url
    if url then
        return Url.redactForLog(url)
    end
    if data.rule then
        return tostring(data.rule):sub(1, 120)
    end
    if data.count ~= nil then
        return tostring(data.count)
    end
    if data.status ~= nil then
        return tostring(data.status)
    end
    return ""
end

local function logSnippet(field, snippet)
    if tostring(field or ""):lower():find("url", 1, true) then
        return Url.redactForLog(snippet)
    end
    return snippet
end

function RequestSupport.addDebug(debug, event, data)
    table.insert(debug, {
        event = event,
        data = data,
    })
    logger.dbg("NovelSource:", event, logDetail(data))
end

function RequestSupport.error(kind, message, data)
    return {
        kind = kind,
        message = message,
        data = data,
    }
end

function RequestSupport.responseSummary(response)
    response = response or {}
    return {
        request_url = response.request_url,
        final_url = response.final_url or response.url,
        status = response.status,
        bytes = #(response.body or ""),
        charset = response.charset,
        charset_error = response.charset_error,
        redirects = response.redirects or {},
    }
end

function RequestSupport.copyUnsupported(target, source, field, items, start_index)
    for index = start_index or 1, #(items or {}) do
        local item = items[index]
        local entry = {
            source = SourceInfo.title(source),
            field = field or item.field or "rule",
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        }
        table.insert(target, entry)
        logger.warn("NovelSource: unsupported", entry.source, entry.field,
            entry.kind, logSnippet(entry.field, entry.snippet))
    end
end

function RequestSupport.copyUrlUnsupported(target, source, items, field)
    for index = 1, #(items or {}) do
        local item = items[index]
        local entry = {
            source = SourceInfo.title(source),
            field = item.field == "url" and (field or item.field) or item.field,
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        }
        table.insert(target, entry)
        logger.warn("NovelSource: unsupported", entry.source, entry.field,
            entry.kind, logSnippet(entry.field, entry.snippet))
    end
end

function RequestSupport.addUnsupported(target, source, field, kind, snippet)
    local entry = {
        source = SourceInfo.title(source),
        field = field,
        kind = kind,
        snippet = tostring(snippet or ""):sub(1, 120),
    }
    table.insert(target, entry)
    logger.warn("NovelSource: unsupported", entry.source, entry.field,
        entry.kind, logSnippet(entry.field, entry.snippet))
end

function RequestSupport.requestSpec(source, rule_url, options, context)
    options = options or {}
    context = context or {}
    source = source or {}

    local spec = Url.parse(rule_url, {
        base_url = context.base_url or source.bookSourceUrl,
        headers = context.headers or source.header,
        key = context.key,
        page = context.page or options.page,
    })
    spec.timeout = options.timeout or spec.timeout
    spec.total_timeout = options.total_timeout or spec.total_timeout
    spec.max_redirects = options.max_redirects or spec.max_redirects
    spec.cookie_key = source.bookSourceUrl or spec.base_url or spec.url
    return spec
end

function RequestSupport.execute(service, source, spec)
    local token, wait_ms = service.throttle:acquire(source, source.concurrentRate)
    if not token then
        return nil, RequestSupport.error("throttle",
            "source request is rate limited", {
                wait_ms = wait_ms,
            })
    end

    local ok, response = pcall(function()
        return service.request.execute(spec)
    end)
    service.throttle:release(token)

    if not ok then
        logger.warn("NovelSource: request exception", SourceInfo.title(source),
            tostring(response))
        return nil, RequestSupport.error("request", tostring(response))
    end
    if not response.ok then
        logger.warn("NovelSource: request error", SourceInfo.title(source),
            response.error and response.error.kind or "request",
            response.error and response.error.message or "")
        return nil, response.error
            or RequestSupport.error("request", "request failed"), response
    end
    return response
end

return RequestSupport
