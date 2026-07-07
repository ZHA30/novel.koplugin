local _ = require("novel.i18n")
local SourceStore = require("novel.storage.sourcestore")
local ContentBuilder = require("novel.ui.contentbuilder")
local Grouping = require("novel.ui.widget.grouping")

local SourcesPage = {}

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
    for index = 1, #sources do
        if sourceEnabled(sources[index]) then
            count = count + 1
        end
    end
    return count
end

local function groupCount(group)
    return tostring(enabledCount(group.sources)) .. "/" .. tostring(#group.sources)
end

function SourcesPage.build(shell, plugin, _route, runtime)
    local store = plugin.app:getSourceStore()
    local source_list = store:list()
    local groups = store:listGroups()
    if #source_list == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    local items = {}
    for group_index = 1, #groups do
        local group = groups[group_index]
        local key = group.name or ""
        local collapsed = Grouping.collapsed(plugin, "sources_collapsed_groups", key)
        table.insert(items, {
            title = groupTitle(group),
            mandatory = groupCount(group),
            icon = collapsed and "group-collapsed" or "group-expanded",
            bold = true,
            callback = function()
                Grouping.toggle(plugin, "sources_collapsed_groups", key)
                runtime.reshow(plugin)
            end,
        })
        if not collapsed then
            for source_index = 1, #group.sources do
                local source = group.sources[source_index]
                table.insert(items, {
                    title = SourceStore.title(source),
                    mandatory = sourceStatus(source),
                    indent = 1,
                    dim = not sourceEnabled(source),
                    callback = function()
                        local next_enabled = not sourceEnabled(source)
                        if store:setEnabled(source.bookSourceUrl, next_enabled) then
                            runtime.reshow(plugin)
                        end
                    end,
                })
            end
        end
    end

    return ContentBuilder.buildList(shell, items)
end

return SourcesPage
