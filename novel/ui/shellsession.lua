local ShellRoutes = require("novel.ui.shellroutes")

local ShellSession = {}

function ShellSession.get(plugin)
    if type(plugin.novel_shell_state) ~= "table" then
        plugin.novel_shell_state = {}
    end
    local state = plugin.novel_shell_state
    if type(state.stack) ~= "table" then
        state.stack = {}
    end
    if state.list_page == nil then
        state.list_page = 1
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
    ShellSession.resetListPage(plugin)
end

function ShellSession.push(plugin, route)
    table.insert(ShellSession.stack(plugin), ShellRoutes.copy(route))
    ShellSession.resetListPage(plugin)
end

function ShellSession.replace(plugin, route)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 then
        ShellSession.push(plugin, route)
        return
    end
    stack[#stack] = ShellRoutes.copy(route)
    if route and route.list_page_anchor == "last" then
        ShellSession.setListPage(plugin, "last")
    elseif route and route.list_page ~= nil then
        ShellSession.setListPage(plugin, route.list_page)
    end
end

function ShellSession.pop(plugin)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 then
        return nil
    end
    local route = table.remove(stack)
    ShellSession.resetListPage(plugin)
    return route
end

function ShellSession.listPage(plugin)
    return ShellSession.get(plugin).list_page or 1
end

function ShellSession.setListPage(plugin, page)
    local state = ShellSession.get(plugin)
    if page == "last" then
        state.list_page = "last"
        return state.list_page
    end
    page = math.floor(tonumber(page) or 1)
    if page < 1 then
        page = 1
    end
    state.list_page = page
    return state.list_page
end

function ShellSession.resetListPage(plugin)
    local state = ShellSession.get(plugin)
    state.list_page = 1
    state.list_info = nil
end

function ShellSession.setListInfo(plugin, info)
    ShellSession.get(plugin).list_info = info
end

function ShellSession.listInfo(plugin)
    return ShellSession.get(plugin).list_info
end

return ShellSession
