local Device = require("device")
local TrapWidget = require("ui/widget/trapwidget")

local LoadingTrap = TrapWidget:extend{
    dismissable = true,
    flush_events_on_show = true,
}

function LoadingTrap:init()
    TrapWidget.init(self)
    if self.dismissable == false then
        self.ges_events = {}
        self.key_events = {}
    end
end

function LoadingTrap:onShow()
    local handled = TrapWidget.onShow(self)
    if self.flush_events_on_show ~= false then
        Device.input:inhibitInputUntil(true)
    end
    return handled
end

return LoadingTrap
