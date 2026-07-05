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
    ShellSession.get(plugin).stack = {}
end

function ShellSession.push(plugin, route)
    table.insert(ShellSession.stack(plugin), ShellRoutes.copy(route))
end

function ShellSession.replace(plugin, route)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 then
        ShellSession.push(plugin, route)
        return
    end
    stack[#stack] = ShellRoutes.copy(route)
end

function ShellSession.pop(plugin)
    local stack = ShellSession.stack(plugin)
    if #stack == 0 then
        return nil
    end
    return table.remove(stack)
end

return ShellSession
