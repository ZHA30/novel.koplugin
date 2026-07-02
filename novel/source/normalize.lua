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

local function encodeJSON(value)
    local ok, encoded = pcall(rapidjson.encode, value)
    if ok and type(encoded) == "string" then
        return encoded
    end
    return nil
end

local function stringLikeOrNil(value)
    value = valueOrNil(value)
    if value == nil then
        return nil
    end
    if type(value) == "table" then
        return encodeJSON(value)
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

local function startsWithIgnoreCase(value, prefix)
    return value:sub(1, #prefix):lower() == prefix:lower()
end

local function containsIgnoreCase(value, pattern)
    return value:lower():find(pattern:lower(), 1, true) ~= nil
end

local function toNewRule(rule)
    rule = stringOrNil(rule)
    if not rule or rule == "" then
        return nil
    end
    local reverse = false
    local all_in_one = false
    if rule:sub(1, 1) == "-" then
        reverse = true
        rule = rule:sub(2)
    end
    if rule:sub(1, 1) == "+" then
        all_in_one = true
        rule = rule:sub(2)
    end
    if not startsWithIgnoreCase(rule, "@CSS:")
        and not startsWithIgnoreCase(rule, "@XPath:")
        and not startsWithIgnoreCase(rule, "//")
        and not startsWithIgnoreCase(rule, "##")
        and not startsWithIgnoreCase(rule, ":")
        and not containsIgnoreCase(rule, "@js:")
        and not containsIgnoreCase(rule, "<js>") then
        if rule:find("#", 1, true) and not rule:find("##", 1, true) then
            rule = rule:gsub("#", "##")
        end
        if rule:find("|", 1, true) and not rule:find("||", 1, true) then
            local separator_start = rule:find("##", 1, true)
            if separator_start then
                local head = rule:sub(1, separator_start - 1):gsub("|", "||")
                rule = head .. rule:sub(separator_start)
            else
                rule = rule:gsub("|", "||")
            end
        end
        if rule:find("&", 1, true)
            and not rule:find("&&", 1, true)
            and not containsIgnoreCase(rule, "http")
            and rule:sub(1, 1) ~= "/" then
            rule = rule:gsub("&", "&&")
        end
    end
    if all_in_one then
        rule = "+" .. rule
    end
    if reverse then
        rule = "-" .. rule
    end
    return rule
end

local function newRule(fields)
    local rule = {}
    local has_value = false
    for key, value in pairs(fields) do
        rule[key] = toNewRule(value)
        if rule[key] ~= nil and rule[key] ~= "" then
            has_value = true
        end
    end
    if has_value then
        return rule
    end
    return nil
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function replaceOldUrlTemplates(url)
    local templates = {}
    url = url:gsub("{{.-}}", function(template)
        table.insert(templates, template)
        return "\1" .. tostring(#templates) .. "\1"
    end)
    url = url:gsub("{", "<"):gsub("}", ">")
    url = url:gsub("searchKey", "{{key}}")
    url = url:gsub("<searchPage([%+%-]1)>", "{{page%1}}")
    url = url:gsub("searchPage([%+%-]1)", "{{page%1}}")
    url = url:gsub("searchPage", "{{page}}")
    url = url:gsub("\1(%d+)\1", function(index)
        local template = templates[tonumber(index)] or ""
        return template:gsub("searchKey", "key"):gsub("searchPage", "page")
    end)
    return url
end

local function toNewUrl(url)
    url = stringOrNil(url)
    if not url or url == "" then
        return nil
    end
    if startsWithIgnoreCase(url, "<js>") then
        return url:gsub("=searchKey", "={{key}}")
            :gsub("=searchPage", "={{page}}")
    end

    local options = {}
    local header = url:match("@[Hh][Ee][Aa][Dd][Ee][Rr]:%b{}")
    if header then
        url = url:gsub(header:gsub("([^%w])", "%%%1"), "", 1)
        options.headers = header:sub(9)
    end

    local charset_start = url:find("|", 1, true)
    if charset_start then
        local charset = url:sub(charset_start + 1):match("^[Cc][Hh][Aa][Rr][Ss][Ee][Tt]=(.*)$")
        if charset then
            options.charset = charset
            url = url:sub(1, charset_start - 1)
        end
    end

    url = replaceOldUrlTemplates(url)

    local body_start = url:find("@", 1, true)
    if body_start then
        options.method = "POST"
        options.body = url:sub(body_start + 1)
        url = url:sub(1, body_start - 1)
    end

    if next(options) ~= nil then
        url = url .. "," .. encodeJSON(options)
    end
    return url
end

local function toNewUrls(urls)
    urls = stringOrNil(urls)
    if not urls or urls == "" then
        return nil
    end
    if startsWithIgnoreCase(urls, "@js:")
        or startsWithIgnoreCase(urls, "<js>") then
        return urls
    end
    if not urls:find("\n", 1, true) and not urls:find("&&", 1, true) then
        return toNewUrl(urls)
    end
    local parts = {}
    local normalized = urls:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("&&", "\n")
    for line in (normalized .. "\n"):gmatch("([^\n]*)\n") do
        local converted = toNewUrl(trim(line))
        if converted and converted ~= "" then
            local single_line = converted:gsub("\n%s*", "")
            table.insert(parts, single_line)
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "\n")
end

local function headerValue(raw)
    local header = stringOrNil(raw.header)
    if header and header ~= "" then
        return header
    end
    return stringLikeOrNil(raw.headerMap)
end

local function loginUrlValue(value)
    value = valueOrNil(value)
    if type(value) == "table" then
        return stringOrNil(value.url)
    end
    return stringOrNil(value)
end

local function contentRule(value)
    local rule = toNewRule(value)
    if rule and rule:sub(1, 1) == "$" and rule:sub(1, 2) ~= "$." then
        return rule:sub(2)
    end
    return rule
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
        header = headerValue(raw),
        loginUrl = loginUrlValue(raw.loginUrl),
        loginUi = stringLikeOrNil(raw.loginUi),
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
        exploreUrl = toNewUrls(raw.ruleFindUrl),
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
            content = contentRule(raw.ruleBookContent),
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
