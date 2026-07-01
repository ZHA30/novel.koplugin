local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local ok_sha2, sha2 = pcall(require, "ffi/sha2")

local Cache = {
    path = DataStorage:getDataDir() .. "/cache/novel.lua",
    schema_version = 1,
    default_ttl = 7 * 24 * 60 * 60,
}
Cache.__index = Cache

local function now()
    return os.time()
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function stable(value, seen)
    local value_type = type(value)
    if value_type ~= "table" then
        return value_type .. ":" .. tostring(value)
    end
    seen = seen or {}
    if seen[value] then
        return "table:<cycle>"
    end
    seen[value] = true

    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    local parts = { "table:{" }
    for key_index = 1, #keys do
        local key = keys[key_index]
        table.insert(parts, stable(key, seen))
        table.insert(parts, "=")
        table.insert(parts, stable(value[key], seen))
        table.insert(parts, ";")
    end
    table.insert(parts, "}")
    seen[value] = nil
    return table.concat(parts)
end

local function fallbackHash(value)
    local hash = 5381
    for index = 1, #value do
        hash = (hash * 33 + value:byte(index)) % 4294967296
    end
    return string.format("%08x", hash)
end

local function hash(value)
    if ok_sha2 and sha2 and sha2.md5 then
        return sha2.md5(value)
    end
    return fallbackHash(value)
end

local function bucketName(kind)
    return tostring(kind or "default")
end

function Cache:new()
    return setmetatable({
        settings = LuaSettings:open(Cache.path),
    }, self)
end

function Cache.makeKey(kind, parts)
    return bucketName(kind) .. ":" .. hash(stable(parts or {}))
end

function Cache.isEnabled(options)
    options = options or {}
    return options.no_cache ~= true and options.disable_cache ~= true
end

function Cache:bucket(kind)
    local name = bucketName(kind)
    local buckets = self.settings:readSetting("buckets")
    if type(buckets) ~= "table" then
        buckets = {}
        self.settings:saveSetting("buckets", buckets)
    end
    if type(buckets[name]) ~= "table" then
        buckets[name] = {}
    end
    return buckets[name], buckets
end

function Cache:get(kind, key, options)
    options = options or {}
    if not Cache.isEnabled(options) or options.refresh == true then
        return nil
    end

    local bucket = self:bucket(kind)
    local record = bucket[key]
    if type(record) ~= "table" then
        return nil
    end
    if record.schema_version ~= Cache.schema_version then
        bucket[key] = nil
        self.settings:flush()
        return nil
    end
    if record.expires_at and record.expires_at < now() then
        bucket[key] = nil
        self.settings:flush()
        return nil
    end
    if record.value == nil then
        bucket[key] = nil
        self.settings:flush()
        return nil
    end
    return clone(record.value), {
        key = key,
        stored_at = record.stored_at,
        expires_at = record.expires_at,
    }
end

function Cache:set(kind, key, value, options)
    options = options or {}
    if not Cache.isEnabled(options) or value == nil then
        return false
    end

    local ttl = tonumber(options.ttl or Cache.default_ttl)
    local timestamp = now()
    local bucket = self:bucket(kind)
    bucket[key] = {
        schema_version = Cache.schema_version,
        stored_at = timestamp,
        expires_at = ttl and ttl > 0 and (timestamp + ttl) or nil,
        value = clone(value),
    }
    self.settings:flush()
    return true
end

function Cache:invalidate(kind, key)
    local bucket = self:bucket(kind)
    if key then
        bucket[key] = nil
    else
        for bucket_key in pairs(bucket) do
            bucket[bucket_key] = nil
        end
    end
    self.settings:flush()
end

function Cache.deleteStorage()
    os.remove(Cache.path)
    os.remove(Cache.path .. ".old")
end

return Cache
