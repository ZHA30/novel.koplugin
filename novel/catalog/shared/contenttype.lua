local HtmlFormat = require("novel.catalog.shared.format")

local ContentType = {
    text = "text",
    html = "html",
}

local function hasHtmlGetter(rule, getter)
    local pattern = "@%s*" .. getter .. "%s*"
    return rule:match(pattern .. "$") ~= nil
        or rule:match(pattern .. "##") ~= nil
        or rule:match(pattern .. "&&") ~= nil
        or rule:match(pattern .. "%|%|") ~= nil
        or rule:match(pattern .. "%%%%") ~= nil
end

function ContentType.normalizeType(content_type)
    return content_type == ContentType.html and ContentType.html
        or ContentType.text
end

function ContentType.typeForRule(rule)
    rule = tostring(rule or ""):lower()
    if hasHtmlGetter(rule, "html")
        or hasHtmlGetter(rule, "innerhtml")
        or hasHtmlGetter(rule, "outerhtml") then
        return ContentType.html
    end
    return ContentType.text
end

function ContentType.format(value, content_type)
    if ContentType.normalizeType(content_type) == ContentType.html then
        return HtmlFormat.html(value)
    end
    return HtmlFormat.text(value)
end

function ContentType.join(parts, content_type)
    return table.concat(parts,
        ContentType.normalizeType(content_type) == ContentType.html and "\n"
            or "\n\n")
end

function ContentType.isCurrent(expected_type, actual_type)
    expected_type = ContentType.normalizeType(expected_type)
    if expected_type == ContentType.text then
        return actual_type == nil or actual_type == ContentType.text
    end
    return actual_type == expected_type
end

return ContentType
