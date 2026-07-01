local HtmlRule = require("novel.rule.html")
local JsonRule = require("novel.rule.json")
local Regex = require("novel.rule.regex")
local Split = require("novel.rule.split")
local Url = require("novel.net.url")

local Analyzer = {}
Analyzer.__index = Analyzer

local function isList(value)
    if type(value) ~= "table" then
        return false
    end
    return #value > 0
end

local function asString(value)
    if value == nil then
        return ""
    end
    if type(value) == "table" then
        local strings = {}
        for index = 1, #value do
            table.insert(strings, asString(value[index]))
        end
        return table.concat(strings, "\n")
    end
    return tostring(value)
end

local function stringList(value)
    if value == nil then
        return {}
    end
    if type(value) == "table" then
        local result = {}
        for index = 1, #value do
            table.insert(result, asString(value[index]))
        end
        return result
    end
    return { tostring(value) }
end

local function replaceRegex(value, rule)
    if not rule.replace_regex or rule.replace_regex == "" then
        return value
    end
    local pattern = Regex.toLuaPattern(rule.replace_regex)
    local replacement = rule.replacement or ""
    if rule.replace_first then
        return (tostring(value):gsub(pattern, replacement, 1))
    end
    return (tostring(value):gsub(pattern, replacement))
end

function Analyzer:new(options)
    options = options or {}
    return setmetatable({
        content = options.content,
        base_url = options.base_url or "",
        redirect_url = options.redirect_url or options.base_url or "",
        variables = options.variables or {},
        unsupported = {},
    }, self)
end

function Analyzer:setContent(content, base_url)
    self.content = content
    if base_url then
        self.base_url = base_url
        self.redirect_url = base_url
    end
    return self
end

function Analyzer:setBaseUrl(base_url)
    self.base_url = base_url or ""
    self.redirect_url = self.redirect_url ~= "" and self.redirect_url or self.base_url
    return self
end

function Analyzer:setRedirectUrl(redirect_url)
    self.redirect_url = redirect_url or ""
    return self
end

function Analyzer:put(key, value)
    self.variables[key] = value
    return value
end

function Analyzer:get(key)
    return self.variables[key] or ""
end

function Analyzer:addUnsupported(field, kind, snippet)
    table.insert(self.unsupported, {
        field = field,
        kind = kind,
        snippet = tostring(snippet or ""):sub(1, 120),
    })
end

function Analyzer:makeRule(rule)
    if not rule.dynamic_parts or #rule.dynamic_parts == 0 then
        return rule.rule
    end

    local parts = {}
    for part_index = 1, #rule.dynamic_parts do
        local part = rule.dynamic_parts[part_index]
        if part.kind == "literal" then
            table.insert(parts, part.value)
        elseif part.kind == "get" then
            table.insert(parts, self:get(part.value))
        elseif part.kind == "js" then
            self:addUnsupported("rule", "js", "{{" .. part.value .. "}}")
        end
    end
    return table.concat(parts)
end

function Analyzer:applyPutMap(put_map)
    for key, value_rule in pairs(put_map or {}) do
        self:put(key, self:getString(value_rule))
    end
end

local function applyReplacement(result, rule)
    if not rule.replace_regex or rule.replace_regex == "" then
        return result
    end
    if type(result) == "table" then
        local replaced = {}
        for index = 1, #result do
            replaced[index] = replaceRegex(result[index], rule)
        end
        return replaced
    end
    return replaceRegex(result, rule)
end

function Analyzer:dispatchStringList(content, rule)
    local active_rule = self:makeRule(rule)
    if active_rule == "" and rule.replace_regex ~= "" then
        return stringList(content)
    end

    if rule.mode == Split.modes.json then
        return JsonRule.parse(content):getStringList(active_rule)
    elseif rule.mode == Split.modes.regex then
        return { active_rule }
    elseif rule.mode == Split.modes.js then
        self:addUnsupported("rule.js", "js", active_rule)
        return {}
    elseif rule.mode == Split.modes.xpath then
        self:addUnsupported("rule.xpath", "xpath", active_rule)
        return {}
    end
    return HtmlRule.parse(content):getStringList(active_rule)
end

function Analyzer:dispatchElements(content, rule)
    local active_rule = self:makeRule(rule)

    if rule.mode == Split.modes.json then
        return JsonRule.parse(content):getList(active_rule)
    elseif rule.mode == Split.modes.regex then
        local patterns = Split.splitTopLevel(active_rule, "&&")
        local values, err = Regex.getElements(asString(content), patterns)
        if err then
            self:addUnsupported("rule.regex", err.kind, err.pattern)
        end
        return values
    elseif rule.mode == Split.modes.js then
        self:addUnsupported("rule.js", "js", active_rule)
        return {}
    elseif rule.mode == Split.modes.xpath then
        self:addUnsupported("rule.xpath", "xpath", active_rule)
        return {}
    end
    return HtmlRule.parse(content):getElements(active_rule)
end

function Analyzer:evaluate(rule_text, content, mode)
    local rules = Split.splitSourceRules(rule_text, {
        all_in_one = mode == "elements",
        content_is_json = type(content or self.content) == "table",
    })
    local result = content or self.content
    if not result or #rules == 0 then
        return nil
    end

    for rule_index = 1, #rules do
        local rule = rules[rule_index]
        self:applyPutMap(rule.put_map)
        if mode == "elements" then
            result = self:dispatchElements(result, rule)
        else
            result = self:dispatchStringList(result, rule)
            if mode == "string" and type(result) == "table" then
                result = table.concat(result, "\n")
            end
        end
        result = applyReplacement(result, rule)
        if result == nil then
            return nil
        end
    end

    return result
end

function Analyzer:absoluteValues(values)
    local result, seen = {}, {}
    for index = 1, #values do
        local absolute = Url.absolute(self.redirect_url ~= "" and self.redirect_url or self.base_url,
            values[index])
        if absolute ~= "" and not seen[absolute] then
            seen[absolute] = true
            table.insert(result, absolute)
        end
    end
    return result
end

function Analyzer:getStringList(rule_text, content, is_url)
    local result = self:evaluate(rule_text, content, "list")
    local values = stringList(result)
    if is_url then
        return self:absoluteValues(values)
    end
    return values
end

function Analyzer:getString(rule_text, content, is_url)
    local result = self:evaluate(rule_text, content, "string")
    local value = asString(result)
    if is_url then
        if value == "" then
            return self.base_url
        end
        return Url.absolute(self.redirect_url ~= "" and self.redirect_url or self.base_url, value)
    end
    return value
end

function Analyzer:getElements(rule_text, content)
    local result = self:evaluate(rule_text, content, "elements")
    if isList(result) then
        return result
    end
    return {}
end

function Analyzer:getElement(rule_text, content)
    local elements = self:getElements(rule_text, content)
    return elements[1]
end

return Analyzer
