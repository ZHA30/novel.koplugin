local BookshelfStore = require("novel.storage.bookshelfstore")
local Cache = require("novel.storage.cache")
local Manifest = require("novel.storage.manifest")
local ReaderSettings = require("novel.reader.settings")
local SourceStore = require("novel.storage.sourcestore")
local PluginSettings = require("novel.storage.pluginsettings")
local logger = require("logger")

local Log = {}
Log.__index = Log

local function appendEntry(entries, settings, level, message, context)
    table.insert(entries, {
        level = level,
        message = message,
        context = context,
        time = os.time(),
    })

    local max_entries = settings.debug.max_entries or 200
    while #entries > max_entries do
        table.remove(entries, 1)
    end

    logger.dbg("Novel:", level, message)
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
    appendEntry(self.entries, self.settings, level, message, context)
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

local AppContext = {}
AppContext.__index = AppContext

function AppContext:new(args)
    local settings = PluginSettings.load()
    return setmetatable({
        plugin = args.plugin,
        settings = settings,
        log = Log:new(settings),
        closed = false,
    }, self)
end

function AppContext:init()
    self.log:debug("app initialized")
end

function AppContext:onClose()
    self.closed = true
    self.source_store = nil
    self.bookshelf_store = nil
end

function AppContext:saveSettings()
    PluginSettings.save(self.settings)
end

function AppContext:resetSettings()
    self.settings = PluginSettings.reset()
    self.log = Log:new(self.settings)
end

function AppContext.deleteStoredSettings()
    PluginSettings.delete()
    SourceStore.deleteStorage()
    BookshelfStore.deleteStorage()
    Cache.deleteStorage()
    Manifest.deleteStorage()
    ReaderSettings.deleteStorage()
end

function AppContext:getSourceStore()
    if not self.source_store then
        self.source_store = SourceStore:new()
    end
    return self.source_store
end

function AppContext:getBookshelfStore()
    if not self.bookshelf_store then
        self.bookshelf_store = BookshelfStore:new()
    end
    return self.bookshelf_store
end

return AppContext
