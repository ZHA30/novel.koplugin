local DownloadItem = {}

local function clean(value)
    value = tostring(value or ""):gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function legacyKey(book_id, position)
    return tostring(book_id or "") .. ":" .. tostring(position or 0)
end

function DownloadItem.key(book_id, chapter, position)
    local file_name = clean(chapter and chapter.file_name)
    if file_name == "" then
        return legacyKey(book_id, position)
    end
    return tostring(book_id or "") .. ":chapter:" .. file_name
end

function DownloadItem.bind(item, chapter, position)
    if not item or not chapter then
        return item
    end
    item.position = position
    item.chapter_file_name = clean(chapter.file_name)
    item.chapter_url = clean(chapter.url)
    item.key = DownloadItem.key(item.book_id, chapter, position)
    return item
end

function DownloadItem.resolve(manifest, item)
    local chapters = manifest and manifest.chapters or {}
    local file_name = clean(item and item.chapter_file_name)
    if file_name ~= "" then
        for position = 1, #chapters do
            if clean(chapters[position].file_name) == file_name then
                return chapters[position], position
            end
        end
        return nil
    end

    local chapter_url = clean(item and item.chapter_url)
    if chapter_url ~= "" then
        for position = 1, #chapters do
            if clean(chapters[position].url) == chapter_url then
                return chapters[position], position
            end
        end
        return nil
    end

    local title = clean(item and item.title)
    if title ~= "" then
        local matched_chapter
        local matched_position
        local matches = 0
        for position = 1, #chapters do
            if clean(chapters[position].title) == title then
                matched_chapter = chapters[position]
                matched_position = position
                matches = matches + 1
            end
        end
        if matches == 1 then
            return matched_chapter, matched_position
        end
        return nil
    end

    local position = tonumber(item and item.position)
    if position and chapters[position] then
        return chapters[position], position
    end
end

return DownloadItem
