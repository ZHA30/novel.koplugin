local SourceInfo = {}

function SourceInfo.title(source)
    if type(source) ~= "table" then
        return ""
    end
    if source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return source.bookSourceUrl or ""
end

function SourceInfo.key(source)
    if type(source) ~= "table" then
        return ""
    end
    return source.bookSourceUrl or ""
end

return SourceInfo
