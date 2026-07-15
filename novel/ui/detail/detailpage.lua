local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailFlow = require("novel.ui.detail.flow")
local DetailPager = require("novel.ui.detail.detailpager")
local DetailSettings = require("novel.ui.detail.settings")

local DetailPage = {}

local function textFor(route)
    local book = route.book or {}
    local parts = {}
    local author = tostring(book.author or ""):match("%S") and tostring(book.author) or ""
    if author ~= "" then
        parts[#parts + 1] = author
    end
    local kind = tostring(book.kind or ""):match("%S") and tostring(book.kind) or ""
    if kind ~= "" then
        parts[#parts + 1] = kind
    end
    if #parts > 0 then
        parts[#parts + 1] = ""
    end
    parts[#parts + 1] = tostring(route.text or book.intro or "")
    return table.concat(parts, "\n")
end

function DetailPage.build(shell, plugin, route, runtime)
    if route.loading then
        return ContentBuilder.buildStatusContent(shell, _("Loading"), _("Loading"))
    end
    if route.error and not tostring(route.text or ""):match("%S") then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), route.error)
    end

    local settings = DetailSettings.get(plugin)
    return DetailPager:new{
        text = textFor(route),
        width = shell.body_width,
        height = shell.body_height,
        font_face = settings.font_face,
        font_size = settings.font_size,
        vertical_margin = settings.vertical_margin,
        horizontal_margin = settings.horizontal_margin,
        page = route.detail_page,
        on_page_info = function(info)
            shell.detail_page_info = info
        end,
        previous_page_callback = function()
            runtime.replace(plugin, DetailFlow.withPage(route, route.detail_page - 1))
        end,
        next_page_callback = function()
            runtime.replace(plugin, DetailFlow.withPage(route, route.detail_page + 1))
        end,
    }
end

return DetailPage
