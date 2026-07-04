local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local ok_sha2, sha2 = pcall(require, "ffi/sha2")

local Cache = {
    path = DataStorage:getDataDir() .. "/cache/novel.lua",
    schema_version = 2,
    default_ttl = 0,
    default_max_records = 10000,
    access_flush_interval = 60 * 60,
}
Cache.__index = Cache

local KIND_TTL_OPTIONS = {
    search = "search_ttl_days",
    detail = "detail_ttl_days",
    toc = "toc_ttl_days",
    content = "content_ttl_days",
}

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

local function daysToSeconds(days)
    days = tonumber(days)
    if days and days > 0 then
        return math.floor(days * 24 * 60 * 60)
    end
    return nil
end

local function estimateSize(value)
    return #stable(value or {})
end

local function settingsCacheOptions(options)
    options = options or {}
    local settings = options.settings
        or (options.app and options.app.settings)
        or (options.plugin and options.plugin.app and options.plugin.app.settings)
    return settings and settings.cache or nil
end

local function ttlForKind(kind, options)
    options = options or {}
    if options.ttl ~= nil then
        return tonumber(options.ttl)
    end

    local cache_settings = settingsCacheOptions(options)
    local ttl_option = KIND_TTL_OPTIONS[bucketName(kind)]
    local ttl_days = ttl_option and cache_settings and cache_settings[ttl_option]
    local ttl = daysToSeconds(ttl_days)
    return ttl or Cache.default_ttl
end

local function maxRecordsForOptions(options)
    local cache_settings = settingsCacheOptions(options)
    return tonumber(cache_settings and cache_settings.max_metadata_records)
        or Cache.default_max_records
end

function Cache:new()
    return setmetatable({
        settings = LuaSettings:open(Cache.path),
        dirty = false,
    }, self)
end

function Cache.instance(options)
    options = options or {}
    if not Cache.isEnabled(options) then
        return nil
    end
    if options.cache and options.cache ~= true then
        return options.cache
    end
    return Cache:new()
end

function Cache.makeKey(kind, parts)
    return bucketName(kind) .. ":" .. hash(stable(parts or {}))
end

function Cache.isEnabled(options)
    options = options or {}
    if options.cache == false or options.no_cache == true
        or options.disable_cache == true then
        return false
    end
    local cache_settings = settingsCacheOptions(options)
    if cache_settings and cache_settings.enabled == false then
        return false
    end
    return true
end

function Cache.isKindEnabled(kind, options)
    if not Cache.isEnabled(options) then
        return false
    end
    local cache_settings = settingsCacheOptions(options)
    if bucketName(kind) == "content"
        and cache_settings
        and cache_settings.chapter_content_enabled == false then
        return false
    end
    return true
end

function Cache:markDirty()
    self.dirty = true
end

function Cache:flush()
    if self.dirty then
        self.settings:flush()
        self.dirty = false
    end
end

function Cache:bucket(kind, create)
    local name = bucketName(kind)
    local buckets = self.settings:readSetting("buckets")
    if type(buckets) ~= "table" then
        if create == false then
            return nil
        end
        buckets = {}
        self.settings:saveSetting("buckets", buckets)
        self:markDirty()
    end
    if type(buckets[name]) ~= "table" then
        if create == false then
            return nil
        end
        buckets[name] = {}
        self:markDirty()
    end
    return buckets[name], buckets
end

function Cache:get(kind, key, options)
    options = options or {}
    if not Cache.isEnabled(options) or options.refresh == true then
        return nil
    end

    local bucket = self:bucket(kind, false)
    if not bucket then
        return nil
    end
    local record = bucket[key]
    if type(record) ~= "table" then
        return nil
    end
    if record.schema_version ~= Cache.schema_version then
        bucket[key] = nil
        self:markDirty()
        self:flush()
        return nil
    end
    if record.expires_at and record.expires_at < now() then
        bucket[key] = nil
        self:markDirty()
        self:flush()
        return nil
    end
    if record.value == nil then
        bucket[key] = nil
        self:markDirty()
        self:flush()
        return nil
    end

    local timestamp = now()
    local previous_accessed_at = tonumber(record.last_accessed_at) or 0
    record.last_accessed_at = timestamp
    record.hit_count = (tonumber(record.hit_count) or 0) + 1
    self:markDirty()
    if options.flush_on_hit == true
        or (options.flush_on_hit ~= false
            and timestamp - previous_accessed_at >= Cache.access_flush_interval) then
        self:flush()
    end

    return clone(record.value), {
        key = key,
        stored_at = record.stored_at,
        expires_at = record.expires_at,
        last_accessed_at = record.last_accessed_at,
        hit_count = record.hit_count,
        owner = record.owner,
        tags = record.tags,
    }
end

function Cache:set(kind, key, value, options)
    options = options or {}
    if not Cache.isEnabled(options) or value == nil then
        return false
    end

    local ttl = ttlForKind(kind, options)
    local timestamp = now()
    local bucket = self:bucket(kind)
    bucket[key] = {
        schema_version = Cache.schema_version,
        stored_at = timestamp,
        last_accessed_at = timestamp,
        hit_count = 0,
        expires_at = ttl and ttl > 0 and (timestamp + ttl) or nil,
        owner = clone(options.owner),
        tags = clone(options.tags),
        size_estimate = estimateSize(value),
        value = clone(value),
    }
    self:markDirty()
    if options.flush ~= false then
        self:flush()
    end
    local max_records = maxRecordsForOptions(options)
    if max_records and max_records > 0 and options.prune ~= false then
        self:pruneLRU(max_records)
    end
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
    self:markDirty()
    self:flush()
end

local function kindMatches(kind, kinds)
    if not kinds then
        return true
    end
    if type(kinds) == "string" then
        return kind == bucketName(kinds)
    end
    if type(kinds) == "table" then
        for _, item in ipairs(kinds) do
            if kind == bucketName(item) then
                return true
            end
        end
    end
    return false
end

function Cache:invalidateByOwner(owner, kinds)
    if type(owner) ~= "table" then
        return 0
    end
    local buckets = self.settings:readSetting("buckets")
    if type(buckets) ~= "table" then
        return 0
    end
    local removed = 0
    for kind, bucket in pairs(buckets) do
        if type(bucket) == "table" then
            if kindMatches(kind, kinds) then
                for key, record in pairs(bucket) do
                    local record_owner = type(record) == "table" and record.owner
                    local matched = true
                    for owner_key, owner_value in pairs(owner) do
                        if type(record_owner) ~= "table"
                            or record_owner[owner_key] ~= owner_value then
                            matched = false
                            break
                        end
                    end
                    if matched then
                        bucket[key] = nil
                        removed = removed + 1
                    end
                end
            end
        end
    end
    if removed > 0 then
        self:markDirty()
        self:flush()
    end
    return removed
end

function Cache:pruneExpired()
    local buckets = self.settings:readSetting("buckets")
    if type(buckets) ~= "table" then
        return 0
    end

    local timestamp = now()
    local removed = 0
    for _, bucket in pairs(buckets) do
        if type(bucket) == "table" then
            for key, record in pairs(bucket) do
                if type(record) ~= "table"
                    or record.schema_version ~= Cache.schema_version
                    or record.value == nil
                    or (record.expires_at and record.expires_at < timestamp) then
                    bucket[key] = nil
                    removed = removed + 1
                end
            end
        end
    end
    if removed > 0 then
        self:markDirty()
        self:flush()
    end
    return removed
end

function Cache:pruneLRU(max_records, max_bytes)
    max_records = tonumber(max_records)
    max_bytes = tonumber(max_bytes)
    if not max_records and not max_bytes then
        return 0
    end

    local buckets = self.settings:readSetting("buckets")
    if type(buckets) ~= "table" then
        return 0
    end

    local records = {}
    local total_size = 0
    for kind, bucket in pairs(buckets) do
        if type(bucket) == "table" then
            for key, record in pairs(bucket) do
                if type(record) == "table" then
                    local size = tonumber(record.size_estimate) or 0
                    total_size = total_size + size
                    table.insert(records, {
                        bucket = bucket,
                        kind = kind,
                        key = key,
                        size = size,
                        last_accessed_at = tonumber(record.last_accessed_at)
                            or tonumber(record.stored_at) or 0,
                    })
                end
            end
        end
    end

    table.sort(records, function(left, right)
        return left.last_accessed_at < right.last_accessed_at
    end)

    local removed = 0
    for index = 1, #records do
        local over_records = max_records and (#records - removed) > max_records
        local over_bytes = max_bytes and total_size > max_bytes
        if not over_records and not over_bytes then
            break
        end
        local record = records[index]
        if record.bucket[record.key] then
            record.bucket[record.key] = nil
            total_size = total_size - record.size
            removed = removed + 1
        end
    end

    if removed > 0 then
        self:markDirty()
        self:flush()
    end
    return removed
end

function Cache.deleteStorage()
    os.remove(Cache.path)
    os.remove(Cache.path .. ".old")
end

return Cache
