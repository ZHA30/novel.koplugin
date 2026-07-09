local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local Persist = require("persist")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")

local ok_device, Device = pcall(require, "device")
if not ok_device then
    Device = nil
end
local ok_sha2, sha2 = pcall(require, "ffi/sha2")

local Cache = {
    cache_dir = DataStorage:getDataDir() .. "/cache",
    db_path = DataStorage:getDataDir() .. "/cache/novel.sqlite3",
    legacy_path = DataStorage:getDataDir() .. "/cache/novel.lua",
    schema_version = 2,
    db_schema_version = 1,
    codec = "zstd",
    default_ttl = 0,
    default_max_records = 10000,
    default_max_bytes = 20 * 1024 * 1024,
    access_flush_interval = 60 * 60,
    prune_interval = 15 * 60,
    busy_timeout = 5000,
}
Cache.path = Cache.legacy_path
Cache.__index = Cache

local KIND_TTL_OPTIONS = {
    search = "search_ttl_days",
    detail = "detail_ttl_days",
    toc = "toc_ttl_days",
    content = "content_ttl_days",
}

local CREATE_SCHEMA = [[
CREATE TABLE IF NOT EXISTS cache_records (
    kind TEXT NOT NULL,
    key TEXT NOT NULL,
    schema_version INTEGER NOT NULL,
    stored_at INTEGER NOT NULL,
    expires_at INTEGER,
    last_accessed_at INTEGER NOT NULL,
    hit_count INTEGER NOT NULL DEFAULT 0,
    owner_source TEXT,
    owner_book TEXT,
    owner_blob BLOB,
    tags_blob BLOB,
    value_blob BLOB NOT NULL,
    size_estimate INTEGER NOT NULL DEFAULT 0,
    blob_size INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(kind, key)
);
CREATE INDEX IF NOT EXISTS cache_records_expires
    ON cache_records(expires_at);
CREATE INDEX IF NOT EXISTS cache_records_last_access
    ON cache_records(last_accessed_at);
CREATE INDEX IF NOT EXISTS cache_records_owner
    ON cache_records(owner_source, owner_book);
CREATE TABLE IF NOT EXISTS cache_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
]]

local SELECT_RECORD = [[
SELECT schema_version, stored_at, expires_at, last_accessed_at, hit_count,
       owner_blob, tags_blob, value_blob
FROM cache_records
WHERE kind = ? AND key = ?;
]]

local INSERT_RECORD = [[
INSERT OR REPLACE INTO cache_records
    (kind, key, schema_version, stored_at, expires_at, last_accessed_at,
     hit_count, owner_source, owner_book, owner_blob, tags_blob, value_blob,
     size_estimate, blob_size)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
]]

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

local function maxBytesForOptions(options)
    local cache_settings = settingsCacheOptions(options)
    return tonumber(cache_settings and cache_settings.max_metadata_bytes)
        or Cache.default_max_bytes
end

local function isFile(path)
    return lfs and lfs.attributes(path, "mode") == "file"
end

local function fileSize(path)
    local attr = lfs and lfs.attributes(path)
    if attr and attr.mode == "file" then
        return tonumber(attr.size) or 0
    end
    return 0
end

local function encode(codec, value)
    if value == nil then
        return nil, 0
    end
    local encoded, size_or_err = codec.serialize(value)
    if not encoded then
        return nil, size_or_err
    end
    return encoded, tonumber(size_or_err) or #encoded
end

local function decode(codec, blob)
    if blob == nil then
        return nil
    end
    local value, err = codec.deserialize(blob)
    if value == nil and err then
        logger.warn("novel cache decode failed:", err)
    end
    return value
end

local function ownerValue(owner, key)
    return type(owner) == "table" and owner[key] or nil
end

local function ownerMatches(record_owner, owner)
    if type(owner) ~= "table" then
        return false
    end
    for owner_key, owner_value in pairs(owner) do
        if type(record_owner) ~= "table"
            or record_owner[owner_key] ~= owner_value then
            return false
        end
    end
    return true
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

local function quotedKindList(kinds)
    if not kinds then
        return nil
    end
    local list = {}
    if type(kinds) == "string" then
        list[1] = bucketName(kinds)
    elseif type(kinds) == "table" then
        for _, item in ipairs(kinds) do
            table.insert(list, bucketName(item))
        end
    end
    if #list == 0 then
        return nil
    end
    local quoted = {}
    for index = 1, #list do
        quoted[index] = "'" .. list[index]:gsub("'", "''") .. "'"
    end
    return table.concat(quoted, ",")
end

local function setMeta(db, key, value)
    local stmt = db:prepare([[
        INSERT OR REPLACE INTO cache_meta (key, value) VALUES (?, ?);
    ]])
    stmt:reset():bind(key, value):step()
end

local function getMeta(db, key)
    local stmt = db:prepare("SELECT value FROM cache_meta WHERE key = ?;")
    local row = stmt:reset():bind(key):step()
    return row and row[1]
end

function Cache:openDB()
    local ok, err = util.makePath(self.cache_dir)
    if not ok then
        return nil, err
    end

    local db = SQ3.open(self.db_path)
    if db.set_busy_timeout then
        db:set_busy_timeout(self.busy_timeout)
    end
    if Device and Device.canUseWAL and Device:canUseWAL() then
        db:exec("PRAGMA journal_mode=WAL;")
    else
        db:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    return db
end

function Cache:withDB(callback)
    local db, err = self:openDB()
    if not db then
        logger.warn("novel cache open failed:", err)
        return nil, err
    end

    local ok, first, second, third = pcall(callback, db)
    db:close()
    if not ok then
        logger.warn("novel cache operation failed:", first)
        return nil, first
    end
    return first, second, third
end

function Cache:insertRecord(db, kind, key, record)
    if type(record) ~= "table" or record.value == nil then
        return false
    end

    local value_blob, value_size = encode(self.codec, record.value)
    if not value_blob then
        logger.warn("novel cache value encode failed:", value_size)
        return false
    end

    local owner_blob, owner_size = encode(self.codec, record.owner)
    if record.owner ~= nil and not owner_blob then
        logger.warn("novel cache owner encode failed:", owner_size)
        return false
    end

    local tags_blob, tags_size = encode(self.codec, record.tags)
    if record.tags ~= nil and not tags_blob then
        logger.warn("novel cache tags encode failed:", tags_size)
        return false
    end

    local stmt = db:prepare(INSERT_RECORD)
    stmt:reset():bind(
        bucketName(kind),
        key,
        record.schema_version or Cache.schema_version,
        tonumber(record.stored_at) or now(),
        record.expires_at,
        tonumber(record.last_accessed_at) or tonumber(record.stored_at)
            or now(),
        tonumber(record.hit_count) or 0,
        ownerValue(record.owner, "source"),
        ownerValue(record.owner, "book"),
        owner_blob,
        tags_blob,
        value_blob,
        tonumber(record.size_estimate) or estimateSize(record.value),
        value_size + owner_size + tags_size
    ):step()
    return true
end

function Cache:migrateLegacy(db)
    if getMeta(db, "legacy_lua_imported") == "1" then
        return
    end

    if not isFile(Cache.legacy_path) then
        setMeta(db, "legacy_lua_imported", "1")
        return
    end

    local settings = LuaSettings:open(Cache.legacy_path)
    local buckets = settings:readSetting("buckets")
    local imported = 0
    if type(buckets) == "table" then
        db:exec("BEGIN IMMEDIATE;")
        for kind, bucket in pairs(buckets) do
            if type(bucket) == "table" then
                for key, record in pairs(bucket) do
                    if self:insertRecord(db, kind, key, record) then
                        imported = imported + 1
                    end
                end
            end
        end
        db:exec("COMMIT;")
    end
    setMeta(db, "legacy_lua_imported", "1")
    logger.dbg("novel cache legacy import:", imported)
end

function Cache:init()
    self:withDB(function(db)
        db:exec(CREATE_SCHEMA)
        local version = tonumber(db:rowexec("PRAGMA user_version;")) or 0
        if version < Cache.db_schema_version then
            db:exec(string.format("PRAGMA user_version=%d;",
                Cache.db_schema_version))
        end
        self:migrateLegacy(db)
    end)
end

function Cache:new()
    local cache = setmetatable({
        codec = Persist.getCodec(Cache.codec),
    }, self)
    cache:init()
    return cache
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

function Cache.markDirty() end

function Cache.flush() end

function Cache:get(kind, key, options)
    options = options or {}
    if not Cache.isEnabled(options) or options.refresh == true then
        return nil
    end

    kind = bucketName(kind)
    return self:withDB(function(db)
        local stmt = db:prepare(SELECT_RECORD)
        local row = stmt:reset():bind(kind, key):step()
        if not row then
            return nil
        end

        local schema_version = tonumber(row[1])
        local stored_at = tonumber(row[2])
        local expires_at = tonumber(row[3])
        local last_accessed_at = tonumber(row[4]) or 0
        local hit_count = tonumber(row[5]) or 0
        local timestamp = now()

        if schema_version ~= Cache.schema_version
            or (expires_at and expires_at < timestamp) then
            local delete_stmt = db:prepare([[
                DELETE FROM cache_records WHERE kind = ? AND key = ?;
            ]])
            delete_stmt:reset():bind(kind, key):step()
            return nil
        end

        local value = decode(self.codec, row[8])
        if value == nil then
            local delete_stmt = db:prepare([[
                DELETE FROM cache_records WHERE kind = ? AND key = ?;
            ]])
            delete_stmt:reset():bind(kind, key):step()
            return nil
        end

        local next_hit_count = hit_count + 1
        if options.flush_on_hit == true
            or (options.flush_on_hit ~= false
                and timestamp - last_accessed_at >= Cache.access_flush_interval) then
            local update_stmt = db:prepare([[
                UPDATE cache_records
                SET last_accessed_at = ?, hit_count = ?
                WHERE kind = ? AND key = ?;
            ]])
            update_stmt:reset():bind(timestamp, next_hit_count, kind, key):step()
            last_accessed_at = timestamp
            hit_count = next_hit_count
        end

        return clone(value), {
            key = key,
            stored_at = stored_at,
            expires_at = expires_at,
            last_accessed_at = last_accessed_at,
            hit_count = hit_count,
            owner = decode(self.codec, row[6]),
            tags = decode(self.codec, row[7]),
        }
    end)
end

function Cache:set(kind, key, value, options)
    options = options or {}
    if not Cache.isEnabled(options) or value == nil then
        return false
    end

    local ttl = ttlForKind(kind, options)
    local timestamp = now()
    local record = {
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

    local ok = self:withDB(function(db)
        local inserted = self:insertRecord(db, kind, key, record)
        if inserted and options.prune ~= false then
            Cache.pruneIfDueDB(db, options)
        end
        return inserted
    end)
    return ok == true
end

function Cache:invalidate(kind, key)
    kind = bucketName(kind)
    self:withDB(function(db)
        if key then
            local stmt = db:prepare([[
                DELETE FROM cache_records WHERE kind = ? AND key = ?;
            ]])
            stmt:reset():bind(kind, key):step()
        else
            local stmt = db:prepare([[
                DELETE FROM cache_records WHERE kind = ?;
            ]])
            stmt:reset():bind(kind):step()
        end
    end)
end

function Cache:invalidateByOwner(owner, kinds)
    if type(owner) ~= "table" then
        return 0
    end

    return self:withDB(function(db)
        local filters = {}
        local kind_list = quotedKindList(kinds)
        if kind_list then
            table.insert(filters, "kind IN (" .. kind_list .. ")")
        end
        if owner.source ~= nil then
            table.insert(filters, "owner_source = '"
                .. tostring(owner.source):gsub("'", "''") .. "'")
        end
        if owner.book ~= nil then
            table.insert(filters, "owner_book = '"
                .. tostring(owner.book):gsub("'", "''") .. "'")
        end

        local sql = "SELECT kind, key, owner_blob FROM cache_records"
        if #filters > 0 then
            sql = sql .. " WHERE " .. table.concat(filters, " AND ")
        end
        sql = sql .. ";"

        local select_stmt = db:prepare(sql)
        local delete_stmt = db:prepare([[
            DELETE FROM cache_records WHERE kind = ? AND key = ?;
        ]])
        local removed = 0
        local row = select_stmt:reset():step()
        while row do
            local kind = row[1]
            local key = row[2]
            local record_owner = decode(self.codec, row[3])
            if kindMatches(kind, kinds) and ownerMatches(record_owner, owner) then
                delete_stmt:reset():bind(kind, key):step()
                removed = removed + 1
            end
            row = select_stmt:step()
        end
        return removed
    end) or 0
end

function Cache.pruneExpiredDB(db)
    local timestamp = now()
    local count = tonumber(db:rowexec(string.format([[
        SELECT COUNT(*) FROM cache_records
        WHERE schema_version != %d
           OR value_blob IS NULL
           OR (expires_at IS NOT NULL AND expires_at < %d);
    ]], Cache.schema_version, timestamp))) or 0
    if count > 0 then
        db:exec(string.format([[
            DELETE FROM cache_records
            WHERE schema_version != %d
               OR value_blob IS NULL
               OR (expires_at IS NOT NULL AND expires_at < %d);
        ]], Cache.schema_version, timestamp))
    end
    return count
end

function Cache:pruneExpired()
    return self:withDB(function(db)
        return Cache.pruneExpiredDB(db)
    end) or 0
end

function Cache.pruneLRUDB(db, max_records, max_bytes)
    max_records = tonumber(max_records)
    max_bytes = tonumber(max_bytes)
    if not max_records and not max_bytes then
        return 0
    end

    local removed = 0
    local delete_stmt = db:prepare([[
        DELETE FROM cache_records WHERE kind = ? AND key = ?;
    ]])

    local function removeOldest()
        local select_stmt = db:prepare([[
            SELECT kind, key, blob_size FROM cache_records
            ORDER BY last_accessed_at ASC, stored_at ASC
            LIMIT 1;
        ]])
        local row = select_stmt:reset():step()
        if not row then
            return 0
        end
        delete_stmt:reset():bind(row[1], row[2]):step()
        removed = removed + 1
        return tonumber(row[3]) or 0
    end

    local record_count = tonumber(db:rowexec(
        "SELECT COUNT(*) FROM cache_records;")) or 0
    while max_records and max_records > 0 and record_count > max_records do
        if removeOldest() == 0 and record_count <= 1 then
            break
        end
        record_count = record_count - 1
    end

    local total_bytes = tonumber(db:rowexec(
        "SELECT COALESCE(SUM(blob_size), 0) FROM cache_records;")) or 0
    while max_bytes and max_bytes > 0 and total_bytes > max_bytes do
        local removed_bytes = removeOldest()
        if removed_bytes <= 0 then
            break
        end
        total_bytes = total_bytes - removed_bytes
    end

    return removed
end

function Cache:pruneLRU(max_records, max_bytes)
    return self:withDB(function(db)
        return Cache.pruneLRUDB(db, max_records, max_bytes)
    end) or 0
end

function Cache:stats()
    return self:withDB(function(db)
        return {
            record_count = tonumber(db:rowexec([[
                SELECT COUNT(*) FROM cache_records;
            ]])) or 0,
            blob_bytes = tonumber(db:rowexec([[
                SELECT COALESCE(SUM(blob_size), 0) FROM cache_records;
            ]])) or 0,
            file_bytes = fileSize(Cache.db_path)
                + fileSize(Cache.db_path .. "-wal")
                + fileSize(Cache.db_path .. "-shm"),
        }
    end) or {
        record_count = 0,
        blob_bytes = 0,
        file_bytes = 0,
    }
end

function Cache:clear()
    local summary, err = self:withDB(function(db)
        local record_count = tonumber(db:rowexec([[
            SELECT COUNT(*) FROM cache_records;
        ]])) or 0
        local blob_bytes = tonumber(db:rowexec([[
            SELECT COALESCE(SUM(blob_size), 0) FROM cache_records;
        ]])) or 0
        db:exec("DELETE FROM cache_records;")
        setMeta(db, "last_pruned_at", tostring(now()))
        return {
            records_removed = record_count,
            bytes_removed = blob_bytes,
        }
    end)
    return summary, err
end

function Cache.pruneIfDueDB(db, options)
    options = options or {}
    local timestamp = now()
    local interval = tonumber(options.prune_interval) or Cache.prune_interval
    local last_pruned = tonumber(getMeta(db, "last_pruned_at")) or 0
    if options.prune ~= true
        and interval > 0
        and timestamp - last_pruned < interval then
        return 0
    end

    local removed = Cache.pruneExpiredDB(db)
    removed = removed + Cache.pruneLRUDB(db, maxRecordsForOptions(options),
        maxBytesForOptions(options))
    setMeta(db, "last_pruned_at", tostring(timestamp))
    return removed
end

function Cache.deleteStorage()
    os.remove(Cache.db_path)
    os.remove(Cache.db_path .. "-wal")
    os.remove(Cache.db_path .. "-shm")
    os.remove(Cache.legacy_path)
    os.remove(Cache.legacy_path .. ".old")
end

return Cache
