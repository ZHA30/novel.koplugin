local _ = require("novel.i18n")
local Blitbuffer = require("ffi/blitbuffer")
local Detail = require("novel.ui.detail")
local BookMenu = require("novel.widget.bookmenu")
local Capability = require("novel.source.capability")
local Dialog = require("novel.widget.dialog")
local Discovery = require("novel.catalog.discovery")
local Grouping = require("novel.widget.grouping")
local Menu = require("novel.widget.menu")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Discover = {}

local function invalidate(plugin)
    plugin.discover_request_id = (plugin.discover_request_id or 0) + 1
end

local function sourceTitle(source)
    return Capability.title(source)
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

local function sourceKey(source)
    return Capability.key(source)
end

local function sourceCollapsed(plugin, source)
    return Grouping.collapsed(plugin, "discover_collapsed_sources", sourceKey(source))
end

local function sourceIcon(plugin, source)
    return Grouping.icon(sourceCollapsed(plugin, source))
end

local function showUnsupported(items)
    Dialog.showUnsupported(items)
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

function Discover.close(plugin)
    invalidate(plugin)
    Dialog.closeWidget(plugin, "discover_group_menu")
    Dialog.closeWidget(plugin, "discover_results_menu")
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
    if not Discovery.canRequestNextPage(source, group, current_page) then
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
            return Discovery.runEncoded(source, group, next_page)
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
            Dialog.message(_("Discover canceled."))
            return
        end

        local result = Discovery.decodeResult(encoded_result)
        if not result then
            result = Discovery.run(source, group, next_page)
        end
        if not result or not result.ok then
            results_menu:updatePageInfo()
            Dialog.message(_("Discover failed: ") .. Dialog.errorText(result))
            return
        end
        if not result.books or #result.books == 0 then
            results_menu.no_more_source_pages = true
            results_menu:updatePageInfo()
            Dialog.message(_("No more results."))
            return
        end

        removeEmptyMarker(results_menu.item_table)
        local first_new_index = #results_menu.item_table + 1
        local appended = appendBookItems(results_menu.item_table, plugin, source,
            result.books, existingBookKeys(results_menu.item_table))
        if appended == 0 then
            results_menu.no_more_source_pages = true
            results_menu:updatePageInfo()
            Dialog.message(_("No more results."))
            return
        end
        results_menu.discover_source_page = next_page
        results_menu.no_more_source_pages = not Discovery.canRequestNextPage(
            source, group, next_page)
        results_menu:switchItemTable(
            resultTitle(group, results_menu.discover_first_source_page, next_page),
            results_menu.item_table,
            first_new_index)
    end)
    return true
end

function Discover.showResults(plugin, source, group, page, result)
    Dialog.closeWidget(plugin, "discover_results_menu")

    if not result or not result.ok then
        Dialog.message(_("Discover failed: ") .. Dialog.errorText(result))
        return
    end

    local no_more_source_pages = not Discovery.canRequestNextPage(source, group, page)
    local results_menu
    results_menu = BookMenu:new{
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
        Dialog.message(_("Novel is not ready."))
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
            return Discovery.runEncoded(source, group, page)
        end, _("Loading discovery... (tap to cancel)"), true)

        if not plugin.app or plugin.discover_request_id ~= request_id then
            return
        end
        if not completed then
            Dialog.message(_("Discover canceled."))
            return
        end
        local result = Discovery.decodeResult(encoded_result)
        if not result then
            result = Discovery.run(source, group, page)
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
        Dialog.message(_("Novel is not ready."))
        return
    end

    Dialog.closeWidget(plugin, "discover_group_menu")
    local source_groups, unsupported = Discovery.sourceGroups(
        plugin.app:getSourceRepository():list())
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
