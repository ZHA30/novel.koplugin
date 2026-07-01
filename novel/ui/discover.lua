local _ = require("novel.i18n")
local Detail = require("novel.ui.detail")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
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

local function resultActions(plugin, source, book)
    return {
        {
            text = _("Details"),
            callback = function()
                Detail.show(plugin, source, book)
            end,
        },
    }
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
            mandatory = book.author ~= "" and book.author or nil,
            sub_item_table = resultActions(plugin, source, book),
        })
    end
    return item_table
end

function Discover.showResults(plugin, source, group, page, result)
    closeWidget(plugin, "discover_results_menu")

    if not result or not result.ok then
        local error_message = result and result.error
            and (result.error.message or result.error.kind)
            or _("Discover failed.")
        showMessage(_("Discover failed: ") .. tostring(error_message))
        return
    end

    local title = (group.title or _("Discover")) .. " (" .. tostring(page) .. ")"
    local results_menu
    results_menu = Menu:new{
        title = title,
        item_table = buildResultItems(plugin, source, group, page, result),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(results_menu)
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
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ExploreService = require("novel.service.explore")
            return ExploreService.run(source, group, {
                page = page,
            })
        end, _("Loading discovery... (tap to cancel)"))

        if not plugin.app or plugin.discover_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Discover canceled."))
            return
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
                closeWidget(plugin, "discover_group_menu")
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
            UIManager:close(group_menu)
            if plugin.discover_group_menu == group_menu then
                plugin.discover_group_menu = nil
            end
        end,
    }
    plugin.discover_group_menu = group_menu
    UIManager:show(group_menu)
end

return Discover
