local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BaseMenu = require("ui/widget/menu")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("novel.ui.menu")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local ROW_BASE_HEIGHT = 96
local MIN_PER_PAGE = 4
local MAX_PER_PAGE = 8

local DiscoverList = {}

local function clean(value)
    value = tostring(value or "")
    value = value:gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function appendText(parts, value)
    value = clean(value)
    if value ~= "" then
        table.insert(parts, value)
    end
end

local function fontSizeForHeight(row_height, nominal, minimum, maximum)
    local size = math.floor(nominal * row_height / Screen:scaleBySize(ROW_BASE_HEIGHT))
    size = math.max(minimum, size)
    return math.min(maximum, size)
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
    local title = clean(entry.text)
    if title == "" then
        title = clean(book.name)
    end
    if title == "" then
        title = clean(book.bookUrl)
    end
    return title
end

local function bookMetadata(entry)
    local book = entry.book or {}
    local parts = {}
    appendText(parts, book.author)
    appendText(parts, book.kind)
    appendText(parts, book.originName)
    if #parts == 0 then
        appendText(parts, entry.source_title)
    end
    return table.concat(parts, " / ")
end

local function bookIntro(entry)
    local book = entry.book or {}
    local intro = clean(book.intro)
    if intro == "" then
        intro = clean(book.latestChapterTitle)
    end
    if intro == "" then
        intro = clean(book.latestChapter)
    end
    return intro
end

local function bookDetails(entry)
    local book = entry.book or {}
    local top = clean(book.wordCount)
    if top == "" then
        top = clean(book.kind)
    end
    local bottom = clean(book.latestChapterTitle)
    if bottom == "" then
        bottom = clean(book.latestChapter)
    end
    if bottom == top then
        bottom = ""
    end
    return top, bottom
end

local DiscoverListItem = InputContainer:extend{
    entry = nil,
    menu = nil,
    dimen = nil,
    width = nil,
    height = nil,
    _underline_container = nil,
}

function DiscoverListItem:init()
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

    self._underline_container = UnderlineContainer:new{
        vertical_align = "top",
        padding = 0,
        dimen = Geom:new{
            w = self.width,
            h = self.height,
        },
        linesize = Size.line.thin,
    }
    self[1] = self._underline_container
    self:update()
end

function DiscoverListItem:contentDimen()
    local pad = Screen:scaleBySize(10)
    return pad, Geom:new{
        w = math.max(Screen:scaleBySize(40), self.width - 2 * pad),
        h = self.height - Size.line.thin,
    }
end

function DiscoverListItem:buildActionWidget()
    local pad, content_dimen = self:contentDimen()
    local fgcolor = self.entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil
    local font_size = fontSizeForHeight(self.height, 20, 16, 24)
    local info_size = fontSizeForHeight(self.height, 15, 12, 18)
    local face = Font:getFace("cfont", font_size)
    local info_face = Font:getFace("infont", info_size)
    local mandatory = clean(self.entry.mandatory)
    local right_width = 0
    if mandatory ~= "" then
        right_width = math.min(
            math.floor(content_dimen.w * 0.3),
            textWidth(mandatory, info_face) + Screen:scaleBySize(4))
    end
    local gap = right_width > 0 and Screen:scaleBySize(10) or 0
    local text_height = lineHeight(face)
    local info_height = lineHeight(info_face)
    local left_width = math.max(Screen:scaleBySize(40), content_dimen.w - right_width - gap)
    local item_text = textBox(
        BD.auto(BaseMenu.getMenuText(self.entry)),
        face,
        left_width,
        text_height,
        {
            bold = self.entry.bold == true,
            fgcolor = fgcolor,
        })

    local content = OverlapGroup:new{
        dimen = content_dimen:copy(),
        LeftContainer:new{
            dimen = content_dimen:copy(),
            CenterContainer:new{
                dimen = Geom:new{ w = left_width, h = content_dimen.h },
                item_text,
            },
        },
    }
    if mandatory ~= "" then
        table.insert(content, RightContainer:new{
            dimen = content_dimen:copy(),
            CenterContainer:new{
                dimen = Geom:new{ w = right_width, h = content_dimen.h },
                textBox(BD.auto(mandatory), info_face, right_width, info_height, {
                    alignment = "right",
                    fgcolor = fgcolor,
                }),
            },
        })
    end

    return LeftContainer:new{
        dimen = Geom:new{ w = self.width, h = content_dimen.h },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = pad },
            content,
            HorizontalSpan:new{ width = pad },
        },
    }
end

function DiscoverListItem:buildBookWidget()
    local pad, content_dimen = self:contentDimen()
    local fgcolor = self.entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil
    local title_face = Font:getFace("cfont", fontSizeForHeight(self.height, 21, 17, 24))
    local meta_face = Font:getFace("cfont", fontSizeForHeight(self.height, 15, 12, 18))
    local detail_face = Font:getFace("cfont", fontSizeForHeight(self.height, 14, 11, 16))
    local right_face = Font:getFace("infont", fontSizeForHeight(self.height, 13, 11, 16))
    local top_detail, bottom_detail = bookDetails(self.entry)
    local right_width = 0
    if top_detail ~= "" or bottom_detail ~= "" then
        right_width = math.floor(content_dimen.w * 0.32)
        local measured = math.max(
            top_detail ~= "" and textWidth(top_detail, right_face) or 0,
            bottom_detail ~= "" and textWidth(bottom_detail, right_face) or 0)
        right_width = math.min(right_width, measured + Screen:scaleBySize(6))
    end
    local gap = right_width > 0 and Screen:scaleBySize(12) or 0
    local main_width = math.max(Screen:scaleBySize(60), content_dimen.w - right_width - gap)
    local title_height = lineHeight(title_face)
    local meta_height = lineHeight(meta_face)
    local detail_height = lineHeight(detail_face)
    local top_padding = Screen:scaleBySize(5)
    local metadata = bookMetadata(self.entry)
    local intro = bookIntro(self.entry)
    local main_items = {
        VerticalSpan:new{ width = top_padding },
        textBox(BD.auto(bookTitle(self.entry)), title_face, main_width, title_height, {
            bold = true,
            fgcolor = fgcolor,
        }),
    }
    if metadata ~= "" then
        table.insert(main_items, textBox(BD.auto(metadata), meta_face, main_width, meta_height, {
            fgcolor = fgcolor,
        }))
    end
    if intro ~= "" then
        local used_height = top_padding + title_height + (metadata ~= "" and meta_height or 0)
        local available_detail_height = math.max(detail_height, content_dimen.h - used_height)
        table.insert(main_items, textBox(BD.auto(intro), detail_face, main_width,
            math.min(available_detail_height, detail_height * 2), {
                fgcolor = fgcolor,
            }))
    end

    local content = OverlapGroup:new{
        dimen = content_dimen:copy(),
        LeftContainer:new{
            dimen = content_dimen:copy(),
            VerticalGroup:new(main_items),
        },
    }

    if right_width > 0 then
        local right_items = {
            align = "right",
            VerticalSpan:new{ width = top_padding },
        }
        if top_detail ~= "" then
            table.insert(right_items, textBox(BD.auto(top_detail), right_face, right_width,
                lineHeight(right_face), {
                    alignment = "right",
                    fgcolor = fgcolor,
                }))
        end
        if bottom_detail ~= "" then
            table.insert(right_items, textBox(BD.auto(bottom_detail), right_face, right_width,
                lineHeight(right_face), {
                    alignment = "right",
                    fgcolor = fgcolor,
                }))
        end
        table.insert(content, RightContainer:new{
            dimen = content_dimen:copy(),
            HorizontalGroup:new{
                VerticalGroup:new(right_items),
            },
        })
    end

    return LeftContainer:new{
        dimen = Geom:new{ w = self.width, h = content_dimen.h },
        HorizontalGroup:new{
            HorizontalSpan:new{ width = pad },
            content,
            HorizontalSpan:new{ width = pad },
        },
    }
end

function DiscoverListItem:update()
    if self._underline_container[1] then
        self._underline_container[1]:free()
    end
    if self.entry.book then
        self._underline_container[1] = self:buildBookWidget()
    else
        self._underline_container[1] = self:buildActionWidget()
    end
end

function DiscoverListItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    return true
end

function DiscoverListItem:onUnfocus()
    self._underline_container.color = Blitbuffer.COLOR_WHITE
    return true
end

function DiscoverListItem:onTapSelect()
    self.menu:onMenuSelect(self.entry)
    return true
end

function DiscoverListItem:onHoldSelect()
    self.menu:onMenuHold(self.entry)
    return true
end

function DiscoverList._recalculateDimen(self)
    local top_height = 0
    if self.title_bar and not self.no_title then
        top_height = self.title_bar:getHeight()
    end
    local bottom_height = 0
    if self.page_return_arrow and self.page_info_text then
        bottom_height = math.max(self.page_return_arrow:getSize().h, self.page_info_text:getSize().h)
            + Size.padding.button
    end
    self.available_height = self.inner_dimen.h - top_height - bottom_height - Size.line.thin
    local base_height = Screen:scaleBySize(ROW_BASE_HEIGHT)
    self.perpage = self.items_per_page
        or math.max(MIN_PER_PAGE, math.floor(self.available_height / base_height))
    self.perpage = math.min(MAX_PER_PAGE, self.perpage)
    self.perpage = math.max(1, self.perpage)
    self.page_num = self:getPageNumber(#self.item_table)
    if self.page > self.page_num then
        self.page = self.page_num
    end
    self.item_height = math.floor(self.available_height / self.perpage) - Size.line.thin
    self.item_width = self.inner_dimen.w
    self.item_dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.item_width,
        h = self.item_height,
    }
end

function DiscoverList._updateItemsBuildUI(self)
    local line_widget = LineWidget:new{
        dimen = Geom:new{ w = self.item_width, h = Size.line.thin },
        background = self.line_color or Blitbuffer.COLOR_DARK_GRAY,
    }
    table.insert(self.item_group, line_widget)
    local idx_offset = (self.page - 1) * self.perpage
    local select_number
    for idx = 1, self.perpage do
        local index = idx_offset + idx
        local entry = self.item_table[index]
        if entry == nil then
            break
        end
        entry.idx = index
        if index == self.itemnumber then
            select_number = idx
        end
        local item_shortcut, shortcut_style
        if self.is_enable_shortcut then
            item_shortcut = self.item_shortcuts[idx]
            shortcut_style = (idx < 11 or idx > 20) and "square" or "grey_square"
        end
        local item = DiscoverListItem:new{
            idx = index,
            width = self.item_width,
            height = self.item_height,
            dimen = self.item_dimen:copy(),
            entry = entry,
            menu = self,
            shortcut = item_shortcut,
            shortcut_style = shortcut_style,
        }
        table.insert(self.item_group, item)
        table.insert(self.item_group, line_widget)
        table.insert(self.layout, { item })
    end
    return select_number
end

function DiscoverList.updateItems(self, select_number, no_recalculate_dimen)
    local old_dimen = self.dimen and self.dimen:copy()
    self.layout = {}
    self.item_group:clear()
    if not no_recalculate_dimen then
        self:_recalculateDimen()
    end
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    select_number = self:_updateItemsBuildUI() or select_number
    self:updatePageInfo(select_number)
    BaseMenu.mergeTitleBarIntoLayout(self)
    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen = old_dimen and old_dimen:combine(self.dimen) or self.dimen
        return "ui", refresh_dimen
    end)
end

function DiscoverList.new(_list, args)
    args = args or {}
    args.updateItems = args.updateItems or DiscoverList.updateItems
    args._recalculateDimen = args._recalculateDimen or DiscoverList._recalculateDimen
    args._updateItemsBuildUI = args._updateItemsBuildUI or DiscoverList._updateItemsBuildUI
    return Menu:new(args)
end

return DiscoverList
