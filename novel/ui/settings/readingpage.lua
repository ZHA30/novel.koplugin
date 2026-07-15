local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local ShellRoutes = require("novel.ui.shellroutes")

local ReadingPage = {}

function ReadingPage.build(shell, plugin, route, runtime)
    return ContentBuilder.buildList(shell, {
        {
            title = _("Intro"),
            icon = "info",
            callback = function()
                runtime.push(plugin, ShellRoutes.introSettings{
                    tab = route and route.tab or "settings",
                })
            end,
        },
    })
end

return ReadingPage
