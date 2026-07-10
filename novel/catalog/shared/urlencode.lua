local Charset = require("novel.catalog.shared.charset")

local UrlEncode = {}

local function isHexPair(value, index)
    local pair = value:sub(index + 1, index + 2)
    return #pair == 2 and pair:match("^[0-9A-Fa-f][0-9A-Fa-f]$") ~= nil
end

local function encodeByte(byte)
    return string.format("%%%02X", byte)
end

local function encodeString(value)
    value = tostring(value or "")
    local output = {}
    local index = 1
    while index <= #value do
        local byte = value:byte(index)
        local char = value:sub(index, index)
        if char == "%" and isHexPair(value, index) then
            table.insert(output, value:sub(index, index + 2))
            index = index + 3
        elseif byte >= 0x30 and byte <= 0x39
            or byte >= 0x41 and byte <= 0x5A
            or byte >= 0x61 and byte <= 0x7A
            or char == "-" or char == "_" or char == "." or char == "~" then
            table.insert(output, char)
            index = index + 1
        elseif char == " " then
            table.insert(output, "+")
            index = index + 1
        else
            table.insert(output, encodeByte(byte))
            index = index + 1
        end
    end
    return table.concat(output)
end

function UrlEncode.value(value, charset)
    local encoded, err = Charset.fromUTF8(tostring(value or ""), charset)
    return encodeString(encoded or ""), err
end

function UrlEncode.fields(fields, charset)
    if type(fields) ~= "table" then
        return nil
    end

    local parts = {}
    for key, value in pairs(fields) do
        local encoded_key = UrlEncode.value(key, charset)
        local encoded_value = UrlEncode.value(value or "", charset)
        table.insert(parts, encoded_key .. "=" .. encoded_value)
    end
    table.sort(parts)
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "&")
end

function UrlEncode.appendQuery(url, fields, charset)
    local query = UrlEncode.fields(fields, charset)
    if not query or query == "" then
        return url
    end
    local separator = tostring(url or ""):find("?", 1, true) and "&" or "?"
    return tostring(url or "") .. separator .. query
end

return UrlEncode
