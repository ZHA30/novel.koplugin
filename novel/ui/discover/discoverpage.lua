local _ = require("novel.i18n")
local SourceStore = require("novel.storage.sourcestore")
local ContentBuilder = require("novel.ui.contentbuilder")
local Dialog = require("novel.ui.widget.dialog")
local DiscoverFlow = require("novel.ui.discover.flow")
local DiscoverService = require("novel.catalog.listing.discoverservice")
local Grouping = require("novel.ui.widget.grouping")
local SearchSupport = require("novel.ui.search.searchsupport")
local SearchFlow = require("novel.ui.search.flow")

local DiscoverPage = {}

local function categoryTitle(group)
    if group.title and group.title ~= "" then
        return group.title
    end
    return group.url or _("Discover")
end

function DiscoverPage.build(shell, plugin, route, runtime)
    local source_groups, unsupported = DiscoverService.sourceGroups(
        plugin.app:getSourceStore():list()
    )
    local searchable_sources = SearchSupport.searchableSources(plugin)
    if #source_groups == 0 and #unsupported == 0 and #searchable_sources == 0 then
        return ContentBuilder.buildEmptyContent(shell, _("No discoverable sources."))
    end

    local items = {}
    if #searchable_sources > 0 then
        table.insert(items, {
            title = _("Search"),
            mandatory = tostring(#searchable_sources),
            icon = "search",
            callback = function()
                SearchFlow.show(plugin, {
                    tab = route and route.tab or "discover",
                })
            end,
        })
    end
    if #unsupported > 0 then
        table.insert(items, {
            title = _("Unsupported rules"),
            mandatory = tostring(#unsupported),
            icon = "funnel",
            callback = function()
                Dialog.showUnsupported(unsupported)
            end,
        })
    end

    for source_index = 1, #source_groups do
        local source_group = source_groups[source_index]
        local source = source_group.source
        local source_key = SourceStore.key(source)
        local collapsed = Grouping.collapsed(plugin, "discover_collapsed_sources", source_key)
        table.insert(items, {
            title = SourceStore.title(source),
            mandatory = tostring(#source_group.groups),
            icon = collapsed and "group-collapsed" or "group-expanded",
            bold = true,
            callback = function()
                Grouping.toggle(plugin, "discover_collapsed_sources", source_key)
                runtime.reshow(plugin)
            end,
        })
        if not collapsed then
            if #source_group.groups == 0 then
                table.insert(items, {
                    title = _("No discover categories."),
                    indent = 1,
                    dim = true,
                })
            else
                for group_index = 1, #source_group.groups do
                    local group = source_group.groups[group_index]
                    table.insert(items, {
                        title = categoryTitle(group),
                        indent = 1,
                        callback = function()
                            DiscoverFlow.start(plugin, source, group, 1, {
                                tab = route and route.tab or "discover",
                            })
                        end,
                    })
                end
            end
        end
    end

    return ContentBuilder.buildList(shell, items)
end

return DiscoverPage
