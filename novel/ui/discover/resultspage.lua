local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailFlow = require("novel.ui.detail.flow")
local DetailVisits = require("novel.ui.detail.detailvisits")
local Dialog = require("novel.ui.widget.dialog")
local ShellRoutes = require("novel.ui.shellroutes")

local DiscoverResultsPage = {}

local function copiedBooks(books)
    local copied = {}
    for index = 1, #(books or {}) do
        copied[index] = books[index]
    end
    return copied
end

local function routeWith(route, patch)
    local copied = ShellRoutes.discoverResults(route)
    for key, value in pairs(patch or {}) do
        copied[key] = value
    end
    return copied
end

function DiscoverResultsPage.build(shell, plugin, route, runtime)
    if route.loading and #(route.books or {}) == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Loading"), _("Loading results..."))
    end

    if route.error and #(route.books or {}) == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), tostring(route.error))
    end

    local items = {}
    if route.unsupported and #route.unsupported > 0 then
        table.insert(items, {
            title = _("Unsupported rules"),
            mandatory = tostring(#route.unsupported),
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
            callback = function()
                DetailFlow.show(plugin, route.source, book, {
                    on_visited = function(visited_book)
                        local books = copiedBooks(route.books)
                        books[index] = visited_book or books[index]
                        runtime.replace(plugin, routeWith(route, {
                            books = books,
                        }))
                    end,
                })
            end,
        })
    end

    if #items == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Empty"), _("No results."))
    end

    if route.error then
        table.insert(items, {
            title = _("Last request failed"),
            subtitle = tostring(route.error),
            dim = true,
        })
    end

    if route.loading_more then
        table.insert(items, {
            title = _("Loading more..."),
            dim = true,
        })
    elseif route.no_more_source_pages then
        table.insert(items, {
            title = _("No more results."),
            dim = true,
        })
    end

    return ContentBuilder.buildList(shell, items)
end

return DiscoverResultsPage
