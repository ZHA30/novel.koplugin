local socket_ok, socket = pcall(require, "socket")

local Throttle = {}
Throttle.__index = Throttle

local function nowMs()
    if socket_ok and socket and socket.gettime then
        return math.floor(socket.gettime() * 1000)
    end
    return os.time() * 1000
end

local function sourceKey(source)
    if type(source) == "table" then
        return source.bookSourceUrl or source.bookSourceName or tostring(source)
    end
    return tostring(source or "global")
end

local function parseRate(rate)
    if rate == nil or rate == "" then
        return nil
    end
    rate = tostring(rate):match("^%s*(.-)%s*$")
    local limit, window = rate:match("^(%d+)%s*/%s*(%d+)$")
    if limit and window then
        limit = tonumber(limit)
        window = tonumber(window)
        if limit and limit > 0 and window and window > 0 then
            return {
                mode = "window",
                limit = limit,
                window = window,
            }
        end
        return nil
    end

    local interval = tonumber(rate)
    if interval and interval > 0 then
        return {
            mode = "interval",
            interval = interval,
        }
    end
end

function Throttle:new(options)
    options = options or {}
    return setmetatable({
        records = {},
        clock = options.clock or nowMs,
    }, self)
end

function Throttle:clear()
    self.records = {}
end

function Throttle:reset(source)
    self.records[sourceKey(source)] = nil
end

function Throttle:acquire(source, rate, timestamp)
    if type(source) == "table" then
        rate = rate or source.concurrentRate
    end

    local rule = parseRate(rate)
    local key = sourceKey(source)
    if not rule then
        return {
            key = key,
            limited = false,
        }, 0
    end

    timestamp = timestamp or self.clock()

    if rule.mode == "interval" then
        return self:_acquireInterval(key, rule, timestamp)
    end
    return self:_acquireWindow(key, rule, timestamp)
end

function Throttle:_acquireInterval(key, rule, timestamp)
    local record = self.records[key]
    if not record then
        self.records[key] = {
            mode = "interval",
            time = timestamp,
            active = 1,
        }
        return {
            key = key,
            mode = "interval",
            limited = true,
        }, 0
    end

    if record.active and record.active > 0 then
        return nil, rule.interval
    end

    local next_time = record.time + rule.interval
    if timestamp >= next_time then
        record.time = timestamp
        record.active = 1
        return {
            key = key,
            mode = "interval",
            limited = true,
        }, 0
    end

    return nil, next_time - timestamp
end

function Throttle:_acquireWindow(key, rule, timestamp)
    local record = self.records[key]
    if not record or record.mode ~= "window" or timestamp >= record.time + rule.window then
        self.records[key] = {
            mode = "window",
            time = timestamp,
            count = 1,
        }
        return {
            key = key,
            mode = "window",
            limited = true,
        }, 0
    end

    if record.count >= rule.limit then
        return nil, record.time + rule.window - timestamp
    end

    record.count = record.count + 1
    return {
        key = key,
        mode = "window",
        limited = true,
    }, 0
end

function Throttle:release(token)
    if not token or not token.limited or token.mode ~= "interval" then
        return
    end

    local record = self.records[token.key]
    if record and record.mode == "interval" and record.active and record.active > 0 then
        record.active = record.active - 1
    end
end

function Throttle:withPermit(source, rate, callback)
    local token, wait_ms = self:acquire(source, rate)
    if not token then
        return nil, wait_ms
    end

    local ok, result, extra = pcall(callback, token)
    self:release(token)
    if not ok then
        error(result)
    end
    return result, 0, extra
end

return Throttle
