local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Input = Device.input
local Screen = Device.screen

local EmptyView = InputContainer:extend{
    is_borderless = true,
    title = "",
    kaomoji = "(._.)",
    message = "",
    close_callback = nil,
}

function EmptyView:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }

    self.title_bar = TitleBar:new{
        width = self.dimen.w,
        fullscreen = true,
        align = "center",
        title = self.title,
        subtitle = "",
        title_top_padding = Screen:scaleBySize(6),
        button_padding = Screen:scaleBySize(5),
        close_callback = function()
            self:onClose()
        end,
    }

    local emoji = TextWidget:new{
        text = self.kaomoji,
        face = Font:getFace("cfont", 42),
    }
    local message = TextWidget:new{
        text = self.message,
        face = Font:getFace("cfont", 22),
    }

    local body_height = math.max(self.dimen.h - self.title_bar:getHeight(), 0)
    local content = VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = self.dimen.w,
                h = emoji:getSize().h,
            },
            emoji,
        },
        VerticalSpan:new{
            width = Screen:scaleBySize(6),
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.dimen.w,
                h = message:getSize().h,
            },
            message,
        },
    }

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = self.is_borderless and 0 or Size.border.window,
        padding = 0,
        margin = 0,
        radius = 0,
        VerticalGroup:new{
            align = "left",
            self.title_bar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.dimen.w,
                    h = body_height,
                },
                content,
            },
        },
    }

    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
        self.key_events.LeftButtonTap = { { "Menu" } }
        if Device:hasFewKeys() then
            self.key_events.Close = { { "Left" } }
        end
    end
end

function EmptyView:onLeftButtonTap()
    return self:onClose()
end

function EmptyView:onClose()
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function EmptyView:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.dimen
    end)
end

return EmptyView
