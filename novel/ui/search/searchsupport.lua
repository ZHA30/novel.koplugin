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
    if source.concurrentRate and source.concurrentRate ~= "" then
        table.insert(parts, _("Rate: ") .. source.concurrentRate)
    end
    return table.concat(parts, " / ")
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
