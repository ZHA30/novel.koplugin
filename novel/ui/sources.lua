local _ = require("novel.i18n")
local Blitbuffer = require("ffi/blitbuffer")
local Grouping = require("novel.ui.grouping")
local Menu = require("novel.ui.menu")
local Size = require("ui/size")
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

local function sourceEnabled(source)
    return source.enabled ~= false
end

local function sourceStatus(source)
    return sourceEnabled(source) and _("Enabled") or _("Disabled")
end

local function enabledCount(sources)
    local count = 0
    for source_index = 1, #sources do
        if sourceEnabled(sources[source_index]) then
            count = count + 1
        end
    end
    return count
end

local function groupCount(group)
    return tostring(enabledCount(group.sources)) .. "/" .. tostring(#group.sources)
end

local function groupKey(group)
    return group.name or ""
end

local function groupCollapsed(plugin, group)
    return Grouping.collapsed(plugin, "sources_collapsed_groups", groupKey(group))
end

local function groupIcon(plugin, group)
    return Grouping.icon(groupCollapsed(plugin, group))
end

local function groupText(group)
    return groupTitle(group)
end

local function refreshCurrentMenu(plugin)
    if plugin.sources_menu then
        plugin.sources_menu:updateItems(plugin.sources_menu.itemnumber, true)
    end
end

local function rebuildMenuItems(plugin, sources, groups)
    if plugin.sources_menu then
        plugin.sources_menu.item_table = Sources.buildItems(plugin, sources, groups)
        plugin.sources_menu:updateItems(plugin.sources_menu.itemnumber, true)
    end
end

local function buildSourceItem(plugin, repo, source)
    local item
    item = {
        text_func = function()
            return sourceTitle(source)
        end,
        mandatory_func = function()
            return sourceStatus(source)
        end,
        mandatory_dim_func = function()
            return not sourceEnabled(source)
        end,
        dim = not sourceEnabled(source),
        callback = function()
            local enabled = sourceEnabled(source)
            local next_enabled = not enabled
            if repo:setEnabled(source.bookSourceUrl, next_enabled) then
                source.enabled = next_enabled
                item.dim = not next_enabled
                refreshCurrentMenu(plugin)
            end
        end,
    }
    return item
end

function Sources.buildItems(plugin, sources, groups)
    if #sources == 0 then
        return {
            {
                text = _("No local book source files."),
                select_enabled = false,
                dim = true,
            },
        }
    end

    local repo = plugin.app:getSourceRepo()
    local item_table = {}
    for group_index = 1, #groups do
        local group = groups[group_index]
        table.insert(item_table, {
            text_func = function()
                return groupText(group)
            end,
            mandatory_func = function()
                return groupCount(group)
            end,
            state = groupIcon(plugin, group),
            bold = true,
            callback = function()
                Grouping.toggle(plugin, "sources_collapsed_groups", groupKey(group))
                rebuildMenuItems(plugin, sources, groups)
            end,
        })
        if not groupCollapsed(plugin, group) then
            for source_index = 1, #group.sources do
                table.insert(item_table, buildSourceItem(plugin, repo, group.sources[source_index]))
            end
        end
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
        item_table = Sources.buildItems(plugin, sources, groups),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        state_w = Grouping.state_w,
        single_line = true,
        align_baselines = true,
        items_padding = math.floor(Size.padding.fullscreen / 2),
        line_color = Blitbuffer.COLOR_BLACK,
        close_callback = function()
            if plugin.sources_menu == sources_menu then
                plugin.sources_menu = nil
            end
        end,
    }
    plugin.sources_menu = sources_menu
    UIManager:show(sources_menu)
end

return Sources
