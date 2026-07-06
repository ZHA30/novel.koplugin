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

local BOTTOM_BAR_HEIGHT = Screen:scaleBySize(72)
local CONTENT_ICON_SIZE = Screen:scaleBySize(72)
local ACTION_ICON_SIZE = Screen:scaleBySize(24)
local ACTION_LABEL_SIZE = 14
local CONTENT_LABEL_SIZE = 28

local ShellActionButton = InputContainer:extend{
    key = nil,
    text = "",
    icon = nil,
    active = false,
    dim = false,
    enabled = true,
    width = 0,
    height = BOTTOM_BAR_HEIGHT,
    callback = nil,
}

function ShellActionButton:init()
    local enabled = self.enabled ~= false
    local dim = not enabled or self.dim == true
    local icon = Icons.widget(self.icon, {
        size = ACTION_ICON_SIZE,
        dim = dim,
    })
    local fgcolor = dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
    local label = TextWidget:new{
        text = self.text,
        face = Font:getFace("smallinfofont", ACTION_LABEL_SIZE),
        fgcolor = fgcolor,
        bold = self.active and enabled,
    }
    local indicator_h = Screen:scaleBySize(3)
    local indicator = LineWidget:new{
        dimen = Geom:new{
            w = math.max(self.width - Screen:scaleBySize(24), Screen:scaleBySize(16)),
            h = indicator_h,
        },
        background = self.active and enabled
            and Blitbuffer.COLOR_BLACK
            or Blitbuffer.COLOR_WHITE,
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
                        h = ACTION_ICON_SIZE,
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

function ShellActionButton:onTapSelect()
    if self.enabled ~= false and self.callback then
        self.callback(self.key)
    end
    return true
end

local HomeShell = InputContainer:extend{
    is_borderless = true,
    title = "",
    active_tab = "bookshelf",
    tabs = nil,
    list_page = 1,
    paginate_lists = false,
    previous_page_callback = nil,
    next_page_callback = nil,
    bottom_actions = nil,
    bottom_actions_builder = nil,
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

function HomeShell:buildBottomBar()
    local width = self.dimen.w
    local actions = self.bottom_actions or {}
    local count = math.max(#actions, 1)
    local action_width = math.floor(width / count)
    local group = HorizontalGroup:new{}

    for index = 1, #actions do
        local action = actions[index]
        local current_width = index == #actions
            and width - action_width * (#actions - 1)
            or action_width
        table.insert(group, ShellActionButton:new{
            key = action.key,
            text = action.text,
            icon = action.icon,
            active = action.active == true,
            dim = action.dim == true,
            enabled = action.enabled ~= false,
            width = current_width,
            callback = function()
                if action.callback then
                    action.callback(action.key)
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
        title_h_padding = Size.padding.large,
        button_padding = Screen:scaleBySize(11),
        left_icon = self.left_icon,
        left_icon_tap_callback = function()
            self:onLeftButtonTap()
        end,
        show_parent = self,
    }

    local body_height = math.max(
        self.dimen.h - self.title_bar:getHeight() - BOTTOM_BAR_HEIGHT,
        0
    )
    self.body_width = self.dimen.w
    self.body_height = body_height
    local content = self:buildContent()
    if type(self.bottom_actions_builder) == "function" then
        self.bottom_actions = self.bottom_actions_builder(self)
    end

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
                content,
            },
            self:buildBottomBar(),
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
