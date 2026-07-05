local ExploreService = require("novel.catalog.listing.exploreservice")
local SourceStore = require("novel.storage.sourcestore")
local Url = require("novel.catalog.shared.url")
local rapidjson = require("rapidjson")

local DiscoverService = {}

local function compactBooks(books)
    local compact = {}
    for book_index = 1, #(books or {}) do
        local book = books[book_index]
        compact[book_index] = {
            name = book.name or "",
            author = book.author or "",
            intro = book.intro or "",
            kind = book.kind or "",
            latestChapter = book.latestChapter or "",
            latestChapterTitle = book.latestChapterTitle or "",
            updateTime = book.updateTime or "",
            bookUrl = book.bookUrl or "",
            coverUrl = book.coverUrl or "",
            wordCount = book.wordCount or "",
            origin = book.origin or "",
            originName = book.originName or "",
            originOrder = book.originOrder or 0,
            type = book.type or 0,
        }
    end
    return compact
end

local function compactUnsupported(items)
    local compact = {}
    for item_index = 1, #(items or {}) do
        local item = items[item_index]
        compact[item_index] = {
            source = item.source or "",
            field = item.field or "",
            kind = item.kind or "",
            snippet = item.snippet or "",
        }
    end
    return compact
end

local function compactResponse(response)
    if type(response) ~= "table" then
        return nil
    end
    return {
        request_url = response.request_url,
        final_url = response.final_url,
        status = response.status,
        bytes = response.bytes,
        charset = response.charset,
        charset_error = response.charset_error,
    }
end

local function jsonString(value)
    value = tostring(value or "")
    value = value:gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
    return "\"" .. value .. "\""
end

local function errorJSON(kind, message)
    return '{"ok":false,"books":[],"unsupported":[],"error":{"kind":'
        .. jsonString(kind) .. ',"message":' .. jsonString(message) .. "}}"
end

local function compactResult(result)
    result = result or {}
    return {
        ok = result.ok == true,
        books = compactBooks(result.books),
        unsupported = compactUnsupported(result.unsupported),
        error = result.error and {
            kind = result.error.kind or "unknown",
            message = result.error.message or tostring(result.error.kind or ""),
        } or nil,
        response = compactResponse(result.response),
        group = result.group and {
            title = result.group.title,
            url = result.group.url,
            page = result.group.page,
        } or nil,
    }
end

local function sortedFields(fields)
    local parts = {}
    if type(fields) ~= "table" then
        return ""
    end
    for key, value in pairs(fields) do
        table.insert(parts, tostring(key) .. "=" .. tostring(value or ""))
    end
    table.sort(parts)
    return table.concat(parts, "&")
end

local function requestSignature(source, group, page)
    if type(source) ~= "table" or type(group) ~= "table" or not group.url then
        return nil
    end
    local spec = Url.parse(group.url, {
        base_url = source.bookSourceUrl,
        headers = source.header,
        page = page,
    })
    return table.concat({
        tostring(spec.method or "GET"),
        tostring(spec.url or ""),
        tostring(spec.body or ""),
        sortedFields(spec.fields),
    }, "\n")
end

function DiscoverService.isSourceEnabled(source)
    return SourceStore.canExplore(source)
end

function DiscoverService.sourceGroups(sources)
    local source_groups, unsupported = {}, {}
    for source_index = 1, #(sources or {}) do
        local source = sources[source_index]
        if DiscoverService.isSourceEnabled(source) then
            local groups, source_unsupported = ExploreService.groups(source)
            table.insert(source_groups, {
                source = source,
                groups = groups,
            })
            for item_index = 1, #source_unsupported do
                table.insert(unsupported, source_unsupported[item_index])
            end
        end
    end
    return source_groups, unsupported
end

function DiscoverService.canRequestNextPage(source, group, page)
    page = tonumber(page) or 1
    local current_signature = requestSignature(source, group, page)
    local next_signature = requestSignature(source, group, page + 1)
    return current_signature ~= nil
        and next_signature ~= nil
        and current_signature ~= next_signature
end

function DiscoverService.run(source, group, page)
    local ok, result = xpcall(function()
        return ExploreService.run(source, group, {
            page = page,
        })
    end, debug.traceback)
    if ok then
        return result
    end
    return {
        ok = false,
        books = {},
        unsupported = {},
        error = {
            kind = "exception",
            message = result,
        },
    }
end

function DiscoverService.encodeResult(result)
    local ok, encoded_or_error = pcall(rapidjson.encode, compactResult(result))
    if ok and type(encoded_or_error) == "string" then
        return encoded_or_error
    end
    local message = ok and "rapidjson.encode returned nil" or encoded_or_error
    ok, encoded_or_error = pcall(rapidjson.encode, {
        ok = false,
        books = {},
        unsupported = {},
        error = {
            kind = "serialization",
            message = tostring(message),
        },
    })
    if ok and type(encoded_or_error) == "string" then
        return encoded_or_error
    end
    return errorJSON("serialization", message)
end

function DiscoverService.decodeResult(encoded)
    if type(encoded) ~= "string" or encoded == "" then
        return nil
    end
    local ok, decoded = pcall(rapidjson.decode, encoded)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return {
        ok = false,
        books = {},
        unsupported = {},
        error = {
            kind = "serialization",
            message = tostring(decoded),
        },
    }
end

function DiscoverService.runEncoded(source, group, page)
    local ok, encoded_or_error = xpcall(function()
        return DiscoverService.encodeResult(DiscoverService.run(source, group, page))
    end, debug.traceback)
    if ok and type(encoded_or_error) == "string" then
        return encoded_or_error
    end
    return errorJSON("exception", encoded_or_error)
end

return DiscoverService
