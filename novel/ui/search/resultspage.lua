local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailFlow = require("novel.ui.detail.flow")
local DetailVisits = require("novel.ui.detail.detailvisits")
local Dialog = require("novel.ui.widget.dialog")
local ShellRoutes = require("novel.ui.shellroutes")
local SearchFlow = require("novel.ui.search.flow")

local SearchResultsPage = {}

local function copiedBooks(books)
    local copied = {}
    for index = 1, #(books or {}) do
        copied[index] = books[index]
    end
    return copied
end

local function routeWith(route, patch)
    local copied = ShellRoutes.searchResults(route)
    for key, value in pairs(patch or {}) do
        copied[key] = value
    end
    return copied
end

function SearchResultsPage.build(shell, plugin, route, runtime)
    if route.loading and #(route.books or {}) == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Loading"), _("Searching..."))
    end

    if route.error and #(route.books or {}) == 0 then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), tostring(route.error))
    end

    local items = {
        {
            title = _("Search again"),
            mandatory = route.keyword,
            callback = function()
                SearchFlow.showInput(plugin, route.source, route.keyword, {
                    tab = route.tab,
                })
            end,
        },
    }

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

    if #route.books == 0 then
        table.insert(items, {
            title = _("No results."),
            dim = true,
        })
    end

    if route.error and #route.books > 0 then
        table.insert(items, {
            title = _("Last request failed"),
            subtitle = tostring(route.error),
            dim = true,
        })
    end

    return ContentBuilder.buildList(shell, items)
end

return SearchResultsPage
