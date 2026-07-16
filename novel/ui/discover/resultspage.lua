local _ = require("novel.i18n")
local BookActions = require("novel.ui.bookactions")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailVisits = require("novel.ui.detail.detailvisits")
local Dialog = require("novel.ui.widget.dialog")
local ShellRoutes = require("novel.ui.shellroutes")

local DiscoverResultsPage = {}

local function routeWith(route, patch)
    local copied = ShellRoutes.discoverResults(route)
    for key, value in pairs(patch or {}) do
        copied[key] = value
    end
    return copied
end

function DiscoverResultsPage.build(shell, plugin, route, runtime)
    if route.error and #(route.books or {}) == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    local items = {}
    local action_context = BookActions.context(plugin)
    if route.unsupported and #route.unsupported > 0 then
        table.insert(items, {
            title = _("Unsupported rules"),
            mandatory = tostring(#route.unsupported),
            icon = "funnel",
            callback = function()
                Dialog.showUnsupported(route.unsupported)
            end,
        })
    end

    for index = 1, #(route.books or {}) do
        local book = route.books[index]
        table.insert(items, {
            text = book.name,
            book = book,
            source_title = route.source_name,
            dim = DetailVisits.isVisited(plugin, route.source, book),
            action_buttons = BookActions.buttons(runtime, plugin, route, index,
                book, action_context, routeWith),
            callback = BookActions.detailCallback(runtime, plugin, route, index,
                book, routeWith),
        })
    end

    if #items == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    return ContentBuilder.buildList(shell, items)
end

return DiscoverResultsPage
