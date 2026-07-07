local _ = require("novel.i18n")
local ButtonDialog = require("ui/widget/buttondialog")
local ChapterListing = require("novel.ui.chapters.listing")
local ContentBuilder = require("novel.ui.contentbuilder")
local ChapterOpen = require("novel.reader.chapteropen")
local Dialog = require("novel.ui.widget.dialog")
local Manifest = require("novel.storage.manifest")
local ShellRoutes = require("novel.ui.shellroutes")
local UIManager = require("ui/uimanager")

local ChaptersPage = {}

local function chapterRoute(route, manifest)
    return ShellRoutes.chapters{
        tab = route.tab,
        source = route.source or manifest.source,
        book = route.book or manifest.book,
        manifest = manifest,
        filter = route.filter,
        sort = route.sort,
    }
end

local function refresh(runtime, plugin, route, manifest)
    if runtime and type(runtime.replace) == "function" then
        runtime.replace(plugin, manifest and chapterRoute(route, manifest) or route)
    end
end

local function closeDialog(dialog)
    if dialog and UIManager:isWidgetShown(dialog) then
        UIManager:close(dialog)
    end
end

local function markRead(plugin, manifest, row, runtime, route)
    local manifest_store = Manifest:new()
    local current_manifest = manifest_store:load(manifest.book_id) or manifest
    local updated_manifest, err = manifest_store:markReadMany(
        current_manifest,
        { row.position },
        true
    )
    if not updated_manifest then
        Dialog.message(Dialog.failureMessage(err))
        return
    end
    ChapterListing.setSelected(plugin, updated_manifest, row.position, false)
    refresh(runtime, plugin, route, updated_manifest)
end

local function toggleSelected(plugin, manifest, row, runtime, route)
    local selected = ChapterListing.toggleSelected(plugin, manifest, row.position)
    if selected then
        ChapterListing.setSelectionMode(plugin, manifest, true)
    end
    refresh(runtime, plugin, route)
end

local function showActions(plugin, route, runtime, manifest, row)
    local dialog
    dialog = ButtonDialog:new{
        title = row.title,
        buttons = {{
            {
                text = _("Mark as read"),
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    markRead(plugin, manifest, row, runtime, route)
                end,
            },
            {
                text = _("Download"),
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    Dialog.message(_("Download is not implemented."))
                end,
            },
            {
                text = _("Select"),
                checked_func = function()
                    return ChapterListing.isSelected(plugin, manifest, row.position)
                end,
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    toggleSelected(plugin, manifest, row, runtime, route)
                end,
            },
        }},
    }
    UIManager:show(dialog)
end

local function trailingActions(plugin, route, runtime, manifest, row, selection_mode)
    local actions = {
        {
            icon = "ellipsis-vertical",
            dim = not row.openable,
            callback = row.openable and function()
                showActions(plugin, route, runtime, manifest, row)
            end or nil,
        },
    }
    if selection_mode then
        table.insert(actions, {
            icon = ChapterListing.isSelected(plugin, manifest, row.position)
                and "square-check" or "square",
            dim = not row.openable,
            callback = row.openable and function()
                toggleSelected(plugin, manifest, row, runtime, route)
            end or nil,
        })
    end
    return actions
end

function ChaptersPage.build(shell, plugin, route, runtime)
    if route.error then
        return ContentBuilder.buildStatusContent(shell, _("Failed"), tostring(route.error))
    end

    local manifest = route.manifest
    if not manifest then
        return ContentBuilder.buildEmptyState(shell)
    end

    local filter, sort = ChapterListing.resolveState(plugin, manifest, {
        filter = route.filter,
        sort = route.sort,
    })
    local model = ChapterListing.buildModel(manifest, filter, sort)
    if model.count == 0 then
        return ContentBuilder.buildEmptyState(shell)
    end

    local selection_mode = ChapterListing.isSelectionMode(plugin, manifest)

    return ContentBuilder.buildList(shell, nil, {
        item_count = model.count,
        fixed_item = true,
        item_at = function(index)
            local row = model.rowAt(index)
            return {
                title = row.title,
                dim = row.dim,
                trailing_actions = trailingActions(
                    plugin,
                    route,
                    runtime,
                    manifest,
                    row,
                    selection_mode
                ),
                callback = row.openable and function()
                    ChapterOpen.open(plugin, manifest, row.position, {
                        from_reader = plugin.ui and plugin.ui.document ~= nil,
                        jump = "start",
                    })
                end or nil,
            }
        end,
    })
end

return ChaptersPage
