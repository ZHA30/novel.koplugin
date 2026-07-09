local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Icons = require("novel.icons")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen
local Input = Device.input

local DIALOG_WIDTH_FACTOR = 0.68
local DIALOG_MIN_WIDTH = Screen:scaleBySize(260)
local ICON_SIZE = Screen:scaleBySize(24)
local ROW_HEIGHT = Screen:scaleBySize(60)
local ROW_PADDING_H = Size.padding.default
local ROW_ICON_SLOT = Screen:scaleBySize(32)
local ROW_ICON_GAP = Size.padding.large
local TITLE_FONT_SIZE = 22
local TITLE_LINE_HEIGHT = 0.1
local TITLE_LINES = 2
local TITLE_BOTTOM_GAP = Size.padding.default
local SEPARATOR_BOTTOM_GAP = Size.padding.small

local ActionRow = InputContainer:extend{
    dialog = nil,
    width = nil,
    icon = nil,
    text = nil,
    enabled = true,
    callback = nil,
}

function ActionRow:init()
    local enabled = self.enabled ~= false
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = ROW_HEIGHT,
    }
    local fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local label_width = math.max(0, self.width
        - 2 * ROW_PADDING_H
        - ROW_ICON_SLOT
        - ROW_ICON_GAP)
    local content = HorizontalGroup:new{
        HorizontalSpan:new{
            width = ROW_PADDING_H,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = ROW_ICON_SLOT,
                h = ROW_HEIGHT,
            },
            Icons.widget(self.icon, {
                size = ICON_SIZE,
                dim = not enabled,
            }),
        },
        HorizontalSpan:new{
            width = ROW_ICON_GAP,
        },
        LeftContainer:new{
            dimen = Geom:new{
                w = label_width,
                h = ROW_HEIGHT,
            },
            TextBoxWidget:new{
                text = tostring(self.text or ""),
                width = label_width,
                face = Font:getFace("cfont", 22),
                fgcolor = fgcolor,
                alignment = "left",
                height_overflow_show_ellipsis = true,
            },
        },
    }

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        LeftContainer:new{
            dimen = self.dimen:copy(),
            content,
        },
    }

    if Device:isTouchDevice() then
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
    end
end

function ActionRow:onTapSelect()
    if self.enabled == false then
        return true
    end
    if self.dialog then
        self.dialog:onClose()
    end
    if self.callback then
        self.callback()
    end
    return true
end

local ChapterActionDialog = InputContainer:extend{
    modal = true,
    title = nil,
    actions = nil,
}

local function dialogWidth()
    local screen_max_width = math.max(
        DIALOG_MIN_WIDTH,
        Screen:getWidth() - 2 * Size.padding.fullscreen
    )
    local target_width = math.floor(
        math.min(Screen:getWidth(), Screen:getHeight()) * DIALOG_WIDTH_FACTOR
    )
    return math.min(screen_max_width, math.max(DIALOG_MIN_WIDTH, target_width))
end

local function actionRows(dialog, width, actions)
    local group = VerticalGroup:new{
        align = "left",
    }
    for action_index = 1, #(actions or {}) do
        if action_index > 1 then
            table.insert(group, LineWidget:new{
                dimen = Geom:new{
                    w = width,
                    h = Size.line.thin,
                },
                background = Blitbuffer.COLOR_GRAY_5,
            })
        end
        table.insert(group, ActionRow:new{
            dialog = dialog,
            width = width,
            icon = actions[action_index].icon,
            text = actions[action_index].text,
            enabled = actions[action_index].enabled,
            callback = actions[action_index].callback,
        })
    end
    return group
end

function ChapterActionDialog:init()
    local width = dialogWidth()
    local title_face = Font:getFace("cfont", TITLE_FONT_SIZE)
    local title_line_height_px = math.floor(
        (1 + TITLE_LINE_HEIGHT) * title_face.size + 0.5
    )
    local title = TextBoxWidget:new{
        text = tostring(self.title or ""),
        width = width,
        height = title_line_height_px * TITLE_LINES,
        face = title_face,
        bold = true,
        line_height = TITLE_LINE_HEIGHT,
        alignment = "left",
        height_overflow_show_ellipsis = true,
    }
    local content = VerticalGroup:new{
        align = "left",
        title,
        VerticalSpan:new{
            width = TITLE_BOTTOM_GAP,
        },
        LineWidget:new{
            dimen = Geom:new{
                w = width,
                h = Size.line.thin,
            },
            background = Blitbuffer.COLOR_GRAY_5,
        },
        VerticalSpan:new{
            width = SEPARATOR_BOTTOM_GAP,
        },
        actionRows(self, width, self.actions),
    }

    self.movable = MovableContainer:new{
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = Size.padding.large,
            content,
        },
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0,
                    y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            },
        }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end
end

function ChapterActionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function ChapterActionDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function ChapterActionDialog:onClose()
    UIManager:close(self)
    return true
end

function ChapterActionDialog:onTapClose(_, ges)
    if ges and ges.pos and ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

return ChapterActionDialog
