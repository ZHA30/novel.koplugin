local logger = require("logger")

local Log = {}
Log.__index = Log

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

return Log
