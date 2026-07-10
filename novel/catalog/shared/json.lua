local rapidjson = require("rapidjson")
local Split = require("novel.catalog.shared.split")

local JsonRule = {}
JsonRule.__index = JsonRule

local function isArray(value)
    if type(value) ~= "table" then
        return false
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function toString(value)
    if value == nil or value == rapidjson.null then
        return nil
    end
    if type(value) == "table" then
        local ok, encoded = pcall(rapidjson.encode, value)
        if ok then
            return encoded
        end
    end
    return tostring(value)
end

local function addValue(values, value)
    if value ~= nil and value ~= rapidjson.null then
        table.insert(values, value)
    end
end

local function appendAll(target, values)
    for index = 1, #values do
        table.insert(target, values[index])
    end
end

local function parseContent(content)
    if type(content) == "table" then
        return content
    end
    if type(content) ~= "string" or content == "" then
        return nil
    end
    local ok, decoded = pcall(rapidjson.decode, content)
    if ok then
        return decoded
    end
end

function JsonRule:new(content)
    return setmetatable({
        root = parseContent(content),
    }, self)
end

local function readBracket(value, index)
    local start_index = index
    local in_quote = nil
    local escaped = false
    while index <= #value do
        local char = value:sub(index, index)
        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif in_quote then
            if char == in_quote then
                in_quote = nil
            end
        elseif char == "'" or char == '"' then
            in_quote = char
        elseif char == "]" then
            return value:sub(start_index, index - 1), index + 1
        end
        index = index + 1
    end
end

local function splitTopLevel(value, delimiter)
    local parts = {}
    local start_index = 1
    local index = 1
    local in_quote = nil
    local escaped = false
    while index <= #value do
        local char = value:sub(index, index)
        if escaped then
            escaped = false
        elseif char == "\\" then
            escaped = true
        elseif in_quote then
            if char == in_quote then
                in_quote = nil
            end
        elseif char == "'" or char == '"' then
            in_quote = char
        elseif char == delimiter then
            table.insert(parts, value:sub(start_index, index - 1):match("^%s*(.-)%s*$"))
            start_index = index + 1
        end
        index = index + 1
    end
    table.insert(parts, value:sub(start_index):match("^%s*(.-)%s*$"))
    return parts
end

local function unquote(value)
    value = value:match("^%s*(.-)%s*$")
    local quote = value:sub(1, 1)
    if (quote == "'" or quote == '"') and value:sub(-1) == quote then
        return value:sub(2, -2)
    end
    return value
end

local function tokenize(path)
    path = tostring(path or "")
    if path == "" then
        return {}
    end

    local tokens = {}
    local index = 1
    if path:sub(1, 1) == "$" then
        index = 2
    end

    while index <= #path do
        local char = path:sub(index, index)
        if char == "." then
            if path:sub(index + 1, index + 1) == "." then
                local name
                name, index = path:match("^%.%.([%w_%-]+)()", index)
                if not name then
                    return nil, "unsupported recursive JSONPath"
                end
                table.insert(tokens, {
                    type = "recursive",
                    value = name,
                })
            elseif path:sub(index + 1, index + 1) == "*" then
                table.insert(tokens, { type = "wildcard" })
                index = index + 2
            else
                local name
                name, index = path:match("^%.([%w_%-]+)()", index)
                if not name then
                    return nil, "invalid field selector"
                end
                table.insert(tokens, {
                    type = "field",
                    value = name,
                })
            end
        elseif char == "[" then
            local expression
            expression, index = readBracket(path, index + 1)
            if not expression then
                return nil, "unclosed bracket selector"
            end
            expression = expression:match("^%s*(.-)%s*$")
            if (expression:sub(1, 1) == "'" or expression:sub(1, 1) == '"')
                and not expression:find(",", 1, true) then
                table.insert(tokens, {
                    type = "field",
                    value = unquote(expression),
                })
            else
                if expression == "*" then
                    table.insert(tokens, { type = "wildcard" })
                elseif expression:match("^%-?%d+$") then
                    table.insert(tokens, {
                        type = "index",
                        value = tonumber(expression),
                    })
                elseif expression:find(":", 1, true) then
                    local slice_parts = splitTopLevel(expression, ":")
                    if #slice_parts < 2 or #slice_parts > 3 then
                        return nil, "unsupported slice selector"
                    end
                    local start_text = slice_parts[1]
                    local end_text = slice_parts[2]
                    local step_text = slice_parts[3]
                    if (start_text ~= "" and not start_text:match("^%-?%d+$"))
                        or (end_text ~= "" and not end_text:match("^%-?%d+$"))
                        or (step_text ~= nil and step_text ~= "" and not step_text:match("^%-?%d+$")) then
                        return nil, "unsupported slice selector"
                    end
                    if step_text ~= nil and tonumber(step_text) <= 0 then
                        return nil, "unsupported slice selector"
                    end
                    table.insert(tokens, {
                        type = "slice",
                        start_value = tonumber(start_text),
                        end_value = tonumber(end_text),
                        step = tonumber(step_text) or 1,
                    })
                elseif expression:find(",", 1, true) then
                    local selectors = {}
                    for _, item in ipairs(splitTopLevel(expression, ",")) do
                        if item:match("^%-?%d+$") then
                            table.insert(selectors, {
                                type = "index",
                                value = tonumber(item),
                            })
                        else
                            table.insert(selectors, {
                                type = "field",
                                value = unquote(item),
                            })
                        end
                    end
                    table.insert(tokens, {
                        type = "union",
                        selectors = selectors,
                    })
                else
                    return nil, "unsupported bracket selector"
                end
            end
        elseif char:match("%s") then
            index = index + 1
        else
            return nil, "invalid JSONPath token"
        end
    end

    return tokens
end

local function recursiveFind(value, field, output)
    if type(value) ~= "table" then
        return
    end
    for key, item in pairs(value) do
        if key == field then
            addValue(output, item)
        end
        recursiveFind(item, field, output)
    end
end

local function applyToken(values, token)
    local next_values = {}
    for index = 1, #values do
        local value = values[index]
        if type(value) == "table" then
            if token.type == "field" then
                addValue(next_values, value[token.value])
            elseif token.type == "index" then
                local position = token.value
                if position == 0 then
                    position = 1
                elseif position < 0 then
                    position = #value + position + 1
                else
                    position = position + 1
                end
                addValue(next_values, value[position])
            elseif token.type == "wildcard" then
                if isArray(value) then
                    appendAll(next_values, value)
                else
                    for key in pairs(value) do
                        addValue(next_values, value[key])
                    end
                end
            elseif token.type == "slice" then
                if isArray(value) then
                    local step = token.step or 1
                    if step == 0 then
                        step = 1
                    end
                    local length = #value
                    local start_pos = token.start_value or 0
                    local end_pos = token.end_value
                    if start_pos < 0 then
                        start_pos = length + start_pos
                    end
                    if end_pos == nil then
                        end_pos = length
                    elseif end_pos < 0 then
                        end_pos = length + end_pos
                    end
                    start_pos = math.max(0, start_pos) + 1
                    end_pos = math.min(length, end_pos)
                    for item_index = start_pos, end_pos, step do
                        addValue(next_values, value[item_index])
                    end
                end
            elseif token.type == "union" then
                for _, selector in ipairs(token.selectors or {}) do
                    local selected = applyToken({ value }, selector)
                    appendAll(next_values, selected)
                end
            elseif token.type == "recursive" then
                recursiveFind(value, token.value, next_values)
            end
        end
    end
    return next_values
end

function JsonRule:getList(path)
    if not self.root then
        return {}
    end
    path = tostring(path or "")
    if path == "" or path == "$" then
        return { self.root }
    end

    local tokens = tokenize(path)
    if not tokens then
        return {}
    end

    local values = { self.root }
    for token_index = 1, #tokens do
        values = applyToken(values, tokens[token_index])
        if #values == 0 then
            break
        end
    end
    return values
end

local function replaceInner(rule, reader)
    local output = {}
    local index = 1
    local changed = false

    while index <= #rule do
        local start_index = rule:find("{$.", index, true)
        if not start_index then
            table.insert(output, rule:sub(index))
            break
        end
        table.insert(output, rule:sub(index, start_index - 1))
        local end_index = rule:find("}", start_index + 1, true)
        if not end_index then
            table.insert(output, rule:sub(start_index))
            break
        end
        local inner_rule = rule:sub(start_index + 1, end_index - 1)
        local value = reader:getString(inner_rule)
        if value and value ~= "" then
            table.insert(output, value)
            changed = true
        end
        index = end_index + 1
    end

    if changed then
        return table.concat(output)
    end
end

local function combineLists(lists, operator)
    local result = {}
    if operator == "%%" and #lists > 0 then
        for item_index = 1, #lists[1] do
            for list_index = 1, #lists do
                if item_index <= #lists[list_index] then
                    table.insert(result, lists[list_index][item_index])
                end
            end
        end
    else
        for list_index = 1, #lists do
            appendAll(result, lists[list_index])
        end
    end
    return result
end

function JsonRule:getStringList(rule)
    rule = tostring(rule or "")
    if rule == "" then
        return {}
    end

    local rules, operator = Split.splitOperators(rule)
    if #rules > 1 then
        local lists = {}
        for rule_index = 1, #rules do
            local values = self:getStringList(rules[rule_index])
            if #values > 0 then
                table.insert(lists, values)
                if operator == "||" then
                    break
                end
            end
        end
        return combineLists(lists, operator)
    end

    local inner = replaceInner(rule, self)
    if inner then
        return { inner }
    end

    local values = self:getList(rule)
    local strings = {}
    for value_index = 1, #values do
        local value = toString(values[value_index])
        if value then
            table.insert(strings, value)
        end
    end
    return strings
end

function JsonRule:getString(rule)
    local strings = self:getStringList(rule)
    if #strings == 0 then
        return nil
    end
    return table.concat(strings, "\n")
end

function JsonRule:getObject(rule)
    local values = self:getList(rule)
    return values[1]
end

function JsonRule.parse(content)
    return JsonRule:new(content)
end

return JsonRule
