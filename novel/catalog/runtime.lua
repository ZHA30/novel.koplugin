local Capability = require("novel.source.capability")
local Url = require("novel.net.url")

local Runtime = {}

function Runtime.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function Runtime.isBlank(value)
    return value == nil or Runtime.trim(value) == ""
end

function Runtime.sourceName(source)
    return Capability.title(source)
end

function Runtime.sourceKey(source)
    return Capability.key(source)
end

function Runtime.addDebug(debug, event, data)
    table.insert(debug, {
        event = event,
        data = data,
    })
end

function Runtime.error(kind, message, data)
    return {
        kind = kind,
        message = message,
        data = data,
    }
end

function Runtime.responseSummary(response)
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

function Runtime.copyUnsupported(target, source, field, items, start_index)
    for index = start_index or 1, #(items or {}) do
        local item = items[index]
        table.insert(target, {
            source = Runtime.sourceName(source),
            field = field or item.field or "rule",
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        })
    end
end

function Runtime.copyUrlUnsupported(target, source, items, field)
    for index = 1, #(items or {}) do
        local item = items[index]
        table.insert(target, {
            source = Runtime.sourceName(source),
            field = item.field == "url" and (field or item.field) or item.field,
            kind = item.kind or "unknown",
            snippet = tostring(item.snippet or ""):sub(1, 120),
        })
    end
end

function Runtime.addUnsupported(target, source, field, kind, snippet)
    table.insert(target, {
        source = Runtime.sourceName(source),
        field = field,
        kind = kind,
        snippet = tostring(snippet or ""):sub(1, 120),
    })
end

function Runtime.requestSpec(source, rule_url, options, context)
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
        or (tonumber(source.respondTime) and tonumber(source.respondTime) / 1000)
    spec.max_redirects = options.max_redirects or spec.max_redirects
    return spec
end

function Runtime.execute(service, source, spec)
    local token, wait_ms = service.throttle:acquire(source, source.concurrentRate)
    if not token then
        return nil, Runtime.error("throttle", "source request is rate limited", {
            wait_ms = wait_ms,
        })
    end

    local ok, response = pcall(function()
        return service.request.execute(spec)
    end)
    service.throttle:release(token)

    if not ok then
        return nil, Runtime.error("request", tostring(response))
    end
    if not response.ok then
        return nil, response.error or Runtime.error("request", "request failed"),
            response
    end
    return response
end

return Runtime
