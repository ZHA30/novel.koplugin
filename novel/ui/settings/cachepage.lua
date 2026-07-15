local _ = require("novel.i18n")
local Cache = require("novel.storage.cache")
local CacheCleanup = require("novel.storage.cachecleanup")
local ContentBuilder = require("novel.ui.contentbuilder")
local Dialog = require("novel.ui.widget.dialog")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local util = require("util")

local CachePage = {}
local BYTES_PER_MB = 1024 * 1024
local DEFAULT_CACHE_LIMIT_MB = math.floor(Cache.default_max_bytes / BYTES_PER_MB)
local MIN_CACHE_LIMIT_MB = 1
local MAX_CACHE_LIMIT_MB = 512

local function friendlySize(bytes)
    return util.getFriendlySize(tonumber(bytes) or 0) or "0 B"
end

local function formatMB(value)
    return string.format("%d MB", tonumber(value) or 0)
end

local function recordCountText(count)
    count = tonumber(count) or 0
    if count == 1 then
        return _("1 record")
    end
    return string.format(_("%d records"), count)
end

local function cacheLimit(settings)
    local cache_settings = settings and settings.cache or {}
    return tonumber(cache_settings.max_metadata_bytes)
        or Cache.default_max_bytes
end

local function cacheLimitMB(settings)
    return math.max(
        MIN_CACHE_LIMIT_MB,
        math.floor(cacheLimit(settings) / BYTES_PER_MB + 0.5)
    )
end

local function cacheRecordLimit(settings)
    local cache_settings = settings and settings.cache or {}
    return tonumber(cache_settings.max_metadata_records)
        or Cache.default_max_records
end

local function refresh(plugin, route, runtime)
    if runtime and type(runtime.replace) == "function" then
        runtime.replace(plugin, route)
    end
end

local function clearCache(plugin, route, runtime)
    Dialog.confirm(
        _("Clear metadata cache?"),
        _("Clear"),
        function()
            local summary = CacheCleanup.clearMetadata()
            if not summary.ok then
                Dialog.message(Dialog.failureMessage(summary, _("Failed")))
                return
            end
            Dialog.message(string.format(
                _("Removed %d metadata cache records."),
                tonumber(summary.records_removed) or 0
            ))
            refresh(plugin, route, runtime)
        end
    )
end

local function showCacheLimitDialog(plugin, route, runtime)
    local settings = plugin.app and plugin.app.settings or {}
    UIManager:show(SpinWidget:new{
        title_text = _("Cache limit"),
        value = cacheLimitMB(settings),
        value_min = MIN_CACHE_LIMIT_MB,
        value_max = MAX_CACHE_LIMIT_MB,
        value_step = 1,
        value_hold_step = 10,
        unit = "MB",
        default_value = DEFAULT_CACHE_LIMIT_MB,
        ok_text = _("Apply"),
        callback = function(spin)
            settings.cache = settings.cache or {}
            settings.cache.max_metadata_bytes = tonumber(spin.value)
                * BYTES_PER_MB
            if plugin.app and type(plugin.app.saveSettings) == "function" then
                plugin.app:saveSettings()
            end
            refresh(plugin, route, runtime)
        end,
    })
end

function CachePage.build(shell, plugin, route, runtime)
    local settings = plugin.app and plugin.app.settings or {}
    local stats = Cache:new():stats()
    local file_size = friendlySize(stats.file_bytes)
    local current_subtitle = string.format(
        _("Records: %s; Record data: %s"),
        recordCountText(stats.record_count),
        friendlySize(stats.blob_bytes)
    )
    local limit_subtitle = string.format(
        _("Records: %s"),
        recordCountText(cacheRecordLimit(settings))
    )
    local items = {
        {
            title = _("Current cache size"),
            subtitle = current_subtitle,
            mandatory = file_size,
        },
        {
            title = _("Cache limit"),
            subtitle = limit_subtitle,
            mandatory = formatMB(cacheLimitMB(settings)),
            callback = function()
                showCacheLimitDialog(plugin, route, runtime)
            end,
        },
        {
            title = _("Clear metadata cache"),
            callback = function()
                clearCache(plugin, route, runtime)
            end,
        },
    }

    return ContentBuilder.buildList(shell, items)
end

return CachePage
