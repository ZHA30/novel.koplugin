local Chapter = {}

Chapter.fields = {
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

Chapter.defaults = {
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

function Chapter.new(values)
    values = values or {}
    local chapter = clone(Chapter.defaults)
    for field_index = 1, #Chapter.fields do
        local field = Chapter.fields[field_index]
        if values[field] ~= nil then
            chapter[field] = values[field]
        end
    end
    return chapter
end

function Chapter.isOpenable(chapter)
    return chapter and not chapter.isVolume and not chapter.isVip
end

function Chapter.nextOpenable(chapters, position, step)
    step = step or 1
    local target_position = (tonumber(position) or 0) + step
    while chapters and chapters[target_position] do
        if Chapter.isOpenable(chapters[target_position]) then
            return chapters[target_position], target_position
        end
        target_position = target_position + step
    end
    return nil
end

return Chapter
