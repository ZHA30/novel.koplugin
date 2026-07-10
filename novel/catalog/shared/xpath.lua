local HtmlRule = require("novel.catalog.shared.html")

local XPathRule = {}
XPathRule.__index = XPathRule

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function appendPredicate(selector, predicate)
    predicate = trim(predicate)
    if predicate:match("^%d+$") then
        local position = tonumber(predicate)
        if position and position > 0 then
            return selector, nil, position
        end
        return nil, "unsupported XPath position"
    end
    local exists = predicate:match("^@([%w_:%-]+)$")
    if exists then
        return selector .. "[" .. exists .. "]"
    end
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
    elseif attr and value then
        return selector .. "[" .. attr .. "*='" .. value .. "']"
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

    local segments = {}
    for raw_segment in (rule .. "/"):gmatch("(.-)/") do
        local segment = trim(raw_segment)
        if segment ~= "" then
            table.insert(segments, segment)
        end
    end

    local selectors = {}
    local position
    for index = 1, #segments do
        local selector, err, segment_position = segmentToSelector(segments[index])
        if not selector then
            return nil, err
        end
        if segment_position and index ~= #segments then
            return nil, "unsupported non-terminal XPath position"
        end
        table.insert(selectors, selector)
        position = segment_position or position
    end
    if #selectors == 0 then
        return nil, "empty XPath selector"
    end
    return table.concat(selectors, " ") .. "@" .. getter, nil, position
end

function XPathRule:new(content)
    return setmetatable({
        html = HtmlRule.parse(content),
    }, self)
end

function XPathRule:getStringList(rule)
    local css_rule, err, position = translate(rule)
    if not css_rule then
        return {}, err
    end
    if not position then
        return self.html:getStringList(css_rule)
    end
    local values = self.html:getStringList(css_rule)
    if not values[position] then
        return {}
    end
    return { values[position] }
end

function XPathRule:getElements(rule)
    local css_rule, err, position = translate(rule)
    if not css_rule then
        return {}, err
    end
    local selector = css_rule:match("^(.-)@[^@]+$") or css_rule
    local nodes = self.html:getElements(selector)
    if position then
        return nodes[position] and { nodes[position] } or {}
    end
    return nodes
end

function XPathRule.parse(content)
    return XPathRule:new(content)
end

return XPathRule
