local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")

local FileLock = {
    retry_interval = 0.05,
    timeout = 10,
    stale_after = 60,
}

local serial = 0

local function tokenPath(path)
    return path .. "/owner"
end

local function readToken(path)
    local file = io.open(tokenPath(path), "rb")
    if not file then
        return nil
    end
    local token = file:read("*all")
    file:close()
    return token
end

local function writeToken(path, token)
    local file = io.open(tokenPath(path), "wb")
    if not file then
        return false
    end
    file:write(token)
    file:close()
    return true
end

local function removeLock(path, token)
    if token and readToken(path) ~= token then
        return false
    end
    os.remove(tokenPath(path))
    return lfs.rmdir(path)
end

function FileLock.with(path, callback, options)
    options = options or {}
    local timeout = tonumber(options.timeout) or FileLock.timeout
    local stale_after = tonumber(options.stale_after) or FileLock.stale_after
    local started_at = socket.gettime()

    while not lfs.mkdir(path) do
        local modified = lfs.attributes(path, "modification")
        if modified and os.time() - modified > stale_after then
            removeLock(path)
        elseif socket.gettime() - started_at >= timeout then
            return nil, "timed out waiting for storage lock"
        else
            socket.sleep(FileLock.retry_interval)
        end
    end

    serial = serial + 1
    local token = table.concat({ tostring(os.time()), tostring(socket.gettime()), tostring(serial) }, ":")
    if not writeToken(path, token) then
        removeLock(path)
        return nil, "cannot initialize storage lock"
    end

    local results = { pcall(callback) }
    removeLock(path, token)
    if not results[1] then
        return nil, results[2]
    end
    table.remove(results, 1)
    return unpack(results)
end

return FileLock
