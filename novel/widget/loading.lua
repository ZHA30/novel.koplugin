local _ = require("novel.i18n")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")

local Loading = {}

local active_widget
local active_refs = {}

local function isShown(widget)
    return widget and UIManager:isWidgetShown(widget)
end

local function clearRefAt(index)
    local ref = active_refs[index]
    if ref.owner and ref.key and ref.owner[ref.key] == ref.widget then
        ref.owner[ref.key] = nil
    end
    table.remove(active_refs, index)
end

local function clearRefsForWidget(widget)
    for ref_index = #active_refs, 1, -1 do
        if active_refs[ref_index].widget == widget then
            clearRefAt(ref_index)
        end
    end
end

local function addRef(owner, key, widget)
    if not owner or not key then
        return
    end
    for ref_index = 1, #active_refs do
        local ref = active_refs[ref_index]
        if ref.owner == owner and ref.key == key then
            ref.widget = widget
            return
        end
    end
    table.insert(active_refs, {
        owner = owner,
        key = key,
        widget = widget,
    })
end

local function removeRef(owner, key, widget)
    if not owner or not key then
        return
    end
    for ref_index = #active_refs, 1, -1 do
        local ref = active_refs[ref_index]
        if ref.owner == owner
            and ref.key == key
            and (not widget or ref.widget == widget) then
            clearRefAt(ref_index)
        end
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

function Loading.show(owner, key)
    local existing = owner and key and owner[key]
    if isShown(existing) then
        addRef(owner, key, existing)
        return existing
    end

    if existing then
        removeRef(owner, key, existing)
        owner[key] = nil
    end

    local widget = active_widget
    if not isShown(widget) then
        clearRefsForWidget(widget)
        widget = TrapWidget:new{
            text = _("Loading..."),
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

    removeRef(owner, key, loading)
    if owner and key and owner[key] == loading then
        owner[key] = nil
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
