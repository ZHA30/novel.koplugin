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
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen
local Input = Device.input

local DIALOG_WIDTH_FACTOR = 0.62
local DIALOG_MIN_WIDTH = Screen:scaleBySize(260)
local CELL_FONT_SIZE = 18
local CELL_HEIGHT = Screen:scaleBySize(76)
local CELL_ICON_GAP = Size.padding.small
local CELL_PADDING_H = Size.padding.large
local CELL_TEXT_LINE_HEIGHT = 0.1
local CELL_TEXT_LINES = 2
local GRID_SEPARATOR = Size.line.thin
local ICON_SIZE = Screen:scaleBySize(22)
local LAST_CELL_HEIGHT = Screen:scaleBySize(68)
local TITLE_FONT_SIZE = 20
local TITLE_PADDING_H = Screen:scaleBySize(14)
local TITLE_ROW_HEIGHT = Screen:scaleBySize(36)

local ActionCell = InputContainer:extend{
    dialog = nil,
    height = nil,
    width = nil,
    icon = nil,
    text = nil,
    enabled = true,
    callback = nil,
}

function ActionCell:init()
    local enabled = self.enabled ~= false
    local height = self.height or CELL_HEIGHT
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = height,
    }
    local fgcolor = enabled and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY
    local label_width = math.max(0, self.width - 2 * CELL_PADDING_H)
    local label_face = Font:getFace("cfont", CELL_FONT_SIZE)
    local label_line_height = math.floor(
        (1 + CELL_TEXT_LINE_HEIGHT) * label_face.size + 0.5
    )
    local label = TextBoxWidget:new{
        text = tostring(self.text or ""),
        width = label_width,
        height = label_line_height * CELL_TEXT_LINES,
        height_adjust = true,
        face = label_face,
        fgcolor = fgcolor,
        line_height = CELL_TEXT_LINE_HEIGHT,
        alignment = "center",
        alignment_strict = true,
        height_overflow_show_ellipsis = true,
    }
    local content = VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = label_width,
                h = ICON_SIZE,
            },
            Icons.widget(self.icon, {
                size = ICON_SIZE,
                dim = not enabled,
            }),
        },
        VerticalSpan:new{
            width = CELL_ICON_GAP,
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = label_width,
                h = label:getSize().h,
            },
            label,
        },
    }

    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        content,
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

function ActionCell:onTapSelect()
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

local ActionDialog = InputContainer:extend{
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

local function actionCell(dialog, width, action, height)
    return ActionCell:new{
        dialog = dialog,
        height = height,
        width = width,
        icon = action.icon,
        text = action.text,
        enabled = action.enabled,
        callback = action.callback,
    }
end

local function actionGrid(dialog, width, actions)
    local group = VerticalGroup:new{
        align = "left",
    }
    actions = actions or {}
    local left_width = math.floor((width - GRID_SEPARATOR) / 2)
    local right_width = width - GRID_SEPARATOR - left_width
    local action_index = 1
    local row_index = 1
    while action_index <= #actions do
        if row_index > 1 then
            table.insert(group, LineWidget:new{
                dimen = Geom:new{
                    w = width,
                    h = GRID_SEPARATOR,
                },
                background = Blitbuffer.COLOR_GRAY_5,
            })
        end
        if action_index == #actions then
            table.insert(group, actionCell(dialog, width, actions[action_index],
                LAST_CELL_HEIGHT))
            action_index = action_index + 1
        else
            table.insert(group, HorizontalGroup:new{
                actionCell(dialog, left_width, actions[action_index]),
                LineWidget:new{
                    dimen = Geom:new{
                        w = GRID_SEPARATOR,
                        h = CELL_HEIGHT,
                    },
                    background = Blitbuffer.COLOR_GRAY_5,
                },
                actionCell(dialog, right_width, actions[action_index + 1]),
            })
            action_index = action_index + 2
        end
        row_index = row_index + 1
    end
    return group
end

function ActionDialog:init()
    local width = dialogWidth()
    local title_width = math.max(0, width - 2 * TITLE_PADDING_H)
    local title_face = Font:getFace("cfont", TITLE_FONT_SIZE)
    local title = TextWidget:new{
        text = tostring(self.title or ""),
        face = title_face,
        bold = true,
        padding = 0,
        max_width = title_width,
    }
    local title_row = CenterContainer:new{
        dimen = Geom:new{
            w = width,
            h = TITLE_ROW_HEIGHT,
        },
        LeftContainer:new{
            dimen = Geom:new{
                w = title_width,
                h = title:getSize().h,
            },
            title,
        },
    }
    local content = VerticalGroup:new{
        align = "left",
        title_row,
        LineWidget:new{
            dimen = Geom:new{
                w = width,
                h = Size.line.thin,
            },
            background = Blitbuffer.COLOR_GRAY_5,
        },
        actionGrid(self, width, self.actions),
    }

    self.movable = MovableContainer:new{
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = Size.border.window,
            radius = Size.radius.window,
            padding = 0,
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

function ActionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function ActionDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function ActionDialog:onClose()
    UIManager:close(self)
    return true
end

function ActionDialog:onTapClose(_, ges)
    if ges and ges.pos and ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

return ActionDialog
