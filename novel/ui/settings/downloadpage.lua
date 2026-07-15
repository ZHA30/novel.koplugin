local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local DownloadQueue = require("novel.reader.downloadqueue")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")

local DownloadPage = {}

local BACKGROUND_OPTIONS = {
    {
        value = DownloadQueue.BACKGROUND_NOVEL_ONLY,
        label = _("Only in Novel"),
    },
    {
        value = DownloadQueue.BACKGROUND_PAUSE_WHILE_READING,
        label = _("Pause while reading"),
    },
    {
        value = DownloadQueue.BACKGROUND_ALWAYS,
        label = _("Always download in background"),
    },
}

local function refresh(plugin, route, runtime)
    if runtime and type(runtime.replace) == "function" then
        runtime.replace(plugin, route)
    end
end

local function downloadSettings(plugin)
    local settings = plugin.app and plugin.app.settings or {}
    settings.download = settings.download or {}
    return settings.download
end

local function save(plugin, route, runtime)
    if plugin.app and type(plugin.app.saveSettings) == "function" then
        plugin.app:saveSettings()
    end
    DownloadQueue.settingsChanged(plugin)
    refresh(plugin, route, runtime)
end

local function backgroundLabel(mode)
    for option_index = 1, #BACKGROUND_OPTIONS do
        local option = BACKGROUND_OPTIONS[option_index]
        if option.value == mode then
            return option.label
        end
    end
    return BACKGROUND_OPTIONS[2].label
end

local function showBackgroundDialog(plugin, route, runtime)
    local download = downloadSettings(plugin)
    local mode = DownloadQueue.backgroundMode(plugin)
    local radio_buttons = {}
    for option_index = 1, #BACKGROUND_OPTIONS do
        local option = BACKGROUND_OPTIONS[option_index]
        table.insert(radio_buttons, {{
            text = option.label,
            provider = option.value,
            checked = option.value == mode,
        }})
    end
    UIManager:show(RadioButtonWidget:new{
        title_text = _("Background download mode"),
        info_text = _("Background downloading is available only while KOReader is running."),
        radio_buttons = radio_buttons,
        callback = function(radio)
            download.background_mode = radio.provider
            save(plugin, route, runtime)
        end,
    })
end

local function showWorkersDialog(plugin, route, runtime)
    local download = downloadSettings(plugin)
    UIManager:show(SpinWidget:new{
        title_text = _("Simultaneous downloads"),
        value = DownloadQueue.workerCount(plugin),
        value_min = DownloadQueue.min_workers,
        value_max = DownloadQueue.max_workers,
        value_step = 1,
        default_value = 1,
        ok_text = _("Apply"),
        callback = function(spin)
            download.workers = tonumber(spin.value) or 1
            save(plugin, route, runtime)
        end,
    })
end

function DownloadPage.build(shell, plugin, route, runtime)
    local mode = DownloadQueue.backgroundMode(plugin)
    local workers = DownloadQueue.workerCount(plugin)
    local items = {
        {
            title = _("Background download mode"),
            mandatory = backgroundLabel(mode),
            callback = function()
                showBackgroundDialog(plugin, route, runtime)
            end,
        },
        {
            title = _("Simultaneous downloads"),
            subtitle = _("More simultaneous downloads use more network, CPU, and memory."),
            mandatory = tostring(workers),
            callback = function()
                showWorkersDialog(plugin, route, runtime)
            end,
        },
    }
    return ContentBuilder.buildList(shell, items)
end

return DownloadPage
