local _ = require("novel.i18n")
local BookRefresh = require("novel.bookshelfrefresh")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")

local RefreshFlow = {}

local book_fields = {
    "bookUrl",
    "tocUrl",
    "origin",
    "originName",
    "name",
    "author",
    "kind",
    "customTag",
    "coverUrl",
    "customCoverUrl",
    "intro",
    "customIntro",
    "charset",
    "type",
    "group",
    "latestChapterTitle",
    "updateTime",
    "latestChapterTime",
    "lastCheckTime",
    "lastCheckCount",
    "totalChapterNum",
    "durChapterTitle",
    "durChapterIndex",
    "durChapterPos",
    "durChapterTime",
    "wordCount",
    "canUpdate",
    "order",
    "originOrder",
    "useReplaceRule",
    "infoHtml",
    "tocHtml",
}

local chapter_fields = {
    "url",
    "title",
    "isVolume",
    "isVip",
    "baseUrl",
    "bookUrl",
    "index",
    "resourceUrl",
    "tag",
    "start",
    "end",
    "startFragmentId",
    "endFragmentId",
}

local function primitive(value)
    local value_type = type(value)
    if value_type == "string" or value_type == "number" or value_type == "boolean" then
        return value
    end
    return nil
end

local function copyFields(value, fields)
    if type(value) ~= "table" then
        return nil
    end
    local copy = {}
    for field_index = 1, #fields do
        local field = fields[field_index]
        local item = primitive(value[field])
        if item ~= nil then
            copy[field] = item
        end
    end
    return copy
end

local function sanitizeError(error_value, fallback)
    if type(error_value) ~= "table" then
        return {
            kind = "refresh",
            message = tostring(error_value or fallback or _("Refresh failed.")),
        }
    end
    return {
        kind = tostring(error_value.kind or "refresh"),
        message = tostring(error_value.message or fallback or _("Refresh failed.")),
    }
end

local function sanitizeUnsupported(items)
    local sanitized = {}
    if type(items) ~= "table" then
        return sanitized
    end
    for item_index = 1, #items do
        local item = items[item_index]
        if type(item) == "table" then
            table.insert(sanitized, {
                source = tostring(item.source or ""),
                field = tostring(item.field or ""),
                kind = tostring(item.kind or ""),
                message = tostring(item.message or item.text or ""),
            })
        end
    end
    return sanitized
end

local function sanitizeRefreshResult(result)
    if not result then
        return {
            ok = false,
            error = {
                kind = "refresh",
                message = _("Refresh subprocess returned no result."),
            },
        }
    end
    if not result.ok then
        return {
            ok = false,
            stage = tostring(result.stage or "refresh"),
            error = sanitizeError(result.error, _("Refresh failed.")),
            unsupported = sanitizeUnsupported(result.unsupported),
        }
    end

    local chapters = {}
    for chapter_index = 1, #(result.chapters or {}) do
        table.insert(chapters, copyFields(result.chapters[chapter_index], chapter_fields) or {})
    end
    return {
        ok = true,
        book = copyFields(result.book, book_fields) or {},
        chapters = chapters,
        unsupported = sanitizeUnsupported(result.unsupported),
    }
end

local function invalidate(plugin)
    if not plugin then
        return nil
    end
    plugin.novel_refresh_request_id = (plugin.novel_refresh_request_id or 0) + 1
    return plugin.novel_refresh_request_id
end

local function currentRequest(plugin)
    return plugin and plugin.novel_refresh_request_id
end

local function refreshMessage(applied)
    local count = applied and applied.chapters and #applied.chapters or 0
    return _("Book refreshed.") .. "\n" .. _("Chapters: ") .. tostring(count)
end

local function refreshSummary(message, success_count, failure_count, first_failure)
    local summary = string.format(message, success_count, failure_count)
    if failure_count > 0 and first_failure then
        return summary .. "\n" .. first_failure
    end
    return summary
end

local function settingsFor(plugin)
    return plugin and plugin.app and plugin.app.settings
end

local function fetchInSubprocess(source, book, settings)
    local ok, result = pcall(function()
        local Refresh = require("novel.bookshelfrefresh")
        return sanitizeRefreshResult(Refresh.fetch(source, book, {
            settings = settings,
        }))
    end)
    if ok then
        return result or {
            ok = false,
            error = {
                kind = "refresh",
                message = _("Refresh returned no result."),
            },
        }
    end
    return {
        ok = false,
        error = {
            kind = "refresh",
            message = tostring(result),
        },
    }
end

function RefreshFlow.refreshBook(plugin, source, book, options)
    options = options or {}
    if not plugin or not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        RefreshFlow.refreshBook(plugin, source, book, options)
    end) then
        return
    end

    local request_id = invalidate(plugin)
    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "novel_refresh_loading", {
            text = options.loading_text or _("Refreshing..."),
        })
        local settings = settingsFor(plugin)
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            return fetchInSubprocess(source, book, settings)
        end, loading_widget)
        Loading.close(plugin, "novel_refresh_loading", loading_widget)

        if not plugin.app or currentRequest(plugin) ~= request_id then
            return
        end
        if not completed then
            Dialog.message(Dialog.canceledMessage())
            return
        end
        if not result or not result.ok then
            Dialog.message(Dialog.failureMessage(sanitizeRefreshResult(result)))
            return
        end

        local applied, err = BookRefresh.apply(plugin, source, book, result, {
            require_bookshelf = options.require_bookshelf,
        })
        if not applied then
            Dialog.message(Dialog.failureMessage(err))
            return
        end
        if options.message ~= false then
            Dialog.message(refreshMessage(applied))
        end
        if options.on_done then
            options.on_done(applied)
        end
    end)
end

function RefreshFlow.refreshBookshelf(plugin, records, options)
    options = options or {}
    if not plugin or not plugin.app then
        Dialog.message(_("Novel is not ready."))
        return
    end
    if #(records or {}) == 0 then
        Dialog.message(_("Bookshelf is empty."))
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        RefreshFlow.refreshBookshelf(plugin, records, options)
    end) then
        return
    end

    local request_id = invalidate(plugin)
    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "novel_refresh_loading", {
            text = string.format(_("Refreshing %d/%d..."), 1, #records),
        })
        local settings = settingsFor(plugin)
        local success_count = 0
        local failure_count = 0
        local first_failure
        local canceled = false

        for record_index = 1, #records do
            if not plugin.app or currentRequest(plugin) ~= request_id then
                canceled = true
                break
            end
            local record = records[record_index]
            local source = BookRefresh.findCurrentSource(plugin, record)
            if record_index > 1 then
                Loading.update(
                    plugin,
                    "novel_refresh_loading",
                    string.format(
                        _("Refreshing %d/%d..."),
                        record_index,
                        #records
                    ),
                    loading_widget
                )
            end
            local completed, result = Trapper:dismissableRunInSubprocess(function()
                return fetchInSubprocess(source, record.book, settings)
            end, loading_widget)
            if not completed then
                canceled = true
                break
            end
            if result and result.ok then
                local applied, err = BookRefresh.apply(plugin, source, record.book, result, {
                    require_bookshelf = true,
                })
                if applied then
                    success_count = success_count + 1
                else
                    failure_count = failure_count + 1
                    first_failure = first_failure or Dialog.failureMessage(err)
                end
            else
                failure_count = failure_count + 1
                first_failure = first_failure or Dialog.failureMessage(
                    sanitizeRefreshResult(result)
                )
            end
        end

        Loading.close(plugin, "novel_refresh_loading", loading_widget)
        if not plugin.app or currentRequest(plugin) ~= request_id then
            return
        end
        if options.message ~= false then
            if canceled then
                Dialog.message(refreshSummary(
                    _("Refresh canceled. Success: %d. Failed: %d."),
                    success_count,
                    failure_count,
                    first_failure
                ))
            else
                Dialog.message(refreshSummary(
                    _("Refresh complete. Success: %d. Failed: %d."),
                    success_count,
                    failure_count,
                    first_failure
                ))
            end
        end
        if options.on_done then
            options.on_done({
                success_count = success_count,
                failure_count = failure_count,
                canceled = canceled,
            })
        end
    end)
end

function RefreshFlow.close(plugin)
    invalidate(plugin)
    Loading.close(plugin, "novel_refresh_loading")
end

return RefreshFlow
