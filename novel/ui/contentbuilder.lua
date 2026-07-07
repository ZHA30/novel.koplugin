local _ = require("novel.i18n")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HomeList = require("novel.ui.widget.homelist")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local ContentBuilder = {}
local Screen = Device.screen

local function centeredContent(shell, top_text, bottom_text, top_face, bottom_face, gap)
    local top = TextWidget:new{
        text = top_text,
        face = top_face,
    }
    local bottom = TextWidget:new{
        text = bottom_text,
        face = bottom_face,
    }
    return VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{
                w = shell.body_width,
                h = top:getSize().h,
            },
            top,
        },
        VerticalSpan:new{
            width = Screen:scaleBySize(gap or 6),
        },
        CenterContainer:new{
            dimen = Geom:new{
                w = shell.body_width,
                h = bottom:getSize().h,
            },
            bottom,
        },
    }
end

function ContentBuilder.buildEmptyContent(shell, message)
    return centeredContent(
        shell,
        "(._.)",
        message,
        Font:getFace("cfont", 42),
        Font:getFace("cfont", 22),
        6
    )
end

function ContentBuilder.buildEmptyState(shell)
    return ContentBuilder.buildEmptyContent(shell, _("Empty"))
end

function ContentBuilder.buildStatusContent(shell, title, message)
    return centeredContent(
        shell,
        title,
        message,
        Font:getFace("cfont", 30),
        Font:getFace("smallinfofont", 18),
        10
    )
end

function ContentBuilder.buildList(shell, items)
    return HomeList:new{
        dimen = Geom:new{
            w = shell.body_width,
            h = shell.body_height,
        },
        show_parent = shell,
        items = items,
        page = shell.list_page,
        paginate = shell.paginate_lists,
        previous_page_callback = shell.previous_page_callback,
        next_page_callback = shell.next_page_callback,
        on_page_info = function(info)
            shell.list_page_info = info
        end,
    }
end

return ContentBuilder
