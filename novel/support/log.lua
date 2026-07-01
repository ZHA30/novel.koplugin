local logger = require("logger")

local Log = {}
Log.__index = Log

local function sortedKeys(value)
    local keys = {}
    for key in pairs(value or {}) do
        table.insert(keys, key)
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function appendLine(lines, indent, text)
    table.insert(lines, string.rep("  ", indent or 0) .. text)
end

local function scalarText(value)
    if value == nil then
        return "nil"
    end
    if type(value) == "boolean" then
        return value and "true" or "false"
    end
    return tostring(value)
end

local function appendValue(lines, key, value, indent, depth)
    indent = indent or 0
    depth = depth or 0
    if type(value) ~= "table" then
        appendLine(lines, indent, tostring(key) .. ": " .. scalarText(value))
        return
    end

    if depth >= 2 then
        appendLine(lines, indent, tostring(key) .. ": {...}")
        return
    end

    local keys = sortedKeys(value)
    if #keys == 0 then
        appendLine(lines, indent, tostring(key) .. ": {}")
        return
    end

    appendLine(lines, indent, tostring(key) .. ":")
    for index = 1, #keys do
        local child_key = keys[index]
        appendValue(lines, child_key, value[child_key], indent + 1, depth + 1)
    end
end

local function appendSection(lines, title, content)
    if not content or content == "" then
        return
    end
    if #lines > 0 then
        table.insert(lines, "")
    end
    table.insert(lines, title)
    table.insert(lines, content)
end

function Log:new(settings)
    return setmetatable({
        settings = settings,
        entries = {},
    }, self)
end

function Log:isEnabled()
    return self.settings
        and self.settings.debug
        and self.settings.debug.enabled == true
end

function Log:append(level, message, context)
    if not self:isEnabled() then
        return
    end

    table.insert(self.entries, {
        level = level,
        message = message,
        context = context,
        time = os.time(),
    })

    local max_entries = self.settings.debug.max_entries or 200
    while #self.entries > max_entries do
        table.remove(self.entries, 1)
    end

    logger.dbg("Novel:", level, message)
end

function Log:debug(message, context)
    self:append("debug", message, context)
end

function Log:info(message, context)
    self:append("info", message, context)
end

function Log:warn(message, context)
    self:append("warn", message, context)
end

function Log:err(message, context)
    self:append("error", message, context)
end

function Log:clear()
    self.entries = {}
end

function Log.formatValue(value)
    if type(value) ~= "table" then
        return scalarText(value)
    end

    local lines = {}
    local keys = sortedKeys(value)
    for index = 1, #keys do
        local key = keys[index]
        appendValue(lines, key, value[key], 0, 0)
    end
    return table.concat(lines, "\n")
end

function Log.formatEvents(events, options)
    options = options or {}
    local limit = options.limit or 12
    local lines = {}
    for index = 1, math.min(#(events or {}), limit) do
        local event = events[index]
        if type(event) ~= "table" then
            event = {
                event = tostring(event),
            }
        end
        appendLine(lines, 0, "[" .. tostring(index) .. "] "
            .. tostring(event.event or "event"))
        if type(event.data) == "table" then
            local keys = sortedKeys(event.data)
            for key_index = 1, #keys do
                local key = keys[key_index]
                appendValue(lines, key, event.data[key], 1, 0)
            end
        elseif event.data ~= nil then
            appendLine(lines, 1, scalarText(event.data))
        end
    end

    if #(events or {}) > limit then
        appendLine(lines, 0, "..." .. tostring(#events - limit) .. " more")
    end
    return table.concat(lines, "\n")
end

function Log.formatUnsupported(items, options)
    options = options or {}
    local limit = options.limit or 12
    local lines = {}
    for index = 1, math.min(#(items or {}), limit) do
        local item = items[index]
        if type(item) ~= "table" then
            item = {
                kind = "unknown",
                snippet = tostring(item),
            }
        end
        appendLine(lines, 0, "[" .. tostring(index) .. "] "
            .. tostring(item.kind or "unknown"))
        appendValue(lines, "source", item.source or "", 1, 0)
        appendValue(lines, "field", item.field or "", 1, 0)
        appendValue(lines, "snippet", item.snippet or "", 1, 0)
    end

    if #(items or {}) > limit then
        appendLine(lines, 0, "..." .. tostring(#items - limit) .. " more")
    end
    return table.concat(lines, "\n")
end

function Log.formatResponse(response)
    if type(response) ~= "table" then
        return ""
    end

    local lines = {}
    appendValue(lines, "request_url", response.request_url or "", 0, 0)
    appendValue(lines, "final_url", response.final_url or response.url or "", 0, 0)
    appendValue(lines, "status", response.status or "", 0, 0)
    appendValue(lines, "bytes", response.bytes or #(response.body or ""), 0, 0)
    if response.redirects and #response.redirects > 0 then
        appendValue(lines, "redirects", response.redirects, 0, 0)
    end
    return table.concat(lines, "\n")
end

function Log.formatDiagnostic(result, options)
    options = options or {}
    local lines = {}
    if type(result) ~= "table" then
        return ""
    end

    appendSection(lines, options.response_title or "Response",
        Log.formatResponse(result.response))
    appendSection(lines, options.debug_title or "Debug events",
        Log.formatEvents(result.debug))
    appendSection(lines, options.unsupported_title or "Unsupported",
        Log.formatUnsupported(result.unsupported))
    return table.concat(lines, "\n")
end

return Log
