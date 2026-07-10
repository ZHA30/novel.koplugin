local HtmlRule = require("novel.catalog.shared.html")

local XPathRule = {}
XPathRule.__index = XPathRule

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function appendPredicate(selector, predicate)
    predicate = trim(predicate)
    local attr, value = predicate:match("^@([%w_:%-]+)%s*=%s*['\"]([^'\"]+)['\"]$")
    if attr and value then
        if attr == "class" and value:match("^[%w_%-]+$") then
            return selector .. "." .. value
        elseif attr == "id" and value:match("^[%w_%-]+$") then
            return selector .. "#" .. value
        end
        return selector .. "[" .. attr .. "='" .. value .. "']"
    end

    attr, value = predicate:match("^contains%(%s*@([%w_:%-]+)%s*,%s*['\"]([^'\"]+)['\"]%s*%)$")
    if attr and value and attr == "class" and value:match("^[%w_%-]+$") then
        return selector .. "." .. value
    end
    return nil, "unsupported XPath predicate"
end

local function segmentToSelector(segment)
    segment = trim(segment)
    if segment == "" then
        return nil
    end
    if segment == "*" then
        return "*"
    end

    local name, predicate = segment:match("^([%w_:%-%*]+)%[(.+)%]$")
    if name then
        local selector = name == "*" and "*" or name
        return appendPredicate(selector, predicate)
    end
    if segment:match("^[%w_:%-]+$") then
        return segment
    end
    return nil, "unsupported XPath segment"
end

local function translate(rule)
    rule = trim(rule)
    if rule == "" then
        return nil, "empty XPath"
    end

    local getter = "text"
    local attr = rule:match("/@([%w_:%-]+)$")
    if attr then
        getter = "attr(" .. attr .. ")"
        rule = rule:gsub("/@[%w_:%-]+$", "")
    elseif rule:match("/text%(%)$") then
        getter = "text"
        rule = rule:gsub("/text%(%)$", "")
    elseif rule:match("/html%(%)$") then
        getter = "html"
        rule = rule:gsub("/html%(%)$", "")
    end

    rule = rule:gsub("^%./", "")
    rule = rule:gsub("^//", "")
    rule = rule:gsub("^/", "")
    rule = rule:gsub("//", " / ")

    local selectors = {}
    for raw_segment in (rule .. "/"):gmatch("(.-)/") do
        local segment = trim(raw_segment)
        if segment ~= "" then
            local selector, err = segmentToSelector(segment)
            if not selector then
                return nil, err
            end
            table.insert(selectors, selector)
        end
    end
    if #selectors == 0 then
        return nil, "empty XPath selector"
    end
    return table.concat(selectors, " ") .. "@" .. getter
end

function XPathRule:new(content)
    return setmetatable({
        html = HtmlRule.parse(content),
    }, self)
end

function XPathRule:getStringList(rule)
    local css_rule, err = translate(rule)
    if not css_rule then
        return {}, err
    end
    return self.html:getStringList(css_rule)
end

function XPathRule:getElements(rule)
    local css_rule, err = translate(rule)
    if not css_rule then
        return {}, err
    end
    local selector = css_rule:match("^(.-)@[^@]+$") or css_rule
    return self.html:getElements(selector)
end

function XPathRule.parse(content)
    return XPathRule:new(content)
end

return XPathRule
