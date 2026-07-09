local ShellRoutes = require("novel.ui.shellroutes")

local ShellSession = {}

local function normalizeListPage(page)
    if page == "last" then
        return "last"
    end
    page = math.floor(tonumber(page) or 1)
    if page < 1 then
        page = 1
    end
    return page
end

local function prepareRoute(route, previous_route)
    local copied = ShellRoutes.copy(route)
    if copied.list_page_anchor == "last" then
        copied.list_page = "last"
    elseif copied.list_page ~= nil then
        copied.list_page = normalizeListPage(copied.list_page)
    elseif previous_route and previous_route.list_page ~= nil then
        copied.list_page = previous_route.list_page
    else
        copied.list_page = 1
    end
    copied.list_page_anchor = nil
    return copied
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copied = {}
    for key, item in pairs(value) do
        copied[key] = clone(item)
    end
    return copied
end

function ShellSession.get(plugin)
    if type(plugin.novel_shell_state) ~= "table" then
        plugin.novel_shell_state = {}
    end
    local state = plugin.novel_shell_state
    if type(state.stack) ~= "table" then
        state.stack = {}
    end
    state.active_tab = ShellRoutes.normalizeTab(state.active_tab or "bookshelf")
    return state
end

function ShellSession.activeTab(plugin)
    return ShellSession.get(plugin).active_tab
end

function ShellSession.setActiveTab(plugin, active_tab)
    local state = ShellSession.get(plugin)
    state.active_tab = ShellRoutes.normalizeTab(active_tab)
    return state.active_tab
end

function ShellSession.stack(plugin)
    return ShellSession.get(plugin).stack
end

function ShellSession.currentRoute(plugin)
    local stack = ShellSession.stack(plugin)
    return stack[#stack]
end

function ShellSession.resetStack(plugin)
    local state = ShellSession.get(plugin)
    state.stack = {}
    state.list_page = 1
    state.list_info = nil
end

function ShellSession.push(plugin, route)
    table.insert(ShellSession.stack(plugin), prepareRoute(route))
    ShellSession.get(plugin).list_info = nil
end

function ShellSession.replace(plugin, route)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 then
        ShellSession.push(plugin, route)
        return
    end
    stack[#stack] = prepareRoute(route, stack[#stack])
    ShellSession.get(plugin).list_info = nil
end

function ShellSession.pop(plugin)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 then
        return nil
    end
    local route = table.remove(stack)
    ShellSession.get(plugin).list_info = nil
    return route
end

function ShellSession.listPage(plugin)
    local route = ShellSession.currentRoute(plugin)
    if route and route.list_page ~= nil then
        return route.list_page
    end
    return ShellSession.get(plugin).list_page or 1
end

function ShellSession.setListPage(plugin, page)
    local state = ShellSession.get(plugin)
    local list_page = normalizeListPage(page)
    local route = ShellSession.currentRoute(plugin)
    if route then
        route.list_page = list_page
    else
        state.list_page = list_page
    end
    return list_page
end

function ShellSession.resetListPage(plugin)
    local state = ShellSession.get(plugin)
    local route = ShellSession.currentRoute(plugin)
    if route then
        route.list_page = 1
    else
        state.list_page = 1
    end
    state.list_info = nil
end

function ShellSession.setListInfo(plugin, info)
    local state = ShellSession.get(plugin)
    state.list_info = info
    if info and info.current_page then
        ShellSession.setListPage(plugin, info.current_page)
        local route = ShellSession.currentRoute(plugin)
        if route then
            route.list_item_anchor = nil
        end
    end
end

function ShellSession.listInfo(plugin)
    return ShellSession.get(plugin).list_info
end

function ShellSession.snapshot(plugin)
    return clone(ShellSession.get(plugin))
end

function ShellSession.clone(snapshot)
    return clone(snapshot or {})
end

function ShellSession.restore(plugin, snapshot)
    plugin.novel_shell_state = ShellSession.clone(snapshot)
    return ShellSession.get(plugin)
end

return ShellSession
