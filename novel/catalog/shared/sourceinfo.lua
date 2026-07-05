local SourceStore = require("novel.storage.sourcestore")

local SourceInfo = {}

function SourceInfo.title(source)
    return SourceStore.title(source)
end

function SourceInfo.key(source)
    return SourceStore.key(source)
end

return SourceInfo
