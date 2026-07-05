local _ = require("novel.i18n")
local ChapterListing = require("novel.ui.chapters.listing")
local ContentBuilder = require("novel.ui.contentbuilder")
local ChapterOpen = require("novel.reader.chapteropen")
local ShellRoutes = require("novel.ui.shellroutes")

local ChaptersPage = {}

local function summaryText(manifest, shown_count)
    return tostring(shown_count) .. "/" .. tostring(#(manifest.chapters or {}))
end

local function chapterRoute(route, manifest, filter, sort)
    return ShellRoutes.chapters{
        tab = route.tab,
        source = route.source or manifest.source,
        book = route.book or manifest.book,
        manifest = manifest,
        filter = filter,
        sort = sort,
    }
end

function ChaptersPage.build(shell, plugin, route, runtime)
    if route.loading then
        return ContentBuilder.buildStatusContent(shell, _("Loading"), _("Loading chapters..."))
    end

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
    local items = {
        {
            title = _("Filter"),
            mandatory = ChapterListing.filterLabel(filter),
            callback = function()
                local next_filter = filter == ChapterListing.FILTER_UNREAD
                    and ChapterListing.FILTER_ALL
                    or ChapterListing.FILTER_UNREAD
                runtime.replace(plugin, chapterRoute(route, manifest, next_filter, sort))
            end,
        },
        {
            title = _("Order"),
            mandatory = ChapterListing.sortLabel(sort),
            callback = function()
                local next_sort = sort == ChapterListing.SORT_DESCENDING
                    and ChapterListing.SORT_ASCENDING
                    or ChapterListing.SORT_DESCENDING
                runtime.replace(plugin, chapterRoute(route, manifest, filter, next_sort))
            end,
        },
        {
            title = _("Chapters"),
            mandatory = summaryText(manifest, shown_count),
            dim = true,
        },
    }

    for index = 1, #rows do
        local row = rows[index]
        table.insert(items, {
            title = row.title,
            mandatory = row.mandatory,
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
