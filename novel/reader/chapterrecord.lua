local ChapterRecord = {}

ChapterRecord.fields = {
    "url",
    "title",
    "isVolume",
    "isVip",
    "baseUrl",
    "bookUrl",
    "index",
    "resourceUrl",
    "tag",
    "start",
    "end",
    "startFragmentId",
    "endFragmentId",
    "variable",
}

ChapterRecord.defaults = {
    url = "",
    title = "",
    isVolume = false,
    isVip = false,
    baseUrl = "",
    bookUrl = "",
    index = 0,
    resourceUrl = nil,
    tag = nil,
    start = nil,
    ["end"] = nil,
    startFragmentId = nil,
    endFragmentId = nil,
    variable = nil,
}

local function clone(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

function ChapterRecord.new(values)
    values = values or {}
    local chapter = clone(ChapterRecord.defaults)
    for field_index = 1, #ChapterRecord.fields do
        local field = ChapterRecord.fields[field_index]
        if values[field] ~= nil then
            chapter[field] = values[field]
        end
    end
    return chapter
end

function ChapterRecord.isOpenable(chapter)
    return chapter and not chapter.isVolume and not chapter.isVip
end

function ChapterRecord.nextOpenable(chapters, position, step)
    step = step or 1
    local target_position = (tonumber(position) or 0) + step
    while chapters and chapters[target_position] do
        if ChapterRecord.isOpenable(chapters[target_position]) then
            return chapters[target_position], target_position
        end
        target_position = target_position + step
    end
    return nil
end

return ChapterRecord
