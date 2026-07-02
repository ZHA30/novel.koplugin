local BaseMenu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local NovelMenu = {}

local function closeAfterSelect(menu)
    if UIManager:isWidgetShown(menu) then
        UIManager:close(menu)
    end
    if menu.close_callback then
        menu.close_callback()
    end
end

local function defaultOnMenuSelect(menu, item)
    if item.sub_item_table == nil then
        if item.select_enabled == false then
            return true
        end
        if item.select_enabled_func and not item.select_enabled_func() then
            return true
        end

        menu:onMenuChoice(item)
        if item.close_menu == true then
            closeAfterSelect(menu)
        end
    else
        menu.item_table.title = menu.title
        table.insert(menu.item_table_stack, menu.item_table)
        menu:switchItemTable(item.text, item.sub_item_table)
    end
    return true
end

function NovelMenu.new(_menu, args)
    args = args or {}
    args.onMenuSelect = args.onMenuSelect or defaultOnMenuSelect
    return BaseMenu:new(args)
end

return NovelMenu
