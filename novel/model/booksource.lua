local BookSource = {}

BookSource.book_types = {
    default = 0,
    audio = 1,
    image = 2,
    file = 3,
}

BookSource.fields = {
    "bookSourceName",
    "bookSourceGroup",
    "bookSourceUrl",
    "bookSourceType",
    "bookUrlPattern",
    "customOrder",
    "enabled",
    "enabledExplore",
    "concurrentRate",
    "header",
    "loginUrl",
    "loginUi",
    "loginCheckJs",
    "lastUpdateTime",
    "weight",
    "exploreUrl",
    "ruleExplore",
    "searchUrl",
    "ruleSearch",
    "ruleBookInfo",
    "ruleToc",
    "ruleContent",
    "bookSourceComment",
    "respondTime",
}

BookSource.defaults = {
    bookSourceName = "",
    bookSourceGroup = nil,
    bookSourceUrl = "",
    bookSourceType = BookSource.book_types.default,
    bookUrlPattern = nil,
    customOrder = 0,
    enabled = true,
    enabledExplore = true,
    concurrentRate = nil,
    header = nil,
    loginUrl = nil,
    loginUi = nil,
    loginCheckJs = nil,
    lastUpdateTime = 0,
    weight = 0,
    exploreUrl = nil,
    ruleExplore = nil,
    searchUrl = nil,
    ruleSearch = nil,
    ruleBookInfo = nil,
    ruleToc = nil,
    ruleContent = nil,
    bookSourceComment = nil,
    respondTime = 180000,
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

function BookSource.new(values)
    local source = clone(BookSource.defaults)
    for field_index = 1, #BookSource.fields do
        local key = BookSource.fields[field_index]
        if values[key] ~= nil then
            source[key] = values[key]
        end
    end
    source.support_status = values.support_status or {}
    return source
end

function BookSource.getKey(source)
    return source.bookSourceUrl
end

function BookSource.getName(source)
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl
end

return BookSource
