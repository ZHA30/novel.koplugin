local _ = require("novel.i18n")
local SourceStore = require("novel.storage.sourcestore")

local DiscoverResultSet = {}

function DiscoverResultSet.sourceTitle(source)
    return SourceStore.title(source)
end

function DiscoverResultSet.resultTitle(group, first_page, last_page)
    local title = group and group.title or _("Discover")
    first_page = tonumber(first_page) or tonumber(last_page) or 1
    last_page = tonumber(last_page) or first_page
    if first_page ~= last_page then
        return title .. " (" .. tostring(first_page) .. "-" .. tostring(last_page) .. ")"
    end
    return title .. " (" .. tostring(last_page) .. ")"
end

function DiscoverResultSet.bookKey(book)
    book = book or {}
    local book_url = tostring(book.bookUrl or "")
    if book_url ~= "" then
        return book_url
    end
    local name = tostring(book.name or "")
    if name == "" then
        return nil
    end
    return name .. "\n" .. tostring(book.author or "")
end

function DiscoverResultSet.mergeBooks(existing_books, new_books)
    local merged = {}
    local known = {}

    for index = 1, #(existing_books or {}) do
        local book = existing_books[index]
        merged[#merged + 1] = book
        local key = DiscoverResultSet.bookKey(book)
        if key then
            known[key] = true
        end
    end

    local appended = 0
    for index = 1, #(new_books or {}) do
        local book = new_books[index]
        local key = DiscoverResultSet.bookKey(book)
        if not key or not known[key] then
            merged[#merged + 1] = book
            appended = appended + 1
            if key then
                known[key] = true
            end
        end
    end

    return merged, appended
end

function DiscoverResultSet.sameRoute(route, source, group)
    if not route or route.key ~= "discover_results" then
        return false
    end
    local route_source = route.source or {}
    local route_group = route.group or {}
    local source_url = source and source.bookSourceUrl or nil
    local group_url = group and group.url or nil
    return route_source.bookSourceUrl == source_url
        and route_group.url == group_url
end

return DiscoverResultSet
