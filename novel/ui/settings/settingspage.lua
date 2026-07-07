local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local ShellRoutes = require("novel.ui.shellroutes")

local SettingsPage = {}

function SettingsPage.build(shell, plugin, route, runtime)
    local store = plugin.app:getSourceStore()
    local items = {
        {
            title = _("Sources"),
            mandatory = tostring(store:count()),
            icon = "sources",
            callback = function()
                runtime.push(plugin, ShellRoutes.sources{
                    tab = route and route.tab or "settings",
                })
            end,
        },
    }

    return ContentBuilder.buildList(shell, items)
end

return SettingsPage
