local Device = require("device")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")

local LoadingTrap = TrapWidget:extend{
    dismissable = true,
    flush_events_on_show = true,
}

function LoadingTrap:init()
    TrapWidget.init(self)
    self.text_widget = self.frame and self.frame[1]
    if self.dismissable == false then
        self.ges_events = {}
        self.key_events = {}
    end
end

function LoadingTrap:setText(text)
    text = tostring(text or "")
    if self.text == text then
        return
    end
    self.text = text
    if not self.text_widget or not self.frame then
        return
    end

    local old_dimen = self.frame.dimen and self.frame.dimen:copy()
    self.text_widget:setText(text)
    local new_dimen = old_dimen and old_dimen:copy()
    if new_dimen then
        local size = self.frame:getSize()
        new_dimen.w = size.w
        new_dimen.h = size.h
    end
    self.frame.dimen = nil

    local dirty_region = old_dimen
        and new_dimen
        and old_dimen:combine(new_dimen)
        or old_dimen
    UIManager:setDirty(self, "ui", dirty_region)
end

function LoadingTrap:onShow()
    local handled = TrapWidget.onShow(self)
    if self.flush_events_on_show ~= false then
        Device.input:inhibitInputUntil(true)
    end
    return handled
end

return LoadingTrap
