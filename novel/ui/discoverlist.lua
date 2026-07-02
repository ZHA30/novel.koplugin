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

local ROW_BASE_HEIGHT = 64
local MIN_PER_PAGE = 4
local SCALE_BY_SIZE = Screen:scaleBySize(1000000) * (1 / 1000000)

local DiscoverList = {}
local book_info_manager

local function bookInfoManager()
    if book_info_manager then
        return book_info_manager
    end
    local ok, manager = pcall(require, "bookinfomanager")
    if ok then
        book_info_manager = manager
        return manager
    end
end

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

local function bookMetadata(entry)
    local book = entry.book or {}
    local parts = {}
    local latest_chapter = clean(book.latestChapterTitle)
    if latest_chapter == "" then
        latest_chapter = book.latestChapter
    end
    appendText(parts, book.kind)
    appendText(parts, latest_chapter)
    appendText(parts, book.wordCount)
    return table.concat(parts, " / ")
end

local function bookAuthor(entry)
    local book = entry.book or {}
    return clean(book.author)
end

local function bookUpdateTime(entry)
    local book = entry.book or {}
    return clean(book.updateTime)
end

local function nativeListPerPage(available_height)
    local manager = bookInfoManager()
    if manager then
        local ok, value = pcall(function()
            return manager:getSetting("files_per_page")
        end)
        value = ok and tonumber(value) or nil
        if value and value > 0 then
            return value
        end
    end

    local calculated = math.floor(available_height / SCALE_BY_SIZE / ROW_BASE_HEIGHT)
    calculated = math.max(MIN_PER_PAGE, calculated)
    if manager then
        pcall(function()
            manager:saveSetting("files_per_page", calculated)
        end)
    end
    return calculated
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

    self.underline_h = 1
    self._underline_container = UnderlineContainer:new{
        vertical_align = "top",
        padding = 0,
        dimen = Geom:new{
            w = self.width,
            h = self.height,
        },
        linesize = self.underline_h,
    }
    self[1] = self._underline_container
    self:update()
end

function DiscoverListItem:rowDimen()
    return Geom:new{
        w = self.width,
        h = self.height - 2 * self.underline_h,
    }
end

function DiscoverListItem:fontSize(nominal, maximum)
    local dimen = self:rowDimen()
    local font_size = math.floor(nominal * dimen.h * (1 / ROW_BASE_HEIGHT) / SCALE_BY_SIZE)
    if maximum and font_size >= maximum then
        return maximum
    end
    return font_size
end

function DiscoverListItem:buildActionWidget()
    local dimen = self:rowDimen()
    local fgcolor = self.entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil
    local face = Font:getFace("cfont", self:fontSize(20, 24))
    local info_face = Font:getFace("infont", self:fontSize(14, 18))
    local mandatory = clean(self.entry.mandatory)
    local wright = TextWidget:new{
        text = mandatory,
        face = info_face,
        fgcolor = fgcolor,
    }
    local pad_width = Screen:scaleBySize(10)
    local wleft_width = math.max(Screen:scaleBySize(40),
        dimen.w - wright:getWidth() - 3 * pad_width)
    local wleft = TextBoxWidget:new{
        text = BD.auto(BaseMenu.getMenuText(self.entry)),
        face = face,
        width = wleft_width,
        alignment = "left",
        bold = self.entry.bold == true,
        height = dimen.h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        fgcolor = fgcolor,
    }

    return OverlapGroup:new{
        dimen = dimen:copy(),
        LeftContainer:new{
            dimen = dimen:copy(),
            HorizontalGroup:new{
                HorizontalSpan:new{ width = pad_width },
                wleft,
            },
        },
        RightContainer:new{
            dimen = dimen:copy(),
            HorizontalGroup:new{
                wright,
                HorizontalSpan:new{ width = pad_width },
            },
        },
    }
end

function DiscoverListItem:buildBookWidget()
    local dimen = self:rowDimen()
    local fgcolor = self.entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil
    local fontsize_dec_step = math.max(1, math.ceil(self:fontSize(100) * (1 / 100)))
    local fontsize_info = self:fontSize(14, 18)
    local right_face = Font:getFace("cfont", fontsize_info)
    local author = bookAuthor(self.entry)
    local update_time = bookUpdateTime(self.entry)

    local wright
    local wright_width = 0
    local wright_right_padding = 0
    if author ~= "" or update_time ~= "" then
        local max_right_width = math.floor(dimen.w * 0.4)
        wright_width = math.min(max_right_width, math.max(
            textWidth(author, right_face),
            textWidth(update_time, right_face)))
        wright_width = math.max(wright_width, Screen:scaleBySize(20))
        local right_line_height = lineHeight(right_face)
        local function rightLine(text)
            return textBox(BD.auto(text), right_face, wright_width, right_line_height, {
                alignment = "right",
                fgcolor = fgcolor,
            })
        end
        wright = CenterContainer:new{
            dimen = Geom:new{ w = wright_width, h = dimen.h },
            VerticalGroup:new{
                align = "right",
                rightLine(author),
                rightLine(update_time),
            },
        }
        wright_right_padding = Screen:scaleBySize(10)
    end

    local wmain_left_padding = Screen:scaleBySize(10)
    local wmain_right_padding = Screen:scaleBySize(10)
    local wmain_width = math.max(Screen:scaleBySize(40),
        dimen.w - wmain_left_padding - wmain_right_padding
        - wright_width - wright_right_padding)
    local fontsize_title = self:fontSize(20, 24)
    local fontsize_subtitle = self:fontSize(18, 22)
    local title = BD.auto(bookTitle(self.entry))
    local subtitle = bookMetadata(self.entry)
    if subtitle ~= "" then
        subtitle = BD.auto(subtitle)
    end
    local wtitle, wsubtitle

    local buildTitle = function(height)
        if wtitle then
            wtitle:free(true)
        end
        wtitle = TextBoxWidget:new{
            text = title,
            face = Font:getFace("cfont", fontsize_title),
            width = wmain_width,
            height = height,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            bold = true,
            fgcolor = fgcolor,
        }
    end
    local buildSubtitle = function(height)
        if wsubtitle then
            wsubtitle:free(true)
        end
        wsubtitle = TextBoxWidget:new{
            text = subtitle,
            face = Font:getFace("cfont", fontsize_subtitle),
            width = wmain_width,
            height = height,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            fgcolor = fgcolor,
        }
    end

    while true do
        buildTitle()
        local text_height = wtitle:getSize().h
        if subtitle ~= "" then
            buildSubtitle()
            text_height = text_height + wsubtitle:getSize().h
        end
        if text_height <= dimen.h then
            break
        end
        if fontsize_title <= 12 or fontsize_subtitle <= 10 then
            local title_height = math.min(wtitle:getSize().h, dimen.h)
            if subtitle ~= "" then
                local subtitle_height = math.min(wsubtitle:getSize().h,
                    math.max(0, dimen.h - title_height))
                if title_height + subtitle_height > dimen.h then
                    title_height = math.max(0, dimen.h - subtitle_height)
                end
                if title_height < wtitle:getSize().h then
                    buildTitle(title_height)
                end
                if subtitle_height < wsubtitle:getSize().h then
                    buildSubtitle(subtitle_height)
                end
            elseif title_height < wtitle:getSize().h then
                buildTitle(title_height)
            end
            break
        end
        fontsize_title = fontsize_title - fontsize_dec_step
        fontsize_subtitle = fontsize_subtitle - fontsize_dec_step
    end

    local main_items = { wtitle }
    if subtitle ~= "" then
        table.insert(main_items, wsubtitle)
    end
    local wmain = HorizontalGroup:new{
        HorizontalSpan:new{ width = wmain_left_padding },
        LeftContainer:new{
            dimen = dimen:copy(),
            VerticalGroup:new(main_items),
        },
    }
    local widget = OverlapGroup:new{
        dimen = dimen:copy(),
        LeftContainer:new{
            dimen = dimen:copy(),
            wmain,
        },
    }
    if wright then
        table.insert(widget, RightContainer:new{
            dimen = dimen:copy(),
            HorizontalGroup:new{
                wright,
                HorizontalSpan:new{ width = wright_right_padding },
            },
        })
    end
    return widget
end

function DiscoverListItem:update()
    if self._underline_container[1] then
        self._underline_container[1]:free()
    end
    local widget
    if self.entry.book then
        widget = self:buildBookWidget()
    else
        widget = self:buildActionWidget()
    end
    self._underline_container[1] = VerticalGroup:new{
        VerticalSpan:new{ width = self.underline_h },
        widget,
    }
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
    self.perpage = nativeListPerPage(self.available_height)
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

function DiscoverList.canLoadNextSourcePage(self)
    return self.load_next_page_callback ~= nil
        and self.loading_next_page ~= true
        and self.no_more_source_pages ~= true
end

function DiscoverList.updatePageInfo(self, select_number)
    BaseMenu.updatePageInfo(self, select_number)
    if #self.item_table > 0 and self.page_info_right_chev then
        self.page_info_right_chev:enableDisable(
            self.page < self.page_num or self:canLoadNextSourcePage())
    end
end

function DiscoverList.onNextPage(self)
    if self.page < self.page_num then
        return BaseMenu.onNextPage(self)
    end
    if self:canLoadNextSourcePage() then
        self.loading_next_page = true
        self:updatePageInfo()
        local ok = self.load_next_page_callback(self)
        if ok == false then
            self.loading_next_page = false
            self:updatePageInfo()
        end
        return true
    end
    return true
end

function DiscoverList.new(_list, args)
    args = args or {}
    args.updateItems = args.updateItems or DiscoverList.updateItems
    args.updatePageInfo = args.updatePageInfo or DiscoverList.updatePageInfo
    args.onNextPage = args.onNextPage or DiscoverList.onNextPage
    args.canLoadNextSourcePage = args.canLoadNextSourcePage or DiscoverList.canLoadNextSourcePage
    args._recalculateDimen = args._recalculateDimen or DiscoverList._recalculateDimen
    args._updateItemsBuildUI = args._updateItemsBuildUI or DiscoverList._updateItemsBuildUI
    return Menu:new(args)
end

return DiscoverList
