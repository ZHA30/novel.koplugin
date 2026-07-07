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
        return ContentBuilder.buildStatusContent(shell, _("Empty"), _("No chapters."))
    end

    local filter, sort = ChapterListing.resolveState(plugin, manifest, {
        filter = route.filter,
        sort = route.sort,
    })
    local rows, shown_count = ChapterListing.buildRows(manifest, filter, sort)
    if shown_count == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Empty"), _("No chapters."))
    end

    local items = {}

    for index = 1, #rows do
        local row = rows[index]
        table.insert(items, {
            title = row.title,
            dim = row.dim,
            callback = row.openable and function()
                ChapterOpen.open(plugin, manifest, row.position, {
                    from_reader = plugin.ui and plugin.ui.document ~= nil,
                    jump = "start",
                })
            end or nil,
        })
    end

    return ContentBuilder.buildList(shell, items)
end

return ChaptersPage
