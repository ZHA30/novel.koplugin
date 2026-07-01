local _ = require("novel.i18n")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local Sources = {}

local function sourceTitle(source)
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl
end

local function sourceSummary(source)
    local lines = {
        source.bookSourceUrl,
    }
    if source.bookSourceGroup and source.bookSourceGroup ~= "" then
        table.insert(lines, _("Group: ") .. source.bookSourceGroup)
    end
    if source.enabled == false then
        table.insert(lines, _("Disabled"))
    end
    if source.enabledExplore == false then
        table.insert(lines, _("Discover disabled"))
    end
    if source.support_status and #source.support_status > 0 then
        table.insert(lines, _("Unsupported rules are present."))
    end
    return table.concat(lines, "\n")
end

local function groupTitle(group)
    if group.name and group.name ~= "" then
        return group.name
    end
    return _("Ungrouped")
end

local function closeDialog(plugin, key)
    if plugin[key] then
        local dialog = plugin[key]
        plugin[key] = nil
        UIManager:close(dialog)
    end
end

local function refresh(plugin)
    UIManager:nextTick(function()
        if plugin.app then
            Sources.show(plugin)
        end
    end)
end

local function showImportResult(result)
    local message = _("Imported sources: ") .. tostring(result.imported)
    if result.errors and #result.errors > 0 then
        message = message .. "\n" .. _("Import errors: ") .. tostring(#result.errors)
    end
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

function Sources.showImportDialog(plugin)
    closeDialog(plugin, "sources_input_dialog")

    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Import sources"),
        input = "",
        input_hint = _("Path to JSON file"),
        description = _("Enter a local JSON book source file path."),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    closeDialog(plugin, "sources_input_dialog")
                end,
            },
            {
                text = _("Import"),
                is_enter_default = true,
                callback = function()
                    local path = input_dialog:getInputText()
                    if path == "" then
                        return
                    end
                    closeDialog(plugin, "sources_input_dialog")
                    local result = plugin.app:getSourceRepo():importFile(path)
                    showImportResult(result)
                    refresh(plugin)
                end,
            },
        }},
    }
    plugin.sources_input_dialog = input_dialog
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Sources.showExportDialog(plugin)
    closeDialog(plugin, "sources_input_dialog")

    local repo = plugin.app:getSourceRepo()
    local input_dialog
    input_dialog = InputDialog:new{
        title = _("Export sources"),
        input = repo.export_path,
        input_hint = _("Path to JSON file"),
        description = _("Enter the export file path."),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    closeDialog(plugin, "sources_input_dialog")
                end,
            },
            {
                text = _("Export"),
                is_enter_default = true,
                callback = function()
                    local path = input_dialog:getInputText()
                    if path == "" then
                        return
                    end
                    closeDialog(plugin, "sources_input_dialog")
                    local ok, err = repo:exportFile(path)
                    UIManager:show(InfoMessage:new{
                        text = ok and (_("Exported sources to: ") .. path)
                            or (_("Export failed: ") .. tostring(err)),
                    })
                end,
            },
        }},
    }
    plugin.sources_input_dialog = input_dialog
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function Sources.confirmDeleteAll(plugin)
    closeDialog(plugin, "sources_confirm_dialog")

    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Delete all imported book sources?"),
        ok_text = _("Delete"),
        ok_callback = function()
            closeDialog(plugin, "sources_confirm_dialog")
            plugin.app:getSourceRepo():clear()
            refresh(plugin)
        end,
        cancel_callback = function()
            plugin.sources_confirm_dialog = nil
        end,
    }
    plugin.sources_confirm_dialog = confirm_dialog
    UIManager:show(confirm_dialog)
end

function Sources.confirmDeleteSource(plugin, source)
    closeDialog(plugin, "sources_confirm_dialog")

    local confirm_dialog
    confirm_dialog = ConfirmBox:new{
        text = _("Delete book source?") .. "\n" .. sourceTitle(source),
        ok_text = _("Delete"),
        ok_callback = function()
            closeDialog(plugin, "sources_confirm_dialog")
            plugin.app:getSourceRepo():remove(source.bookSourceUrl)
            refresh(plugin)
        end,
        cancel_callback = function()
            plugin.sources_confirm_dialog = nil
        end,
    }
    plugin.sources_confirm_dialog = confirm_dialog
    UIManager:show(confirm_dialog)
end

local function sourceActions(plugin, source)
    local repo = plugin.app:getSourceRepo()
    local enabled = source.enabled ~= false
    local enabled_explore = source.enabledExplore ~= false
    return {
        {
            text = _("Details"),
            callback = function()
                UIManager:show(InfoMessage:new{
                    text = sourceSummary(source),
                })
            end,
        },
        {
            text = enabled and _("Disable") or _("Enable"),
            callback = function()
                repo:setEnabled(source.bookSourceUrl, not enabled)
                refresh(plugin)
            end,
        },
        {
            text = enabled_explore and _("Disable Discover") or _("Enable Discover"),
            callback = function()
                repo:setEnabledExplore(source.bookSourceUrl, not enabled_explore)
                refresh(plugin)
            end,
        },
        {
            text = _("Delete"),
            callback = function()
                Sources.confirmDeleteSource(plugin, source)
            end,
        },
    }
end

local function buildSourceItems(plugin, sources)
    local item_table = {}
    for source_index = 1, #sources do
        local source = sources[source_index]
        table.insert(item_table, {
            text = sourceTitle(source),
            mandatory = source.enabled == false and _("Disabled") or nil,
            sub_item_table = sourceActions(plugin, source),
        })
    end
    return item_table
end

local function buildItems(plugin, sources, groups)
    local item_table = {
        {
            text = _("Import sources"),
            callback = function()
                Sources.showImportDialog(plugin)
            end,
        },
        {
            text = _("Export sources"),
            select_enabled_func = function()
                return #plugin.app:getSourceRepo():list() > 0
            end,
            callback = function()
                Sources.showExportDialog(plugin)
            end,
        },
        {
            text = _("Delete all sources"),
            select_enabled_func = function()
                return #plugin.app:getSourceRepo():list() > 0
            end,
            callback = function()
                Sources.confirmDeleteAll(plugin)
            end,
            separator = true,
        },
    }

    if #sources == 0 then
        table.insert(item_table, {
            text = _("No book sources imported."),
            select_enabled = false,
            dim = true,
        })
        return item_table
    end

    for group_index = 1, #groups do
        local group = groups[group_index]
        table.insert(item_table, {
            text = groupTitle(group),
            mandatory = tostring(#group.sources),
            sub_item_table = buildSourceItems(plugin, group.sources),
        })
    end

    return item_table
end

function Sources.show(plugin)
    if not plugin.app then
        UIManager:show(InfoMessage:new{
            text = _("Novel is not ready."),
        })
        return
    end

    local repo = plugin.app:getSourceRepo()
    local sources = repo:list()
    local groups = repo:listGroups()

    if plugin.sources_menu then
        UIManager:close(plugin.sources_menu)
        plugin.sources_menu = nil
    end

    local sources_menu
    sources_menu = Menu:new{
        title = _("Sources") .. " (" .. tostring(#sources) .. ")",
        item_table = buildItems(plugin, sources, groups),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            UIManager:close(sources_menu)
            if plugin.sources_menu == sources_menu then
                plugin.sources_menu = nil
            end
        end,
    }
    plugin.sources_menu = sources_menu
    UIManager:show(sources_menu)
end

return Sources
