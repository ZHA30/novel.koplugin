local _ = require("novel.i18n")
local LoadingTrap = require("novel.ui.widget.loadingtrap")
local UIManager = require("ui/uimanager")

local Loading = {}

local active_widget
-- Each show() call owns one lease, even when the same owner/key reuses
-- the shared widget, so an older callback only releases its own lease.
local active_refs = {}

local function isShown(widget)
    return widget and UIManager:isWidgetShown(widget)
end

local function clearRefAt(index)
    table.remove(active_refs, index)
end

local function clearRefsForWidget(widget)
    for ref_index = #active_refs, 1, -1 do
        local ref = active_refs[ref_index]
        if ref.widget == widget then
            if ref.owner and ref.key and ref.owner[ref.key] == widget then
                ref.owner[ref.key] = nil
            end
            clearRefAt(ref_index)
        end
    end
end

local function addRef(owner, key, widget)
    if not owner or not key then
        return
    end
    table.insert(active_refs, {
        owner = owner,
        key = key,
        widget = widget,
    })
end

local function hasKeyRefs(owner, key)
    for ref_index = 1, #active_refs do
        local ref = active_refs[ref_index]
        if ref.owner == owner and ref.key == key then
            return true
        end
    end
    return false
end

local function removeRef(owner, key, widget, remove_all)
    if not owner or not key then
        return
    end
    for ref_index = #active_refs, 1, -1 do
        local ref = active_refs[ref_index]
        if ref.owner == owner
            and ref.key == key
            and (not widget or ref.widget == widget) then
            clearRefAt(ref_index)
            if not remove_all then
                break
            end
        end
    end
    if owner[key] and not hasKeyRefs(owner, key) then
        owner[key] = nil
    end
end

local function hasRefs(widget)
    for ref_index = 1, #active_refs do
        if active_refs[ref_index].widget == widget then
            return true
        end
    end
    return false
end

function Loading.show(owner, key, options)
    options = options or {}
    local existing = owner and key and owner[key]
    if isShown(existing) then
        addRef(owner, key, existing)
        return existing
    end

    if existing then
        removeRef(owner, key, existing, true)
        owner[key] = nil
    end

    local widget = active_widget
    if not isShown(widget) then
        clearRefsForWidget(widget)
        widget = LoadingTrap:new{
            text = _("Loading..."),
            dismissable = options.dismissable ~= false,
            flush_events_on_show = options.flush_events_on_show ~= false,
        }
        active_widget = widget
        UIManager:show(widget)
        UIManager:forceRePaint()
    end

    if owner and key then
        owner[key] = widget
        addRef(owner, key, widget)
    end
    return widget
end

function Loading.close(owner, key, widget)
    local loading = widget or (owner and key and owner[key])
    if not loading then
        return
    end

    if owner and key then
        removeRef(owner, key, loading, not widget)
    end

    if loading == active_widget and not isShown(loading) then
        clearRefsForWidget(loading)
        active_widget = nil
        return
    end

    if loading == active_widget and hasRefs(loading) then
        return
    end

    if loading == active_widget then
        clearRefsForWidget(loading)
        active_widget = nil
    end

    if isShown(loading) then
        UIManager:close(loading)
        UIManager:forceRePaint()
    end
end

function Loading.closeKeys(owner, keys)
    for key_index = 1, #(keys or {}) do
        Loading.close(owner, keys[key_index])
    end
end

return Loading
