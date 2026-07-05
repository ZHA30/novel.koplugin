local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Icons = require("novel.icons")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen
local Input = Device.input

local TAB_BAR_HEIGHT = Screen:scaleBySize(72)
local CONTENT_ICON_SIZE = Screen:scaleBySize(72)
local TAB_ICON_SIZE = Screen:scaleBySize(24)
local TAB_LABEL_SIZE = 14
local CONTENT_LABEL_SIZE = 28

local HomeTabButton = InputContainer:extend{
    key = nil,
    text = "",
    icon = nil,
    active = false,
    width = 0,
    height = TAB_BAR_HEIGHT,
    callback = nil,
}

function HomeTabButton:init()
    local icon = Icons.widget(self.icon, {
        size = TAB_ICON_SIZE,
        dim = not self.active,
    })
    local fgcolor = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local label = TextWidget:new{
        text = self.text,
        face = Font:getFace("smallinfofont", TAB_LABEL_SIZE),
        fgcolor = fgcolor,
        bold = self.active,
    }
    local indicator_h = Screen:scaleBySize(3)
    local indicator = LineWidget:new{
        dimen = Geom:new{
            w = math.max(self.width - Screen:scaleBySize(24), Screen:scaleBySize(16)),
            h = indicator_h,
        },
        background = self.active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
    }

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.height,
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        CenterContainer:new{
            dimen = self.dimen:copy(),
            VerticalGroup:new{
                align = "center",
                CenterContainer:new{
                    dimen = Geom:new{
                        w = self.width,
                        h = indicator_h,
                    },
                    indicator,
                },
                VerticalSpan:new{
                    width = Screen:scaleBySize(10),
                },
                CenterContainer:new{
                    dimen = Geom:new{
                        w = self.width,
                        h = TAB_ICON_SIZE,
                    },
                    icon,
                },
                VerticalSpan:new{
                    width = Screen:scaleBySize(4),
                },
                CenterContainer:new{
                    dimen = Geom:new{
                        w = self.width,
                        h = label:getSize().h,
                    },
                    label,
                },
            },
        },
    }

    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function HomeTabButton:onTapSelect()
    if self.callback then
        self.callback(self.key)
    end
    return true
end

local HomeShell = InputContainer:extend{
    is_borderless = true,
    title = "",
    subtitle = "",
    active_tab = "bookshelf",
    tabs = nil,
    content_builder = nil,
    left_icon = nil,
    left_callback = nil,
    close_request_callback = nil,
    close_callback = nil,
}

local function activeTabSpec(self)
    for index = 1, #(self.tabs or {}) do
        local tab = self.tabs[index]
        if tab.key == self.active_tab then
            return tab
        end
    end
    return self.tabs and self.tabs[1] or nil
end

function HomeShell:buildContent()
    self.cropping_widget = nil
    if type(self.content_builder) == "function" then
        local widget = self.content_builder(self)
        if widget then
            if widget.is_home_scrollable then
                self.cropping_widget = widget
            end
            return widget
        end
    end

    local tab = activeTabSpec(self)
    if not tab then
        return VerticalGroup:new{}
    end

    local icon = Icons.widget(tab.icon, {
        size = CONTENT_ICON_SIZE,
    })
    local title = TextWidget:new{
        text = tab.text,
        face = Font:getFace("cfont", CONTENT_LABEL_SIZE),
        bold = true,
    }

    return VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = self.dimen.w,
                h = CONTENT_ICON_SIZE,
            },
            icon,
        },
        VerticalSpan:new{
            width = Screen:scaleBySize(14),
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = self.dimen.w,
                h = title:getSize().h,
            },
            title,
        },
    }
end

function HomeShell:buildTabBar()
    local width = self.dimen.w
    local tabs = self.tabs or {}
    local count = math.max(#tabs, 1)
    local tab_width = math.floor(width / count)
    local group = HorizontalGroup:new{}

    for index = 1, #tabs do
        local tab = tabs[index]
        local current_width = index == #tabs and width - tab_width * (#tabs - 1) or tab_width
        table.insert(group, HomeTabButton:new{
            key = tab.key,
            text = tab.text,
            icon = tab.icon,
            active = tab.key == self.active_tab,
            width = current_width,
            callback = function()
                if tab.callback then
                    tab.callback(tab.key)
                end
            end,
        })
    end

    return FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        VerticalGroup:new{
            align = "left",
            LineWidget:new{
                dimen = Geom:new{
                    w = width,
                    h = Size.line.thin,
                },
                background = Blitbuffer.COLOR_DARK_GRAY,
            },
            group,
        },
    }
end

function HomeShell:init()
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
        subtitle = self.subtitle,
        title_h_padding = Size.padding.large,
        button_padding = Screen:scaleBySize(11),
        left_icon = self.left_icon,
        left_icon_tap_callback = function()
            self:onLeftButtonTap()
        end,
        show_parent = self,
        close_callback = function()
            self:onClose()
        end,
    }

    local body_height = math.max(
        self.dimen.h - self.title_bar:getHeight() - TAB_BAR_HEIGHT,
        0
    )
    self.body_width = self.dimen.w
    self.body_height = body_height

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
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
                self:buildContent(),
            },
            self:buildTabBar(),
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

function HomeShell:onLeftButtonTap()
    if self.left_callback then
        self.left_callback()
        return true
    end
    return self:onClose()
end

function HomeShell:onClose()
    if self.close_request_callback then
        return self.close_request_callback()
    end
    UIManager:close(self)
    if self.close_callback then
        self.close_callback()
    end
    return true
end

function HomeShell:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.dimen
    end)
end

return HomeShell
