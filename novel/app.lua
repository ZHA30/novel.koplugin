local Log = require("novel.support.log")
local Bookshelf = require("novel.service.bookshelf")
local Repo = require("novel.source.repo")
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
    self.source_repo = nil
    self.bookshelf_service = nil
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
    Repo.deleteStorage()
    Bookshelf.deleteStorage()
end

function App:getSourceRepo()
    if not self.source_repo then
        self.source_repo = Repo:new()
    end
    return self.source_repo
end

function App:getBookshelfService()
    if not self.bookshelf_service then
        self.bookshelf_service = Bookshelf:new()
    end
    return self.bookshelf_service
end

return App
