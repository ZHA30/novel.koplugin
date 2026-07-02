local _ = require("novel.i18n")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local Sources = {}

local function sourceTitle(source)
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl
end

local function groupTitle(group)
    if group.name and group.name ~= "" then
        return group.name
    end
    return _("Ungrouped")
end

local function refresh(plugin)
    UIManager:nextTick(function()
        if plugin.app then
            Sources.show(plugin)
        end
    end)
end

local function sourceEnabled(source)
    return source.enabled ~= false
end

local function buildSourceItems(plugin, sources)
    local repo = plugin.app:getSourceRepo()
    local item_table = {}
    for source_index = 1, #sources do
        local source = sources[source_index]
        table.insert(item_table, {
            text = sourceTitle(source),
            checked_func = function()
                return sourceEnabled(source)
            end,
            callback = function()
                local enabled = sourceEnabled(source)
                if repo:setEnabled(source.bookSourceUrl, not enabled) then
                    source.enabled = not enabled
                end
                refresh(plugin)
            end,
        })
    end
    return item_table
end

local function buildItems(plugin, sources, groups)
    if #sources == 0 then
        return {
            {
                text = _("No local book source files."),
                select_enabled = false,
                dim = true,
            },
        }
    end

    local item_table = {}
    for group_index = 1, #groups do
        local group = groups[group_index]
        table.insert(item_table, {
            text = groupTitle(group),
            mandatory = tostring(#group.sources),
            sub_item_table = buildSourceItems(plugin, group.sources),
        })
    end
    return item_table
end

function Sources.show(plugin)
    if not plugin.app then
        return
    end

    local repo = plugin.app:getSourceRepo()
    local sources = repo:list()
    local groups = repo:listGroups()

    if plugin.sources_menu then
        UIManager:close(plugin.sources_menu)
        plugin.sources_menu = nil
    end

    local sources_menu
    sources_menu = Menu:new{
        title = _("Sources") .. " (" .. tostring(#sources) .. ")",
        item_table = buildItems(plugin, sources, groups),
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
