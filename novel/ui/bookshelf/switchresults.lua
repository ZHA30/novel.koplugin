local _ = require("novel.i18n")
local BookshelfSupport = require("novel.ui.bookshelf.bookshelfsupport")
local ContentBuilder = require("novel.ui.contentbuilder")
local DetailFlow = require("novel.ui.detail.flow")
local Dialog = require("novel.ui.widget.dialog")

local SwitchResultsPage = {}

function SwitchResultsPage.build(shell, plugin, route)
    local items = {
        {
            title = _("Summary"),
            mandatory = tostring(#(route.candidates or {})),
            callback = function()
                Dialog.message(BookshelfSupport.switchSummary(route))
            end,
        },
    }

    if not route.candidates or #route.candidates == 0 then
        table.insert(items, {
            title = _("No matching books."),
            dim = true,
        })
        return ContentBuilder.buildList(shell, items)
    end

    for index = 1, #route.candidates do
        local candidate = route.candidates[index]
        table.insert(items, {
            text = BookshelfSupport.bookTitle(candidate.book),
            book = candidate.book,
            source_title = candidate.source_name,
            book_extra_metadata = BookshelfSupport.switchReasonText(candidate.reason),
            callback = function()
                DetailFlow.show(plugin, candidate.source, candidate.book)
            end,
        })
        table.insert(items, {
            title = _("Apply switch"),
            mandatory = candidate.source_name,
            indent = 1,
            callback = function()
                route.apply_callback(candidate)
            end,
        })
    end

    return ContentBuilder.buildList(shell, items)
end

return SwitchResultsPage
