local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
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
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local BOTTOM_BAR_HEIGHT = Screen:scaleBySize(72)
local BOTTOM_ICON_SIZE = Screen:scaleBySize(24)
local BOTTOM_LABEL_SIZE = 14
local BOTTOM_INDICATOR_SIZE = Screen:scaleBySize(3)
local BOTTOM_INDICATOR_INSET = Screen:scaleBySize(12)
local SIDE_BAR_WIDTH = Screen:scaleBySize(84)
local SIDE_ACTION_HEIGHT = Screen:scaleBySize(80)
local SIDE_ICON_SIZE = Screen:scaleBySize(30)
local SIDE_LABEL_SIZE = 15
local SIDE_INDICATOR_SIZE = Screen:scaleBySize(4)
local SIDE_INDICATOR_INSET = Screen:scaleBySize(14)
local ACTION_ICON_GAP = Screen:scaleBySize(4)
local ACTION_TOP_GAP = Screen:scaleBySize(10)
local BOTTOM_METRICS = {
    icon_size = BOTTOM_ICON_SIZE,
    label_size = BOTTOM_LABEL_SIZE,
    indicator_size = BOTTOM_INDICATOR_SIZE,
    indicator_inset = BOTTOM_INDICATOR_INSET,
}
local SIDE_METRICS = {
    icon_size = SIDE_ICON_SIZE,
    label_size = SIDE_LABEL_SIZE,
    indicator_size = SIDE_INDICATOR_SIZE,
    indicator_inset = SIDE_INDICATOR_INSET,
}

local function isSide(placement)
    return placement == "left" or placement == "right"
end

local function actionMetrics(placement)
    if isSide(placement) then
        return SIDE_METRICS
    end
    return BOTTOM_METRICS
end

local ShellActionButton = InputContainer:extend{
    key = nil,
    text = "",
    icon = nil,
    active = false,
    dim = false,
    enabled = true,
    width = 0,
    height = 0,
    placement = "bottom",
    callback = nil,
    hold_callback = nil,
}

local function actionContent(button, content_width, enabled, dim)
    local metrics = actionMetrics(button.placement)
    local icon = Icons.widget(button.icon, {
        size = metrics.icon_size,
        dim = dim,
    })
    local label = TextBoxWidget:new{
        text = button.text,
        face = Font:getFace("smallinfofont", metrics.label_size),
        fgcolor = dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK,
        bold = button.active and enabled,
        width = math.max(content_width - Screen:scaleBySize(8), 1),
        line_height = 0.1,
        alignment = "center",
        alignment_strict = true,
    }
    return VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = content_width,
                h = metrics.icon_size,
            },
            icon,
        },
        VerticalSpan:new{
            width = ACTION_ICON_GAP,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = content_width,
                h = label:getSize().h,
            },
            label,
        },
    }
end

local function horizontalIndicator(button)
    local metrics = actionMetrics(button.placement)
    return LineWidget:new{
        dimen = Geom:new{
            w = math.max(
                button.width - 2 * metrics.indicator_inset,
                Screen:scaleBySize(16)
            ),
            h = metrics.indicator_size,
        },
        background = button.active and button.enabled ~= false
            and Blitbuffer.COLOR_BLACK
            or Blitbuffer.COLOR_WHITE,
    }
end

local function verticalIndicator(button)
    local metrics = actionMetrics(button.placement)
    return LineWidget:new{
        dimen = Geom:new{
            w = metrics.indicator_size,
            h = math.max(
                button.height - 2 * metrics.indicator_inset,
                Screen:scaleBySize(16)
            ),
        },
        background = button.active and button.enabled ~= false
            and Blitbuffer.COLOR_BLACK
            or Blitbuffer.COLOR_WHITE,
    }
end

local function bottomButton(button, enabled, dim)
    local metrics = actionMetrics(button.placement)
    local content = actionContent(button, button.width, enabled, dim)
    return CenterContainer:new{
        dimen = button.dimen:copy(),
        VerticalGroup:new{
            align = "center",
            CenterContainer:new{
                dimen = Geom:new{
                    w = button.width,
                    h = metrics.indicator_size,
                },
                horizontalIndicator(button),
            },
            VerticalSpan:new{
                width = ACTION_TOP_GAP,
            },
            content,
        },
    }
end

local function sideButton(button, enabled, dim)
    local metrics = actionMetrics(button.placement)
    local content = CenterContainer:new{
        dimen = button.dimen:copy(),
        actionContent(button, button.width, enabled, dim),
    }
    local indicator = CenterContainer:new{
        dimen = Geom:new{
            w = metrics.indicator_size,
            h = button.height,
        },
        verticalIndicator(button),
    }
    local indicator_area = button.placement == "left"
        and RightContainer:new{
            dimen = button.dimen:copy(),
            indicator,
        }
        or LeftContainer:new{
            dimen = button.dimen:copy(),
            indicator,
        }
    return OverlapGroup:new{
        dimen = button.dimen:copy(),
        allow_mirroring = false,
        content,
        indicator_area,
    }
end

function ShellActionButton:init()
    local enabled = self.enabled ~= false
    local dim = not enabled or self.dim == true
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
        isSide(self.placement)
            and sideButton(self, enabled, dim)
            or bottomButton(self, enabled, dim),
    }
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    return self.dimen
                end,
            },
        },
    }
    if self.hold_callback then
        self.ges_events.HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = function()
                    return self.dimen
                end,
            },
        }
    end
end

function ShellActionButton:onTapSelect()
    if self.enabled ~= false and self.callback then
        self.callback(self.key)
    end
    return true
end

function ShellActionButton:onHoldSelect()
    if self.enabled ~= false and self.hold_callback then
        self.hold_callback(self.key)
    end
    return true
end

local ShellActionBar = InputContainer:extend{
    placement = "bottom",
    actions = nil,
    width = 0,
    height = 0,
}

function ShellActionBar.thickness(placement)
    local bar_size = isSide(placement) and SIDE_BAR_WIDTH or BOTTOM_BAR_HEIGHT
    return bar_size + Size.line.thin
end

local function actionCallback(action)
    return function()
        if action.callback then
            action.callback(action.key)
        end
    end
end

local function holdCallback(action)
    if not action.hold_callback then
        return nil
    end
    return function()
        action.hold_callback(action.key)
    end
end

function ShellActionBar:buildBottom()
    local actions = self.actions or {}
    local count = math.max(#actions, 1)
    local action_width = math.floor(self.width / count)
    local group = HorizontalGroup:new{}
    for index = 1, #actions do
        local action = actions[index]
        local current_width = index == #actions
            and self.width - action_width * (#actions - 1)
            or action_width
        table.insert(group, ShellActionButton:new{
            key = action.key,
            text = action.text,
            icon = action.icon,
            active = action.active == true,
            dim = action.dim == true,
            enabled = action.enabled ~= false,
            width = current_width,
            height = BOTTOM_BAR_HEIGHT,
            placement = self.placement,
            callback = actionCallback(action),
            hold_callback = holdCallback(action),
        })
    end
    return VerticalGroup:new{
        align = "left",
        LineWidget:new{
            dimen = Geom:new{
                w = self.width,
                h = Size.line.thin,
            },
            background = Blitbuffer.COLOR_DARK_GRAY,
        },
        group,
    }
end

function ShellActionBar:buildSide()
    local actions = self.actions or {}
    local count = math.max(#actions, 1)
    local action_height = math.min(
        SIDE_ACTION_HEIGHT,
        math.floor(self.height / count)
    )
    local group = VerticalGroup:new{
        align = "left",
    }
    for index = 1, #actions do
        local action = actions[index]
        table.insert(group, ShellActionButton:new{
            key = action.key,
            text = action.text,
            icon = action.icon,
            active = action.active == true,
            dim = action.dim == true,
            enabled = action.enabled ~= false,
            width = SIDE_BAR_WIDTH,
            height = action_height,
            placement = self.placement,
            callback = actionCallback(action),
            hold_callback = holdCallback(action),
        })
    end
    local buttons = BottomContainer:new{
        dimen = Geom:new{
            w = SIDE_BAR_WIDTH,
            h = self.height,
        },
        group,
    }
    local separator = LineWidget:new{
        dimen = Geom:new{
            w = Size.line.thin,
            h = self.height,
        },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }
    if self.placement == "left" then
        return HorizontalGroup:new{
            allow_mirroring = false,
            buttons,
            separator,
        }
    end
    return HorizontalGroup:new{
        allow_mirroring = false,
        separator,
        buttons,
    }
end

function ShellActionBar:init()
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
        isSide(self.placement) and self:buildSide() or self:buildBottom(),
    }
end

return ShellActionBar
