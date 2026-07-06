local _ = require("novel.i18n")
local BookshelfFlow = require("novel.ui.bookshelf.flow")
local ChaptersFlow = require("novel.ui.chapters.flow")
local ContentBuilder = require("novel.ui.contentbuilder")

local BookshelfPage = {}

local function records(plugin)
    if not plugin or not plugin.app then
        return {}
    end
    return plugin.app:getBookshelfStore():list()
end

local function title(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function findCurrentSource(plugin, record)
    local source_url = record.source_url or ""
    local sources = plugin.app:getSourceStore():list()
    for index = 1, #sources do
        local source = sources[index]
        if source.bookSourceUrl == source_url then
            return source
        end
    end
    return record.source
end

local function subtitleParts(record)
    local current = record and record.current or nil
    if current and current.chapter and current.chapter.title then
        return {
            _("Current chapter: ") .. tostring(current.chapter.title),
        }
    end
    if current and current.chapter_title then
        return {
            _("Current chapter: ") .. tostring(current.chapter_title),
        }
    end
    return nil
end

function BookshelfPage.build(shell, plugin)
    local records_list = records(plugin)
    if #records_list == 0 then
        return ContentBuilder.buildEmptyContent(shell, _("Empty"))
    end

    local items = {}
    for index = 1, #records_list do
        local record = records_list[index]
        items[index] = {
            text = title(record.book),
            book = record.book,
            source_title = record.source_name,
            book_subtitle_parts = subtitleParts(record),
            action_buttons = {
                {
                    id = "resume",
                    icon = "circle-play",
                    callback = function()
                        BookshelfFlow.resume(plugin, record)
                    end,
                },
                {
                    id = "more",
                    icon = "ellipsis-vertical",
                    callback = function()
                        if type(BookshelfFlow.showDetails) == "function" then
                            BookshelfFlow.showDetails(plugin, record)
                        end
                    end,
                },
            },
            callback = function()
                ChaptersFlow.show(plugin, findCurrentSource(plugin, record), record.book)
            end,
        }
    end

    return ContentBuilder.buildList(shell, items)
end

return BookshelfPage
