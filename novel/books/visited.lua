local DetailVisited = {}

local MAX_BOOKS = 2000

local function clean(value)
    value = tostring(value or ""):gsub("%s+", " ")
    return value:match("^%s*(.-)%s*$") or ""
end

local function sourceKey(source)
    source = source or {}
    local key = clean(source.bookSourceUrl)
    if key ~= "" then
        return key
    end
    return clean(source.bookSourceName)
end

local function store(plugin, create)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil, false
    end

    local changed = false
    if type(settings.book_list) ~= "table" then
        if not create then
            return nil, false
        end
        settings.book_list = {}
        changed = true
    end
    if type(settings.book_list.detail_visited) ~= "table" then
        if not create then
            return nil, changed
        end
        settings.book_list.detail_visited = {}
        changed = true
    end
    return settings.book_list.detail_visited, changed
end

local function bookKey(source, book)
    book = book or {}
    local source_key = sourceKey(source)
    local book_url = clean(book.bookUrl)
    if source_key ~= "" and book_url ~= "" then
        return source_key .. "\n" .. book_url
    end

    local title = clean(book.name)
    if title == "" then
        return nil
    end
    return table.concat({
        source_key,
        title,
        clean(book.author),
    }, "\n")
end

local function prune(visited)
    local keys = {}
    for key in pairs(visited or {}) do
        keys[#keys + 1] = key
    end
    if #keys <= MAX_BOOKS then
        return false
    end

    table.sort(keys, function(left, right)
        local left_time = tonumber(visited[left]) or 0
        local right_time = tonumber(visited[right]) or 0
        if left_time ~= right_time then
            return left_time < right_time
        end
        return left < right
    end)

    for index = 1, #keys - MAX_BOOKS do
        visited[keys[index]] = nil
    end
    return true
end

function DetailVisited.isVisited(plugin, source, book)
    local key = bookKey(source, book)
    if not key then
        return false
    end
    local visited = store(plugin, false)
    return type(visited) == "table" and visited[key] ~= nil or false
end

function DetailVisited.markVisited(plugin, source, book)
    local key = bookKey(source, book)
    if not key or not plugin or not plugin.app then
        return false
    end

    local visited, changed = store(plugin, true)
    if type(visited) ~= "table" then
        return false
    end
    if visited[key] == nil then
        visited[key] = os.time()
        changed = true
    end
    if prune(visited) then
        changed = true
    end
    if changed then
        plugin.app:saveSettings()
    end
    return changed
end

return DetailVisited
