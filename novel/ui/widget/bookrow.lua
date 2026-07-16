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
local RenderText = require("ui/rendertext")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")

local Screen = Device.screen

local BookRow = {}

local ROW_BASE_HEIGHT = 64
local RIGHT_METADATA_MAX_WIDTH_RATIO = 0.36
local MAIN_CONTENT_MIN_WIDTH_RATIO = 0.65
local RIGHT_METADATA_MIN_WIDTH = Screen:scaleBySize(100)
local SCALE_BY_SIZE = Screen:scaleBySize(1000000) * (1 / 1000000)
local ACTION_ICON_SIZE = Screen:scaleBySize(32)
local ACTION_BUTTON_PADDING = Screen:scaleBySize(6)
local ACTION_BUTTON_GAP = Screen:scaleBySize(6)
local ACTION_HIT_WIDTH = Screen:scaleBySize(60)
local ACTION_COLUMN_METADATA_GAP = Screen:scaleBySize(10)
local ACTION_COLUMN_OUTER_PADDING = Screen:scaleBySize(10)
local CONTENT_OUTER_PADDING = Screen:scaleBySize(10)
local CONTENT_METADATA_GAP = Screen:scaleBySize(10)
local SUBTITLE_ICON_TEXT_GAP = Screen:scaleBySize(4)
local SUBTITLE_SEGMENT_GAP = Screen:scaleBySize(12)

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

local function textWidth(text, face, bold)
    local widget = TextWidget:new{
        text = text,
        face = face,
        bold = bold,
    }
    local width = widget:getSize().w
    widget:free()
    return width
end

local function minimumTextBoxWidth(face, bold)
    return math.max(
        Screen:scaleBySize(20),
        RenderText:getEllipsisWidth(face, bold) + 1
    )
end

local function textBox(text, face, width, height, options)
    options = options or {}
    return TextBoxWidget:new{
        text = text,
        face = face,
        width = math.max(minimumTextBoxWidth(face, options.bold), width),
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
    if entry.book_subtitle_parts_only == true then
        return table.concat(parts, "  ")
    end
    appendUniqueText(parts, seen, latestChapter(book))
    appendUniqueText(parts, seen, book.wordCount)
    appendUniqueText(parts, seen, book.kind)
    appendUniqueText(parts, seen, sourceTitle(entry))
    appendEntryParts(parts, seen, entry.book_extra_metadata)
    return table.concat(parts, "  ")
end

local function subtitleSegments(entry)
    local normalized = {}
    if type(entry.book_subtitle_segments) ~= "table" then
        return nil
    end
    for segment_index = 1, #entry.book_subtitle_segments do
        local segment = entry.book_subtitle_segments[segment_index] or {}
        local icon = clean(segment.icon)
        local text = clean(segment.text)
        if icon ~= "" or text ~= "" then
            table.insert(normalized, {
                icon = icon,
                text = text,
            })
        end
    end
    if #normalized == 0 then
        return nil
    end
    return normalized
end

local function subtitleIconSize(height)
    return math.max(1, math.floor(tonumber(height) or 0))
end

local function iconTextSegment(segment, face, width, height, options)
    options = options or {}
    local items = {}
    local used_width = 0
    local icon_size = subtitleIconSize(height)
    if segment.icon ~= "" then
        table.insert(items, CenterContainer:new{
            dimen = Geom:new{
                w = icon_size,
                h = height,
            },
            Icons.widget(segment.icon, {
                size = icon_size,
                dim = options.dim,
            }),
        })
        used_width = used_width + icon_size
        if segment.text ~= "" then
            table.insert(items, HorizontalSpan:new{
                width = SUBTITLE_ICON_TEXT_GAP,
            })
            used_width = used_width + SUBTITLE_ICON_TEXT_GAP
        end
    end
    if segment.text ~= "" then
        local text_width = math.max(
            Screen:scaleBySize(20),
            width - used_width
        )
        table.insert(items, textBox(BD.auto(segment.text), face,
            text_width, height, {
                fgcolor = options.fgcolor,
            }))
    end
    return HorizontalGroup:new(items)
end

local function fixedSegmentWidth(segment, face, height)
    local width = 0
    if segment.icon ~= "" then
        width = width + subtitleIconSize(height)
        if segment.text ~= "" then
            width = width + SUBTITLE_ICON_TEXT_GAP
        end
    end
    if segment.text ~= "" then
        width = width + math.max(
            minimumTextBoxWidth(face),
            textWidth(segment.text, face)
        )
    end
    return width
end

local function buildIconSubtitle(segments, face, width, height, options)
    local fixed_width = 0
    local last_index = #segments
    for segment_index = 1, last_index - 1 do
        fixed_width = fixed_width + fixedSegmentWidth(
            segments[segment_index],
            face,
            height
        ) + SUBTITLE_SEGMENT_GAP
    end
    local last_width = math.max(
        minimumTextBoxWidth(face),
        width - fixed_width
    )
    local items = {}
    for segment_index = 1, last_index do
        local segment_width
        if segment_index == last_index then
            segment_width = last_width
        else
            segment_width = fixedSegmentWidth(
                segments[segment_index],
                face,
                height
            )
        end
        table.insert(items, iconTextSegment(
            segments[segment_index],
            face,
            segment_width,
            height,
            options
        ))
        if segment_index < last_index then
            table.insert(items, HorizontalSpan:new{
                width = SUBTITLE_SEGMENT_GAP,
            })
        end
    end
    return LeftContainer:new{
        dimen = Geom:new{
            w = width,
            h = height,
        },
        HorizontalGroup:new(items),
    }
end

local function subtitleContentWidth(segments, text, face, height)
    -- Keep the subtitle's full content in the main column when the row can
    -- accommodate it; the side metadata is the flexible, truncated column.
    if segments then
        local width = 0
        for segment_index = 1, #segments do
            width = width + fixedSegmentWidth(
                segments[segment_index],
                face,
                height
            )
            if segment_index < #segments then
                width = width + SUBTITLE_SEGMENT_GAP
            end
        end
        return width
    end
    if text ~= "" then
        return textWidth(text, face)
    end
    return 0
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
    }, row_width, ACTION_COLUMN_OUTER_PADDING
end

function BookRow.build(entry, args)
    args = args or {}
    local width = math.max(Screen:scaleBySize(40), tonumber(args.width) or 0)
    local height = math.max(Screen:scaleBySize(40), tonumber(args.height) or 0)
    local actions_on_left = args.action_side == "left"
    local fgcolor = entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil
    local metadata_fgcolor = fgcolor
    local fontsize_info = fontSize(height, 14, 18)
    local right_face = Font:getFace("cfont", fontsize_info)
    local right_line_height = lineHeight(right_face)
    local side_lines, side_seen = bookSideMetadata(entry)
    local fontsize_title = fontSize(height, 20, 24)
    local fontsize_metadata = fontSize(height, 18, 22)
    local title_face = Font:getFace("cfont", fontsize_title)
    local metadata_face = Font:getFace("cfont", fontsize_metadata)
    local title = BD.auto(bookTitle(entry))
    local subtitle_segments = subtitleSegments(entry)
    local subtitle = subtitle_segments and "" or bookSubtitle(entry, side_seen)
    if not subtitle_segments and subtitle ~= "" then
        subtitle = BD.auto(subtitle)
    end
    local title_line_height = lineHeight(title_face)
    local subtitle_height = 0
    if subtitle_segments or subtitle ~= "" then
        subtitle_height = lineHeight(metadata_face)
        if title_line_height + subtitle_height > height then
            subtitle_segments = nil
            subtitle = ""
            subtitle_height = 0
        end
    end
    local action_column, action_width, action_outer_padding = buildActionColumn(
        entry,
        height,
        entry.action_buttons,
        args.action_refs
    )
    if args.action_refs and action_width > 0 then
        local action_origin_x = actions_on_left
            and action_outer_padding
            or width - action_outer_padding - action_width
        for action_index = 1, #args.action_refs do
            local ref = args.action_refs[action_index]
            if ref then
                ref.x = action_origin_x + ref.x
            end
        end
    end

    local left_outer_padding = actions_on_left and action_column
        and action_outer_padding or CONTENT_OUTER_PADDING
    local left_action_gap = actions_on_left and action_column
        and ACTION_COLUMN_METADATA_GAP or 0
    local right_outer_padding = not actions_on_left and action_column
        and action_outer_padding or CONTENT_OUTER_PADDING
    local right_action_gap = not actions_on_left and action_column
        and ACTION_COLUMN_METADATA_GAP or 0
    local main_width_without_metadata = width - left_outer_padding
        - left_action_gap - right_action_gap - right_outer_padding
        - (actions_on_left and action_width or 0)
        - (not actions_on_left and action_width or 0)

    local wright
    local wright_width = 0
    if hasText(side_lines) then
        local reserved_action_width = action_width + action_outer_padding
        local subtitle_width = subtitleContentWidth(
            subtitle_segments,
            subtitle,
            metadata_face,
            subtitle_height
        )
        local main_min_width = math.floor(
            main_width_without_metadata * MAIN_CONTENT_MIN_WIDTH_RATIO
        )
        local title_width = textWidth(title, title_face, true)
        local main_content_width = math.max(title_width, subtitle_width)
        local main_width_for_content = math.max(
            main_min_width,
            main_content_width
        )
        local right_width_for_main = main_width_without_metadata
            - main_width_for_content - CONTENT_METADATA_GAP
        local max_right_width = math.floor(
            (width - reserved_action_width) * RIGHT_METADATA_MAX_WIDTH_RATIO
        )
        max_right_width = math.min(
            max_right_width,
            right_width_for_main
        )
        for line_index = 1, #side_lines do
            wright_width = math.max(wright_width,
                textWidth(side_lines[line_index], right_face))
        end
        if max_right_width >= RIGHT_METADATA_MIN_WIDTH then
            wright_width = math.min(max_right_width, wright_width)
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
        end
    end

    local wmain_width = main_width_without_metadata
    if wright then
        wmain_width = wmain_width - CONTENT_METADATA_GAP - wright_width
    end
    wmain_width = math.max(Screen:scaleBySize(40), wmain_width)
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
    if subtitle_segments then
        wsubtitle = buildIconSubtitle(
            subtitle_segments,
            metadata_face,
            wmain_width,
            subtitle_height,
            {
                fgcolor = metadata_fgcolor,
                dim = entry.dim == true,
            }
        )
    elseif subtitle ~= "" then
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
    local row_items = {
        allow_mirroring = false,
    }
    if actions_on_left and action_column then
        table.insert(row_items, HorizontalSpan:new{
            width = left_outer_padding,
        })
        table.insert(row_items, action_column)
        table.insert(row_items, HorizontalSpan:new{
            width = left_action_gap,
        })
    else
        table.insert(row_items, HorizontalSpan:new{
            width = left_outer_padding,
        })
    end

    table.insert(row_items, LeftContainer:new{
        dimen = Geom:new{ w = wmain_width, h = height },
        VerticalGroup:new(main_items),
    })

    if wright then
        table.insert(row_items, HorizontalSpan:new{
            width = CONTENT_METADATA_GAP,
        })
        table.insert(row_items, wright)
    end

    if not actions_on_left and action_column then
        table.insert(row_items, HorizontalSpan:new{
            width = right_action_gap,
        })
        table.insert(row_items, action_column)
    end
    table.insert(row_items, HorizontalSpan:new{
        width = right_outer_padding,
    })

    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = height },
        HorizontalGroup:new(row_items),
    }
end

return BookRow
