local Regex = {}

local unsupported_tokens = {
    "%(%?[:=!<]",
    "\\b",
    "\\B",
    "\\A",
    "\\Z",
    "\\p",
}

local escape_map = {
    d = "%d",
    D = "%D",
    s = "%s",
    S = "%S",
    w = "%w",
    W = "%W",
    n = "\n",
    r = "\r",
    t = "\t",
    ["\\"] = "\\",
    ["."] = "%.",
    ["-"] = "%-",
    ["+"] = "%+",
    ["*"] = "%*",
    ["?"] = "%?",
    ["("] = "%(",
    [")"] = "%)",
    ["["] = "%[",
    ["]"] = "%]",
    ["^"] = "%^",
    ["$"] = "%$",
}

local function hasUnsupported(pattern)
    local unsupported = {}
    for token_index = 1, #unsupported_tokens do
        local token = unsupported_tokens[token_index]
        if pattern:find(token) then
            table.insert(unsupported, token)
        end
    end
    return unsupported
end

local function translateEscapes(pattern)
    local output = {}
    local index = 1
    while index <= #pattern do
        local char = pattern:sub(index, index)
        if char == "\\" and index < #pattern then
            local next_char = pattern:sub(index + 1, index + 1)
            table.insert(output, escape_map[next_char] or next_char)
            index = index + 2
        else
            table.insert(output, char)
            index = index + 1
        end
    end
    return table.concat(output)
end

local function normalizePatterns(patterns)
    if type(patterns) == "string" then
        return { patterns }
    end
    if type(patterns) == "table" then
        return patterns
    end
    return {}
end

local function pack(...)
    return { n = select("#", ...), ... }
end

local function splitAlternatives(pattern)
    local parts = {}
    local start_index = 1
    local index = 1
    local escaped = false
    local in_class = false
    local depth = 0
    local has_alternative = false

    while index <= #pattern do
        local char = pattern:sub(index, index)
        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == "[" then
            in_class = true
        elseif char == "]" then
            in_class = false
        elseif not in_class then
            if char == "(" then
                depth = depth + 1
            elseif char == ")" and depth > 0 then
                depth = depth - 1
            elseif char == "|" and depth == 0 then
                table.insert(parts, pattern:sub(start_index, index - 1))
                start_index = index + 1
                has_alternative = true
            end
        end
        index = index + 1
    end

    table.insert(parts, pattern:sub(start_index))
    return parts, has_alternative
end

local function hasNestedAlternative(pattern)
    local escaped = false
    local in_class = false
    local depth = 0
    for index = 1, #pattern do
        local char = pattern:sub(index, index)
        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif char == "[" then
            in_class = true
        elseif char == "]" then
            in_class = false
        elseif not in_class then
            if char == "(" then
                depth = depth + 1
            elseif char == ")" and depth > 0 then
                depth = depth - 1
            elseif char == "|" and depth > 0 then
                return true
            end
        end
    end
    return false
end

function Regex.toLuaPattern(pattern)
    pattern = tostring(pattern or "")
    pattern = pattern:gsub("%[\\s\\S%]", "[%z\1-\255]")
    pattern = pattern:gsub("%[\\d%]", "[%d]")
    pattern = pattern:gsub("%[\\w%]", "[%w]")
    pattern = pattern:gsub("%.%*%?", ".-")
    pattern = pattern:gsub("%.%+%?", ".-")
    return translateEscapes(pattern)
end

function Regex.toLuaReplacement(replacement)
    replacement = tostring(replacement or "")
    replacement = replacement:gsub("%$(%d%d?)", "%%%1")
    return replacement
end

function Regex.analyze(pattern)
    pattern = tostring(pattern or "")
    local unsupported = hasUnsupported(pattern)
    if hasNestedAlternative(pattern) then
        table.insert(unsupported, "nested_alternation")
    end
    local alternatives, has_alternative = splitAlternatives(pattern)
    local lua_alternatives
    if has_alternative then
        lua_alternatives = {}
        for index = 1, #alternatives do
            if alternatives[index] == "" then
                table.insert(unsupported, "empty_alternative")
            end
            lua_alternatives[index] = Regex.toLuaPattern(alternatives[index])
        end
    end
    return {
        pattern = pattern,
        lua_pattern = Regex.toLuaPattern(pattern),
        alternatives = has_alternative and alternatives or nil,
        lua_alternatives = lua_alternatives,
        supported = #unsupported == 0,
        unsupported = unsupported,
    }
end

local function matchGroups(content, lua_pattern)
    local results = {}
    local start_index = 1
    while start_index <= #content + 1 do
        local captures = pack(content:find(lua_pattern, start_index))
        local start_pos = captures[1]
        local end_pos = captures[2]
        if not start_pos then
            break
        end
        local groups = {
            content:sub(start_pos, end_pos),
            capture_count = captures.n - 2,
        }
        for capture_index = 3, captures.n do
            table.insert(groups, captures[capture_index] or "")
        end
        table.insert(results, groups)
        if end_pos < start_index then
            start_index = start_index + 1
        else
            start_index = end_pos + 1
        end
    end
    return results
end

local function nextAlternativeMatch(content, lua_patterns, start_index)
    local best
    for pattern_index = 1, #lua_patterns do
        local captures = pack(content:find(lua_patterns[pattern_index], start_index))
        local start_pos = captures[1]
        if start_pos and (not best or start_pos < best.start_pos
            or start_pos == best.start_pos and pattern_index < best.pattern_index) then
            local groups = {
                content:sub(start_pos, captures[2]),
                capture_count = captures.n - 2,
            }
            for capture_index = 3, captures.n do
                table.insert(groups, captures[capture_index] or "")
            end
            best = {
                start_pos = start_pos,
                end_pos = captures[2],
                pattern_index = pattern_index,
                groups = groups,
            }
        end
    end
    return best
end

local function matchAlternativeGroups(content, lua_patterns)
    local results = {}
    local start_index = 1
    while start_index <= #content + 1 do
        local match = nextAlternativeMatch(content, lua_patterns, start_index)
        if not match then
            break
        end
        table.insert(results, match.groups)
        if match.end_pos < start_index then
            start_index = start_index + 1
        else
            start_index = match.end_pos + 1
        end
    end
    return results
end

local function expandReplacement(replacement, groups)
    local output = {}
    local index = 1
    while index <= #replacement do
        local char = replacement:sub(index, index)
        if char ~= "%" then
            table.insert(output, char)
            index = index + 1
        elseif index == #replacement then
            return nil, "invalid use of '%' in replacement string"
        else
            local next_char = replacement:sub(index + 1, index + 1)
            if next_char == "%" then
                table.insert(output, "%")
            elseif next_char:match("%d") then
                local group_index = tonumber(next_char)
                if group_index == 0 then
                    table.insert(output, groups[1] or "")
                elseif group_index == 1 and (groups.capture_count or 0) == 0 then
                    table.insert(output, groups[1] or "")
                elseif group_index <= (groups.capture_count or 0) then
                    table.insert(output, groups[group_index + 1] or "")
                else
                    return nil, "invalid capture index %" .. next_char
                end
            else
                return nil, "invalid use of '%' in replacement string"
            end
            index = index + 2
        end
    end
    return table.concat(output)
end

function Regex.replace(content, pattern, replacement, replace_first)
    content = tostring(content or "")
    local analysis = Regex.analyze(pattern)
    if not analysis.supported then
        return content, 0, {
            kind = "unsupported_regex",
            pattern = analysis.pattern,
            unsupported = analysis.unsupported,
        }
    end
    replacement = Regex.toLuaReplacement(replacement)
    if not analysis.lua_alternatives then
        local ok, value, count
        if replace_first then
            ok, value, count = pcall(string.gsub, content,
                analysis.lua_pattern, replacement, 1)
        else
            ok, value, count = pcall(string.gsub, content,
                analysis.lua_pattern, replacement)
        end
        if ok then
            return value, count
        end
        return content, 0, {
            kind = "unsupported_regex",
            pattern = analysis.pattern,
            unsupported = { tostring(value) },
        }
    end

    local output = {}
    local start_index = 1
    local count = 0
    while start_index <= #content + 1 do
        local match = nextAlternativeMatch(content, analysis.lua_alternatives, start_index)
        if not match then
            break
        end
        table.insert(output, content:sub(start_index, match.start_pos - 1))
        local expanded, expand_err = expandReplacement(replacement, match.groups)
        if not expanded then
            return content, 0, {
                kind = "unsupported_regex",
                pattern = analysis.pattern,
                unsupported = { expand_err },
            }
        end
        table.insert(output, expanded)
        count = count + 1
        if replace_first then
            start_index = match.end_pos + 1
            break
        end
        if match.end_pos < match.start_pos then
            if match.start_pos <= #content then
                table.insert(output, content:sub(match.start_pos, match.start_pos))
            end
            start_index = match.start_pos + 1
        else
            start_index = match.end_pos + 1
        end
    end
    table.insert(output, content:sub(start_index))
    return table.concat(output), count
end

local function concatFirstGroup(matches)
    local parts = {}
    for match_index = 1, #matches do
        table.insert(parts, matches[match_index][1] or "")
    end
    return table.concat(parts)
end

function Regex.getElements(content, patterns)
    content = tostring(content or "")
    patterns = normalizePatterns(patterns)
    if #patterns == 0 then
        return {}
    end

    local current = content
    for pattern_index = 1, #patterns do
        local analysis = Regex.analyze(patterns[pattern_index])
        if not analysis.supported then
            return {}, {
                kind = "unsupported_regex",
                pattern = analysis.pattern,
                unsupported = analysis.unsupported,
            }
        end
        local matches
        if analysis.lua_alternatives then
            matches = matchAlternativeGroups(current, analysis.lua_alternatives)
        else
            matches = matchGroups(current, analysis.lua_pattern)
        end
        if #matches == 0 then
            return {}
        end
        if pattern_index == #patterns then
            return matches
        end
        current = concatFirstGroup(matches)
    end
    return {}
end

function Regex.getElement(content, patterns)
    local matches, err = Regex.getElements(content, patterns)
    if err then
        return nil, err
    end
    return matches[1]
end

function Regex.getStringList(content, patterns, group_index)
    local matches, err = Regex.getElements(content, patterns)
    if err then
        return {}, err
    end

    group_index = group_index or 1
    local result = {}
    for match_index = 1, #matches do
        local value = matches[match_index][group_index]
        if value and value ~= "" then
            table.insert(result, value)
        end
    end
    return result
end

function Regex.getString(content, patterns, group_index)
    local values, err = Regex.getStringList(content, patterns, group_index)
    if err then
        return nil, err
    end
    if #values == 0 then
        return nil
    end
    return table.concat(values, "\n")
end

return Regex
