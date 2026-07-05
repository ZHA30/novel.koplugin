local HtmlParser = require("htmlparser")
local HtmlFormat = require("novel.catalog.shared.format")
local Split = require("novel.catalog.shared.split")

local HtmlRule = {}
HtmlRule.__index = HtmlRule

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function appendAll(target, values)
    for index = 1, #values do
        table.insert(target, values[index])
    end
end

local function normalizeRule(rule)
    rule = trim(rule)
    if rule:sub(1, 5):lower() == "@css:" then
        return trim(rule:sub(6)), true
    end
    if rule:sub(1, 1) == "@" then
        return trim(rule:sub(2)), false
    end
    return rule, false
end

local function safeParse(content)
    if type(content) == "table" and content.select then
        return content
    end
    local ok, root = pcall(HtmlParser.parse, content or "")
    if ok then
        return root
    end
end

function HtmlRule:new(content)
    return setmetatable({
        root = safeParse(content),
    }, self)
end

local function nodeText(node)
    if not node then
        return nil
    end
    if node.textonly then
        return trim(HtmlFormat.decodeEntities(node:textonly()):gsub("%s+", " "))
    end
    return trim(HtmlFormat.decodeEntities(tostring(node)))
end

local function nodeHtml(node)
    if node and node.getcontent then
        return node:getcontent()
    end
end

local function nodeOuterHtml(node)
    if node and node.gettext then
        return node:gettext()
    end
end

local function attrName(getter)
    return getter:match("^attr%((.-)%)$") or getter:match("^attr:%s*(.-)%s*$")
end

local function extractNode(node, getter)
    getter = trim(getter or "text")
    local lowered = getter:lower()

    if lowered == "" or lowered == "text" then
        return nodeText(node)
    end
    if lowered == "html" or lowered == "innerhtml" then
        return nodeHtml(node)
    end
    if lowered == "outerhtml" then
        return nodeOuterHtml(node)
    end
    if lowered == "data" then
        return nodeHtml(node) or nodeText(node)
    end

    local name = attrName(getter) or getter
    if node and node.attributes then
        return HtmlFormat.attribute(node.attributes[name])
    end
end

local function splitSelector(rule)
    local selector, getter = rule, "text"
    local index = #rule
    while index > 0 do
        local char = rule:sub(index, index)
        if char == "@" then
            selector = trim(rule:sub(1, index - 1))
            getter = trim(rule:sub(index + 1))
            break
        end
        index = index - 1
    end
    if selector == "" then
        selector = "*"
    end
    return selector, getter
end

function HtmlRule:getElements(rule)
    if not self.root then
        return {}
    end
    rule = normalizeRule(rule)
    if rule == "" then
        return { self.root }
    end

    local selector = splitSelector(rule)
    local ok, nodes = pcall(function()
        return self.root:select(selector)
    end)
    if ok and type(nodes) == "table" then
        return nodes
    end
    return {}
end

local function combineLists(lists, operator)
    local result = {}
    if operator == "%%" and #lists > 0 then
        for item_index = 1, #lists[1] do
            for list_index = 1, #lists do
                if item_index <= #lists[list_index] then
                    table.insert(result, lists[list_index][item_index])
                end
            end
        end
    else
        for list_index = 1, #lists do
            appendAll(result, lists[list_index])
        end
    end
    return result
end

function HtmlRule:getStringList(rule)
    rule = tostring(rule or "")
    if rule == "" then
        return {}
    end

    local rules, operator = Split.splitOperators(rule)
    if #rules > 1 then
        local lists = {}
        for rule_index = 1, #rules do
            local values = self:getStringList(rules[rule_index])
            if #values > 0 then
                table.insert(lists, values)
                if operator == "||" then
                    break
                end
            end
        end
        return combineLists(lists, operator)
    end

    local normalized_rule = normalizeRule(rule)
    local selector, getter = splitSelector(normalized_rule)
    local nodes = self:getElements(selector)
    local result = {}
    for node_index = 1, #nodes do
        local value = extractNode(nodes[node_index], getter)
        if value and value ~= "" then
            table.insert(result, value)
        end
    end
    return result
end

function HtmlRule:getString(rule)
    local strings = self:getStringList(rule)
    if #strings == 0 then
        return nil
    end
    return table.concat(strings, "\n")
end

function HtmlRule:getObject(rule)
    local nodes = self:getElements(rule)
    return nodes[1]
end

function HtmlRule.parse(content)
    return HtmlRule:new(content)
end

return HtmlRule
