local RequestSupport = require("novel.catalog.shared.requestsupport")
local Text = require("novel.catalog.shared.text")
local HtmlFormat = require("novel.catalog.shared.format")

local Extract = {}

local function cleanText(value)
    value = HtmlFormat.text(value)
    value = value:gsub("[ \t\r\n]+", " ")
    return Text.trim(value)
end

local function rawString(analyzer, unsupported, source, field, rule, content, is_url)
    if Text.isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local value = analyzer:getString(rule, content, is_url)
    RequestSupport.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return value or ""
end

local function elementMarkup(element)
    if type(element) == "table" then
        if element.getcontent then
            return element:getcontent()
        end
        if element.gettext then
            return element:gettext()
        end
    elseif type(element) == "string" and element:find("<", 1, true) then
        return element
    end
end

local function removeUnsupportedFrom(analyzer, start_index)
    for index = #analyzer.unsupported, start_index, -1 do
        analyzer.unsupported[index] = nil
    end
end

local function htmlElementText(analyzer, unsupported, source, field, rule, content)
    if Text.isBlank(rule) then
        return ""
    end

    local start_index = #analyzer.unsupported + 1
    local elements = analyzer:getElements(rule, content)
    local output = {}
    for index = 1, #elements do
        local markup = elementMarkup(elements[index])
        local value = markup and HtmlFormat.text(markup) or ""
        if value ~= "" then
            table.insert(output, value)
        end
    end

    if #output == 0 then
        removeUnsupportedFrom(analyzer, start_index)
        return ""
    end

    RequestSupport.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return Text.trim(table.concat(output, "\n"))
end

function Extract.raw(analyzer, unsupported, source, field, rule, content)
    return rawString(analyzer, unsupported, source, field, rule, content)
end

function Extract.text(analyzer, unsupported, source, field, rule, content)
    return HtmlFormat.text(rawString(analyzer, unsupported, source, field,
        rule, content))
end

function Extract.paragraphText(analyzer, unsupported, source, field, rule, content)
    local value = htmlElementText(analyzer, unsupported, source, field,
        rule, content)
    if value ~= "" then
        return value
    end
    return Extract.text(analyzer, unsupported, source, field, rule, content)
end

function Extract.cleanString(analyzer, unsupported, source, field, rule, content)
    return cleanText(rawString(analyzer, unsupported, source, field,
        rule, content))
end

function Extract.url(analyzer, unsupported, source, field, rule, content)
    return Text.trim(rawString(analyzer, unsupported, source, field,
        rule, content, true))
end

function Extract.urlList(analyzer, unsupported, source, field, rule, content)
    if Text.isBlank(rule) then
        return {}
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, content, true)
    RequestSupport.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return values
end

function Extract.listText(analyzer, unsupported, source, field, rule, content)
    if Text.isBlank(rule) then
        return ""
    end
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getStringList(rule, content)
    RequestSupport.copyUnsupported(unsupported, source, field,
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

function Extract.elements(analyzer, unsupported, source, field, rule)
    local start_index = #analyzer.unsupported + 1
    local values = analyzer:getElements(rule)
    RequestSupport.copyUnsupported(unsupported, source, field,
        analyzer.unsupported, start_index)
    return values
end

function Extract.boolean(value)
    value = Text.trim(value):lower()
    return value == "true" or value == "1" or value == "yes"
        or value == "y" or value == "on" or value == "vip"
end

return Extract
