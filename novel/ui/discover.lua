local _ = require("novel.i18n")
local Blitbuffer = require("ffi/blitbuffer")
local Detail = require("novel.ui.detail")
local DiscoverList = require("novel.ui.discoverlist")
local Grouping = require("novel.ui.grouping")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("novel.ui.menu")
local NetworkMgr = require("ui/network/manager")
local rapidjson = require("rapidjson")
local Size = require("ui/size")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local Url = require("novel.net.url")

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

local function resultTitle(group, first_page, last_page)
    local title = group.title or _("Discover")
    first_page = tonumber(first_page) or tonumber(last_page) or 1
    last_page = tonumber(last_page) or first_page
    if first_page ~= last_page then
        return title .. " (" .. tostring(first_page) .. "-" .. tostring(last_page) .. ")"
    end
    return title .. " (" .. tostring(last_page) .. ")"
end

local function categoryTitle(group)
    if group.title and group.title ~= "" then
        return group.title
    end
    return group.url or _("Discover")
end

local function isDiscoverable(source)
    return source.enabled ~= false
        and source.enabledExplore ~= false
        and source.exploreUrl ~= nil
        and source.exploreUrl ~= ""
end

local function sourceKey(source)
    return source.bookSourceUrl or ""
end

local function sourceCollapsed(plugin, source)
    return Grouping.collapsed(plugin, "discover_collapsed_sources", sourceKey(source))
end

local function sourceIcon(plugin, source)
    return Grouping.icon(sourceCollapsed(plugin, source))
end

local function discoverSources(plugin)
    local ExploreService = require("novel.service.explore")
    local sources = plugin.app:getSourceRepo():list()
    local source_groups, unsupported = {}, {}
    for source_index = 1, #sources do
        local source = sources[source_index]
        if isDiscoverable(source) then
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

local function buildBookItem(plugin, source, book)
    return {
        text = book.name,
        book = book,
        source_title = sourceTitle(source),
        callback = function()
            Detail.show(plugin, source, book)
        end,
    }
end

local function bookKey(book)
    book = book or {}
    local book_url = tostring(book.bookUrl or "")
    if book_url ~= "" then
        return book_url
    end
    local name = tostring(book.name or "")
    if name == "" then
        return nil
    end
    return name .. "\n" .. tostring(book.author or "")
end

local function existingBookKeys(item_table)
    local keys = {}
    for item_index = 1, #(item_table or {}) do
        local item = item_table[item_index]
        if item.book then
            local key = bookKey(item.book)
            if key then
                keys[key] = true
            end
        end
    end
    return keys
end

local function appendBookItems(item_table, plugin, source, books, known_keys)
    local appended = 0
    for book_index = 1, #(books or {}) do
        local book = books[book_index]
        local key = known_keys and bookKey(book)
        if not key or not known_keys[key] then
            table.insert(item_table, buildBookItem(plugin, source, book))
            appended = appended + 1
            if known_keys and key then
                known_keys[key] = true
            end
        end
    end
    return appended
end

local function removeEmptyMarker(item_table)
    for item_index = #item_table, 1, -1 do
        if item_table[item_index].discover_empty_marker then
            table.remove(item_table, item_index)
        end
    end
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

local function canRequestNextPage(source, group, page)
    page = tonumber(page) or 1
    local current_signature = requestSignature(source, group, page)
    local next_signature = requestSignature(source, group, page + 1)
    return current_signature ~= nil
        and next_signature ~= nil
        and current_signature ~= next_signature
end

function Discover.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "discover_group_menu")
    closeWidget(plugin, "discover_results_menu")
    Detail.close(plugin)
end

local function buildResultItems(plugin, source, result)
    local item_table = {}

    if result.unsupported and #result.unsupported > 0 then
        table.insert(item_table, {
            text = _("Unsupported rules"),
            mandatory = tostring(#result.unsupported),
            callback = function()
                showUnsupported(result.unsupported)
            end,
            separator = true,
        })
    end

    if not result.books or #result.books == 0 then
        table.insert(item_table, {
            text = _("No results."),
            select_enabled = false,
            dim = true,
            discover_empty_marker = true,
        })
        return item_table
    end

    appendBookItems(item_table, plugin, source, result.books)
    return item_table
end

function Discover.loadNextPage(plugin, results_menu)
    if not plugin.app
        or not results_menu
        or plugin.discover_results_menu ~= results_menu
        or not UIManager:isWidgetShown(results_menu) then
        if results_menu then
            results_menu.loading_next_page = false
        end
        return false
    end

    local source = results_menu.discover_source
    local group = results_menu.discover_group
    local current_page = tonumber(results_menu.discover_source_page) or 1
    local next_page = current_page + 1
    if not source or not group then
        results_menu.loading_next_page = false
        results_menu:updatePageInfo()
        return false
    end
    if not canRequestNextPage(source, group, current_page) then
        results_menu.no_more_source_pages = true
        results_menu.loading_next_page = false
        results_menu:updatePageInfo()
        return false
    end

    if NetworkMgr:willRerunWhenOnline(function()
        Discover.loadNextPage(plugin, results_menu)
    end) then
        results_menu.loading_next_page = false
        results_menu:updatePageInfo()
        return false
    end

    results_menu.loading_next_page = true
    results_menu:updatePageInfo()

    invalidate(plugin)
    local request_id = plugin.discover_request_id

    Trapper:wrap(function()
        local completed, encoded_result = Trapper:dismissableRunInSubprocess(function()
            local ok, encoded_or_error = xpcall(function()
                return encodeResult(runExplore(source, group, next_page))
            end, debug.traceback)
            if ok and type(encoded_or_error) == "string" then
                return encoded_or_error
            end
            return errorJSON("exception", encoded_or_error)
        end, _("Loading discovery... (tap to cancel)"), true)

        if not plugin.app
            or plugin.discover_request_id ~= request_id
            or plugin.discover_results_menu ~= results_menu
            or not UIManager:isWidgetShown(results_menu) then
            return
        end

        results_menu.loading_next_page = false
        if not completed then
            results_menu:updatePageInfo()
            showMessage(_("Discover canceled."))
            return
        end

        local result = decodeResult(encoded_result)
        if not result then
            result = runExplore(source, group, next_page)
        end
        if not result or not result.ok then
            results_menu:updatePageInfo()
            showMessage(_("Discover failed: ") .. errorText(result))
            return
        end
        if not result.books or #result.books == 0 then
            results_menu.no_more_source_pages = true
            results_menu:updatePageInfo()
            showMessage(_("No more results."))
            return
        end

        removeEmptyMarker(results_menu.item_table)
        local first_new_index = #results_menu.item_table + 1
        local appended = appendBookItems(results_menu.item_table, plugin, source,
            result.books, existingBookKeys(results_menu.item_table))
        if appended == 0 then
            results_menu.no_more_source_pages = true
            results_menu:updatePageInfo()
            showMessage(_("No more results."))
            return
        end
        results_menu.discover_source_page = next_page
        results_menu.no_more_source_pages = not canRequestNextPage(source, group, next_page)
        results_menu:switchItemTable(
            resultTitle(group, results_menu.discover_first_source_page, next_page),
            results_menu.item_table,
            first_new_index)
    end)
    return true
end

function Discover.showResults(plugin, source, group, page, result)
    closeWidget(plugin, "discover_results_menu")

    if not result or not result.ok then
        showMessage(_("Discover failed: ") .. errorText(result))
        return
    end

    local no_more_source_pages = not canRequestNextPage(source, group, page)
    local results_menu
    results_menu = DiscoverList:new{
        title = resultTitle(group, page, page),
        item_table = buildResultItems(plugin, source, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        no_more_source_pages = no_more_source_pages,
        load_next_page_callback = function(menu)
            return Discover.loadNextPage(plugin, menu)
        end,
        close_callback = function()
            if plugin.discover_results_menu == results_menu then
                plugin.discover_results_menu = nil
            end
        end,
    }
    results_menu.discover_source = source
    results_menu.discover_group = group
    results_menu.discover_first_source_page = page
    results_menu.discover_source_page = page
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

local function rebuildGroupItems(plugin, source_groups, unsupported)
    if plugin.discover_group_menu then
        plugin.discover_group_menu.item_table = Discover.buildGroupItems(plugin, source_groups, unsupported)
        plugin.discover_group_menu:updateItems(plugin.discover_group_menu.itemnumber, true)
    end
end

local function buildCategoryItem(plugin, source, group)
    return {
        text_func = function()
            return categoryTitle(group)
        end,
        callback = function()
            Discover.start(plugin, source, group, 1)
        end,
    }
end

function Discover.buildGroupItems(plugin, source_groups, unsupported)
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

    if #source_groups == 0 then
        table.insert(item_table, {
            text = _("No discoverable sources."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for source_index = 1, #source_groups do
        local source_group = source_groups[source_index]
        local source = source_group.source
        table.insert(item_table, {
            text_func = function()
                return sourceTitle(source)
            end,
            mandatory_func = function()
                return tostring(#source_group.groups)
            end,
            state = sourceIcon(plugin, source),
            bold = true,
            callback = function()
                Grouping.toggle(plugin, "discover_collapsed_sources", sourceKey(source))
                rebuildGroupItems(plugin, source_groups, unsupported)
            end,
        })
        if not sourceCollapsed(plugin, source) then
            if #source_group.groups == 0 then
                table.insert(item_table, {
                    text = _("No discover categories."),
                    select_enabled = false,
                    dim = true,
                })
            else
                for group_index = 1, #source_group.groups do
                    table.insert(item_table, buildCategoryItem(plugin, source,
                        source_group.groups[group_index]))
                end
            end
        end
    end
    return item_table
end

function Discover.show(plugin)
    if not plugin.app then
        showMessage(_("Novel is not ready."))
        return
    end

    closeWidget(plugin, "discover_group_menu")
    local source_groups, unsupported = discoverSources(plugin)
    local group_menu
    group_menu = Menu:new{
        title = _("Discover"),
        item_table = Discover.buildGroupItems(plugin, source_groups, unsupported),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        state_w = Grouping.state_w,
        single_line = true,
        align_baselines = true,
        items_padding = math.floor(Size.padding.fullscreen / 2),
        line_color = Blitbuffer.COLOR_BLACK,
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
