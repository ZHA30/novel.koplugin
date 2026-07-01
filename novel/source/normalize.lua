local BookSource = require("novel.model.booksource")
local Status = require("novel.source.status")
local rapidjson = require("rapidjson")

local Normalize = {}

local null = rapidjson.null

local function decodeJSON(json)
    local ok, decoded = pcall(rapidjson.decode, json)
    if ok then
        return decoded
    end
end

local function valueOrNil(value)
    if value == null then
        return nil
    end
    return value
end

local function stringOrNil(value)
    value = valueOrNil(value)
    if value == nil then
        return nil
    end
    return tostring(value)
end

local function boolOrDefault(value, default)
    value = valueOrNil(value)
    if type(value) == "boolean" then
        return value
    end
    return default
end

local function numberOrDefault(value, default)
    value = valueOrNil(value)
    if type(value) == "number" then
        return value
    end
    return default
end

local function normalizeType(value)
    value = valueOrNil(value)
    if value == "AUDIO" or value == "audio" or value == "1" or value == 1 then
        return BookSource.book_types.audio
    elseif value == "IMAGE" or value == "image" or value == "2" or value == 2 then
        return BookSource.book_types.image
    elseif value == "FILE" or value == "file" or value == "3" or value == 3 then
        return BookSource.book_types.file
    end
    return BookSource.book_types.default
end

local function decodeRule(rule)
    rule = valueOrNil(rule)
    if rule == nil then
        return nil
    end
    if type(rule) == "string" then
        local decoded = decodeJSON(rule)
        if type(decoded) == "table" then
            return decoded
        end
        return nil
    end
    if type(rule) == "table" then
        return rule
    end
    return nil
end

local function newRule(fields)
    local rule = {}
    local has_value = false
    for key, value in pairs(fields) do
        rule[key] = stringOrNil(value)
        if rule[key] ~= nil and rule[key] ~= "" then
            has_value = true
        end
    end
    if has_value then
        return rule
    end
    return nil
end

local function toNewUrl(url)
    url = stringOrNil(url)
    if not url or url == "" then
        return nil
    end
    url = url:gsub("searchKey", "{{key}}")
    url = url:gsub("searchPage%+1", "{{page+1}}")
    url = url:gsub("searchPage%-1", "{{page-1}}")
    url = url:gsub("searchPage", "{{page}}")
    return url
end

local function normalizeNew(raw)
    local source = BookSource.new{
        bookSourceName = stringOrNil(raw.bookSourceName) or "",
        bookSourceGroup = stringOrNil(raw.bookSourceGroup),
        bookSourceUrl = stringOrNil(raw.bookSourceUrl) or "",
        bookSourceType = normalizeType(raw.bookSourceType),
        bookUrlPattern = stringOrNil(raw.bookUrlPattern),
        customOrder = numberOrDefault(raw.customOrder, 0),
        enabled = boolOrDefault(raw.enabled, true),
        enabledExplore = boolOrDefault(raw.enabledExplore, true),
        concurrentRate = stringOrNil(raw.concurrentRate),
        header = stringOrNil(raw.header),
        loginUrl = type(valueOrNil(raw.loginUrl)) == "table"
            and stringOrNil(raw.loginUrl.url)
            or stringOrNil(raw.loginUrl),
        loginCheckJs = stringOrNil(raw.loginCheckJs),
        lastUpdateTime = numberOrDefault(raw.lastUpdateTime, 0),
        weight = numberOrDefault(raw.weight, 0),
        exploreUrl = stringOrNil(raw.exploreUrl),
        ruleExplore = decodeRule(raw.ruleExplore),
        searchUrl = stringOrNil(raw.searchUrl),
        ruleSearch = decodeRule(raw.ruleSearch),
        ruleBookInfo = decodeRule(raw.ruleBookInfo),
        ruleToc = decodeRule(raw.ruleToc),
        ruleContent = decodeRule(raw.ruleContent),
        bookSourceComment = stringOrNil(raw.bookSourceComment),
        respondTime = numberOrDefault(raw.respondTime, 180000),
    }
    source.support_status = Status.collect(source)
    return source
end

local function uaToHeader(user_agent)
    user_agent = stringOrNil(user_agent)
    if not user_agent or user_agent == "" then
        return nil
    end
    return rapidjson.encode({ ["User-Agent"] = user_agent })
end

local function normalizeOld(raw)
    local source = BookSource.new{
        bookSourceName = stringOrNil(raw.bookSourceName) or "",
        bookSourceGroup = stringOrNil(raw.bookSourceGroup),
        bookSourceUrl = stringOrNil(raw.bookSourceUrl) or "",
        bookSourceType = normalizeType(raw.bookSourceType),
        bookUrlPattern = stringOrNil(raw.ruleBookUrlPattern),
        customOrder = numberOrDefault(raw.serialNumber, 0),
        enabled = boolOrDefault(raw.enable, true),
        enabledExplore = stringOrNil(raw.ruleFindUrl) ~= nil,
        header = uaToHeader(raw.httpUserAgent),
        searchUrl = toNewUrl(raw.ruleSearchUrl),
        exploreUrl = toNewUrl(raw.ruleFindUrl),
        bookSourceComment = stringOrNil(raw.bookSourceComment),
        ruleSearch = newRule{
            bookList = raw.ruleSearchList,
            name = raw.ruleSearchName,
            author = raw.ruleSearchAuthor,
            intro = raw.ruleSearchIntroduce,
            kind = raw.ruleSearchKind,
            bookUrl = raw.ruleSearchNoteUrl,
            coverUrl = raw.ruleSearchCoverUrl,
            lastChapter = raw.ruleSearchLastChapter,
        },
        ruleExplore = newRule{
            bookList = raw.ruleFindList,
            name = raw.ruleFindName,
            author = raw.ruleFindAuthor,
            intro = raw.ruleFindIntroduce,
            kind = raw.ruleFindKind,
            bookUrl = raw.ruleFindNoteUrl,
            coverUrl = raw.ruleFindCoverUrl,
            lastChapter = raw.ruleFindLastChapter,
        },
        ruleBookInfo = newRule{
            init = raw.ruleBookInfoInit,
            name = raw.ruleBookName,
            author = raw.ruleBookAuthor,
            intro = raw.ruleIntroduce,
            kind = raw.ruleBookKind,
            coverUrl = raw.ruleCoverUrl,
            lastChapter = raw.ruleBookLastChapter,
            tocUrl = raw.ruleChapterUrl,
        },
        ruleToc = newRule{
            chapterList = raw.ruleChapterList,
            chapterName = raw.ruleChapterName,
            chapterUrl = raw.ruleContentUrl,
            nextTocUrl = raw.ruleChapterUrlNext,
        },
        ruleContent = newRule{
            content = raw.ruleBookContent,
            replaceRegex = raw.ruleBookContentReplace,
            nextContentUrl = raw.ruleContentUrlNext,
        },
    }
    source.support_status = Status.collect(source)
    return source
end

function Normalize.source(raw)
    if type(raw) ~= "table" then
        return nil, "book source must be an object"
    end
    if stringOrNil(raw.bookSourceUrl) == nil or stringOrNil(raw.bookSourceUrl) == "" then
        return nil, "bookSourceUrl is required"
    end
    if raw.ruleToc == nil then
        return normalizeOld(raw)
    end
    return normalizeNew(raw)
end

return Normalize
