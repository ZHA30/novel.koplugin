local _ = require("novel.i18n")
local ChapterRecord = require("novel.reader.chapterrecord")

local ChapterListing = {}

ChapterListing.SORT_ASCENDING = "ascending"
ChapterListing.SORT_DESCENDING = "descending"

local FILTER_FIELDS = {
    {
        key = "unread",
        text = function()
            return _("Unread")
        end,
    },
    {
        key = "downloaded",
        text = function()
            return _("Downloaded")
        end,
    },
}

function ChapterListing.refreshManifest(manifest_store, manifest, source, book)
    if not manifest or not source then
        return manifest
    end
    local refreshed = manifest_store:ensureBook(source, book or manifest.book,
        manifest.chapters or {})
    return refreshed or manifest
end

function ChapterListing.bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

function ChapterListing.manifestTitle(manifest)
    return ChapterListing.bookTitle(manifest and manifest.book)
end

function ChapterListing.filterLabel()
    return _("Filter")
end

function ChapterListing.sortLabel(sort)
    if sort == ChapterListing.SORT_DESCENDING then
        return _("Descending")
    end
    return _("Ascending")
end

local function chapterTitle(chapter)
    return tostring(chapter.title or "")
end

local function filterValue(value)
    if value == true then
        return true
    end
    if value == false then
        return false
    end
    return nil
end

local function filterMatchesValue(actual, expected)
    return expected == nil or actual == expected
end

local function cloneFilter(filter)
    local copy = {}
    filter = ChapterListing.normalizeFilter(filter)
    for field_index = 1, #FILTER_FIELDS do
        local key = FILTER_FIELDS[field_index].key
        copy[key] = filter[key]
    end
    return copy
end

function ChapterListing.filterFields()
    local fields = {}
    for field_index = 1, #FILTER_FIELDS do
        local field = FILTER_FIELDS[field_index]
        fields[field_index] = {
            key = field.key,
            text = field.text(),
        }
    end
    return fields
end

function ChapterListing.normalizeFilter(filter)
    if type(filter) ~= "table" then
        return {}
    end

    local normalized = {}
    for field_index = 1, #FILTER_FIELDS do
        local key = FILTER_FIELDS[field_index].key
        normalized[key] = filterValue(filter[key])
    end
    return normalized
end

function ChapterListing.copyFilter(filter)
    return cloneFilter(filter)
end

function ChapterListing.hasActiveFilter(filter)
    filter = ChapterListing.normalizeFilter(filter)
    for field_index = 1, #FILTER_FIELDS do
        if filter[FILTER_FIELDS[field_index].key] ~= nil then
            return true
        end
    end
    return false
end

function ChapterListing.filtersEqual(left, right)
    left = ChapterListing.normalizeFilter(left)
    right = ChapterListing.normalizeFilter(right)
    for field_index = 1, #FILTER_FIELDS do
        local key = FILTER_FIELDS[field_index].key
        if left[key] ~= right[key] then
            return false
        end
    end
    return true
end

local function filterNeedsStorageUpdate(stored, filter)
    if type(stored) ~= "table" and stored ~= nil then
        return true
    end
    if not ChapterListing.filtersEqual(stored, filter) then
        return true
    end
    if not ChapterListing.hasActiveFilter(filter) then
        return stored ~= nil
    end
    return false
end

local function matchesFilter(filter, chapter)
    filter = ChapterListing.normalizeFilter(filter)
    if not ChapterListing.hasActiveFilter(filter) then
        return true
    end
    if not ChapterRecord.isOpenable(chapter) then
        return false
    end
    return filterMatchesValue(chapter.read ~= true, filter.unread)
        and filterMatchesValue(chapter.downloaded == true, filter.downloaded)
end

function ChapterListing.normalizeSort(sort)
    if sort == ChapterListing.SORT_DESCENDING then
        return ChapterListing.SORT_DESCENDING
    end
    return ChapterListing.SORT_ASCENDING
end

local function chapterListBooks(plugin)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil
    end
    if type(settings.chapter_list) ~= "table" then
        settings.chapter_list = {}
    end
    if type(settings.chapter_list.books) ~= "table" then
        settings.chapter_list.books = {}
    end
    return settings.chapter_list.books
end

local function chapterListBookState(plugin, book_id, create)
    if not book_id or book_id == "" then
        return nil
    end

    local books = chapterListBooks(plugin)
    if not books then
        return nil
    end

    local state = books[book_id]
    if type(state) ~= "table" then
        if not create then
            return nil
        end
        state = {}
        books[book_id] = state
    end
    return state
end

local function saveBookState(plugin, book_id, filter, sort)
    local state = chapterListBookState(plugin, book_id, true)
    if not state then
        return
    end

    local changed = false
    if filterNeedsStorageUpdate(state.filter, filter) then
        if ChapterListing.hasActiveFilter(filter) then
            state.filter = ChapterListing.copyFilter(filter)
        else
            state.filter = nil
        end
        changed = true
    end
    if state.sort ~= sort then
        state.sort = sort
        changed = true
    end

    if changed and plugin and plugin.app then
        plugin.app:saveSettings()
    end
end

function ChapterListing.resolveState(plugin, manifest, options)
    options = options or {}
    local book_id = manifest and manifest.book_id or nil
    local book_state = chapterListBookState(plugin, book_id)
    plugin.novel_chapters_filter = plugin.novel_chapters_filter or {}
    plugin.novel_chapters_sort = plugin.novel_chapters_sort or {}

    local filter = options.filter
        or (book_id and plugin.novel_chapters_filter[book_id])
        or (book_state and book_state.filter)
        or {}
    filter = ChapterListing.normalizeFilter(filter)
    if book_id then
        if ChapterListing.hasActiveFilter(filter) then
            plugin.novel_chapters_filter[book_id] = ChapterListing.copyFilter(filter)
        else
            plugin.novel_chapters_filter[book_id] = nil
        end
    end

    local sort = options.sort
        or (book_id and plugin.novel_chapters_sort[book_id])
        or (book_state and book_state.sort)
        or ChapterListing.SORT_ASCENDING
    sort = ChapterListing.normalizeSort(sort)
    if book_id then
        plugin.novel_chapters_sort[book_id] = sort
    end

    if options.filter ~= nil or options.sort ~= nil
        or (book_state and (filterNeedsStorageUpdate(book_state.filter, filter)
            or book_state.sort ~= sort)) then
        saveBookState(plugin, book_id, filter, sort)
    end

    return filter, sort
end

function ChapterListing.buildRows(manifest, filter, sort)
    local model = ChapterListing.buildModel(manifest, filter, sort)
    local rows = {}
    for index = 1, model.count do
        table.insert(rows, model.rowAt(index))
    end
    return rows, model.count
end

function ChapterListing.buildModel(manifest, filter, sort)
    local chapters = manifest and manifest.chapters or {}
    filter = ChapterListing.normalizeFilter(filter)
    local start_position = sort == ChapterListing.SORT_DESCENDING and #chapters or 1
    local end_position = sort == ChapterListing.SORT_DESCENDING and 1 or #chapters
    local step = sort == ChapterListing.SORT_DESCENDING and -1 or 1
    local positions

    if ChapterListing.hasActiveFilter(filter) then
        positions = {}
        for position = start_position, end_position, step do
            local chapter = chapters[position]
            if matchesFilter(filter, chapter) then
                positions[#positions + 1] = position
            end
        end
    end

    local function positionAt(index)
        if positions then
            return positions[index]
        end
        if sort == ChapterListing.SORT_DESCENDING then
            return #chapters - index + 1
        end
        return index
    end

    local count = positions and #positions or #chapters
    return {
        count = count,
        rowAt = function(index)
            local position = positionAt(index)
            local chapter = chapters[position] or {}
            local openable = ChapterRecord.isOpenable(chapter)
            return {
                position = position,
                title = chapterTitle(chapter),
                openable = openable,
                downloaded_label = openable and chapter.downloaded == true
                    and _("Downloaded") or nil,
                dim = chapter.read == true or not openable,
            }
        end,
    }
end

local function selectionMap(plugin, manifest, create)
    local book_id = manifest and manifest.book_id
    if not plugin or not book_id then
        return nil
    end
    if type(plugin.novel_chapter_selection) ~= "table" then
        if not create then
            return nil
        end
        plugin.novel_chapter_selection = {}
    end
    local map = plugin.novel_chapter_selection[book_id]
    if type(map) ~= "table" then
        if not create then
            return nil
        end
        map = {}
        plugin.novel_chapter_selection[book_id] = map
    end
    return map
end

local function selectionModeMap(plugin, create)
    if not plugin then
        return nil
    end
    if type(plugin.novel_chapter_selection_mode) ~= "table" then
        if not create then
            return nil
        end
        plugin.novel_chapter_selection_mode = {}
    end
    return plugin.novel_chapter_selection_mode
end

local function selectable(manifest, position)
    local chapter = manifest and manifest.chapters
        and manifest.chapters[tonumber(position)]
    return ChapterRecord.isOpenable(chapter)
end

function ChapterListing.isSelectionMode(plugin, manifest)
    local modes = selectionModeMap(plugin)
    local book_id = manifest and manifest.book_id
    return modes and book_id and modes[book_id] == true or false
end

function ChapterListing.clearSelected(plugin, manifest)
    local book_id = manifest and manifest.book_id
    if plugin and book_id and type(plugin.novel_chapter_selection) == "table" then
        plugin.novel_chapter_selection[book_id] = nil
    end
end

function ChapterListing.setSelectionMode(plugin, manifest, enabled)
    local modes = selectionModeMap(plugin, enabled == true)
    local book_id = manifest and manifest.book_id
    if not modes or not book_id then
        return false
    end
    if enabled == true then
        modes[book_id] = true
        return true
    end
    modes[book_id] = nil
    ChapterListing.clearSelected(plugin, manifest)
    return false
end

function ChapterListing.isSelected(plugin, manifest, position)
    local map = selectionMap(plugin, manifest)
    return map and map[tonumber(position)] == true or false
end

function ChapterListing.setSelected(plugin, manifest, position, selected)
    position = tonumber(position)
    if not selectable(manifest, position) then
        return false
    end
    local map = selectionMap(plugin, manifest, selected == true)
    if not map then
        return false
    end
    map[position] = selected == true or nil
    return map[position] == true
end

function ChapterListing.toggleSelected(plugin, manifest, position)
    position = tonumber(position)
    if not selectable(manifest, position) then
        return false
    end
    local map = selectionMap(plugin, manifest, true)
    map[position] = not map[position]
    return map[position] == true
end

function ChapterListing.setRowsSelected(plugin, manifest, rows, selected)
    local map = selectionMap(plugin, manifest, true)
    for row_index = 1, #(rows or {}) do
        local row = rows[row_index]
        if row.openable and selectable(manifest, row.position) then
            map[row.position] = selected == true or nil
        end
    end
end

function ChapterListing.positionsForRows(manifest, rows)
    local positions = {}
    for row_index = 1, #(rows or {}) do
        local row = rows[row_index]
        if row.openable and selectable(manifest, row.position) then
            table.insert(positions, row.position)
        end
    end
    table.sort(positions)
    return positions
end

function ChapterListing.selectedPositions(plugin, manifest)
    local map = selectionMap(plugin, manifest)
    local positions = {}
    if not map then
        return positions
    end
    for position, selected in pairs(map) do
        if selected == true and selectable(manifest, position) then
            table.insert(positions, tonumber(position))
        end
    end
    table.sort(positions)
    return positions
end

function ChapterListing.selectedPositionsForRows(plugin, manifest, rows)
    local positions = {}
    for row_index = 1, #(rows or {}) do
        local row = rows[row_index]
        if row.openable
            and ChapterListing.isSelected(plugin, manifest, row.position) then
            table.insert(positions, row.position)
        end
    end
    table.sort(positions)
    return positions
end

function ChapterListing.selectionStateForRows(plugin, manifest, rows)
    local selectable_count = 0
    local selected_count = 0
    for row_index = 1, #(rows or {}) do
        local row = rows[row_index]
        if row.openable and selectable(manifest, row.position) then
            selectable_count = selectable_count + 1
            if ChapterListing.isSelected(plugin, manifest, row.position) then
                selected_count = selected_count + 1
            end
        end
    end
    return {
        selectable_count = selectable_count,
        selected_count = selected_count,
        any_selected = selected_count > 0,
        all_selected = selectable_count > 0
            and selected_count == selectable_count,
    }
end

return ChapterListing
