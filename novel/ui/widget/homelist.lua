local Blitbuffer = require("ffi/blitbuffer")
local BookRow = require("novel.ui.widget.bookrow")
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
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local ROW_MIN_HEIGHT = Screen:scaleBySize(60)
local ROW_BOOK_HEIGHT = Screen:scaleBySize(72)
local ROW_VERTICAL_PADDING = Screen:scaleBySize(10)
local ROW_HORIZONTAL_PADDING = Screen:scaleBySize(16)
local ROW_INDENT = Screen:scaleBySize(18)
local ROW_ICON_SIZE = Screen:scaleBySize(22)
local ROW_ICON_GAP = Screen:scaleBySize(10)
local ROW_TEXT_GAP = Screen:scaleBySize(4)
local ROW_BOOK_HORIZONTAL_PADDING = Screen:scaleBySize(10)

local HomeListItem = InputContainer:extend{
    item = nil,
    width = 0,
    callback = nil,
    hold_callback = nil,
}

local function clean(value)
    value = tostring(value or "")
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function bookRowHeight(item)
    if item.book then
        return ROW_BOOK_HEIGHT
    end
    return ROW_MIN_HEIGHT
end

local function separatorInsets(item)
    if item.book then
        return ROW_BOOK_HORIZONTAL_PADDING, ROW_BOOK_HORIZONTAL_PADDING
    end
    local left = ROW_HORIZONTAL_PADDING + (tonumber(item.indent) or 0) * ROW_INDENT
    local right = ROW_HORIZONTAL_PADDING
    return left, right
end

function HomeListItem:init()
    local item = self.item or {}
    if item.book then
        local row_height = bookRowHeight(item)
        self.dimen = Geom:new{
            x = 0,
            y = 0,
            w = self.width,
            h = row_height,
        }
        self[1] = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            margin = 0,
            BookRow.build(item, {
                width = self.width,
                height = row_height,
            }),
        }

        self.ges_events = {
            TapSelect = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
            HoldSelect = {
                GestureRange:new{
                    ges = "hold",
                    range = self.dimen,
                },
            },
        }
        return
    end

    local dim = item.dim == true
    local fgcolor = dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
    local subtitle_color = dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY_5
    local title = clean(item.title)
    local subtitle = clean(item.subtitle)
    local mandatory = clean(item.mandatory)

    local title_face = Font:getFace("cfont", 22)
    local subtitle_face = Font:getFace("smallinfofont", 18)
    local mandatory_face = Font:getFace("smallinfofont", 18)

    local mandatory_widget
    local mandatory_width = 0
    if mandatory ~= "" then
        mandatory_widget = TextWidget:new{
            text = mandatory,
            face = mandatory_face,
            fgcolor = subtitle_color,
            bold = item.bold == true,
        }
        mandatory_width = mandatory_widget:getSize().w
    end

    local icon_widget
    local icon_width = 0
    if item.icon then
        icon_widget = Icons.widget(item.icon, {
            size = ROW_ICON_SIZE,
            dim = dim,
        })
        icon_width = ROW_ICON_SIZE + ROW_ICON_GAP
    end

    local left_padding = ROW_HORIZONTAL_PADDING + (tonumber(item.indent) or 0) * ROW_INDENT
    local right_padding = ROW_HORIZONTAL_PADDING
    local text_width = math.max(
        Screen:scaleBySize(80),
        self.width - left_padding - right_padding - icon_width - mandatory_width
    )

    local title_widget = TextBoxWidget:new{
        text = title,
        face = title_face,
        width = text_width,
        height = Screen:scaleBySize(28),
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = "left",
        bold = item.bold == true,
        fgcolor = fgcolor,
    }

    local content = VerticalGroup:new{
        align = "left",
        title_widget,
    }

    if subtitle ~= "" then
        local subtitle_widget = TextBoxWidget:new{
            text = subtitle,
            face = subtitle_face,
            width = text_width,
            height = Screen:scaleBySize(22),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            fgcolor = subtitle_color,
        }
        table.insert(content, VerticalSpan:new{
            width = ROW_TEXT_GAP,
        })
        table.insert(content, subtitle_widget)
    end

    local row_height = math.max(
        bookRowHeight(item),
        content:getSize().h + 2 * ROW_VERTICAL_PADDING
    )

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = row_height,
    }

    local left_group = HorizontalGroup:new{
        HorizontalSpan:new{
            width = left_padding,
        },
    }
    if icon_widget then
        table.insert(left_group, icon_widget)
        table.insert(left_group, HorizontalSpan:new{
            width = ROW_ICON_GAP,
        })
    end
    table.insert(left_group, content)

    local row = OverlapGroup:new{
        dimen = self.dimen:copy(),
        LeftContainer:new{
            dimen = self.dimen:copy(),
            left_group,
        },
    }
    if mandatory_widget then
        table.insert(row, RightContainer:new{
            dimen = self.dimen:copy(),
            HorizontalGroup:new{
                mandatory_widget,
                HorizontalSpan:new{
                    width = right_padding,
                },
            },
        })
    end

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        row,
    }

    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = "hold",
                range = self.dimen,
            },
        },
    }
end

function HomeListItem:onTapSelect()
    if self.callback then
        self.callback()
        return true
    end
    return false
end

function HomeListItem:onHoldSelect()
    if self.hold_callback then
        self.hold_callback()
        return true
    end
    return false
end

local HomeList = {}

function HomeList.new(_, args)
    args = args or {}
    local dimen = args.dimen
    local items = args.items or {}
    local content_width = dimen.w - ScrollableContainer:getScrollbarWidth()
    local content = VerticalGroup:new{
        align = "left",
    }

    for index = 1, #items do
        local item = items[index]
        table.insert(content, HomeListItem:new{
            item = item,
            width = content_width,
            callback = item.callback,
            hold_callback = item.hold_callback,
        })
        local next_item = items[index + 1] or item
        local current_left, current_right = separatorInsets(item)
        local next_left, next_right = separatorInsets(next_item)
        local left_inset = math.max(current_left, next_left)
        local right_inset = math.max(current_right, next_right)
        local separator = LineWidget:new{
            dimen = Geom:new{
                w = math.max(
                    Screen:scaleBySize(40),
                    content_width - left_inset - right_inset
                ),
                h = Size.line.thin,
            },
            background = Blitbuffer.COLOR_GRAY_5,
        }
        table.insert(content, HorizontalGroup:new{
            HorizontalSpan:new{
                width = left_inset,
            },
            separator,
            HorizontalSpan:new{
                width = right_inset,
            },
        })
    end

    local widget = ScrollableContainer:new{
        dimen = dimen,
        show_parent = args.show_parent,
        CenterContainer:new{
            dimen = Geom:new{
                w = content_width,
                h = content:getSize().h,
            },
            content,
        },
    }
    widget.is_home_scrollable = true
    return widget
end

return HomeList
