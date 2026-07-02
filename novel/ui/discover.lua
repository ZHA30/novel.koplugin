local _ = require("novel.i18n")
local Detail = require("novel.ui.detail")
local DiscoverList = require("novel.ui.discoverlist")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("novel.ui.menu")
local NetworkMgr = require("ui/network/manager")
local rapidjson = require("rapidjson")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Discover = {}

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function invalidate(plugin)
    plugin.discover_request_id = (plugin.discover_request_id or 0) + 1
end

local function showMessage(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

local function errorText(result)
    if not result then
        return _("no result returned")
    end
    local error_message = result.error
        and (result.error.message or result.error.kind)
        or _("unknown error")
    local parts = { tostring(error_message) }
    if result.response then
        if result.response.status then
            table.insert(parts, "HTTP " .. tostring(result.response.status))
        end
        if result.response.final_url then
            table.insert(parts, tostring(result.response.final_url))
        end
    end
    return table.concat(parts, "\n")
end

local function runExplore(source, group, page)
    local ExploreService = require("novel.service.explore")
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
        error = {
            kind = "exception",
            message = result,
        },
    }
end

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

local function encodeResult(result)
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

local function decodeResult(encoded)
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
        error = {
            kind = "serialization",
            message = tostring(decoded),
        },
    }
end

local function sourceTitle(source)
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl
end

local function isDiscoverable(source)
    return source.enabled ~= false
        and source.enabledExplore ~= false
        and source.exploreUrl ~= nil
        and source.exploreUrl ~= ""
end

local function discoverGroups(plugin)
    local ExploreService = require("novel.service.explore")
    local sources = plugin.app:getSourceRepo():list()
    local groups, unsupported = {}, {}
    for source_index = 1, #sources do
        local source = sources[source_index]
        if isDiscoverable(source) then
            local source_groups, source_unsupported = ExploreService.groups(source)
            for group_index = 1, #source_groups do
                table.insert(groups, source_groups[group_index])
            end
            for item_index = 1, #source_unsupported do
                table.insert(unsupported, source_unsupported[item_index])
            end
        end
    end
    return groups, unsupported
end

local function showUnsupported(items)
    local lines = {}
    for item_index = 1, #(items or {}) do
        local item = items[item_index]
        table.insert(lines, table.concat({
            item.source or "",
            item.field or "",
            item.kind or "",
            item.snippet or "",
        }, "\n"))
    end
    showMessage(table.concat(lines, "\n\n"))
end

function Discover.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "discover_group_menu")
    closeWidget(plugin, "discover_results_menu")
    Detail.close(plugin)
end

local function buildResultItems(plugin, source, group, page, result)
    local item_table = {
        {
            text = _("Next page"),
            callback = function()
                Discover.start(plugin, source, group, page + 1)
            end,
        },
    }

    if result.unsupported and #result.unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#result.unsupported),
            callback = function()
                showUnsupported(result.unsupported)
            end,
            separator = true,
        })
    else
        item_table[1].separator = true
    end

    if not result.books or #result.books == 0 then
        table.insert(item_table, {
            text = _("No results."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for book_index = 1, #result.books do
        local book = result.books[book_index]
        table.insert(item_table, {
            text = book.name,
            book = book,
            source_title = sourceTitle(source),
            callback = function()
                Detail.show(plugin, source, book)
            end,
        })
    end
    return item_table
end

function Discover.showResults(plugin, source, group, page, result)
    closeWidget(plugin, "discover_results_menu")

    if not result or not result.ok then
        showMessage(_("Discover failed: ") .. errorText(result))
        return
    end

    local title = (group.title or _("Discover")) .. " (" .. tostring(page) .. ")"
    local results_menu
    results_menu = DiscoverList:new{
        title = title,
        item_table = buildResultItems(plugin, source, group, page, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.discover_results_menu == results_menu then
                plugin.discover_results_menu = nil
            end
        end,
    }
    plugin.discover_results_menu = results_menu
    UIManager:show(results_menu)
end

function Discover.start(plugin, source, group, page)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end
    page = page or 1
    if NetworkMgr:willRerunWhenOnline(function()
        Discover.start(plugin, source, group, page)
    end) then
        return
    end

    invalidate(plugin)
    local request_id = plugin.discover_request_id

    Trapper:wrap(function()
        local completed, encoded_result = Trapper:dismissableRunInSubprocess(function()
            local ok, encoded_or_error = xpcall(function()
                return encodeResult(runExplore(source, group, page))
            end, debug.traceback)
            if ok and type(encoded_or_error) == "string" then
                return encoded_or_error
            end
            return errorJSON("exception", encoded_or_error)
        end, _("Loading discovery... (tap to cancel)"), true)

        if not plugin.app or plugin.discover_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Discover canceled."))
            return
        end
        local result = decodeResult(encoded_result)
        if not result then
            result = runExplore(source, group, page)
        end
        Discover.showResults(plugin, source, group, page, result)
    end)
end

local function buildGroupItems(plugin, groups, unsupported)
    local item_table = {}
    if #unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#unsupported),
            callback = function()
                showUnsupported(unsupported)
            end,
            separator = true,
        })
    end

    if #groups == 0 then
        table.insert(item_table, {
            text = _("No discoverable sources."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for group_index = 1, #groups do
        local group = groups[group_index]
        table.insert(item_table, {
            text = sourceTitle(group.source),
            mandatory = group.title,
            callback = function()
                Discover.start(plugin, group.source, group, 1)
            end,
        })
    end
    return item_table
end

function Discover.show(plugin)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end

    closeWidget(plugin, "discover_group_menu")
    local groups, unsupported = discoverGroups(plugin)
    local group_menu
    group_menu = Menu:new{
        title = _("Discover"),
        item_table = buildGroupItems(plugin, groups, unsupported),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.discover_group_menu == group_menu then
                plugin.discover_group_menu = nil
            end
        end,
    }
    plugin.discover_group_menu = group_menu
    UIManager:show(group_menu)
end

return Discover
