local _ = require("novel.i18n")
local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")

local Dialog = {}

function Dialog.clearIfOwned(owner, key, widget)
    if owner and key and owner[key] == widget then
        owner[key] = nil
    end
end

function Dialog.closeWidget(owner, key)
    if owner and owner[key] then
        local widget = owner[key]
        owner[key] = nil
        if UIManager:isWidgetShown(widget) then
            UIManager:close(widget)
        end
    end
end

function Dialog.closeKeys(owner, keys)
    for key_index = 1, #(keys or {}) do
        Dialog.closeWidget(owner, keys[key_index])
    end
end

function Dialog.showWidget(owner, key, widget)
    if owner and key then
        Dialog.closeWidget(owner, key)
        owner[key] = widget
    end
    UIManager:show(widget)
    return widget
end

function Dialog.message(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

function Dialog.confirm(message, ok_text, callback)
    UIManager:show(ConfirmBox:new{
        text = message,
        ok_text = ok_text,
        ok_callback = callback,
    })
end

function Dialog.errorText(result, fallback)
    if not result then
        return fallback or _("no result returned")
    end
    local error_message = result.error
        and (result.error.message or result.error.kind)
        or fallback
        or _("unknown error")
    local parts = { tostring(error_message) }
    if result.response then
        if result.response.status then
            table.insert(parts, "HTTP " .. tostring(result.response.status))
        end
        if result.response.final_url then
            table.insert(parts, tostring(result.response.final_url))
        end
    end
    return table.concat(parts, "\n")
end

function Dialog.failureMessage(reason, fallback)
    local detail
    if reason == nil then
        detail = fallback
    elseif type(reason) == "table" then
        detail = Dialog.errorText(reason, fallback)
    else
        detail = tostring(reason)
    end
    if detail == nil or detail == "" then
        return _("Failed")
    end
    return _("Failed: ") .. detail
end

function Dialog.canceledMessage()
    return _("Canceled.")
end

function Dialog.unsupportedText(items)
    local lines = {}
    for item_index = 1, #(items or {}) do
        local item = items[item_index]
        table.insert(lines, table.concat({
            item.source or "",
            item.field or "",
            item.kind or "",
            item.snippet or "",
        }, "\n"))
    end
    return table.concat(lines, "\n\n")
end

function Dialog.showUnsupported(items)
    Dialog.message(Dialog.unsupportedText(items))
end

return Dialog
