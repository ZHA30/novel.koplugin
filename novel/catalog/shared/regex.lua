local Regex = {}

local unsupported_tokens = {
    "%(%?[:=!<]",
    "|",
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
    return {
        pattern = pattern,
        lua_pattern = Regex.toLuaPattern(pattern),
        supported = #unsupported == 0,
        unsupported = unsupported,
    }
end

local function matchGroups(content, lua_pattern)
    local results = {}
    local start_index = 1
    while start_index <= #content + 1 do
        local captures = { content:find(lua_pattern, start_index) }
        local start_pos = captures[1]
        local end_pos = captures[2]
        if not start_pos then
            break
        end
        local groups = {
            content:sub(start_pos, end_pos),
        }
        for capture_index = 3, #captures do
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
        local matches = matchGroups(current, analysis.lua_pattern)
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
