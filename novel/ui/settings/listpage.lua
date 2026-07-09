local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local ShellRoutes = require("novel.ui.shellroutes")

local SettingsListPage = {}

function SettingsListPage.build(shell, plugin, route, runtime)
    local items = {
        {
            title = _("Cache"),
            icon = "cache",
            callback = function()
                runtime.push(plugin, ShellRoutes.cacheSettings{
                    tab = route and route.tab or "settings",
                })
            end,
        },
    }

    return ContentBuilder.buildList(shell, items)
end

return SettingsListPage
