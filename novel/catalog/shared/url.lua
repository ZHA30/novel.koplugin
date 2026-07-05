local rapidjson = require("rapidjson")

local socket_url_ok, socket_url = pcall(require, "socket.url")

local Url = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function decodeJSON(value)
    if type(value) ~= "string" or value == "" then
        return nil
    end
    local ok, decoded = pcall(rapidjson.decode, value)
    if ok and type(decoded) == "table" then
        return decoded
    end
end

local function encodeJSON(value)
    local ok, encoded = pcall(rapidjson.encode, value)
    if ok then
        return encoded
    end
    return tostring(value)
end

local function splitUrlOptions(rule_url)
    if rule_url:match("^%a[%w+.-]*:") and not rule_url:match("^https?://") then
        return rule_url, nil
    end
    local option_start, json_start = rule_url:find("%s*,%s*%{")
    if not option_start then
        return rule_url, nil
    end
    return trim(rule_url:sub(1, option_start - 1)), rule_url:sub(json_start)
end

local function addUnsupported(result, field, kind, snippet)
    table.insert(result.unsupported, {
        field = field,
        kind = kind,
        snippet = tostring(snippet or ""):sub(1, 120),
    })
end

local function addError(result, field, message)
    table.insert(result.errors, {
        field = field,
        error = message,
    })
end

local function hasJsRule(value)
    local lowered = value:lower()
    return lowered:find("@js", 1, true) or lowered:find("<js", 1, true)
end

local function pageValue(expression, page)
    if not page then
        return nil
    end
    expression = trim(expression)
    if expression == "page" then
        return tostring(page)
    end
    local offset = expression:match("^page%s*%+%s*(%d+)$")
    if offset then
        return tostring(page + tonumber(offset))
    end
    offset = expression:match("^page%s*%-%s*(%d+)$")
    if offset then
        return tostring(page - tonumber(offset))
    end
end

local function replaceTemplates(result, value, context)
    return (value:gsub("{{(.-)}}", function(expression)
        local normalized = trim(expression)
        if normalized == "key" then
            return context.key or ""
        end
        local page_replacement = pageValue(normalized, context.page)
        if page_replacement ~= nil then
            return page_replacement
        end
        addUnsupported(result, "url", "js", "{{" .. expression .. "}}")
        return ""
    end))
end

local function replacePageChoices(value, page)
    if not page then
        return value
    end
    return (value:gsub("<(.-)>", function(expression)
        if expression:lower():match("^%s*/?js") then
            return "<" .. expression .. ">"
        end
        local choices = {}
        for choice in (expression .. ","):gmatch("(.-),") do
            table.insert(choices, trim(choice))
        end
        if #choices == 0 then
            return ""
        end
        return choices[page] or choices[#choices]
    end))
end

local function stripOptions(value)
    local url = splitUrlOptions(value or "")
    return url
end

function Url.absolute(base_url, relative_path)
    if not base_url or base_url == "" then
        return relative_path or ""
    end
    if not relative_path or relative_path == "" then
        return stripOptions(base_url)
    end
    if relative_path:match("^%a[%w+.-]*:") then
        return relative_path
    end
    local clean_base = stripOptions(base_url)
    if socket_url_ok and socket_url then
        local ok, absolute = pcall(socket_url.absolute, clean_base, relative_path)
        if ok and absolute then
            return absolute
        end
        local parsed = socket_url.parse(clean_base)
        if parsed then
            ok, absolute = pcall(socket_url.absolute, parsed, relative_path)
            if ok and absolute then
                return absolute
            end
        end
    end
    if relative_path:sub(1, 1) == "/" then
        local origin = clean_base:match("^(https?://[^/]+)")
        if origin then
            return origin .. relative_path
        end
    end
    return relative_path
end

local function baseFromUrl(value)
    return value and value:match("^(https?://[^/]+)") or nil
end

local function boolValue(value)
    if value == nil or value == "" or value == false or value == "false" then
        return false
    end
    return true
end

local function mergeHeaders(target, headers)
    if type(headers) == "string" then
        headers = decodeJSON(headers)
    end
    if type(headers) ~= "table" then
        return
    end
    for key, value in pairs(headers) do
        if value ~= rapidjson.null then
            target[tostring(key)] = tostring(value)
        end
    end
end

local function optionBody(value)
    if value == nil or value == rapidjson.null or value == "" then
        return nil
    end
    if type(value) == "table" then
        return encodeJSON(value)
    end
    return tostring(value)
end

local function splitFields(fields_text)
    local fields = {}
    if not fields_text or fields_text == "" then
        return fields
    end
    for field in (fields_text .. "&"):gmatch("(.-)&") do
        if field ~= "" then
            local key, value = field:match("^([^=]*)=(.*)$")
            if key then
                fields[key] = value
            else
                fields[field] = ""
            end
        end
    end
    return fields
end

local function isStructuredBody(value)
    if not value then
        return false
    end
    local stripped = trim(value)
    return stripped:match("^%{") or stripped:match("^%[") or stripped:match("^<")
end

local function analyzeFields(result)
    result.url_no_query = result.url
    if result.method == "GET" then
        local query_start = result.url:find("?", 1, true)
        if query_start then
            result.query = result.url:sub(query_start + 1)
            result.url_no_query = result.url:sub(1, query_start - 1)
            result.fields = splitFields(result.query)
        end
    elseif result.body and not result.headers["Content-Type"] and not isStructuredBody(result.body) then
        result.fields = splitFields(result.body)
    end
end

local function applyOptions(result, option_json)
    if not option_json then
        return
    end
    local option = decodeJSON(option_json)
    if not option then
        addError(result, "url.options", "invalid JSON options")
        return
    end

    if option.method and tostring(option.method):upper() == "POST" then
        result.method = "POST"
    end
    if option.headers ~= nil then
        mergeHeaders(result.headers, option.headers)
    end
    result.body = optionBody(option.body)
    result.charset = option.charset ~= rapidjson.null and option.charset or nil
    result.type = option.type ~= rapidjson.null and option.type or nil
    result.retry = tonumber(option.retry) or 0
    result.web_view = boolValue(option.webView)
    result.web_js = option.webJs ~= rapidjson.null and option.webJs or nil
    result.js = option.js ~= rapidjson.null and option.js or nil

    if result.web_view then
        addUnsupported(result, "url.options.webView", "webview", tostring(option.webView))
    end
    if result.web_js and result.web_js ~= "" then
        addUnsupported(result, "url.options.webJs", "js", result.web_js)
    end
    if result.js and result.js ~= "" then
        addUnsupported(result, "url.options.js", "js", result.js)
    end
end

function Url.parse(rule_url, options)
    options = options or {}
    local result = {
        rule_url = rule_url or "",
        url = "",
        url_no_query = "",
        base_url = options.base_url or "",
        method = "GET",
        headers = {},
        body = nil,
        charset = nil,
        type = nil,
        retry = 0,
        fields = {},
        query = nil,
        web_view = false,
        web_js = nil,
        js = nil,
        unsupported = {},
        errors = {},
    }

    mergeHeaders(result.headers, options.headers)

    local analyzed_url = result.rule_url
    if hasJsRule(analyzed_url) then
        addUnsupported(result, "url", "js", analyzed_url)
    end
    analyzed_url = replaceTemplates(result, analyzed_url, {
        key = options.key,
        page = options.page,
    })
    analyzed_url = replacePageChoices(analyzed_url, options.page)

    local url_without_options, option_json = splitUrlOptions(analyzed_url)
    result.rule_url = analyzed_url
    result.url = Url.absolute(result.base_url, url_without_options)
    result.base_url = baseFromUrl(result.url) or result.base_url

    applyOptions(result, option_json)
    analyzeFields(result)

    return result
end

return Url
