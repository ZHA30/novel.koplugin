local _ = require("novel.i18n")
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
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
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local SpinWidget = require("ui/widget/spinwidget")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Dialog = require("novel.ui.widget.dialog")

local Screen = Device.screen
local Input = Device.input

local ICON_BUTTON_SIZE = Screen:scaleBySize(30)
local TEXT_FONT_SIZE = 22
local FONT_SIZE_OPTIONS = { 18, 20, 22, 24, 26, 28 }

local DetailIconButton = InputContainer:extend{
    icon = nil,
    enabled = true,
    width = 0,
    callback = nil,
}

function DetailIconButton:init()
    local icon = Icons.widget(self.icon, {
        size = ICON_BUTTON_SIZE,
        dim = false,
    })
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = Screen:scaleBySize(10),
        width = self.width,
        CenterContainer:new{
            dimen = Geom:new{
                w = math.max(self.width - 2 * Screen:scaleBySize(10), ICON_BUTTON_SIZE),
                h = ICON_BUTTON_SIZE,
            },
            icon,
        },
    }
    self.dimen = self[1]:getSize()
    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function DetailIconButton:onTapSelect()
    if not self.enabled then
        return false
    end
    if self.callback then
        self.callback()
        return true
    end
    return false
end

local DetailButtonTable = WidgetContainer:extend{
    width = nil,
    buttons = nil,
    sep_width = Size.line.medium,
}

function DetailButtonTable:init()
    self.container = VerticalGroup:new{
        width = self.width,
    }
    self[1] = self.container
    self:addVerticalSeparator()
    for row_index = 1, #(self.buttons or {}) do
        self:addVerticalSpan()
        local row = self.buttons[row_index]
        local horizontal_group = HorizontalGroup:new{}
        local column_count = #row
        if column_count > 0 then
            local available_width = self.width - self.sep_width * (column_count - 1)
            local default_button_width = math.floor(available_width / column_count)
            for column_index = 1, column_count do
                local entry = row[column_index]
                local button = self:createButton(entry, default_button_width)
                local button_dimen = button:getSize()
                table.insert(horizontal_group, button)
                if column_index < column_count then
                    table.insert(horizontal_group, LineWidget:new{
                        background = Blitbuffer.COLOR_DARK_GRAY,
                        dimen = Geom:new{
                            w = self.sep_width,
                            h = button_dimen.h,
                        },
                    })
                end
            end
            table.insert(self.container, horizontal_group)
        else
            table.insert(self.container, VerticalSpan:new{
                width = 0,
            })
        end
        self:addVerticalSpan()
        if row_index < #self.buttons then
            self:addVerticalSeparator()
        end
    end
end

function DetailButtonTable:createButton(entry, width)
    if entry.icon then
        return DetailIconButton:new{
            icon = entry.icon,
            enabled = entry.enabled ~= false,
            width = entry.width or width,
            callback = entry.callback,
        }
    end

    return Button:new{
        text = entry.text or "",
        width = entry.width or width,
        height = entry.height,
        enabled = entry.enabled,
        callback = entry.callback,
        hold_callback = entry.hold_callback,
        bordersize = 0,
        margin = 0,
        padding = Size.padding.buttontable,
        padding_h = entry.align == "left" and Size.padding.large or Size.padding.button,
        avoid_text_truncation = entry.avoid_text_truncation,
        text_font_face = entry.font_face,
        text_font_size = entry.font_size or TEXT_FONT_SIZE,
        text_font_bold = entry.font_bold,
        background = entry.background,
        align = entry.align,
        show_parent = self.show_parent,
    }
end

function DetailButtonTable:addVerticalSpan()
    table.insert(self.container, VerticalSpan:new{
        width = Size.span.vertical_default,
    })
end

function DetailButtonTable:addVerticalSeparator()
    table.insert(self.container, LineWidget:new{
        background = Blitbuffer.COLOR_DARK_GRAY,
        dimen = Geom:new{
            w = self.width,
            h = self.sep_width,
        },
    })
end

local DetailViewer = InputContainer:extend{
    title = nil,
    text = nil,
    width = nil,
    height = nil,
    buttons_table = nil,
    close_callback = nil,
    on_font_size_change = nil,
    alignment = "left",
    auto_para_direction = true,
    justified = true,
    fgcolor = Blitbuffer.COLOR_BLACK,
    button_padding = Size.padding.default,
    text_padding = Size.padding.large,
    text_margin = Size.margin.small,
    text_font_size = TEXT_FONT_SIZE,
}

function DetailViewer:init()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    self.align = "center"
    self.region = Geom:new{
        w = screen_w,
        h = screen_h,
    }
    self.width = self.width or screen_w - Screen:scaleBySize(30)
    self.height = self.height or screen_h - Screen:scaleBySize(30)

    if Device:hasKeys() then
        self.key_events.Close = { { Input.group.Back } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new{
            w = screen_w,
            h = screen_h,
        }
        self.ges_events = {
            TapClose = {
                GestureRange:new{
                    ges = "tap",
                    range = range,
                },
            },
            MultiSwipe = {
                GestureRange:new{
                    ges = "multiswipe",
                    range = range,
                },
            },
        }
    end

    self.titlebar = TitleBar:new{
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = self.title,
        left_icon = "appbar.textsize",
        left_icon_tap_callback = function()
            self:showFontSizeDialog()
        end,
        close_callback = function()
            self:onClose()
        end,
        show_parent = self,
    }

    local buttons = self.buttons_table
    if type(buttons) ~= "table" or #buttons == 0 then
        buttons = {
            {
                {
                    text = _("Close"),
                    callback = function()
                        self:onClose()
                    end,
                },
            },
        }
    end

    self.button_table = DetailButtonTable:new{
        width = self.width - 2 * self.button_padding,
        buttons = buttons,
        show_parent = self,
    }

    local text_height = self.height - self.titlebar:getHeight() - self.button_table:getSize().h
    self.scroll_text_w = ScrollTextWidget:new{
        text = self.text or "",
        face = Font:getFace("x_smallinfofont", self.text_font_size),
        fgcolor = self.fgcolor,
        width = self.width - 2 * self.text_padding - 2 * self.text_margin,
        height = text_height - 2 * self.text_padding - 2 * self.text_margin,
        dialog = self,
        alignment = self.alignment,
        justified = self.justified,
        auto_para_direction = self.auto_para_direction,
        scroll_by_pan = true,
    }
    self.textw = FrameContainer:new{
        padding = self.text_padding,
        margin = self.text_margin,
        bordersize = 0,
        self.scroll_text_w,
    }

    self.frame = FrameContainer:new{
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{
            self.titlebar,
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.textw:getSize().h,
                },
                self.textw,
            },
            CenterContainer:new{
                dimen = Geom:new{
                    w = self.width,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
            },
        },
    }

    self[1] = WidgetContainer:new{
        align = "center",
        dimen = self.region,
        self.frame,
    }
end

function DetailViewer:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
    return true
end

function DetailViewer:closeFontSizeDialog()
    Dialog.closeWidget(self, "font_size_dialog")
end

function DetailViewer:runCloseCallback()
    local callback = self.close_callback
    self.close_callback = nil
    if callback then
        callback(self)
    end
end

function DetailViewer:showFontSizeDialog()
    if self._is_closed then
        return true
    end

    local value_index = 1
    for index = 1, #FONT_SIZE_OPTIONS do
        if FONT_SIZE_OPTIONS[index] == self.text_font_size then
            value_index = index
            break
        end
    end

    local dialog
    dialog = SpinWidget:new{
        title_text = _("Font size"),
        width_factor = 0.5,
        value_table = FONT_SIZE_OPTIONS,
        value_index = value_index,
        keep_shown_on_apply = false,
        callback = function(widget)
            if self._is_closed or self.font_size_dialog ~= dialog then
                return
            end
            local size = widget.value_table and widget.value_table[widget.value_index or 1]
                or widget.value
            if self.on_font_size_change then
                self.on_font_size_change(size, self)
            end
        end,
        close_callback = function()
            Dialog.clearIfOwned(self, "font_size_dialog", dialog)
        end,
    }
    Dialog.showWidget(self, "font_size_dialog", dialog)
    return true
end

function DetailViewer:onCloseWidget()
    self._is_closed = true
    self:closeFontSizeDialog()
    UIManager:setDirty(nil, function()
        return "partial", self.frame.dimen
    end)
    self:runCloseCallback()
end

function DetailViewer:onTapClose(_, ges)
    if self.frame.dimen and ges.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
        return true
    end
    return false
end

function DetailViewer:onMultiSwipe()
    self:onClose()
    return true
end

function DetailViewer:onClose()
    UIManager:close(self)
    return true
end

return DetailViewer
