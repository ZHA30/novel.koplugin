local rapidjson = require("rapidjson")

local Split = {}

local modes = {
    default = "default",
    json = "json",
    xpath = "xpath",
    js = "js",
    regex = "regex",
    literal = "literal",
}

Split.modes = modes

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function startsWith(value, prefix)
    return value:sub(1, #prefix):lower() == prefix:lower()
end

local function decodePutMap(value)
    local ok, decoded = pcall(rapidjson.decode, value)
    if ok and type(decoded) == "table" then
        local map = {}
        for key, item in pairs(decoded) do
            if item ~= rapidjson.null then
                map[tostring(key)] = tostring(item)
            end
        end
        return map
    end
    return {}
end

local function mergeMap(target, source)
    for key, value in pairs(source) do
        target[key] = value
    end
end

local function findClosing(value, start_index, open_char, close_char)
    local depth = 0
    local in_single_quote = false
    local in_double_quote = false
    local escaped = false

    for index = start_index, #value do
        local char = value:sub(index, index)
        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == "'" and not in_double_quote then
            in_single_quote = not in_single_quote
        elseif char == '"' and not in_single_quote then
            in_double_quote = not in_double_quote
        elseif not in_single_quote and not in_double_quote then
            if char == open_char then
                depth = depth + 1
            elseif char == close_char then
                depth = depth - 1
                if depth == 0 then
                    return index
                end
            end
        end
    end
end

local function isDelimiterAt(value, index, delimiters)
    for delimiter_index = 1, #delimiters do
        local delimiter = delimiters[delimiter_index]
        if delimiter ~= "" and value:sub(index, index + #delimiter - 1) == delimiter then
            return delimiter
        end
    end
end

function Split.splitTopLevel(value, delimiters, options)
    options = options or {}
    value = value or ""
    if type(delimiters) == "string" then
        delimiters = { delimiters }
    end

    local parts = {}
    local delimiter_used = nil
    local start_index = 1
    local index = 1
    local in_single_quote = false
    local in_double_quote = false
    local escaped = false
    local round_depth, square_depth, curly_depth = 0, 0, 0

    while index <= #value do
        local char = value:sub(index, index)

        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == "'" and not in_double_quote then
            in_single_quote = not in_single_quote
        elseif char == '"' and not in_single_quote then
            in_double_quote = not in_double_quote
        elseif not in_single_quote and not in_double_quote then
            if char == "(" then
                round_depth = round_depth + 1
            elseif char == ")" and round_depth > 0 then
                round_depth = round_depth - 1
            elseif char == "[" then
                square_depth = square_depth + 1
            elseif char == "]" and square_depth > 0 then
                square_depth = square_depth - 1
            elseif char == "{" then
                curly_depth = curly_depth + 1
            elseif char == "}" and curly_depth > 0 then
                curly_depth = curly_depth - 1
            elseif round_depth == 0 and square_depth == 0 and curly_depth == 0 then
                local delimiter = isDelimiterAt(value, index, delimiters)
                if delimiter and (not delimiter_used or delimiter == delimiter_used) then
                    delimiter_used = delimiter
                    table.insert(parts, value:sub(start_index, index - 1))
                    index = index + #delimiter
                    start_index = index
                    goto continue
                end
            end
        end

        index = index + 1
        ::continue::
    end

    table.insert(parts, value:sub(start_index))
    if options.trim ~= false then
        for part_index = 1, #parts do
            parts[part_index] = trim(parts[part_index])
        end
    end

    return parts, delimiter_used
end

function Split.splitOperators(value)
    return Split.splitTopLevel(value, { "&&", "||", "%%" })
end

local function splitPutRule(rule)
    local put_map = {}
    local output = {}
    local index = 1

    while index <= #rule do
        local start_at, end_at = rule:find("@put:%{", index)
        if not start_at then
            table.insert(output, rule:sub(index))
            break
        end

        table.insert(output, rule:sub(index, start_at - 1))
        local closing = findClosing(rule, end_at, "{", "}")
        if closing then
            local json = rule:sub(end_at, closing)
            mergeMap(put_map, decodePutMap(json))
            index = closing + 1
        else
            table.insert(output, rule:sub(start_at, end_at))
            index = end_at + 1
        end
    end

    return table.concat(output), put_map
end

local function detectMode(rule, options)
    options = options or {}
    if options.regex then
        return modes.regex, rule
    end
    if startsWith(rule, "@CSS:") then
        return modes.default, rule
    end
    if startsWith(rule, "@@") then
        return modes.default, rule:sub(3)
    end
    if startsWith(rule, "@XPath:") then
        return modes.xpath, rule:sub(8)
    end
    if startsWith(rule, "@Json:") then
        return modes.json, rule:sub(7)
    end
    if rule:match("^%$[%.%[]") then
        return modes.json, rule
    end
    if options.content_is_json and (rule:sub(1, 1) ~= "/" or rule:sub(1, 2) == "//") then
        return modes.json, rule
    end
    if rule:sub(1, 1) == "/" then
        return modes.xpath, rule
    end
    return modes.default, rule
end

local function splitReplacement(rule)
    local parts = Split.splitTopLevel(rule, "##", { trim = false })
    local replace_regex = parts[2] or ""
    local replacement = parts[3] or ""
    local replace_first = #parts > 3
    return trim(parts[1] or ""), replace_regex, replacement, replace_first
end

local function collectDynamicParts(rule)
    local parts = {}
    local index = 1

    while index <= #rule do
        local get_start = rule:find("@get:%{", index)
        local js_start = rule:find("{{", index, true)
        local next_start, kind
        if get_start and (not js_start or get_start < js_start) then
            next_start, kind = get_start, "get"
        elseif js_start then
            next_start, kind = js_start, "js"
        else
            break
        end

        if next_start > index then
            table.insert(parts, {
                kind = "literal",
                value = rule:sub(index, next_start - 1),
            })
        end

        if kind == "get" then
            local open_end = next_start + 5
            local closing = findClosing(rule, open_end, "{", "}")
            if closing then
                table.insert(parts, {
                    kind = "get",
                    value = rule:sub(open_end + 1, closing - 1),
                })
                index = closing + 1
            else
                table.insert(parts, {
                    kind = "literal",
                    value = rule:sub(next_start, open_end),
                })
                index = open_end + 1
            end
        else
            local closing = rule:find("}}", next_start + 2, true)
            if closing then
                table.insert(parts, {
                    kind = "js",
                    value = rule:sub(next_start + 2, closing - 1),
                })
                index = closing + 2
            else
                table.insert(parts, {
                    kind = "literal",
                    value = rule:sub(next_start),
                })
                index = #rule + 1
            end
        end
    end

    if index <= #rule then
        table.insert(parts, {
            kind = "literal",
            value = rule:sub(index),
        })
    end

    return parts
end

function Split.parseSourceRule(rule, options)
    options = options or {}
    local raw = trim(rule)
    local mode, normalized_rule = detectMode(raw, options)
    local put_map
    normalized_rule, put_map = splitPutRule(normalized_rule)

    local result = {
        raw = raw,
        mode = mode,
        rule = normalized_rule,
        put_map = put_map,
        replace_regex = "",
        replacement = "",
        replace_first = false,
        dynamic_parts = {},
        unsupported = {},
    }

    if mode ~= modes.js then
        result.rule, result.replace_regex, result.replacement, result.replace_first =
            splitReplacement(result.rule)
        result.dynamic_parts = collectDynamicParts(result.rule)
        for part_index = 1, #result.dynamic_parts do
            local part = result.dynamic_parts[part_index]
            if part.kind == "js" then
                table.insert(result.unsupported, {
                    kind = "js",
                    snippet = "{{" .. part.value .. "}}",
                })
            end
        end
    end

    if result.mode ~= modes.js and result.mode ~= modes.regex then
        for capture in result.rule:gmatch("%$%d%d?") do
            result.mode = modes.regex
            table.insert(result.unsupported, {
                kind = "regex_capture",
                snippet = capture,
            })
        end
    end

    return result
end

local function appendRule(result, rule, options)
    rule = trim(rule)
    if rule ~= "" then
        table.insert(result, Split.parseSourceRule(rule, options))
    end
end

function Split.splitSourceRules(rule, options)
    options = options or {}
    if not rule or rule == "" then
        return {}
    end

    local result = {}
    local default_options = {
        regex = options.regex,
        content_is_json = options.content_is_json,
    }
    local start_index = 1
    local search_index = 1

    if options.all_in_one and rule:sub(1, 1) == ":" then
        default_options.regex = true
        start_index = 2
        search_index = 2
    end

    while search_index <= #rule do
        local tag_start, tag_end = rule:lower():find("<js>", search_index, true)
        local inline_start = rule:lower():find("@js:", search_index, true)

        if inline_start and (not tag_start or inline_start < tag_start) then
            appendRule(result, rule:sub(start_index, inline_start - 1), default_options)
            table.insert(result, {
                raw = rule:sub(inline_start),
                mode = modes.js,
                rule = rule:sub(inline_start + 4),
                put_map = {},
                replace_regex = "",
                replacement = "",
                replace_first = false,
                dynamic_parts = {},
                unsupported = {
                    {
                        kind = "js",
                        snippet = rule:sub(inline_start, inline_start + 119),
                    },
                },
            })
            return result
        elseif tag_start then
            appendRule(result, rule:sub(start_index, tag_start - 1), default_options)
            local close_start, close_end = rule:lower():find("</js>", tag_end + 1, true)
            if close_start then
                table.insert(result, {
                    raw = rule:sub(tag_start, close_end),
                    mode = modes.js,
                    rule = rule:sub(tag_end + 1, close_start - 1),
                    put_map = {},
                    replace_regex = "",
                    replacement = "",
                    replace_first = false,
                    dynamic_parts = {},
                    unsupported = {
                        {
                            kind = "js",
                            snippet = rule:sub(tag_start, math.min(close_end, tag_start + 119)),
                        },
                    },
                })
                search_index = close_end + 1
                start_index = search_index
            else
                appendRule(result, rule:sub(tag_start), default_options)
                return result
            end
        else
            break
        end
    end

    appendRule(result, rule:sub(start_index), default_options)
    return result
end

return Split
