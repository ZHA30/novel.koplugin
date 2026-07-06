local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Icons = require("novel.icons")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")

local Screen = Device.screen

local BookRow = {}

local ROW_BASE_HEIGHT = 64
local RIGHT_METADATA_MAX_WIDTH_RATIO = 0.36
local SCALE_BY_SIZE = Screen:scaleBySize(1000000) * (1 / 1000000)
local ACTION_ICON_SIZE = Screen:scaleBySize(32)
local ACTION_BUTTON_PADDING = Screen:scaleBySize(6)
local ACTION_BUTTON_GAP = Screen:scaleBySize(6)
local ACTION_HIT_WIDTH = Screen:scaleBySize(60)
local ACTION_COLUMN_METADATA_GAP = Screen:scaleBySize(10)
local ACTION_COLUMN_RIGHT_PADDING = Screen:scaleBySize(10)

local function clean(value)
    value = tostring(value or "")
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function appendUniqueText(parts, seen, value)
    value = clean(value)
    if value ~= "" and not seen[value] then
        table.insert(parts, value)
        seen[value] = true
        return true
    end
    return false
end

local function lineHeight(face)
    local widget = TextBoxWidget:new{
        text = "A",
        face = face,
        width = Screen:scaleBySize(40),
    }
    local height = widget:getLineHeight()
    widget:free()
    return height
end

local function textWidth(text, face)
    local widget = TextWidget:new{
        text = text,
        face = face,
    }
    local width = widget:getSize().w
    widget:free()
    return width
end

local function textBox(text, face, width, height, options)
    options = options or {}
    return TextBoxWidget:new{
        text = text,
        face = face,
        width = math.max(Screen:scaleBySize(20), width),
        height = height,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = options.alignment or "left",
        bold = options.bold,
        fgcolor = options.fgcolor,
    }
end

local function bookTitle(entry)
    local book = entry.book or {}
    local title = clean(book.name)
    if title == "" then
        title = clean(entry.text)
    end
    if title == "" then
        title = clean(book.bookUrl)
    end
    return title
end

local function latestChapter(book)
    local latest_chapter = clean(book.latestChapterTitle)
    if latest_chapter == "" then
        latest_chapter = clean(book.latestChapter)
    end
    return latest_chapter
end

local function sourceTitle(entry)
    local book = entry.book or {}
    local title = clean(book.originName)
    if title == "" then
        title = clean(entry.source_title)
    end
    if title == "" then
        title = clean(book.origin)
    end
    return title
end

local function bookAuthor(book)
    local author = clean(book.author)
    author = author:gsub("^作者%s*[:：]%s*", "")
    return clean(author)
end

local function bookSideMetadata(entry)
    local book = entry.book or {}
    local seen = {}
    local lines = {
        bookAuthor(book),
        clean(book.updateTime),
    }

    for line_index = 1, #lines do
        if lines[line_index] ~= "" then
            seen[lines[line_index]] = true
        end
    end

    return lines, seen
end

local function hasText(lines)
    for line_index = 1, #(lines or {}) do
        if clean(lines[line_index]) ~= "" then
            return true
        end
    end
    return false
end

local function appendEntryParts(parts, seen, values)
    if type(values) ~= "table" then
        appendUniqueText(parts, seen, values)
        return
    end
    for value_index = 1, #values do
        appendUniqueText(parts, seen, values[value_index])
    end
end

local function bookSubtitle(entry, side_seen)
    local book = entry.book or {}
    local seen = side_seen or {}
    local parts = {}

    appendEntryParts(parts, seen, entry.book_subtitle_parts)
    appendUniqueText(parts, seen, latestChapter(book))
    appendUniqueText(parts, seen, book.wordCount)
    appendUniqueText(parts, seen, book.kind)
    appendUniqueText(parts, seen, sourceTitle(entry))
    appendEntryParts(parts, seen, entry.book_extra_metadata)
    return table.concat(parts, "  ")
end

local function fontSize(height, nominal, maximum)
    local font_size = math.floor(nominal * height * (1 / ROW_BASE_HEIGHT) / SCALE_BY_SIZE)
    if maximum and font_size >= maximum then
        return maximum
    end
    return font_size
end

local function buildActionColumn(entry, height, action_buttons, refs)
    if type(action_buttons) ~= "table" or #action_buttons == 0 then
        return nil, 0, 0
    end

    local row_items = {}
    local row_width = 0
    local row_height = 0

    for action_index = 1, #action_buttons do
        local action = action_buttons[action_index]
        local button = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = ACTION_BUTTON_PADDING,
            margin = 0,
            Icons.widget(action.icon, {
                size = ACTION_ICON_SIZE,
                dim = entry.dim == true,
            }),
        }
        local button_size = button:getSize()
        local slot_width = math.max(button_size.w, ACTION_HIT_WIDTH)
        local slot_x = row_width
        local slot = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = 0,
            padding = 0,
            margin = 0,
            width = slot_width,
            height = height,
            CenterContainer:new{
                dimen = Geom:new{ w = slot_width, h = height },
                button,
            },
        }
        slot.overlap_offset = { slot_x, 0 }
        row_width = row_width + slot_width
        row_height = math.max(row_height, height)
        if refs then
            refs[action_index] = {
                x = slot_x,
                y = 0,
                w = slot_width,
                h = height,
            }
        end
        table.insert(row_items, slot)
        if action_index < #action_buttons then
            row_width = row_width + ACTION_BUTTON_GAP
        end
    end

    return CenterContainer:new{
        dimen = Geom:new{ w = row_width, h = height },
        OverlapGroup:new{
            dimen = Geom:new{ w = row_width, h = row_height },
            (table.unpack or unpack)(row_items),
        },
    }, row_width, ACTION_COLUMN_RIGHT_PADDING
end

function BookRow.build(entry, args)
    args = args or {}
    local width = math.max(Screen:scaleBySize(40), tonumber(args.width) or 0)
    local height = math.max(Screen:scaleBySize(40), tonumber(args.height) or 0)
    local fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil
    local metadata_fgcolor = fgcolor
    local fontsize_info = fontSize(height, 14, 18)
    local right_face = Font:getFace("cfont", fontsize_info)
    local right_line_height = lineHeight(right_face)
    local side_lines, side_seen = bookSideMetadata(entry)
    local action_column, action_width, action_right_padding = buildActionColumn(
        entry,
        height,
        entry.action_buttons,
        args.action_refs
    )
    if args.action_refs and action_width > 0 then
        local action_origin_x = width - action_right_padding - action_width
        for action_index = 1, #args.action_refs do
            local ref = args.action_refs[action_index]
            if ref then
                ref.x = action_origin_x + ref.x
            end
        end
    end

    local wright
    local wright_width = 0
    local wright_right_padding = 0
    if hasText(side_lines) then
        local reserved_right_width = action_width + action_right_padding
        local max_right_width = math.floor((width - reserved_right_width) * RIGHT_METADATA_MAX_WIDTH_RATIO)
        for line_index = 1, #side_lines do
            wright_width = math.max(wright_width,
                textWidth(side_lines[line_index], right_face))
        end
        wright_width = math.min(max_right_width, wright_width)
        wright_width = math.max(wright_width, Screen:scaleBySize(20))
        local function rightLine(text)
            return textBox(BD.auto(text), right_face, wright_width, right_line_height, {
                alignment = "right",
                fgcolor = metadata_fgcolor,
            })
        end
        local right_items = { align = "right" }
        for line_index = 1, #side_lines do
            table.insert(right_items, rightLine(side_lines[line_index]))
        end
        wright = CenterContainer:new{
            dimen = Geom:new{ w = wright_width, h = height },
            VerticalGroup:new(right_items),
        }
        if action_column then
            wright_right_padding = ACTION_COLUMN_METADATA_GAP
        else
            wright_right_padding = Screen:scaleBySize(10)
        end
    end

    local wmain_left_padding = Screen:scaleBySize(10)
    local wmain_right_padding = Screen:scaleBySize(10)
    local wmain_width = math.max(Screen:scaleBySize(40),
        width - wmain_left_padding - wmain_right_padding
        - wright_width - wright_right_padding
        - action_width - action_right_padding)
    local fontsize_title = fontSize(height, 20, 24)
    local fontsize_metadata = fontSize(height, 18, 22)
    local title_face = Font:getFace("cfont", fontsize_title)
    local metadata_face = Font:getFace("cfont", fontsize_metadata)
    local title = BD.auto(bookTitle(entry))
    local subtitle = bookSubtitle(entry, side_seen)
    if subtitle ~= "" then
        subtitle = BD.auto(subtitle)
    end
    local title_line_height = lineHeight(title_face)
    local subtitle_height = 0
    if subtitle ~= "" then
        subtitle_height = lineHeight(metadata_face)
        if title_line_height + subtitle_height > height then
            subtitle = ""
            subtitle_height = 0
        end
    end
    local title_height = math.max(title_line_height, height - subtitle_height)

    local wtitle = TextBoxWidget:new{
        text = title,
        face = title_face,
        width = wmain_width,
        height = title_height,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = "left",
        bold = true,
        fgcolor = fgcolor,
    }
    local wsubtitle
    if subtitle ~= "" then
        wsubtitle = TextBoxWidget:new{
            text = subtitle,
            face = metadata_face,
            width = wmain_width,
            height = subtitle_height,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            fgcolor = metadata_fgcolor,
        }
    end

    local main_items = { wtitle }
    if wsubtitle then
        table.insert(main_items, wsubtitle)
    end
    local wmain = HorizontalGroup:new{
        HorizontalSpan:new{ width = wmain_left_padding },
        LeftContainer:new{
            dimen = Geom:new{ w = width, h = height },
            VerticalGroup:new(main_items),
        },
    }
    local widget = OverlapGroup:new{
        dimen = Geom:new{ w = width, h = height },
        LeftContainer:new{
            dimen = Geom:new{ w = width, h = height },
            wmain,
        },
    }
    if wright or action_column then
        local right_group = HorizontalGroup:new{}
        if wright then
            table.insert(right_group, wright)
            if wright_right_padding > 0 then
                table.insert(right_group, HorizontalSpan:new{
                    width = wright_right_padding,
                })
            end
        end
        if action_column then
            table.insert(right_group, action_column)
            if action_right_padding > 0 then
                table.insert(right_group, HorizontalSpan:new{
                    width = action_right_padding,
                })
            end
        end
        table.insert(widget, RightContainer:new{
            dimen = Geom:new{ w = width, h = height },
            right_group,
        })
    end
    return widget
end

return BookRow
