local Normalize = require("novel.source.normalize")
local rapidjson = require("rapidjson")

local Importer = {}

local function decodeJSON(json)
    local ok, decoded_or_error = pcall(rapidjson.decode, json)
    if ok then
        return decoded_or_error
    end
    return nil, decoded_or_error
end

local function isArray(value)
    return type(value) == "table" and value[1] ~= nil
end

function Importer.fromJSON(json)
    local raw, decode_error = decodeJSON(json)
    if not raw then
        return nil, decode_error or "invalid JSON"
    end

    local raw_sources = isArray(raw) and raw or { raw }
    local sources, errors = {}, {}

    for index, raw_source in ipairs(raw_sources) do
        local source, err = Normalize.source(raw_source)
        if source then
            table.insert(sources, source)
        else
            table.insert(errors, {
                index = index,
                error = err,
            })
        end
    end

    return sources, errors
end

return Importer
