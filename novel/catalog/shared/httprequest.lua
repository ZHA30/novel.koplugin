local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")
local logger = require("logger")
local socket = require("socket")
local socketutil = require("socketutil")
local Charset = require("novel.catalog.shared.charset")
local CookieStore = require("novel.storage.cookiestore")
local Url = require("novel.catalog.shared.url")
local UrlEncode = require("novel.catalog.shared.urlencode")

local HttpRequest = {}

local DEFAULT_BLOCK_TIMEOUT = socketutil.LARGE_BLOCK_TIMEOUT or 10
local DEFAULT_TOTAL_TIMEOUT = socketutil.LARGE_TOTAL_TIMEOUT or 30
local DEFAULT_MAX_REDIRECTS = 5

local function copyHeaders(headers)
    local copy = {}
    if type(headers) ~= "table" then
        return copy
    end
    for key, value in pairs(headers) do
        copy[tostring(key)] = tostring(value)
    end
    return copy
end

local function setHeader(headers, wanted, value)
    local wanted_lower = wanted:lower()
    for key, _ in pairs(headers) do
        if tostring(key):lower() == wanted_lower then
            headers[key] = value
            return
        end
    end
    headers[wanted] = value
end

local function headerValue(headers, wanted)
    if type(headers) ~= "table" then
        return nil
    end
    wanted = wanted:lower()
    for key, value in pairs(headers) do
        if tostring(key):lower() == wanted then
            return value
        end
    end
end

local function hasHeader(headers, wanted)
    return headerValue(headers, wanted) ~= nil
end

local function classifyTransportError(code, status)
    local reason = tostring(status or code or "network error")
    if reason:find("timeout", 1, true) or reason == socketutil.TIMEOUT_CODE
        or reason == socketutil.SINK_TIMEOUT_CODE then
        return "timeout"
    end
    if reason == socketutil.SSL_HANDSHAKE_CODE then
        return "ssl"
    end
    return "network"
end

local function classifyHttpStatus(code)
    if type(code) ~= "number" then
        return "network"
    end
    if code >= 400 then
        return "http"
    end
end

local function detectCharset(headers, body, explicit_charset)
    if explicit_charset and explicit_charset ~= "" then
        return explicit_charset
    end

    local content_type = headerValue(headers, "content-type")
    if content_type then
        local charset = content_type:match("[Cc][Hh][Aa][Rr][Ss][Ee][Tt]%s*=%s*['\"]?([%w._%-]+)")
        if charset and charset ~= "" then
            return charset
        end
    end

    if type(body) == "string" and body ~= "" then
        return body:sub(1, 4096):match("[Cc][Hh][Aa][Rr][Ss][Ee][Tt]%s*=%s*['\"]?([%w._%-]+)")
    end
end

local function isRedirect(code)
    return code == 301 or code == 302 or code == 303 or code == 307 or code == 308
end

local function redirectMethod(method, code)
    if code == 301 or code == 302 or code == 303 then
        return "GET"
    end
    return method
end

local function isStructuredBody(value)
    if type(value) ~= "string" then
        return false
    end
    local stripped = value:match("^%s*(.-)%s*$")
    return stripped:match("^%{") ~= nil
        or stripped:match("^%[") ~= nil
        or stripped:match("^<") ~= nil
end

local function contentTypeCharset(charset)
    charset = tostring(charset or ""):match("^%s*(.-)%s*$")
    if charset == "" then
        return "UTF-8"
    end
    return charset
end

local function bodyContentType(body, charset)
    if type(body) ~= "string" or body == "" then
        return nil
    end
    local stripped = body:match("^%s*(.-)%s*$")
    if stripped:match("^%{") or stripped:match("^%[") then
        return "application/json; charset=UTF-8"
    end
    if stripped:match("^<") then
        return "application/xml; charset=UTF-8"
    end
    return "text/plain; charset=" .. contentTypeCharset(charset)
end

local function mergeCookieHeader(headers, stored_cookie)
    if not stored_cookie or stored_cookie == "" then
        return
    end
    local explicit_cookie = headerValue(headers, "cookie")
    if explicit_cookie == nil then
        setHeader(headers, "Cookie", stored_cookie)
        return
    end
    if explicit_cookie == "" then
        return
    end
    local stored = CookieStore.cookieToMap(stored_cookie)
    local explicit = CookieStore.cookieToMap(explicit_cookie)
    for key, value in pairs(explicit) do
        stored[key] = value
    end
    local merged = CookieStore.mapToCookie(stored)
    if merged and merged ~= "" then
        setHeader(headers, "Cookie", merged)
    end
end

local function hasFields(fields)
    return type(fields) == "table" and next(fields) ~= nil
end

local function requestModule(url)
    if url:match("^https://") then
        return https
    end
    if url:match("^http://") then
        return http
    end
end

local function buildRequest(spec, url, method)
    local body = spec.body
    local headers = copyHeaders(spec.headers)

    if method == "POST" and hasFields(spec.fields) then
        body = UrlEncode.fields(spec.fields, spec.charset)
    elseif method == "POST" and (body == nil or body == "") then
        body = nil
    end
    local body_charset_error
    local structured_body = isStructuredBody(body)
    if body and body ~= "" then
        if not structured_body then
            body, body_charset_error = Charset.fromUTF8(body, spec.charset)
        end
    end

    if not hasHeader(headers, "Accept-Encoding") then
        setHeader(headers, "Accept-Encoding", "identity")
    end
    if not hasHeader(headers, "User-Agent") then
        setHeader(headers, "User-Agent", "KOReader")
    end
    mergeCookieHeader(headers, spec.cookie)
    if body and body ~= "" then
        setHeader(headers, "Content-Length", tostring(#body))
        if not hasHeader(headers, "Content-Type") then
            setHeader(headers, "Content-Type",
                hasFields(spec.fields)
                    and "application/x-www-form-urlencoded"
                    or bodyContentType(body, structured_body and nil or spec.charset)
                    or "application/x-www-form-urlencoded")
        end
    end

    local sink = {}
    local request = {
        url = url,
        method = method,
        headers = headers,
        sink = socketutil.table_sink(sink),
        redirect = false,
    }
    if body and body ~= "" then
        request.source = ltn12.source.string(body)
    end
    return request, sink, body_charset_error
end

local function rawExecute(spec, url, method)
    local transport = requestModule(url)
    if not transport then
        return {
            ok = false,
            url = url,
            status = nil,
            headers = {},
            body = "",
            error = {
                kind = "unsupported_scheme",
                message = "only http and https URLs are supported",
            },
        }
    end

    spec.cookie = CookieStore:new():get(spec.cookie_key or url, url)
    local request, sink, body_charset_error = buildRequest(spec, url, method)
    local log_url = Url.redactForLog(url)
    logger.dbg("NovelSource: request", method, log_url)
    local code, headers, status = socket.skip(1, transport.request(request))
    local body = table.concat(sink)
    local charset = detectCharset(headers, body, spec.charset)
    local charset_error
    body, charset_error = Charset.toUTF8(body, charset)
    local error_kind
    if not headers then
        error_kind = classifyTransportError(code, status)
    else
        error_kind = classifyHttpStatus(code)
    end

    local result = {
        ok = error_kind == nil,
        url = url,
        status = code,
        status_line = status,
        headers = headers or {},
        body = body,
        charset = charset,
        charset_error = charset_error,
        body_charset_error = body_charset_error,
        error = error_kind and {
            kind = error_kind,
            message = tostring(status or code or ""),
        } or nil,
    }
    if result.ok then
        logger.dbg("NovelSource: response", method, log_url, code, #body, charset or "")
    else
        logger.warn("NovelSource: request failed", method, log_url,
            result.error and result.error.kind or "unknown",
            result.error and result.error.message or "")
    end
    return result
end

local function shouldRetry(result)
    if result.ok or not result.error then
        return false
    end
    return result.error.kind == "network" or result.error.kind == "timeout"
        or result.error.kind == "ssl"
end

local function executeWithRetry(spec, url, method)
    local result
    local max_attempts = (spec.retry or 0) + 1
    for attempt = 1, max_attempts do
        result = rawExecute(spec, url, method)
        result.attempts = attempt
        if not shouldRetry(result) then
            return result
        end
    end
    return result
end

local function normalizedSpec(spec)
    spec = spec or {}
    return {
        url = spec.url or "",
        url_no_query = spec.url_no_query or spec.url or "",
        method = tostring(spec.method or "GET"):upper(),
        headers = spec.headers or {},
        body = spec.body,
        fields = spec.fields,
        charset = spec.charset,
        retry = tonumber(spec.retry) or 0,
        timeout = tonumber(spec.timeout),
        total_timeout = tonumber(spec.total_timeout),
        max_redirects = spec.max_redirects,
        cookie_key = spec.cookie_key,
    }
end

function HttpRequest.execute(spec)
    spec = normalizedSpec(spec)
    local current_url = spec.method == "POST"
        and spec.url_no_query
        or UrlEncode.appendQuery(spec.url_no_query, spec.fields, spec.charset)
    local current_method = spec.method
    local max_redirects = spec.max_redirects
    if max_redirects == nil then
        max_redirects = DEFAULT_MAX_REDIRECTS
    end

    local previous_block_timeout = socketutil.block_timeout
    local previous_total_timeout = socketutil.total_timeout
    socketutil:set_timeout(spec.timeout or DEFAULT_BLOCK_TIMEOUT,
        spec.total_timeout or DEFAULT_TOTAL_TIMEOUT)

    local redirects = {}
    local ok, response = pcall(function()
        while true do
            local result = executeWithRetry(spec, current_url, current_method)
            result.request_url = spec.url
            result.redirects = redirects
            result.final_url = current_url
            CookieStore:new():mergeResponse(spec.cookie_key or current_url,
                current_url, result.headers)

            local location = headerValue(result.headers, "location")
            if result.status and isRedirect(result.status) and location and location ~= "" then
                if #redirects >= max_redirects then
                    result.ok = false
                    result.error = {
                        kind = "redirect",
                        message = "too many redirects",
                    }
                    return result
                end
                local next_url = Url.absolute(current_url, location)
                table.insert(redirects, {
                    status = result.status,
                    url = current_url,
                    location = next_url,
                })
                logger.dbg("NovelSource: redirect", result.status,
                    Url.redactForLog(current_url), Url.redactForLog(next_url))
                current_url = next_url
                current_method = redirectMethod(current_method, result.status)
                if current_method == "GET" then
                    spec.body = nil
                    spec.fields = nil
                end
            else
                return result
            end
        end
    end)

    socketutil:set_timeout(previous_block_timeout, previous_total_timeout)

    if ok then
        return response
    end
    return {
        ok = false,
        url = current_url,
        request_url = spec.url,
        final_url = current_url,
        status = nil,
        headers = {},
        body = "",
        redirects = redirects,
        error = {
            kind = "exception",
            message = tostring(response),
        },
    }
end

return HttpRequest
