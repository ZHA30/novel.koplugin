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
local TEXTBOX_LINE_HEIGHT = 0.3

local HomeListItem = InputContainer:extend{
    item = nil,
    width = 0,
    row_height = nil,
    callback = nil,
    leading_action_callback = nil,
    leading_action_ref = nil,
    trailing_action_callbacks = nil,
    trailing_action_refs = nil,
    action_buttons = nil,
    action_refs = nil,
}

local function clean(value)
    value = tostring(value or "")
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function explicitBool(value, fallback)
    if value ~= nil then
        return value == true
    end
    return fallback
end

local function trailingActions(item)
    if type(item.trailing_actions) == "table" then
        return item.trailing_actions
    end
    if item.trailing_icon then
        return {
            {
                icon = item.trailing_icon,
                dim = item.trailing_icon_dim,
                callback = item.trailing_icon_callback,
            },
        }
    end
    return {}
end

local function bookRowHeight(item)
    if item.book then
        return ROW_BOOK_HEIGHT
    end
    return ROW_MIN_HEIGHT
end

local function requestedRowHeight(row_height)
    return math.max(0, math.floor(tonumber(row_height) or 0))
end

local function separatorInsets(item)
    if item.book then
        return ROW_BOOK_HORIZONTAL_PADDING, ROW_BOOK_HORIZONTAL_PADDING
    end
    local left = ROW_HORIZONTAL_PADDING + (tonumber(item.indent) or 0) * ROW_INDENT
    local right = ROW_HORIZONTAL_PADDING
    return left, right
end

local function textboxHeight(face, requested_height)
    local line_height = math.floor(
        (1 + TEXTBOX_LINE_HEIGHT) * face.size + 0.5
    )
    return math.max(requested_height, line_height)
end

function HomeListItem:init()
    local item = self.item or {}
    if item.book then
        local row_height = math.max(
            bookRowHeight(item),
            requestedRowHeight(self.row_height)
        )
        self.action_buttons = item.action_buttons
        self.action_refs = {}
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
                action_refs = self.action_refs,
            }),
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
            dim = explicitBool(item.icon_dim, dim),
        })
        icon_width = ROW_ICON_SIZE + ROW_ICON_GAP
        if type(item.icon_callback) == "function" then
            self.leading_action_callback = item.icon_callback
        end
    end

    local trailing_specs = trailingActions(item)
    local trailing_icons = {}
    local trailing_actions_width = 0
    self.trailing_action_callbacks = {}
    self.trailing_action_refs = {}
    for action_index = 1, #trailing_specs do
        local action = trailing_specs[action_index] or {}
        if action.icon then
            table.insert(trailing_icons, {
                icon = Icons.widget(action.icon, {
                    size = ROW_ICON_SIZE,
                    dim = explicitBool(action.dim, dim),
                }),
                callback = action.callback,
            })
            trailing_actions_width = trailing_actions_width + ROW_ICON_SIZE
            if #trailing_icons > 1 then
                trailing_actions_width = trailing_actions_width + ROW_ICON_GAP
            end
        end
    end

    local right_content_width = mandatory_width
    if mandatory_widget and #trailing_icons > 0 then
        right_content_width = right_content_width + ROW_ICON_GAP
    end
    if #trailing_icons > 0 then
        right_content_width = right_content_width + trailing_actions_width
    end

    local left_padding = ROW_HORIZONTAL_PADDING + (tonumber(item.indent) or 0) * ROW_INDENT
    local right_padding = ROW_HORIZONTAL_PADDING
    local text_width = math.max(
        Screen:scaleBySize(80),
        self.width - left_padding - right_padding - icon_width - right_content_width
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
        content:getSize().h + 2 * ROW_VERTICAL_PADDING,
        requestedRowHeight(self.row_height)
    )

    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = row_height,
    }
    if self.leading_action_callback then
        self.leading_action_ref = {
            x = left_padding,
            y = 0,
            w = icon_width,
            h = row_height,
        }
    end

    local trailing_group
    if #trailing_icons > 0 then
        trailing_group = HorizontalGroup:new{}
        local trailing_x = self.width - right_padding - trailing_actions_width
        for action_index = 1, #trailing_icons do
            local action = trailing_icons[action_index]
            if type(action.callback) == "function" then
                table.insert(self.trailing_action_callbacks, action.callback)
                table.insert(self.trailing_action_refs, {
                    x = trailing_x,
                    y = 0,
                    w = ROW_ICON_SIZE + (action_index == #trailing_icons
                        and right_padding or ROW_ICON_GAP),
                    h = row_height,
                })
            end
            table.insert(trailing_group, CenterContainer:new{
                dimen = Geom:new{
                    w = ROW_ICON_SIZE,
                    h = row_height,
                },
                action.icon,
            })
            trailing_x = trailing_x + ROW_ICON_SIZE
            if action_index < #trailing_icons then
                table.insert(trailing_group, HorizontalSpan:new{
                    width = ROW_ICON_GAP,
                })
                trailing_x = trailing_x + ROW_ICON_GAP
            end
        end
    end

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
    if mandatory_widget or trailing_group then
        local right_group = HorizontalGroup:new{}
        if mandatory_widget then
            table.insert(right_group, mandatory_widget)
        end
        if mandatory_widget and trailing_group then
            table.insert(right_group, HorizontalSpan:new{
                width = ROW_ICON_GAP,
            })
        end
        if trailing_group then
            table.insert(right_group, trailing_group)
        end
        table.insert(right_group, HorizontalSpan:new{
            width = right_padding,
        })
        table.insert(row, RightContainer:new{
            dimen = self.dimen:copy(),
            right_group,
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
                range = function()
                    return self.dimen
                end,
            },
        },
    }
end

function HomeListItem:getActionAt(ges)
    if not ges or not ges.pos or not self.dimen or type(self.action_buttons) ~= "table" then
        return nil
    end
    local local_x = ges.pos.x - self.dimen.x
    local local_y = ges.pos.y - self.dimen.y
    for action_index = 1, #self.action_buttons do
        local action = self.action_buttons[action_index]
        local ref = self.action_refs and self.action_refs[action_index]
        if ref
            and local_x >= ref.x and local_x < ref.x + ref.w
            and local_y >= ref.y and local_y < ref.y + ref.h then
            return action
        end
    end
    return nil
end

function HomeListItem:getLeadingActionAt(ges)
    local ref = self.leading_action_ref
    if not ges or not ges.pos or not self.dimen or not ref then
        return nil
    end
    local local_x = ges.pos.x - self.dimen.x
    local local_y = ges.pos.y - self.dimen.y
    if local_x >= ref.x and local_x < ref.x + ref.w
        and local_y >= ref.y and local_y < ref.y + ref.h then
        return self.leading_action_callback
    end
    return nil
end

function HomeListItem:getTrailingActionAt(ges)
    if not ges or not ges.pos or not self.dimen
        or type(self.trailing_action_refs) ~= "table" then
        return nil
    end
    local local_x = ges.pos.x - self.dimen.x
    local local_y = ges.pos.y - self.dimen.y
    for action_index = 1, #self.trailing_action_refs do
        local ref = self.trailing_action_refs[action_index]
        if local_x >= ref.x and local_x < ref.x + ref.w
            and local_y >= ref.y and local_y < ref.y + ref.h then
            return self.trailing_action_callbacks
                and self.trailing_action_callbacks[action_index]
        end
    end
    return nil
end

function HomeListItem:onTapSelect(_, ges)
    local leading_callback = self:getLeadingActionAt(ges)
    if leading_callback then
        leading_callback()
        return true
    end
    local trailing_callback = self:getTrailingActionAt(ges)
    if trailing_callback then
        trailing_callback()
        return true
    end
    local action = self:getActionAt(ges)
    if action and type(action.callback) == "function" then
        action.callback()
        return true
    end
    if self.callback then
        self.callback()
        return true
    end
    return false
end

local HomeList = {}

local function appendEntries(content, entries)
    for index = 1, #entries do
        local entry = entries[index]
        table.insert(content, entry.row)
        if entry.separator then
            table.insert(content, entry.separator)
        end
    end
end

local function separatorFor(item, next_item, content_width)
    local current_left, current_right = separatorInsets(item)
    local next_left, next_right = separatorInsets(next_item or item)
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
    return HorizontalGroup:new{
        HorizontalSpan:new{
            width = left_inset,
        },
        separator,
        HorizontalSpan:new{
            width = right_inset,
        },
    }
end

local function rowHeightFor(item)
    item = item or {}
    if item.book then
        return bookRowHeight(item)
    end

    local title_height = textboxHeight(
        Font:getFace("cfont", 22),
        Screen:scaleBySize(28)
    )
    local subtitle_height = 0
    if clean(item.subtitle) ~= "" then
        subtitle_height = ROW_TEXT_GAP + textboxHeight(
            Font:getFace("smallinfofont", 18),
            Screen:scaleBySize(22)
        )
    end
    return math.max(
        bookRowHeight(item),
        title_height + subtitle_height + 2 * ROW_VERTICAL_PADDING
    )
end

local function entryHeightFor(item)
    return rowHeightFor(item) + Size.line.thin
end

local function buildEntries(get_item, item_count, content_width, start_index,
    end_index, row_height_at, omit_last_separator)
    local entries = {}
    start_index = math.max(1, tonumber(start_index) or 1)
    end_index = math.min(item_count, tonumber(end_index) or item_count)
    for index = start_index, end_index do
        local item = get_item(index) or {}
        local row = HomeListItem:new{
            item = item,
            width = content_width,
            row_height = row_height_at and row_height_at(index),
            callback = item.callback,
        }
        local separator
        if index < end_index or not omit_last_separator then
            separator = separatorFor(item, get_item(index + 1), content_width)
        end
        table.insert(entries, {
            row = row,
            separator = separator,
            height = row:getSize().h + (separator and separator:getSize().h or 0),
        })
    end
    return entries
end

local normalizedPage

local function maxEntryHeight(get_item, item_count)
    local entry_height = 0
    for index = 1, item_count do
        entry_height = math.max(entry_height, entryHeightFor(get_item(index)))
    end
    return math.max(1, entry_height)
end

local function fixedPageLayout(height, min_entry_height)
    height = math.max(1, tonumber(height) or 1)
    min_entry_height = math.max(1, tonumber(min_entry_height) or 1)
    local min_row_height = math.max(1, min_entry_height - Size.line.thin)
    local items_per_page = math.max(1,
        math.floor((height + Size.line.thin) / min_entry_height))
    local separator_height = math.max(0, items_per_page - 1) * Size.line.thin
    local rows_height = math.max(items_per_page, height - separator_height)
    local row_height = math.max(
        min_row_height,
        math.floor(rows_height / items_per_page)
    )
    local remainder = math.max(0, rows_height - row_height * items_per_page)
    return {
        items_per_page = items_per_page,
        row_height = row_height,
        remainder = remainder,
    }
end

local function fixedPage(item_count, page, layout)
    local items_per_page = layout.items_per_page
    local total_pages = math.max(1, math.ceil(item_count / items_per_page))
    local current_page = normalizedPage(page, total_pages)
    if item_count == 0 then
        return {
            first = 1,
            last = 0,
        }, current_page, total_pages
    end
    local first = (current_page - 1) * items_per_page + 1
    return {
        first = first,
        last = math.min(item_count, first + items_per_page - 1),
    }, current_page, total_pages
end

local function pageForItemAnchor(item_anchor, item_count, layout)
    local anchor = tonumber(item_anchor)
    if not anchor or item_count <= 0 then
        return nil
    end
    anchor = math.floor(anchor)
    if anchor < 1 then
        anchor = 1
    elseif anchor > item_count then
        anchor = item_count
    end
    return math.ceil(anchor / layout.items_per_page)
end

local function pageItemCount(page)
    local first = tonumber(page and page.first) or 1
    local last = tonumber(page and page.last) or 0
    return math.max(0, last - first + 1)
end

local function fixedRowHeightAt(layout, page)
    if not layout or pageItemCount(page) < layout.items_per_page then
        return nil
    end
    local first = tonumber(page and page.first) or 1
    return function(index)
        local row = index - first + 1
        local row_height = layout.row_height
        if row > 0 and row <= layout.remainder then
            row_height = row_height + 1
        end
        return row_height
    end
end

normalizedPage = function(page, total_pages)
    total_pages = math.max(1, tonumber(total_pages) or 1)
    if page == "last" then
        return total_pages
    end
    page = math.floor(tonumber(page) or 1)
    if page < 1 then
        return 1
    end
    if page > total_pages then
        return total_pages
    end
    return page
end

local function isNextPageSwipe(direction)
    return direction == "north"
        or direction == "west"
        or direction == "northeast"
        or direction == "northwest"
end

local function isPreviousPageSwipe(direction)
    return direction == "south"
        or direction == "east"
        or direction == "southeast"
        or direction == "southwest"
end

function HomeList.new(_, args)
    args = args or {}
    local dimen = args.dimen
    local items = args.items or {}
    local item_count = tonumber(args.item_count) or #items
    local get_item = type(args.item_at) == "function"
        and args.item_at
        or function(index)
            return items[index]
        end
    local paginate = args.paginate == true
    local content_width = paginate
        and dimen.w
        or dimen.w - ScrollableContainer:getScrollbarWidth()
    local content = VerticalGroup:new{
        align = "left",
    }

    if not paginate then
        local entries = buildEntries(get_item, item_count, content_width)
        appendEntries(content, entries)
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

    local fixed_item
    if args.fixed_item == true then
        fixed_item = {}
    elseif type(args.fixed_item) == "table" then
        fixed_item = args.fixed_item
    end
    local page, current_page, total_pages
    local fixed_layout
    if fixed_item then
        fixed_layout = fixedPageLayout(dimen.h, entryHeightFor(fixed_item))
    else
        fixed_layout = fixedPageLayout(dimen.h,
            maxEntryHeight(get_item, item_count))
    end
    local requested_page = pageForItemAnchor(args.item_anchor, item_count,
        fixed_layout) or args.page
    page, current_page, total_pages = fixedPage(item_count, requested_page,
        fixed_layout)
    local row_height_at = fixedRowHeightAt(fixed_layout, page)
    local entries = buildEntries(get_item, item_count, content_width,
        page.first, page.last, row_height_at, row_height_at ~= nil)
    appendEntries(content, entries)

    if type(args.on_page_info) == "function" then
        args.on_page_info({
            current_page = current_page,
            total_pages = total_pages,
            total_items = item_count,
            first = page.first,
            last = page.last,
            has_previous = current_page > 1,
            has_next = current_page < total_pages,
        })
    end

    local widget = InputContainer:new{
        dimen = Geom:new{
            w = dimen.w,
            h = dimen.h,
        },
        content,
    }
    if Device:isTouchDevice() then
        widget.ges_events = {
            Swipe = {
                GestureRange:new{
                    ges = "swipe",
                    range = function()
                        return widget.dimen
                    end,
                },
            },
        }
        widget.onSwipe = function(_, ...)
            local ges = select(2, ...)
            if not ges then
                return false
            end
            if isNextPageSwipe(ges.direction)
                and type(args.next_page_callback) == "function" then
                return args.next_page_callback() == true
            end
            if isPreviousPageSwipe(ges.direction)
                and type(args.previous_page_callback) == "function" then
                return args.previous_page_callback() == true
            end
            return false
        end
    end
    widget.is_home_paginated = true
    return widget
end

return HomeList
