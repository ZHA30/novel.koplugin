local BookSource = require("novel.model.booksource")

local Capability = {}

function Capability.key(source)
    if type(source) ~= "table" then
        return ""
    end
    return BookSource.getKey(source) or ""
end

function Capability.title(source)
    if type(source) ~= "table" then
        return ""
    end
    return BookSource.getName(source) or ""
end

function Capability.canSearch(source)
    return type(source) == "table"
        and source.enabled ~= false
        and source.searchUrl ~= nil
        and source.searchUrl ~= ""
        and type(source.ruleSearch) == "table"
end

function Capability.canExplore(source)
    return type(source) == "table"
        and source.enabled ~= false
        and source.enabledExplore ~= false
        and source.exploreUrl ~= nil
        and source.exploreUrl ~= ""
end

function Capability.searchable(sources)
    local searchable = {}
    for source_index = 1, #(sources or {}) do
        local source = sources[source_index]
        if Capability.canSearch(source) then
            table.insert(searchable, source)
        end
    end
    return searchable
end

return Capability
