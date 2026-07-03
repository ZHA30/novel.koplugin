local Context = require("novel.catalog.client")
local HtmlFormat = require("novel.support.htmlformat")

local Fields = {}

local function cleanText(value)
    value = HtmlFormat.text(value)
    value = value:gsub("[ \t\r\n]+", " ")
    return Context.trim(value)
end

local function rawString(analyzer, unsupported, source, field, rule, content, is_url)
    if Context.isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local value = analyzer:getString(rule, content, is_url)
    Context.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return value or ""
end

function Fields.raw(analyzer, unsupported, source, field, rule, content)
    return rawString(analyzer, unsupported, source, field, rule, content)
end

function Fields.text(analyzer, unsupported, source, field, rule, content)
    return HtmlFormat.text(rawString(analyzer, unsupported, source, field,
        rule, content))
end

function Fields.cleanString(analyzer, unsupported, source, field, rule, content)
    return cleanText(rawString(analyzer, unsupported, source, field,
        rule, content))
end

function Fields.url(analyzer, unsupported, source, field, rule, content)
    return Context.trim(rawString(analyzer, unsupported, source, field,
        rule, content, true))
end

function Fields.urlList(analyzer, unsupported, source, field, rule, content)
    if Context.isBlank(rule) then
        return {}
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, content, true)
    Context.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return values
end

function Fields.listText(analyzer, unsupported, source, field, rule, content)
    if Context.isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, content)
    Context.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)

    local output = {}
    for index = 1, #values do
        local value = cleanText(values[index])
        if value ~= "" then
            table.insert(output, value)
        end
    end
    return table.concat(output, ",")
end

function Fields.elements(analyzer, unsupported, source, field, rule)
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getElements(rule)
    Context.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return values
end

function Fields.boolean(value)
    value = Context.trim(value):lower()
    return value == "true" or value == "1" or value == "yes"
        or value == "y" or value == "on" or value == "vip"
end

return Fields
