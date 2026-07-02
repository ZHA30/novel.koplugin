local util = require("util")

local HtmlFormat = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function HtmlFormat.text(value)
    value = tostring(value or "")
    value = value:gsub("<%s*br%s*/?%s*>", "\n")
    value = value:gsub("</%s*p%s*>", "\n")
    value = value:gsub("</%s*div%s*>", "\n")
    value = value:gsub("</%s*li%s*>", "\n")
    value = value:gsub("<[^>]+>", "")
    value = util.htmlEntitiesToUtf8(value)
    value = value:gsub("\u{00A0}", " ")
    value = value:gsub("[ \t\r\f\v]+", " ")
    value = value:gsub("[ \t]*\n[ \t]*", "\n")
    return trim(value)
end

return HtmlFormat
