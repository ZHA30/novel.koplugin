local _ = require("novel.i18n")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local ChapterListing = require("novel.ui.chapters.listing")
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
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local ChapterFilterDialog = ButtonDialog:extend{
    modal = true,
    filter = nil,
    on_apply = nil,
}

local FilterRow = InputContainer:extend{
    dialog = nil,
    width = nil,
    text = nil,
    value = nil,
    callback = nil,
}

local Screen = Device.screen
local DIALOG_WIDTH_FACTOR = 0.72
local DIALOG_MIN_WIDTH = Screen:scaleBySize(260)
local ICON_SIZE = Screen:scaleBySize(24)
local ROW_HEIGHT = Screen:scaleBySize(52)
local ROW_PADDING_H = 0
local ROW_ICON_GAP = Size.padding.default

local function stateIcon(value)
    if value == true then
        return "square-check"
    end
    if value == false then
        return "square-x"
    end
    return "square"
end

local function nextValue(value)
    if value == nil then
        return true
    end
    if value == true then
        return false
    end
    return nil
end

function FilterRow:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = ROW_HEIGHT,
    }

    local label_face = Font:getFace("cfont", 22)
    self.icon_slot = CenterContainer:new{
        dimen = Geom:new{
            w = ICON_SIZE,
            h = ROW_HEIGHT,
        },
        Icons.widget(stateIcon(self.value), {
            size = ICON_SIZE,
        }),
    }
    local label_width = math.max(0, self.width
        - ROW_PADDING_H
        - ICON_SIZE
        - ROW_ICON_GAP)
    local content = HorizontalGroup:new{
        HorizontalSpan:new{
            width = ROW_PADDING_H,
        },
        self.icon_slot,
        HorizontalSpan:new{
            width = ROW_ICON_GAP,
        },
        TextWidget:new{
            text = tostring(self.text or ""),
            face = label_face,
            max_width = label_width,
        },
    }

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        LeftContainer:new{
            dimen = self.dimen:copy(),
            content,
        },
    }
    self[1] = self.frame

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

function FilterRow:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

function FilterRow:onFocus()
    self.frame.invert = true
    return true
end

function FilterRow:onUnfocus()
    self.frame.invert = false
    return true
end

function FilterRow:setValue(value)
    if self.value == value then
        return
    end
    self.value = value
    if self.icon_slot then
        if self.icon_slot[1] and self.icon_slot[1].free then
            self.icon_slot[1]:free(true)
        end
        self.icon_slot[1] = Icons.widget(stateIcon(value), {
            size = ICON_SIZE,
        })
    end
    if self.dialog then
        UIManager:setDirty(self.dialog, function()
            local dimen = self.dimen
            if dimen and (dimen.x ~= 0 or dimen.y ~= 0) then
                return "ui", dimen
            end
            return "ui", self.dialog.movable.dimen
        end)
    end
end

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

local function addedWidgetWidth(width)
    -- Match ButtonDialog's title/additional-widget content width.
    local buttontable_width = width
        - 2 * Size.border.window
        - 2 * Size.padding.button
    return buttontable_width
        - 2 * (Size.padding.default + Size.margin.default)
end

local function titleSeparator(width)
    local separator = LineWidget:new{
        background = Blitbuffer.COLOR_GRAY,
        dimen = Geom:new{
            w = width,
            h = Size.line.medium,
        },
    }
    separator.not_focusable = true
    return separator
end

function ChapterFilterDialog:resetFocusLayout()
    self.layout = {}
    for row_index = 1, #(self.filter_rows or {}) do
        table.insert(self.layout, { self.filter_rows[row_index] })
    end
    for _, button_row in ipairs(self.buttontable.buttons_layout or {}) do
        table.insert(self.layout, button_row)
    end
    self.selected = { x = 1, y = 1 }
end

function ChapterFilterDialog:init()
    self.filter = ChapterListing.copyFilter(self.filter)
    self.rows = {}
    self.filter_rows = {}
    self.title = _("Filter")
    self.width = dialogWidth()
    self.buttons = {{
        {
            text = _("Clear"),
            callback = function()
                self:clear()
            end,
        },
        {
            text = _("Apply"),
            callback = function()
                self:apply()
            end,
        },
    }}
    self._added_widgets = {}

    local width = addedWidgetWidth(self.width)
    table.insert(self._added_widgets, titleSeparator(width))
    local fields = ChapterListing.filterFields()
    for field_index = 1, #fields do
        local field = fields[field_index]
        local key = field.key
        local row = FilterRow:new{
            dialog = self,
            width = width,
            parent = self,
            text = field.text,
            value = self.filter[key],
            callback = function()
                self:cycleField(key)
            end,
        }
        self.rows[key] = row
        table.insert(self.filter_rows, row)
        table.insert(self._added_widgets, row)
    end

    ButtonDialog.init(self)
    self:resetFocusLayout()
end

function ChapterFilterDialog:setField(key, value)
    self.filter = ChapterListing.copyFilter(self.filter)
    self.filter[key] = value
    local row = self.rows and self.rows[key]
    if row then
        row:setValue(value)
    end
end

function ChapterFilterDialog:cycleField(key)
    self:setField(key, nextValue(self.filter[key]))
end

function ChapterFilterDialog:clear()
    self.filter = {}
    for field_key, row in pairs(self.rows or {}) do
        self.filter[field_key] = nil
        row:setValue(nil)
    end
end

function ChapterFilterDialog:apply()
    local filter = ChapterListing.copyFilter(self.filter)
    UIManager:close(self)
    if self.on_apply then
        self.on_apply(filter)
    end
end

return ChapterFilterDialog
