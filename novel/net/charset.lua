local ffi = require("ffi")

local Charset = {}

local cdef_ok = pcall(ffi.cdef, [[
typedef void* iconv_t;
iconv_t iconv_open(const char *tocode, const char *fromcode);
size_t iconv(iconv_t cd, char **inbuf, size_t *inbytesleft, char **outbuf, size_t *outbytesleft);
int iconv_close(iconv_t cd);
]])

local iconv_lib
local iconv_checked = false
local invalid_size = cdef_ok and ffi.cast("size_t", -1) or nil

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
        return "gb18030"
    end
    return charset
end

local function isUTF8(charset)
    charset = normalize(charset)
    return charset == nil or charset == "utf-8" or charset == "us-ascii" or charset == "ascii"
end

local function iconv()
    if iconv_checked then
        return iconv_lib
    end
    iconv_checked = true
    if not cdef_ok then
        return nil
    end

    local ok, lib = pcall(ffi.load, "iconv")
    if ok and lib then
        iconv_lib = lib
        return iconv_lib
    end

    ok, lib = pcall(function()
        return ffi.C
    end)
    if ok and lib then
        iconv_lib = lib
    end
    return iconv_lib
end

local function openConverter(lib, to_charset, from_charset)
    local ok, cd = pcall(lib.iconv_open, to_charset, from_charset)
    if ok and cd ~= nil and cd ~= ffi.cast("iconv_t", -1) then
        return cd
    end
end

local function convert(value, to_charset, from_charset)
    if type(value) ~= "string" or value == "" then
        return value
    end

    to_charset = normalize(to_charset)
    from_charset = normalize(from_charset)
    if not to_charset or not from_charset or to_charset == from_charset then
        return value
    end

    local lib = iconv()
    if not lib then
        return value, "iconv is unavailable"
    end

    local cd = openConverter(lib, to_charset, from_charset)
    if not cd then
        return value, "unsupported charset: " .. tostring(from_charset)
    end

    local input = ffi.new("char[?]", #value, value)
    local input_ptr = ffi.new("char *[1]", input)
    local input_left = ffi.new("size_t[1]", #value)
    local output_size = math.max(#value * 4 + 16, 64)
    local output = ffi.new("char[?]", output_size)
    local output_ptr = ffi.new("char *[1]", output)
    local output_left = ffi.new("size_t[1]", output_size)

    local ret = lib.iconv(cd, input_ptr, input_left, output_ptr, output_left)
    lib.iconv_close(cd)

    if ret == invalid_size then
        return value, "failed to convert charset: " .. tostring(from_charset)
    end
    return ffi.string(output, output_size - tonumber(output_left[0]))
end

function Charset.toUTF8(value, charset)
    if isUTF8(charset) then
        return value
    end
    return convert(value, "utf-8", charset)
end

function Charset.fromUTF8(value, charset)
    if isUTF8(charset) then
        return value
    end
    return convert(value, charset, "utf-8")
end

return Charset
