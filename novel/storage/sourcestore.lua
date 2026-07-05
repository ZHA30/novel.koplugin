-- luacheck: globals lfs

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local rapidjson = require("rapidjson")

local SourceStore = {
    state_path = DataStorage:getSettingsDir() .. "/novel_sources.lua",
    source_dir = (debug.getinfo(1, "S").source:match("^@(.*/)novel/storage/sourcestore%.lua$")
        or "./") .. "source",
}
SourceStore.__index = SourceStore

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

local Status = {}

local function sourceKey(source)
    return source.bookSourceUrl
end

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

local js_patterns = {
    "@js",
    "<js>",
    "{{",
}

local deferred_fields = {
    loginUrl = "js",
    loginUi = "ui",
    loginCheckJs = "js",
}

local rule_fields = {
    ruleExplore = true,
    ruleSearch = true,
    ruleBookInfo = true,
    ruleToc = true,
    ruleContent = true,
}

local function addStatus(status, source, field, kind, snippet)
    table.insert(status, {
        source = source.bookSourceName ~= "" and source.bookSourceName or source.bookSourceUrl,
        field = field,
        kind = kind,
        snippet = snippet,
    })
end

local function containsUnsupportedRule(value)
    if type(value) ~= "string" then
        return nil
    end
    local lowered = value:lower()
    for _, pattern in ipairs(js_patterns) do
        if lowered:find(pattern, 1, true) then
            return pattern
        end
    end
end

local function scanRuleTable(status, source, field, rule)
    if type(rule) ~= "table" then
        return
    end
    for rule_field, value in pairs(rule) do
        local match = containsUnsupportedRule(value)
        if match then
            addStatus(status, source, field .. "." .. rule_field, "js", value:sub(1, 120))
        end
    end
end

function Status.collect(source)
    local status = {}

    for field, kind in pairs(deferred_fields) do
        local value = source[field]
        if value and value ~= "" then
            addStatus(status, source, field, kind, tostring(value):sub(1, 120))
        end
    end

    for field in pairs(rule_fields) do
        scanRuleTable(status, source, field, source[field])
    end

    return status
end

local function sortSources(sources)
    table.sort(sources, function(left, right)
        if left.customOrder ~= right.customOrder then
            return left.customOrder < right.customOrder
        end
        return (left.bookSourceName or "") < (right.bookSourceName or "")
    end)
end

function SourceStore:new()
    return setmetatable({
        settings = LuaSettings:open(SourceStore.state_path),
    }, self)
end

local function isJSONFile(entry)
    return type(entry) == "string" and entry:lower():match("%.json$") ~= nil
end

local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, err or "failed to open file"
    end

    local content = file:read("*a")
    file:close()
    return content
end

local function sourceFiles()
    if lfs.attributes(SourceStore.source_dir, "mode") ~= "directory" then
        return {}
    end

    local ok, iter, dir_obj = pcall(lfs.dir, SourceStore.source_dir)
    if not ok then
        return {}
    end

    local files = {}
    for entry in iter, dir_obj do
        if isJSONFile(entry) then
            local path = SourceStore.source_dir .. "/" .. entry
            local mode = lfs.attributes(path, "mode")
            if mode == "file" or mode == "link" then
                table.insert(files, path)
            end
        end
    end
    table.sort(files)
    return files
end

local function loadFile(path)
    local content, read_err = readFile(path)
    if not content then
        return {}, {
            { file = path, error = read_err },
        }
    end

    local sources, errors = SourceStore.fromJSON(content)
    if not sources then
        return {}, {
            { file = path, error = errors },
        }
    end

    if type(errors) == "table" then
        for error_index = 1, #errors do
            errors[error_index].file = path
        end
    end
    return sources, errors or {}
end

function SourceStore:enabledStates()
    return self.settings:readSetting("source_enabled") or {}
end

local function applyState(source, states)
    local state = states[sourceKey(source)]
    if state ~= nil then
        source.enabled = state == true
    end
    return source
end

function SourceStore:listWithErrors()
    local sources, errors, index = {}, {}, {}
    local states = self:enabledStates()
    local files = sourceFiles()

    for file_index = 1, #files do
        local imported, file_errors = loadFile(files[file_index])
        for error_index = 1, #file_errors do
            table.insert(errors, file_errors[error_index])
        end
        for source_index = 1, #imported do
            local source = applyState(imported[source_index], states)
            local key = sourceKey(source)
            local existing_position = index[key]
            if existing_position then
                sources[existing_position] = source
            else
                index[key] = #sources + 1
                table.insert(sources, source)
            end
        end
    end

    sortSources(sources)
    return sources, errors
end

function SourceStore:list()
    local sources = self:listWithErrors()
    return sources
end

function SourceStore:get(book_source_url)
    for _, source in ipairs(self:list()) do
        if source.bookSourceUrl == book_source_url then
            return source
        end
    end
end

function SourceStore:count()
    return #self:list()
end

function SourceStore:groups()
    local groups = {}
    for _, source in ipairs(self:list()) do
        local group = source.bookSourceGroup or ""
        groups[group] = (groups[group] or 0) + 1
    end
    return groups
end

function SourceStore:listGroups()
    local groups, group_index = {}, {}
    for _, source in ipairs(self:list()) do
        local group_name = source.bookSourceGroup or ""
        local position = group_index[group_name]
        if not position then
            position = #groups + 1
            group_index[group_name] = position
            groups[position] = {
                name = group_name,
                sources = {},
            }
        end
        table.insert(groups[position].sources, source)
    end

    table.sort(groups, function(left, right)
        if left.name == "" then
            return false
        end
        if right.name == "" then
            return true
        end
        return left.name < right.name
    end)

    return groups
end

function SourceStore:setEnabled(book_source_url, enabled)
    if not self:get(book_source_url) then
        return false
    end

    local states = self:enabledStates()
    states[book_source_url] = enabled == true
    self.settings:saveSetting("source_enabled", states)
    self.settings:flush()
    return true
end

function SourceStore.deleteStorage()
    os.remove(SourceStore.state_path)
    os.remove(SourceStore.state_path .. ".old")
end

function SourceStore.key(source)
    if type(source) ~= "table" then
        return ""
    end
    return BookSource.getKey(source) or ""
end

function SourceStore.title(source)
    if type(source) ~= "table" then
        return ""
    end
    return BookSource.getName(source) or ""
end

function SourceStore.canSearch(source)
    return type(source) == "table"
        and source.enabled ~= false
        and source.searchUrl ~= nil
        and source.searchUrl ~= ""
        and type(source.ruleSearch) == "table"
end

function SourceStore.canExplore(source)
    return type(source) == "table"
        and source.enabled ~= false
        and source.enabledExplore ~= false
        and source.exploreUrl ~= nil
        and source.exploreUrl ~= ""
end

function SourceStore.searchable(sources)
    local searchable = {}
    for source_index = 1, #(sources or {}) do
        local source = sources[source_index]
        if SourceStore.canSearch(source) then
            table.insert(searchable, source)
        end
    end
    return searchable
end

local null = rapidjson.null

local function decodeJSON(json)
    local ok, decoded_or_error = pcall(rapidjson.decode, json)
    if ok then
        return decoded_or_error
    end
    return nil, decoded_or_error
end

local function encodeJSON(value)
    local ok, encoded = pcall(rapidjson.encode, value)
    if ok and type(encoded) == "string" then
        return encoded
    end
    return nil
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

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
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

function SourceStore.normalize(raw)
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

local function isArray(value)
    return type(value) == "table" and value[1] ~= nil
end

function SourceStore.fromJSON(json)
    local raw, decode_error = decodeJSON(json)
    if not raw then
        return nil, decode_error or "invalid JSON"
    end

    local raw_sources = isArray(raw) and raw or { raw }
    local sources, errors = {}, {}

    for index, raw_source in ipairs(raw_sources) do
        local source, err = SourceStore.normalize(raw_source)
        if source then
            table.insert(sources, source)
        else
            table.insert(errors, {
                index = index,
                error = err,
            })
        end
    end

    return sources, errors
end

return SourceStore
