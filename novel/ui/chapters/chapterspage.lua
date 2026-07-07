local _ = require("novel.i18n")
local ChapterListing = require("novel.ui.chapters.listing")
local ContentBuilder = require("novel.ui.contentbuilder")
local ChapterOpen = require("novel.reader.chapteropen")

local ChaptersPage = {}

function ChaptersPage.build(shell, plugin, route)
    if route.error then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), tostring(route.error))
    end

    local manifest = route.manifest
    if not manifest then
        return ContentBuilder.buildEmptyState(shell)
    end

    local filter, sort = ChapterListing.resolveState(plugin, manifest, {
        filter = route.filter,
        sort = route.sort,
    })
    local model = ChapterListing.buildModel(manifest, filter, sort)
    if model.count == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    return ContentBuilder.buildList(shell, nil, {
        item_count = model.count,
        fixed_item = true,
        item_at = function(index)
            local row = model.rowAt(index)
            return {
                title = row.title,
                dim = row.dim,
                callback = row.openable and function()
                    ChapterOpen.open(plugin, manifest, row.position, {
                        from_reader = plugin.ui and plugin.ui.document ~= nil,
                        jump = "start",
                    })
                end or nil,
            }
        end,
    })
end

return ChaptersPage
