local Books = require("novel.catalog.books")
local Runtime = require("novel.catalog.runtime")
local Request = require("novel.net.request")
local Throttle = require("novel.net.throttle")
local rapidjson = require("rapidjson")

local Explore = {}
Explore.__index = Explore

local trim = Runtime.trim
local isBlank = Runtime.isBlank
local addDebug = Runtime.addDebug
local addError = Runtime.error
local addUnsupported = Runtime.addUnsupported
local copyUrlUnsupported = Runtime.copyUrlUnsupported

local function activeRule(source)
    if type(source.ruleExplore) == "table" and not isBlank(source.ruleExplore.bookList) then
        return source.ruleExplore, "ruleExplore"
    end
    return source.ruleSearch, "ruleSearch"
end

local responseSummary = Runtime.responseSummary

local function parseJsonGroups(source, groups, decoded)
    for index = 1, #decoded do
        local item = decoded[index]
        if type(item) == "table" and not isBlank(item.url) then
            table.insert(groups, {
                title = trim(item.title or item.name or item.url),
                url = trim(item.url),
                source = source,
            })
        end
    end
end

local function parseTextGroups(source, groups, text)
    text = tostring(text or ""):gsub("\r\n", "\n")
    for raw_line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local start_index = 1
        while start_index <= #raw_line do
            local delimiter_start = raw_line:find("&&", start_index, true)
            local part = delimiter_start
                and raw_line:sub(start_index, delimiter_start - 1)
                or raw_line:sub(start_index)
            local line = trim(part)
            if line ~= "" then
                local title, url = line:match("^(.-)::(.+)$")
                if title and url then
                    table.insert(groups, {
                        title = trim(title),
                        url = trim(url),
                        source = source,
                    })
                end
            end
            if not delimiter_start then
                break
            end
            start_index = delimiter_start + 2
        end
    end
end

function Explore.groups(source)
    local groups, unsupported = {}, {}
    if type(source) ~= "table" or isBlank(source.exploreUrl) then
        return groups, unsupported
    end
    local text = trim(source.exploreUrl)
    if text:match("^<js>") or text:match("^@js:") or text:match("^%{%{") then
        addUnsupported(unsupported, source, "exploreUrl", "js", text)
        return groups, unsupported
    end

    local ok, decoded = pcall(rapidjson.decode, text)
    if ok and type(decoded) == "table" then
        parseJsonGroups(source, groups, decoded)
    else
        parseTextGroups(source, groups, text .. "\n")
    end
    return groups, unsupported
end

function Explore:new(options)
    options = options or {}
    return setmetatable({
        request = options.request or Request,
        throttle = options.throttle or Throttle:new(),
    }, self)
end

function Explore:explore(source, group, options)
    options = options or {}
    local debug, unsupported = {}, {}

    if type(source) ~= "table" then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source is required"),
        }
    end
    if source.enabled == false or source.enabledExplore == false then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "book source explore is disabled"),
        }
    end
    if type(group) ~= "table" or isBlank(group.url) then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("explore", "exploreUrl is required"),
        }
    end

    local rule, prefix = activeRule(source)
    if type(rule) ~= "table" then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("source", "ruleExplore or ruleSearch is required"),
        }
    end

    local spec = Runtime.requestSpec(source, group.url, options, {
        page = options.page or 1,
    })
    copyUrlUnsupported(unsupported, source, spec.unsupported, "exploreUrl")

    addDebug(debug, "request", {
        url = spec.url,
        method = spec.method,
        title = group.title,
        page = options.page or 1,
    })

    if #spec.errors > 0 then
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = addError("url", spec.errors[1].error, spec.errors[1]),
        }
    end

    local response, request_err, failed_response = Runtime.execute(self, source, spec)
    if not response then
        if failed_response then
            addDebug(debug, "response", responseSummary(failed_response))
        end
        return {
            ok = false,
            books = {},
            debug = debug,
            unsupported = unsupported,
            error = request_err,
            response = failed_response and responseSummary(failed_response) or nil,
        }
    end

    addDebug(debug, "response", responseSummary(response))

    local parsed = Books.parse(source, rule, prefix, response, {
        parse_event = "parse_explore_list",
        size_event = "explore_list_size",
    })
    for index = 1, #parsed.debug do
        table.insert(debug, parsed.debug[index])
    end
    for index = 1, #parsed.unsupported do
        table.insert(unsupported, parsed.unsupported[index])
    end
    parsed.debug = debug
    parsed.unsupported = unsupported
    parsed.response = responseSummary(response)
    parsed.group = {
        title = group.title,
        url = group.url,
        page = options.page or 1,
    }
    return parsed
end

function Explore.run(source, group, options)
    return Explore:new(options):explore(source, group, options)
end

return Explore
