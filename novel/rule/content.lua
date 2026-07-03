local HtmlFormat = require("novel.support.htmlformat")

local ContentRule = {
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

function ContentRule.normalizeType(content_type)
    return content_type == ContentRule.html and ContentRule.html
        or ContentRule.text
end

function ContentRule.typeForRule(rule)
    rule = tostring(rule or ""):lower()
    if hasHtmlGetter(rule, "html")
        or hasHtmlGetter(rule, "innerhtml")
        or hasHtmlGetter(rule, "outerhtml") then
        return ContentRule.html
    end
    return ContentRule.text
end

function ContentRule.format(value, content_type)
    if ContentRule.normalizeType(content_type) == ContentRule.html then
        return HtmlFormat.html(value)
    end
    return HtmlFormat.text(value)
end

function ContentRule.join(parts, content_type)
    return table.concat(parts,
        ContentRule.normalizeType(content_type) == ContentRule.html and "\n"
            or "\n\n")
end

function ContentRule.isCurrent(expected_type, actual_type)
    expected_type = ContentRule.normalizeType(expected_type)
    if expected_type == ContentRule.text then
        return actual_type == nil or actual_type == ContentRule.text
    end
    return actual_type == expected_type
end

return ContentRule
