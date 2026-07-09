local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local DownloadQueue = require("novel.reader.downloadqueue")
local ShellRoutes = require("novel.ui.shellroutes")

local SettingsPage = {}

function SettingsPage.build(shell, plugin, route, runtime)
    local store = plugin.app:getSourceStore()
    local download_summary = DownloadQueue.summary(plugin)
    local download_count = tostring(download_summary.total)
    if download_summary.error > 0 then
        download_count = string.format("%d/%d", download_summary.error,
            download_summary.total)
    end
    local items = {
        {
            title = _("Download queue"),
            mandatory = download_count,
            icon = "arrow-down-to-line",
            callback = function()
                runtime.push(plugin, ShellRoutes.downloads{
                    tab = route and route.tab or "settings",
                })
            end,
        },
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
