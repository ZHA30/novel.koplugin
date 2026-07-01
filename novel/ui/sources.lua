local _ = require("novel.i18n")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local Sources = {}

local function sourceTitle(source)
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl
end

local function sourceSummary(source)
    local lines = {
        source.bookSourceUrl,
    }
    if source.bookSourceGroup and source.bookSourceGroup ~= "" then
        table.insert(lines, _("Group: ") .. source.bookSourceGroup)
    end
    if source.enabled == false then
        table.insert(lines, _("Disabled"))
    end
    if source.support_status and #source.support_status > 0 then
        table.insert(lines, _("Unsupported rules are present."))
    end
    return table.concat(lines, "\n")
end

function Sources.show(plugin)
    local repo = plugin.app:getSourceRepo()
    local sources = repo:list()

    if #sources == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No book sources imported."),
        })
        return
    end

    if plugin.sources_menu then
        UIManager:close(plugin.sources_menu)
        plugin.sources_menu = nil
    end

    local item_table = {}
    for source_index, source in ipairs(sources) do
        table.insert(item_table, {
            source_index = source_index,
            text = sourceTitle(source),
            mandatory = source.enabled == false and _("Disabled") or nil,
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = sourceSummary(source),
                })
            end,
        })
    end

    local sources_menu
    sources_menu = Menu:new{
        title = _("Sources"),
        item_table = item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(sources_menu)
            if plugin.sources_menu == sources_menu then
                plugin.sources_menu = nil
            end
        end,
    }
    plugin.sources_menu = sources_menu
    UIManager:show(sources_menu)
end

return Sources
