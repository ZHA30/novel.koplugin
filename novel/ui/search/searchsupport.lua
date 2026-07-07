local _ = require("novel.i18n")
local SourceStore = require("novel.storage.sourcestore")

local SearchSupport = {}

function SearchSupport.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function SearchSupport.sourceTitle(source)
    return SourceStore.title(source)
end

function SearchSupport.sourceSubtitle(source)
    local parts = {}
    if source.bookSourceGroup and source.bookSourceGroup ~= "" then
        table.insert(parts, source.bookSourceGroup)
    end
    return table.concat(parts, " / ")
end

function SearchSupport.resultTitle(keyword, first_page, last_page)
    local title = SearchSupport.trim(keyword)
    if title == "" then
        title = _("Search")
    end
    first_page = tonumber(first_page) or tonumber(last_page) or 1
    last_page = tonumber(last_page) or first_page
    if first_page ~= last_page then
        return title .. " (" .. tostring(first_page) .. "-" .. tostring(last_page) .. ")"
    end
    return title .. " (" .. tostring(last_page) .. ")"
end

function SearchSupport.searchableSources(plugin)
    return SourceStore.searchable(plugin.app:getSourceStore():list())
end

function SearchSupport.sameResultRoute(route, source, keyword)
    if not route or route.key ~= "search_results" then
        return false
    end
    local route_source = route.source or {}
    local source_url = source and source.bookSourceUrl or nil
    return route_source.bookSourceUrl == source_url
        and tostring(route.keyword or "") == tostring(keyword or "")
end

return SearchSupport
