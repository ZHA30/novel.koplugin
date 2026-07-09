local _ = require("novel.i18n")
local SourceStore = require("novel.storage.sourcestore")

local DiscoverResultSet = {}

function DiscoverResultSet.sourceTitle(source)
    return SourceStore.title(source)
end

function DiscoverResultSet.resultTitle(group, first_page, last_page)
    local title = group and group.title or _("Discover")
    first_page = tonumber(first_page) or tonumber(last_page) or 1
    last_page = tonumber(last_page) or first_page
    if first_page ~= last_page then
        return title .. " (" .. tostring(first_page) .. "-" .. tostring(last_page) .. ")"
    end
    return title .. " (" .. tostring(last_page) .. ")"
end

function DiscoverResultSet.sameRoute(route, source, group)
    if not route or route.key ~= "discover_results" then
        return false
    end
    local route_source = route.source or {}
    local route_group = route.group or {}
    local source_url = source and source.bookSourceUrl or nil
    local group_url = group and group.url or nil
    return route_source.bookSourceUrl == source_url
        and route_group.url == group_url
end

return DiscoverResultSet
