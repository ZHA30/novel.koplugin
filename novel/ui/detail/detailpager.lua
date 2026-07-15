local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")

local Input = Device.input

local DetailPager = InputContainer:extend{
    text = "",
    width = 0,
    height = 0,
    font_face = nil,
    font_size = 22,
    vertical_margin = 16,
    horizontal_margin = 16,
    page = 1,
    on_page_info = nil,
    previous_page_callback = nil,
    next_page_callback = nil,
}

local function createText(text, face, width, height)
    return TextBoxWidget:new{
        text = text,
        face = face,
        width = width,
        height = height,
        alignment = "left",
        justified = true,
        auto_para_direction = true,
    }
end

function DetailPager:init()
    local horizontal_margin = Device.screen:scaleBySize(self.horizontal_margin)
    local vertical_margin = Device.screen:scaleBySize(self.vertical_margin)
    local content_width = math.max(1, self.width - 2 * horizontal_margin)
    local content_height = math.max(1, self.height - 2 * vertical_margin)
    local face = Font:getFace(self.font_face, self.font_size)
    local measurement = createText(self.text or "", face, content_width, content_height)
    local lines_per_page = math.max(1, measurement:getVisLineCount())
    local total_lines = math.max(1, measurement:getAllLineCount())
    measurement:free(true)

    self.total_pages = math.max(1, math.ceil(total_lines / lines_per_page))
    self.page = math.min(math.max(1, tonumber(self.page) or 1), self.total_pages)
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = self.width,
        h = self.height,
    }
    self.text_widget = createText(
        self.text or "",
        face,
        content_width,
        content_height
    )
    if self.total_pages > 1 and self.page > 1 then
        self.text_widget:scrollToRatio(
            (self.page - 1) / (self.total_pages - 1),
            true
        )
    end
    self[1] = FrameContainer:new{
        padding = 0,
        padding_left = horizontal_margin,
        padding_right = horizontal_margin,
        padding_top = vertical_margin,
        padding_bottom = vertical_margin,
        margin = 0,
        bordersize = 0,
        self.text_widget,
    }

    if self.on_page_info then
        self.on_page_info({
            current_page = self.page,
            total_pages = self.total_pages,
            has_previous = self.page > 1,
            has_next = self.page < self.total_pages,
        })
    end

    if Device:isTouchDevice() then
        self.ges_events = {
            SwipePage = {
                GestureRange:new{
                    ges = "swipe",
                    range = function()
                        return self.dimen
                    end,
                },
            },
        }
    end
    if Device:hasKeys() then
        self.key_events = {
            PreviousPage = { { Input.group.PgBack } },
            NextPage = { { Input.group.PgFwd } },
        }
    end
end

function DetailPager:onSwipePage(_, ges)
    if ges.direction == "west" then
        return self:nextPage()
    end
    if ges.direction == "east" then
        return self:previousPage()
    end
    return false
end

function DetailPager:onPreviousPage()
    return self:previousPage()
end

function DetailPager:onNextPage()
    return self:nextPage()
end

function DetailPager:previousPage()
    if self.page <= 1 or not self.previous_page_callback then
        return false
    end
    self.previous_page_callback()
    return true
end

function DetailPager:nextPage()
    if self.page >= self.total_pages or not self.next_page_callback then
        return false
    end
    self.next_page_callback()
    return true
end

return DetailPager
