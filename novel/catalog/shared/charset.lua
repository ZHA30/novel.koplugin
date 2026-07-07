local Charset = {}
local GB18030
local GBK

local function gbk()
    if not GBK then
        GBK = require("novel.catalog.shared.gbk")
    end
    return GBK
end

local function gb18030()
    if not GB18030 then
        GB18030 = require("novel.catalog.shared.gb18030")
    end
    return GB18030
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalize(charset)
    charset = trim(charset):lower():gsub("_", "-")
    if charset == "" then
        return nil
    end
    if charset == "utf8" then
        return "utf-8"
    end
    if charset == "gb2312" or charset == "gbk" or charset == "cp936" then
        return "gbk"
    end
    if charset == "gb18030" then
        return "gb18030"
    end
    return charset
end

local function isUTF8(charset)
    charset = normalize(charset)
    return charset == nil or charset == "utf-8" or charset == "us-ascii" or charset == "ascii"
end

local function unsupported(charset)
    return "unsupported charset: " .. tostring(charset or "")
end

function Charset.toUTF8(value, charset)
    if type(value) ~= "string" or value == "" or isUTF8(charset) then
        return value
    end

    local normalized = normalize(charset)
    if normalized == "gbk" then
        return gbk().toUTF8(value)
    end
    if normalized == "gb18030" then
        return gb18030().toUTF8(value)
    end
    return value, unsupported(charset)
end

function Charset.fromUTF8(value, charset)
    if type(value) ~= "string" or value == "" or isUTF8(charset) then
        return value
    end

    local normalized = normalize(charset)
    if normalized == "gbk" then
        return gbk().fromUTF8(value)
    end
    if normalized == "gb18030" then
        return gb18030().fromUTF8(value)
    end
    return value, unsupported(charset)
end

return Charset
