local _ = require("novel.i18n")
local ContentBuilder = require("novel.ui.contentbuilder")
local Dialog = require("novel.ui.widget.dialog")
local DownloadQueue = require("novel.reader.downloadqueue")

local DownloadsPage = {}

local function subtitleFor(item)
    local parts = {}
    if item.book_title and item.book_title ~= "" then
        table.insert(parts, item.book_title)
    end
    if item.source_name and item.source_name ~= "" then
        table.insert(parts, item.source_name)
    end
    if item.error and item.error ~= "" then
        table.insert(parts, item.error)
    end
    return table.concat(parts, "  ")
end

local function mandatoryFor(item)
    local label = DownloadQueue.statusLabel(item)
    local tries = tonumber(item.tries) or 0
    if tries > 0 and item.status ~= DownloadQueue.STATUS_DONE then
        return string.format("%s %d/%d", label, tries, DownloadQueue.max_retries)
    end
    return label
end

local function trailingActions(plugin, item)
    local actions = {}
    if item.status == DownloadQueue.STATUS_ERROR then
        table.insert(actions, {
            icon = "rotate-cw",
            callback = function()
                DownloadQueue.retry(plugin, item.key)
            end,
        })
    end
    table.insert(actions, {
        icon = "trash-2",
        callback = function()
            Dialog.confirm(
                _("Remove this download?"),
                _("Remove"),
                function()
                    DownloadQueue.remove(plugin, item.key)
                end
            )
        end,
    })
    return actions
end

function DownloadsPage.build(shell, plugin)
    local items = DownloadQueue.items(plugin)
    if #items == 0 then
        return ContentBuilder.buildEmptyContent(shell, _("No downloads"))
    end

    return ContentBuilder.buildList(shell, nil, {
        item_count = #items,
        fixed_item = true,
        item_at = function(index)
            local item = items[index]
            if not item then
                return nil
            end
            return {
                title = item.title,
                subtitle = subtitleFor(item),
                mandatory = mandatoryFor(item),
                trailing_actions = trailingActions(plugin, item),
            }
        end,
    })
end

return DownloadsPage
