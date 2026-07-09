local BookshelfStore = require("novel.storage.bookshelfstore")
local Cache = require("novel.storage.cache")
local DownloadQueue = require("novel.reader.downloadqueue")
local Manifest = require("novel.storage.manifest")
local OfflineFiles = require("novel.storage.offlinefiles")
local ReaderSettings = require("novel.reader.settings")
local SourceStore = require("novel.storage.sourcestore")
local PluginSettings = require("novel.storage.pluginsettings")
local logger = require("logger")

local Log = {}
Log.__index = Log

function Log:new(settings)
    return setmetatable({
        settings = settings,
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
    logger.dbg("Novel:", level, message, context)
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
    self:pruneOfflineOrphans()
    DownloadQueue.init(self.plugin)
end

function AppContext:onClose()
    DownloadQueue.close(self.plugin)
    self:pruneOfflineOrphans()
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

function AppContext:pruneOfflineOrphans()
    local summary = OfflineFiles.pruneOrphans(self:getBookshelfStore())
    if summary and #summary.removed_book_ids > 0 then
        DownloadQueue.removeBooks(self.plugin, summary.removed_book_ids, {
            notify = false,
            restart = false,
        })
    end
    return summary
end

function AppContext.deleteStoredSettings()
    PluginSettings.delete()
    SourceStore.deleteStorage()
    BookshelfStore.deleteStorage()
    Cache.deleteStorage()
    DownloadQueue.deleteStorage()
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
