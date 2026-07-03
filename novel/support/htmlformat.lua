local util = require("util")
local Entities = require("novel.support.entities")

local HtmlFormat = {}
local MAX_DECODE_PASSES = 4

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function isAlphaNum(char)
    return char ~= "" and char:match("^[%w]$") ~= nil
end

local function isHex(char)
    return char ~= "" and char:match("^[%x]$") ~= nil
end

local function isDigit(char)
    return char ~= "" and char:match("^%d$") ~= nil
end

local function codepointToUtf8(value)
    local codepoint = tonumber(value)
    if not codepoint then
        return nil
    end
    return util.unicodeCodepointToUtf8(codepoint)
end

local function readNumericEntity(value, amp_index, length)
    if value:sub(amp_index + 1, amp_index + 1) ~= "#" then
        return nil
    end

    local index = amp_index + 2
    local radix, isValidChar = 10, isDigit
    local prefix = value:sub(index, index)
    if prefix == "x" or prefix == "X" then
        radix, isValidChar = 16, isHex
        index = index + 1
    end

    local first_digit = index
    while index <= length and isValidChar(value:sub(index, index)) do
        index = index + 1
    end
    if index == first_digit then
        return nil
    end

    local has_semicolon = value:sub(index, index) == ";"
    if not has_semicolon and isAlphaNum(value:sub(index, index)) then
        return nil
    end

    local codepoint = tonumber(value:sub(first_digit, index - 1), radix)
    local decoded = codepointToUtf8(codepoint)
    if not decoded then
        return nil
    end
    return decoded, index + (has_semicolon and 1 or 0)
end

local function readNamedEntity(value, amp_index, length)
    local first_char = amp_index + 1
    local index = first_char
    local max_index = math.min(length, first_char + Entities.max_name_length - 1)
    while index <= max_index and isAlphaNum(value:sub(index, index)) do
        index = index + 1
    end
    if index == first_char then
        return nil
    end

    local name = value:sub(first_char, index - 1)
    if value:sub(index, index) == ";" then
        local decoded = Entities[name .. ";"]
        if decoded then
            return decoded, index + 1
        end
    end

    local decoded = Entities[name]
    if decoded then
        return decoded, index
    end
    return nil
end

local function decodeEntitiesOnce(value)
    local length = #value
    local index, changed = 1, false
    local output = {}

    while index <= length do
        local amp_index = value:find("&", index, true)
        if not amp_index then
            table.insert(output, value:sub(index))
            break
        end

        if amp_index > index then
            table.insert(output, value:sub(index, amp_index - 1))
        end

        local decoded, next_index = readNumericEntity(value, amp_index, length)
        if not decoded then
            decoded, next_index = readNamedEntity(value, amp_index, length)
        end

        if decoded then
            table.insert(output, decoded)
            index = next_index
            changed = true
        else
            table.insert(output, "&")
            index = amp_index + 1
        end
    end

    if not changed then
        return value, false
    end
    return table.concat(output), true
end

function HtmlFormat.decodeEntities(value)
    value = tostring(value or "")
    for _ = 1, MAX_DECODE_PASSES do
        local decoded, changed = decodeEntitiesOnce(value)
        value = decoded
        if not changed then
            break
        end
    end
    return value
end

function HtmlFormat.attribute(value)
    return trim(HtmlFormat.decodeEntities(value))
end

function HtmlFormat.text(value)
    value = tostring(value or "")
    value = value:gsub("<!%-%-.-%-%->", "")
    value = value:gsub("<%s*[bB][rR][^>]*>", "\n")
    value = value:gsub("</%s*[pP]%s*>", "\n")
    value = value:gsub("</%s*[dD][iI][vV]%s*>", "\n")
    value = value:gsub("</%s*[lL][iI]%s*>", "\n")
    value = value:gsub("<[^>]+>", "")
    value = HtmlFormat.decodeEntities(value)
    value = value:gsub("\u{00A0}", " ")
    value = value:gsub("[ \t\r\f\v]+", " ")
    value = value:gsub("[ \t]*\n[ \t]*", "\n")
    return trim(value)
end

function HtmlFormat.html(value)
    value = tostring(value or "")
    value = value:gsub("<!%-%-.-%-%->", "")
    value = value:gsub("<%s*[sS][cC][rR][iI][pP][tT][^>]*>.-</%s*[sS][cC][rR][iI][pP][tT]%s*>", "")
    value = value:gsub("<%s*[sS][tT][yY][lL][eE][^>]*>.-</%s*[sS][tT][yY][lL][eE]%s*>", "")
    value = value:gsub("<%s*[nN][oO][sS][cC][rR][iI][pP][tT][^>]*>.-</%s*[nN][oO][sS][cC][rR][iI][pP][tT]%s*>", "")
    return trim(value)
end

return HtmlFormat
