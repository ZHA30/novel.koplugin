local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local SearchSupport = require("novel.ui.search.searchsupport")
local SearchFlow = require("novel.ui.search.flow")

local SearchSourcesPage = {}

function SearchSourcesPage.build(shell, plugin, route)
    local sources = route.sources or {}
    if #sources == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Empty"), _("No enabled searchable sources."))
    end

    local items = {}
    for index = 1, #sources do
        local source = sources[index]
        table.insert(items, {
            title = SearchSupport.sourceTitle(source),
            subtitle = SearchSupport.sourceSubtitle(source),
            callback = function()
                SearchFlow.showInput(plugin, source, nil, {
                    tab = route.tab,
                })
            end,
        })
    end

    return ContentBuilder.buildList(shell, items)
end

return SearchSourcesPage
