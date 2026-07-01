local HtmlFormat = {}

local entities = {
    nbsp = " ",
    amp = "&",
    lt = "<",
    gt = ">",
    quot = "\"",
    apos = "'",
}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function decodeEntity(entity)
    local numeric = entity:match("^#(%d+)$")
    if numeric then
        local codepoint = tonumber(numeric)
        if codepoint and codepoint >= 32 and codepoint < 128 then
            return string.char(codepoint)
        end
        return ""
    end

    local hex = entity:match("^#[xX]([%da-fA-F]+)$")
    if hex then
        local codepoint = tonumber(hex, 16)
        if codepoint and codepoint >= 32 and codepoint < 128 then
            return string.char(codepoint)
        end
        return ""
    end

    return entities[entity] or "&" .. entity .. ";"
end

function HtmlFormat.text(value)
    value = tostring(value or "")
    value = value:gsub("<%s*br%s*/?%s*>", "\n")
    value = value:gsub("</%s*p%s*>", "\n")
    value = value:gsub("</%s*div%s*>", "\n")
    value = value:gsub("</%s*li%s*>", "\n")
    value = value:gsub("<[^>]+>", "")
    value = value:gsub("&([^;]+);", decodeEntity)
    value = value:gsub("[ \t\r\f\v]+", " ")
    value = value:gsub("[ \t]*\n[ \t]*", "\n")
    return trim(value)
end

return HtmlFormat
