local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

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

local function cookieKey(key_or_url)
    local key = trim(key_or_url)
    if key == "" then
        return ""
    end
    return origin(key)
end

function CookieStore:new()
    return setmetatable({
        settings = LuaSettings:open(CookieStore.path),
    }, self)
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
        if value ~= nil and tostring(value) ~= "" then
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

function CookieStore.cookiesFromSetCookie(headers)
    local map = {}
    if type(headers) ~= "table" then
        return map
    end
    for key, value in pairs(headers) do
        if tostring(key):lower() == "set-cookie" then
            if type(value) == "table" then
                for index = 1, #value do
                    local cookie = responseCookieValue(value[index])
                    for name, item in pairs(CookieStore.cookieToMap(cookie)) do
                        map[name] = item
                    end
                end
            else
                local cookie = responseCookieValue(value)
                for name, item in pairs(CookieStore.cookieToMap(cookie)) do
                    map[name] = item
                end
            end
        end
    end
    return map
end

function CookieStore:get(key_or_url)
    local key = cookieKey(key_or_url)
    if key == "" then
        return ""
    end
    local cookies = self.settings:readSetting("cookies") or {}
    return cookies[key] or ""
end

function CookieStore:set(key_or_url, cookie)
    local key = cookieKey(key_or_url)
    if key == "" then
        return false
    end
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
    local next_map = CookieStore.cookieToMap(self:get(key_or_url))
    for key, value in pairs(CookieStore.cookieToMap(cookie)) do
        next_map[key] = value
    end
    return self:set(key_or_url, CookieStore.mapToCookie(next_map))
end

function CookieStore:mergeResponse(key_or_url, headers)
    local response_map = CookieStore.cookiesFromSetCookie(headers)
    if next(response_map) == nil then
        return false
    end
    local current = CookieStore.cookieToMap(self:get(key_or_url))
    for key, value in pairs(response_map) do
        current[key] = value
    end
    return self:set(key_or_url, CookieStore.mapToCookie(current))
end

function CookieStore.deleteStorage()
    os.remove(CookieStore.path)
    os.remove(CookieStore.path .. ".old")
end

return CookieStore
