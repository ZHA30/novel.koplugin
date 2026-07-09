local ResultSet = {}

function ResultSet.bookKey(book)
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

function ResultSet.mergeBooks(existing_books, new_books)
    local merged = {}
    local known = {}

    for index = 1, #(existing_books or {}) do
        local book = existing_books[index]
        merged[#merged + 1] = book
        local key = ResultSet.bookKey(book)
        if key then
            known[key] = true
        end
    end

    local appended = 0
    for index = 1, #(new_books or {}) do
        local book = new_books[index]
        local key = ResultSet.bookKey(book)
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

function ResultSet.appendUnsupported(existing, added)
    local merged = {}
    for index = 1, #(existing or {}) do
        merged[#merged + 1] = existing[index]
    end
    for index = 1, #(added or {}) do
        merged[#merged + 1] = added[index]
    end
    return merged
end

return ResultSet
