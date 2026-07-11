local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local FileLock = require("novel.storage.filelock")

local CookieStore = {
    path = DataStorage:getSettingsDir() .. "/novel_cookies.lua",
}
CookieStore.__index = CookieStore

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function origin(url)
    return tostring(url or ""):match("^(https?://[^/]+)") or tostring(url or "")
end

local function hostAndPath(url)
    local value = tostring(url or "")
    local scheme, authority, path = value:match("^(https?)://([^/?#]+)(/[^?#]*)")
    if not authority then
        scheme, authority = value:match("^(https?)://([^/?#]+)")
    end
    authority = authority and authority:gsub("^.*@", "") or ""
    local host
    if authority:sub(1, 1) == "[" then
        host = authority:match("^%[([^%]]+)%]")
    else
        host = authority:gsub(":%d+$", "")
    end
    return host and host:lower() or "", path or "/", scheme
end

local function cookieKey(key_or_url)
    local key = trim(key_or_url)
    if key == "" then
        return ""
    end
    return origin(key)
end

local function defaultPath(url)
    local _, path = hostAndPath(url)
    if path == "" or path == "/" then
        return "/"
    end
    local parent = path:match("^(.*)/[^/]*$")
    if not parent or parent == "" then
        return "/"
    end
    return parent
end

local function normalizeDomain(domain)
    domain = trim(domain):lower()
    domain = domain:gsub("^%.+", "")
    return domain
end

local function domainMatches(host, domain)
    host = normalizeDomain(host)
    domain = normalizeDomain(domain)
    return domain ~= "" and (host == domain
        or (#host > #domain and host:sub(-#domain - 1) == "." .. domain))
end

local function pathMatches(path, cookie_path)
    cookie_path = cookie_path and cookie_path ~= "" and cookie_path or "/"
    if cookie_path == "/" or path == cookie_path then
        return true
    end
    if path:sub(1, #cookie_path) ~= cookie_path then
        return false
    end
    return cookie_path:sub(-1) == "/"
        or path:sub(#cookie_path + 1, #cookie_path + 1) == "/"
end

local function parseHttpDate(value)
    value = trim(value)
    if value == "" then
        return nil
    end
    local day, mon, year, hour, min, sec =
        value:match("^%a+,%s*(%d%d?)%s+(%a+)%s+(%d%d%d%d)%s+(%d%d):(%d%d):(%d%d)")
    if not day then
        day, mon, year, hour, min, sec = value:match(
            "^%a+,%s*(%d%d?)%-(%a+)%-(%d%d%d?%d?)%s+(%d%d):(%d%d):(%d%d)")
    end
    if not day then
        mon, day, hour, min, sec, year = value:match(
            "^%a+%s+(%a+)%s+(%d%d?)%s+(%d%d):(%d%d):(%d%d)%s+(%d%d%d%d)")
    end
    local month_map = {
        jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
        jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
    }
    local month = mon and month_map[mon:lower():sub(1, 3)]
    if not month then
        return nil
    end
    year = tonumber(year)
    if year and year < 100 then
        year = year < 70 and year + 2000 or year + 1900
    end
    local parsed = os.time({
        year = year,
        month = month,
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
        isdst = false,
    })
    if not parsed then
        return nil
    end
    local now = os.time()
    local local_utc_offset = os.difftime(
        os.time(os.date("!*t", now)), os.time(os.date("*t", now)))
    return parsed - local_utc_offset
end

local function splitCookieParts(header)
    local parts = {}
    for raw_part in (tostring(header or "") .. ";"):gmatch("(.-);") do
        local part = trim(raw_part)
        if part ~= "" then
            table.insert(parts, part)
        end
    end
    return parts
end

local function recordKey(record)
    return table.concat({
        normalizeDomain(record.domain),
        record.path or "/",
        record.name or "",
    }, "\n")
end

local function isExpired(record, now)
    return record.expires ~= nil and tonumber(record.expires) ~= nil
        and tonumber(record.expires) <= (now or os.time())
end

local function recordsToCookie(records, request_url)
    local host, path = hostAndPath(request_url)
    local https = tostring(request_url or ""):match("^https://") ~= nil
    local matched = {}
    local now = os.time()
    for _, record in ipairs(records or {}) do
        local record_domain = normalizeDomain(record.domain or host)
        local domain_ok
        if record.host_only == false then
            domain_ok = domainMatches(host, record_domain)
        else
            domain_ok = host == record_domain
        end
        if not isExpired(record, now)
            and record.name and record.name ~= ""
            and record.value ~= nil
            and (not record.secure or https)
            and (host == "" or domain_ok)
            and pathMatches(path, record.path) then
            table.insert(matched, record)
        end
    end
    table.sort(matched, function(left, right)
        local left_path = left.path or "/"
        local right_path = right.path or "/"
        if #left_path ~= #right_path then
            return #left_path > #right_path
        end
        return recordKey(left) < recordKey(right)
    end)
    local values = {}
    for _, record in ipairs(matched) do
        table.insert(values, tostring(record.name) .. "=" .. tostring(record.value))
    end
    return table.concat(values, "; ")
end

function CookieStore:new()
    return setmetatable({
        settings = LuaSettings:open(CookieStore.path),
    }, self)
end

local function withLatestStore(callback)
    return FileLock.with(CookieStore.path .. ".lock", function()
        return callback(CookieStore:new())
    end)
end

function CookieStore.cookieToMap(cookie)
    local map = {}
    cookie = tostring(cookie or "")
    if cookie == "" then
        return map
    end

    for pair in (cookie .. ";"):gmatch("(.-);") do
        local key, value = pair:match("^%s*([^=;%s]+)%s*=%s*(.-)%s*$")
        if key and key ~= "" then
            map[key] = value or ""
        end
    end
    return map
end

function CookieStore.mapToCookie(map)
    if type(map) ~= "table" then
        return nil
    end
    local parts = {}
    for key, value in pairs(map) do
        if value ~= nil then
            table.insert(parts, tostring(key) .. "=" .. tostring(value))
        end
    end
    table.sort(parts)
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "; ")
end

local function responseCookieValue(header)
    header = tostring(header or "")
    local value = header:match("^%s*([^;]+)")
    if value and value:find("=", 1, true) then
        return value
    end
end

local function legacyCookieRecords(cookie, request_url)
    local host = hostAndPath(request_url)
    local records = {}
    for name, value in pairs(CookieStore.cookieToMap(cookie)) do
        table.insert(records, {
            name = name,
            value = value,
            domain = host,
            path = "/",
            host_only = true,
        })
    end
    return records
end

function CookieStore:readRecords(key_or_url, request_url)
    local key = cookieKey(key_or_url)
    if key == "" then
        return {}
    end
    local jar = self.settings:readSetting("cookie_jar") or {}
    if type(jar[key]) == "table" then
        return jar[key]
    end
    local cookies = self.settings:readSetting("cookies") or {}
    if cookies[key] and cookies[key] ~= "" then
        return legacyCookieRecords(cookies[key], request_url or key)
    end
    return {}
end

function CookieStore:writeRecords(key_or_url, records)
    local key = cookieKey(key_or_url)
    if key == "" then
        return false
    end
    local jar = self.settings:readSetting("cookie_jar") or {}
    jar[key] = records
    self.settings:saveSetting("cookie_jar", jar)
    self.settings:flush()
    return true
end

function CookieStore:get(key_or_url, request_url)
    local records = self:readRecords(key_or_url, request_url or key_or_url)
    return recordsToCookie(records, request_url or key_or_url)
end

function CookieStore:set(key_or_url, cookie)
    if not self then
        return false
    end
    return withLatestStore(function(store)
        return store:setUnlocked(key_or_url, cookie)
    end)
end

function CookieStore:setUnlocked(key_or_url, cookie)
    local key = cookieKey(key_or_url)
    if key == "" then
        return false
    end
    local records = legacyCookieRecords(cookie, key)
    self:writeRecords(key, records)
    local cookies = self.settings:readSetting("cookies") or {}
    if cookie == nil or cookie == "" then
        cookies[key] = nil
    else
        cookies[key] = cookie
    end
    self.settings:saveSetting("cookies", cookies)
    self.settings:flush()
    return true
end

function CookieStore:merge(key_or_url, cookie)
    if not self then
        return false
    end
    return withLatestStore(function(store)
        local next_map = CookieStore.cookieToMap(store:get(key_or_url))
        for key, value in pairs(CookieStore.cookieToMap(cookie)) do
            next_map[key] = value
        end
        return store:setUnlocked(key_or_url, CookieStore.mapToCookie(next_map))
    end)
end

local function parseSetCookie(header, request_url)
    local parts = splitCookieParts(header)
    local first = parts[1]
    if not first then
        return nil
    end
    local name, value = first:match("^%s*([^=;%s]+)%s*=%s*(.-)%s*$")
    if not name or name == "" then
        return nil
    end

    local host, _, scheme = hostAndPath(request_url)
    local record = {
        name = name,
        value = value or "",
        domain = host,
        path = defaultPath(request_url),
        host_only = true,
        expires = nil,
        secure = false,
        http_only = false,
    }
    local delete = false
    local domain_attr
    local expires_attr
    local max_age
    for index = 2, #parts do
        local attr, attr_value = parts[index]:match("^%s*([^=;%s]+)%s*=%s*(.-)%s*$")
        attr = attr and attr:lower()
        if attr == "domain" then
            domain_attr = normalizeDomain(attr_value)
        elseif attr == "path" then
            if attr_value:sub(1, 1) == "/" then
                record.path = attr_value
            end
        elseif attr == "max-age" then
            max_age = tonumber(attr_value)
        elseif attr == "expires" then
            expires_attr = attr_value
        elseif parts[index]:lower() == "secure" then
            record.secure = true
        elseif parts[index]:lower() == "httponly" then
            record.http_only = true
        end
    end
    if domain_attr then
        if not domainMatches(host, domain_attr) then
            return nil
        end
        record.domain = domain_attr
        record.host_only = false
    end
    if record.secure and scheme ~= "https" then
        return nil
    end
    if max_age ~= nil then
        if max_age <= 0 then
            delete = true
        else
            record.expires = os.time() + max_age
        end
    elseif expires_attr then
        record.expires = parseHttpDate(expires_attr)
        delete = record.expires ~= nil and record.expires <= os.time()
    end
    return record, delete
end

local function splitSetCookieHeader(header)
    local values = {}
    local value = tostring(header or "")
    local start_index = 1
    local quote
    local escaped = false
    for index = 1, #value do
        local char = value:sub(index, index)
        if escaped then
            escaped = false
        elseif char == "\\" and quote then
            escaped = true
        elseif quote then
            if char == quote then
                quote = nil
            end
        elseif char == "'" or char == '"' then
            quote = char
        elseif char == "," then
            local rest = value:sub(index + 1)
            if rest:match("^%s*[^%s=;,]+%s*=") then
                table.insert(values, trim(value:sub(start_index, index - 1)))
                start_index = index + 1
            end
        end
    end
    local last = trim(value:sub(start_index))
    if last ~= "" then
        table.insert(values, last)
    end
    return values
end

local function setCookieHeaders(headers)
    local values = {}
    if type(headers) ~= "table" then
        return values
    end
    for key, value in pairs(headers) do
        if tostring(key):lower() == "set-cookie" then
            if type(value) == "table" then
                for index = 1, #value do
                    local split = splitSetCookieHeader(value[index])
                    for split_index = 1, #split do
                        table.insert(values, split[split_index])
                    end
                end
            else
                local split = splitSetCookieHeader(value)
                for index = 1, #split do
                    table.insert(values, split[index])
                end
            end
        end
    end
    return values
end

function CookieStore.cookiesFromSetCookie(headers)
    local map = {}
    for _, header in ipairs(setCookieHeaders(headers)) do
        local cookie = responseCookieValue(header)
        for name, item in pairs(CookieStore.cookieToMap(cookie)) do
            map[name] = item
        end
    end
    return map
end

function CookieStore:mergeResponse(key_or_url, request_url, headers)
    if not self then
        return false
    end
    if headers == nil then
        headers = request_url
        request_url = key_or_url
    end
    local set_cookies = setCookieHeaders(headers)
    if #set_cookies == 0 then
        return false
    end

    return withLatestStore(function(store)
        local records = store:readRecords(key_or_url, request_url)
        local by_key = {}
        for _, record in ipairs(records) do
            if not isExpired(record) then
                by_key[recordKey(record)] = record
            end
        end
        for index = 1, #set_cookies do
            local record, delete = parseSetCookie(set_cookies[index], request_url)
            if record then
                local key = recordKey(record)
                if delete then
                    by_key[key] = nil
                else
                    by_key[key] = record
                end
            end
        end

        local merged = {}
        for _, record in pairs(by_key) do
            table.insert(merged, record)
        end
        table.sort(merged, function(left, right)
            return recordKey(left) < recordKey(right)
        end)
        return store:writeRecords(key_or_url, merged)
    end)
end

function CookieStore.deleteStorage()
    os.remove(CookieStore.path)
    os.remove(CookieStore.path .. ".old")
end

return CookieStore
