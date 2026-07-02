local Status = {}

local js_patterns = {
    "@js",
    "<js>",
    "{{",
}

local deferred_fields = {
    loginUrl = "js",
    loginUi = "ui",
    loginCheckJs = "js",
}

local rule_fields = {
    ruleExplore = true,
    ruleSearch = true,
    ruleBookInfo = true,
    ruleToc = true,
    ruleContent = true,
}

local function add(status, source, field, kind, snippet)
    table.insert(status, {
        source = source.bookSourceName ~= "" and source.bookSourceName or source.bookSourceUrl,
        field = field,
        kind = kind,
        snippet = snippet,
    })
end

local function containsUnsupportedRule(value)
    if type(value) ~= "string" then
        return nil
    end
    local lowered = value:lower()
    for _, pattern in ipairs(js_patterns) do
        if lowered:find(pattern, 1, true) then
            return pattern
        end
    end
end

local function scanRuleTable(status, source, field, rule)
    if type(rule) ~= "table" then
        return
    end
    for rule_field, value in pairs(rule) do
        local match = containsUnsupportedRule(value)
        if match then
            add(status, source, field .. "." .. rule_field, "js", value:sub(1, 120))
        end
    end
end

function Status.collect(source)
    local status = {}

    for field, kind in pairs(deferred_fields) do
        local value = source[field]
        if value and value ~= "" then
            add(status, source, field, kind, tostring(value):sub(1, 120))
        end
    end

    for field in pairs(rule_fields) do
        scanRuleTable(status, source, field, source[field])
    end

    return status
end

return Status
