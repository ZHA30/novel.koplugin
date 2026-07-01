local Log = require("novel.support.log")
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
end

return App
