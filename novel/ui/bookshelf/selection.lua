local OfflineFiles = require("novel.storage.offlinefiles")

local BookshelfSelection = {}

local function selectionKey(record)
    if not record then
        return nil
    end
    return OfflineFiles.bookId(record.source, record.book)
end

local function selectionMap(plugin, create)
    if not plugin then
        return nil
    end
    if type(plugin.novel_bookshelf_selection) ~= "table" then
        if not create then
            return nil
        end
        plugin.novel_bookshelf_selection = {}
    end
    return plugin.novel_bookshelf_selection
end

function BookshelfSelection.isMode(plugin)
    return plugin and plugin.novel_bookshelf_selection_mode == true or false
end

function BookshelfSelection.setMode(plugin, enabled)
    if not plugin then
        return false
    end
    plugin.novel_bookshelf_selection_mode = enabled == true or nil
    if enabled ~= true then
        plugin.novel_bookshelf_selection = nil
    end
    return plugin.novel_bookshelf_selection_mode == true
end

function BookshelfSelection.isSelected(plugin, record)
    local selected = selectionMap(plugin)
    local key = selectionKey(record)
    return selected and key and selected[key] == true or false
end

function BookshelfSelection.toggle(plugin, record)
    local key = selectionKey(record)
    if not key then
        return false
    end
    local selected = selectionMap(plugin, true)
    selected[key] = not selected[key]
    plugin.novel_bookshelf_selection_mode = true
    return selected[key] == true
end

function BookshelfSelection.setAll(plugin, records, selected)
    local selection = selectionMap(plugin, true)
    for index = 1, #(records or {}) do
        local key = selectionKey(records[index])
        if key then
            selection[key] = selected == true or nil
        end
    end
end

function BookshelfSelection.state(plugin, records)
    local selected_count = 0
    local record_count = #(records or {})
    for index = 1, record_count do
        if BookshelfSelection.isSelected(plugin, records[index]) then
            selected_count = selected_count + 1
        end
    end
    return {
        selected_count = selected_count,
        all_selected = record_count > 0 and selected_count == record_count,
    }
end

function BookshelfSelection.records(plugin, records)
    local selected = {}
    for index = 1, #(records or {}) do
        local record = records[index]
        if BookshelfSelection.isSelected(plugin, record) then
            table.insert(selected, record)
        end
    end
    return selected
end

return BookshelfSelection
