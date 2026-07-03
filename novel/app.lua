local Log = require("novel.support.log")
local BookshelfRecords = require("novel.books.records")
local Cache = require("novel.storage.cache")
local Manifest = require("novel.books.manifest")
local SourceRepository = require("novel.source.repository")
local Settings = require("novel.storage.settings")

local App = {}
App.__index = App

function App:new(args)
    local settings = Settings.load()
    return setmetatable({
        plugin = args.plugin,
        settings = settings,
        log = Log:new(settings),
        closed = false,
    }, self)
end

function App:init()
    self.log:debug("app initialized")
end

function App:onClose()
    self.closed = true
    self.source_repository = nil
    self.bookshelf_records = nil
end

function App:saveSettings()
    Settings.save(self.settings)
end

function App:resetSettings()
    self.settings = Settings.reset()
    self.log = Log:new(self.settings)
end

function App.deleteStoredSettings()
    Settings.delete()
    SourceRepository.deleteStorage()
    BookshelfRecords.deleteStorage()
    Cache.deleteStorage()
    Manifest.deleteStorage()
end

function App:getSourceRepository()
    if not self.source_repository then
        self.source_repository = SourceRepository:new()
    end
    return self.source_repository
end

function App:getBookshelfRecords()
    if not self.bookshelf_records then
        self.bookshelf_records = BookshelfRecords:new()
    end
    return self.bookshelf_records
end

return App
