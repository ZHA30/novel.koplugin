local _ = require("novel.i18n")
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ChapterListing = require("novel.ui.chapters.listing")
local ContentBuilder = require("novel.ui.contentbuilder")
local ChapterOpen = require("novel.reader.chapteropen")
local Device = require("device")
local Dialog = require("novel.ui.widget.dialog")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local Icons = require("novel.icons")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Manifest = require("novel.storage.manifest")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Size = require("ui/size")
local ShellRoutes = require("novel.ui.shellroutes")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local ChaptersPage = {}
local Screen = Device.screen
local ACTION_BUTTON_SIZE = Screen:scaleBySize(56)
local ACTION_ICON_SIZE = Screen:scaleBySize(24)
local ACTION_DIALOG_WIDTH_FACTOR = 0.75
local ACTION_DIALOG_MIN_WIDTH = Screen:scaleBySize(260)
local ACTION_TITLE_BOTTOM_GAP = Size.padding.large
local ACTION_SEPARATOR_BOTTOM_GAP = Size.padding.default

local ActionIconButton = InputContainer:extend{
    icon = nil,
    enabled = true,
    callback = nil,
}

function ActionIconButton:init()
    self.dimen = Geom:new{
        x = 0,
        y = 0,
        w = ACTION_BUTTON_SIZE,
        h = ACTION_BUTTON_SIZE,
    }
    self[1] = CenterContainer:new{
        dimen = self.dimen:copy(),
        Icons.widget(self.icon, {
            size = ACTION_ICON_SIZE,
            dim = self.enabled == false,
        }),
    }
    self.ges_events = {
        TapAction = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
    }
end

function ActionIconButton:onTapAction()
    if self.enabled ~= false and self.callback then
        self.callback()
    end
    return true
end

local actionIconRow

local ChapterActionDialog = InputContainer:extend{
    modal = true,
    title = nil,
    actions = nil,
}

function ChapterActionDialog:init()
    local screen_max_width = math.max(
        ACTION_BUTTON_SIZE,
        Screen:getWidth() - 2 * Size.padding.fullscreen
    )
    local target_width = math.floor(
        math.min(Screen:getWidth(), Screen:getHeight()) * ACTION_DIALOG_WIDTH_FACTOR
    )
    local dialog_width = math.min(
        screen_max_width,
        math.max(ACTION_DIALOG_MIN_WIDTH, target_width)
    )
    local title = TextBoxWidget:new{
        text = tostring(self.title or ""),
        width = dialog_width,
        face = Font:getFace("infofont"),
        alignment = "left",
    }

    local content = VerticalGroup:new{
        align = "left",
        title,
        VerticalSpan:new{
            width = ACTION_TITLE_BOTTOM_GAP,
        },
        LineWidget:new{
            dimen = Geom:new{
                w = dialog_width,
                h = Size.line.thin,
            },
            background = Blitbuffer.COLOR_GRAY_5,
        },
        VerticalSpan:new{
            width = ACTION_SEPARATOR_BOTTOM_GAP,
        },
        actionIconRow(dialog_width, self.actions),
    }

    self.movable = MovableContainer:new{
        FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            radius = Size.radius.window,
            padding = Size.padding.default,
            content,
        },
    }
    self[1] = CenterContainer:new{
        dimen = Screen:getSize(),
        self.movable,
    }

    if Device:isTouchDevice() then
        self.ges_events.TapClose = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{
                    x = 0,
                    y = 0,
                    w = Screen:getWidth(),
                    h = Screen:getHeight(),
                },
            },
        }
    end
    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end
end

function ChapterActionDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self.movable.dimen
    end)
end

function ChapterActionDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self.movable.dimen
    end)
end

function ChapterActionDialog:onClose()
    UIManager:close(self)
    return true
end

function ChapterActionDialog:onTapClose(_, ges)
    if ges and ges.pos and ges.pos:notIntersectWith(self.movable.dimen) then
        self:onClose()
    end
    return true
end

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

local function markReadState(plugin, manifest, row, runtime, route, read)
    local manifest_store = Manifest:new()
    local current_manifest = manifest_store:load(manifest.book_id) or manifest
    local updated_manifest, err = manifest_store:markReadMany(
        current_manifest,
        { row.position },
        read
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

function actionIconRow(width, actions)
    local count = #(actions or {})
    local row_width = math.max(0, tonumber(width) or 0)
    local row = HorizontalGroup:new{}
    row.not_focusable = true
    if count == 0 then
        return row
    end

    local gap = math.floor(
        math.max(0, row_width - count * ACTION_BUTTON_SIZE) / (count + 1)
    )
    if gap > 0 then
        table.insert(row, HorizontalSpan:new{
            width = gap,
        })
    end
    for action_index = 1, count do
        local action = actions[action_index]
        table.insert(row, ActionIconButton:new{
            icon = action.icon,
            enabled = action.enabled,
            callback = action.callback,
        })
        if gap > 0 then
            table.insert(row, HorizontalSpan:new{
                width = gap,
            })
        end
    end
    return row
end

local function showActions(plugin, route, runtime, manifest, row)
    local dialog
    dialog = ChapterActionDialog:new{
        title = row.title,
        actions = {
            {
                icon = "check-check",
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    markReadState(plugin, manifest, row, runtime, route, true)
                end,
            },
            {
                icon = "check-check-off",
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    markReadState(plugin, manifest, row, runtime, route, false)
                end,
            },
            {
                icon = "arrow-down-to-line",
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    Dialog.message(_("Download is not implemented."))
                end,
            },
            {
                icon = "trash-2",
                enabled = row.openable,
                callback = function()
                    closeDialog(dialog)
                    Dialog.message(_("Delete is not implemented."))
                end,
            },
        },
    }
    UIManager:show(dialog)
end

local function trailingActions(plugin, route, runtime, manifest, row, selection_mode)
    if selection_mode then
        return {
            {
                icon = ChapterListing.isSelected(plugin, manifest, row.position)
                    and "square-check" or "square",
                dim = not row.openable,
                callback = row.openable and function()
                    toggleSelected(plugin, manifest, row, runtime, route)
                end or nil,
            },
        }
    end
    return {
        {
            icon = "ellipsis-vertical",
            dim = not row.openable,
            callback = row.openable and function()
                showActions(plugin, route, runtime, manifest, row)
            end or nil,
        },
    }
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
