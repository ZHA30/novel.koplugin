-- Generated from Python gb18030 codec range behavior.
-- Two-byte mappings are delegated to novel.net.gbk; four-byte mappings use compressed ranges.

local GBK = require("novel.net.gbk")

local GB18030 = {}

local ranges = {
    { 0, 35, 0x80, 0xA3 },
    { 36, 37, 0xA5, 0xA6 },
    { 38, 44, 0xA9, 0xAF },
    { 45, 49, 0xB2, 0xB6 },
    { 50, 80, 0xB8, 0xD6 },
    { 81, 88, 0xD8, 0xDF },
    { 89, 94, 0xE2, 0xE7 },
    { 95, 95, 0xEB, 0xEB },
    { 96, 99, 0xEE, 0xF1 },
    { 100, 102, 0xF4, 0xF6 },
    { 103, 103, 0xF8, 0xF8 },
    { 104, 104, 0xFB, 0xFB },
    { 105, 108, 0xFD, 0x100 },
    { 109, 125, 0x102, 0x112 },
    { 126, 132, 0x114, 0x11A },
    { 133, 147, 0x11C, 0x12A },
    { 148, 171, 0x12C, 0x143 },
    { 172, 174, 0x145, 0x147 },
    { 175, 178, 0x149, 0x14C },
    { 179, 207, 0x14E, 0x16A },
    { 208, 305, 0x16C, 0x1CD },
    { 306, 306, 0x1CF, 0x1CF },
    { 307, 307, 0x1D1, 0x1D1 },
    { 308, 308, 0x1D3, 0x1D3 },
    { 309, 309, 0x1D5, 0x1D5 },
    { 310, 310, 0x1D7, 0x1D7 },
    { 311, 311, 0x1D9, 0x1D9 },
    { 312, 312, 0x1DB, 0x1DB },
    { 313, 340, 0x1DD, 0x1F8 },
    { 341, 427, 0x1FA, 0x250 },
    { 428, 442, 0x252, 0x260 },
    { 443, 543, 0x262, 0x2C6 },
    { 544, 544, 0x2C8, 0x2C8 },
    { 545, 557, 0x2CC, 0x2D8 },
    { 558, 740, 0x2DA, 0x390 },
    { 741, 741, 0x3A2, 0x3A2 },
    { 742, 748, 0x3AA, 0x3B0 },
    { 749, 749, 0x3C2, 0x3C2 },
    { 750, 804, 0x3CA, 0x400 },
    { 805, 818, 0x402, 0x40F },
    { 819, 819, 0x450, 0x450 },
    { 820, 7921, 0x452, 0x200F },
    { 7922, 7923, 0x2011, 0x2012 },
    { 7924, 7924, 0x2017, 0x2017 },
    { 7925, 7926, 0x201A, 0x201B },
    { 7927, 7933, 0x201E, 0x2024 },
    { 7934, 7942, 0x2027, 0x202F },
    { 7943, 7943, 0x2031, 0x2031 },
    { 7944, 7944, 0x2034, 0x2034 },
    { 7945, 7949, 0x2036, 0x203A },
    { 7950, 8061, 0x203C, 0x20AB },
    { 8062, 8147, 0x20AD, 0x2102 },
    { 8148, 8148, 0x2104, 0x2104 },
    { 8149, 8151, 0x2106, 0x2108 },
    { 8152, 8163, 0x210A, 0x2115 },
    { 8164, 8173, 0x2117, 0x2120 },
    { 8174, 8235, 0x2122, 0x215F },
    { 8236, 8239, 0x216C, 0x216F },
    { 8240, 8261, 0x217A, 0x218F },
    { 8262, 8263, 0x2194, 0x2195 },
    { 8264, 8373, 0x219A, 0x2207 },
    { 8374, 8379, 0x2209, 0x220E },
    { 8380, 8380, 0x2210, 0x2210 },
    { 8381, 8383, 0x2212, 0x2214 },
    { 8384, 8387, 0x2216, 0x2219 },
    { 8388, 8389, 0x221B, 0x221C },
    { 8390, 8391, 0x2221, 0x2222 },
    { 8392, 8392, 0x2224, 0x2224 },
    { 8393, 8393, 0x2226, 0x2226 },
    { 8394, 8395, 0x222C, 0x222D },
    { 8396, 8400, 0x222F, 0x2233 },
    { 8401, 8405, 0x2238, 0x223C },
    { 8406, 8415, 0x223E, 0x2247 },
    { 8416, 8418, 0x2249, 0x224B },
    { 8419, 8423, 0x224D, 0x2251 },
    { 8424, 8436, 0x2253, 0x225F },
    { 8437, 8438, 0x2262, 0x2263 },
    { 8439, 8444, 0x2268, 0x226D },
    { 8445, 8481, 0x2270, 0x2294 },
    { 8482, 8484, 0x2296, 0x2298 },
    { 8485, 8495, 0x229A, 0x22A4 },
    { 8496, 8520, 0x22A6, 0x22BE },
    { 8521, 8602, 0x22C0, 0x2311 },
    { 8603, 8935, 0x2313, 0x245F },
    { 8936, 8945, 0x246A, 0x2473 },
    { 8946, 9045, 0x249C, 0x24FF },
    { 9046, 9049, 0x254C, 0x254F },
    { 9050, 9062, 0x2574, 0x2580 },
    { 9063, 9065, 0x2590, 0x2592 },
    { 9066, 9075, 0x2596, 0x259F },
    { 9076, 9091, 0x25A2, 0x25B1 },
    { 9092, 9099, 0x25B4, 0x25BB },
    { 9100, 9107, 0x25BE, 0x25C5 },
    { 9108, 9110, 0x25C8, 0x25CA },
    { 9111, 9112, 0x25CC, 0x25CD },
    { 9113, 9130, 0x25D0, 0x25E1 },
    { 9131, 9161, 0x25E6, 0x2604 },
    { 9162, 9163, 0x2607, 0x2608 },
    { 9164, 9217, 0x260A, 0x263F },
    { 9218, 9218, 0x2641, 0x2641 },
    { 9219, 11328, 0x2643, 0x2E80 },
    { 11329, 11330, 0x2E82, 0x2E83 },
    { 11331, 11333, 0x2E85, 0x2E87 },
    { 11334, 11335, 0x2E89, 0x2E8A },
    { 11336, 11345, 0x2E8D, 0x2E96 },
    { 11346, 11360, 0x2E98, 0x2EA6 },
    { 11361, 11362, 0x2EA8, 0x2EA9 },
    { 11363, 11365, 0x2EAB, 0x2EAD },
    { 11366, 11369, 0x2EAF, 0x2EB2 },
    { 11370, 11371, 0x2EB4, 0x2EB5 },
    { 11372, 11374, 0x2EB8, 0x2EBA },
    { 11375, 11388, 0x2EBC, 0x2EC9 },
    { 11389, 11681, 0x2ECB, 0x2FEF },
    { 11682, 11685, 0x2FFC, 0x2FFF },
    { 11686, 11686, 0x3004, 0x3004 },
    { 11687, 11691, 0x3018, 0x301C },
    { 11692, 11693, 0x301F, 0x3020 },
    { 11694, 11713, 0x302A, 0x303D },
    { 11714, 11715, 0x303F, 0x3040 },
    { 11716, 11722, 0x3094, 0x309A },
    { 11723, 11724, 0x309F, 0x30A0 },
    { 11725, 11729, 0x30F7, 0x30FB },
    { 11730, 11735, 0x30FF, 0x3104 },
    { 11736, 11981, 0x312A, 0x321F },
    { 11982, 11988, 0x322A, 0x3230 },
    { 11989, 12101, 0x3232, 0x32A2 },
    { 12102, 12335, 0x32A4, 0x338D },
    { 12336, 12347, 0x3390, 0x339B },
    { 12348, 12349, 0x339F, 0x33A0 },
    { 12350, 12383, 0x33A2, 0x33C3 },
    { 12384, 12392, 0x33C5, 0x33CD },
    { 12393, 12394, 0x33CF, 0x33D0 },
    { 12395, 12396, 0x33D3, 0x33D4 },
    { 12397, 12509, 0x33D6, 0x3446 },
    { 12510, 12552, 0x3448, 0x3472 },
    { 12553, 12850, 0x3474, 0x359D },
    { 12851, 12961, 0x359F, 0x360D },
    { 12962, 12972, 0x360F, 0x3619 },
    { 12973, 13737, 0x361B, 0x3917 },
    { 13738, 13822, 0x3919, 0x396D },
    { 13823, 13918, 0x396F, 0x39CE },
    { 13919, 13932, 0x39D1, 0x39DE },
    { 13933, 14079, 0x39E0, 0x3A72 },
    { 14080, 14297, 0x3A74, 0x3B4D },
    { 14298, 14584, 0x3B4F, 0x3C6D },
    { 14585, 14697, 0x3C6F, 0x3CDF },
    { 14698, 15582, 0x3CE1, 0x4055 },
    { 15583, 15846, 0x4057, 0x415E },
    { 15847, 16317, 0x4160, 0x4336 },
    { 16318, 16433, 0x4338, 0x43AB },
    { 16434, 16437, 0x43AD, 0x43B0 },
    { 16438, 16480, 0x43B2, 0x43DC },
    { 16481, 16728, 0x43DE, 0x44D5 },
    { 16729, 17101, 0x44D7, 0x464B },
    { 17102, 17121, 0x464D, 0x4660 },
    { 17122, 17314, 0x4662, 0x4722 },
    { 17315, 17319, 0x4724, 0x4728 },
    { 17320, 17401, 0x472A, 0x477B },
    { 17402, 17417, 0x477D, 0x478C },
    { 17418, 17858, 0x478E, 0x4946 },
    { 17859, 17908, 0x4948, 0x4979 },
    { 17909, 17910, 0x497B, 0x497C },
    { 17911, 17914, 0x497E, 0x4981 },
    { 17915, 17915, 0x4984, 0x4984 },
    { 17916, 17935, 0x4987, 0x499A },
    { 17936, 17938, 0x499C, 0x499E },
    { 17939, 17960, 0x49A0, 0x49B5 },
    { 17961, 18663, 0x49B8, 0x4C76 },
    { 18664, 18702, 0x4C78, 0x4C9E },
    { 18703, 18813, 0x4CA4, 0x4D12 },
    { 18814, 18961, 0x4D1A, 0x4DAD },
    { 18962, 19042, 0x4DAF, 0x4DFF },
    { 19043, 33468, 0x9FA6, 0xD7FF },
    { 33469, 33469, 0xE76C, 0xE76C },
    { 33470, 33470, 0xE7C8, 0xE7C8 },
    { 33471, 33483, 0xE7E7, 0xE7F3 },
    { 33484, 33484, 0xE815, 0xE815 },
    { 33485, 33489, 0xE819, 0xE81D },
    { 33490, 33496, 0xE81F, 0xE825 },
    { 33497, 33500, 0xE827, 0xE82A },
    { 33501, 33504, 0xE82D, 0xE830 },
    { 33505, 33512, 0xE833, 0xE83A },
    { 33513, 33519, 0xE83C, 0xE842 },
    { 33520, 33535, 0xE844, 0xE853 },
    { 33536, 33549, 0xE856, 0xE863 },
    { 33550, 37844, 0xE865, 0xF92B },
    { 37845, 37920, 0xF92D, 0xF978 },
    { 37921, 37947, 0xF97A, 0xF994 },
    { 37948, 38028, 0xF996, 0xF9E6 },
    { 38029, 38037, 0xF9E8, 0xF9F0 },
    { 38038, 38063, 0xF9F2, 0xFA0B },
    { 38064, 38064, 0xFA10, 0xFA10 },
    { 38065, 38065, 0xFA12, 0xFA12 },
    { 38066, 38068, 0xFA15, 0xFA17 },
    { 38069, 38074, 0xFA19, 0xFA1E },
    { 38075, 38075, 0xFA22, 0xFA22 },
    { 38076, 38077, 0xFA25, 0xFA26 },
    { 38078, 39107, 0xFA2A, 0xFE2F },
    { 39108, 39108, 0xFE32, 0xFE32 },
    { 39109, 39112, 0xFE45, 0xFE48 },
    { 39113, 39113, 0xFE53, 0xFE53 },
    { 39114, 39114, 0xFE58, 0xFE58 },
    { 39115, 39115, 0xFE67, 0xFE67 },
    { 39116, 39264, 0xFE6C, 0xFF00 },
    { 39265, 39393, 0xFF5F, 0xFFDF },
    { 39394, 39419, 0xFFE6, 0xFFFF },
    { 189000, 1237575, 0x10000, 0x10FFFF },
}

local function pointer(first, second, third, fourth)
    return (((first - 0x81) * 10 + (second - 0x30)) * 126 + (third - 0x81)) * 10 + (fourth - 0x30)
end

local function bytesFromPointer(value)
    local fourth = value % 10
    value = math.floor(value / 10)
    local third = value % 126
    value = math.floor(value / 126)
    local second = value % 10
    value = math.floor(value / 10)
    local first = value
    return string.char(0x81 + first, 0x30 + second, 0x81 + third, 0x30 + fourth)
end

local function codepointFromPointer(value)
    local low, high = 1, #ranges
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local range = ranges[middle]
        if value < range[1] then
            high = middle - 1
        elseif value > range[2] then
            low = middle + 1
        else
            return range[3] + (value - range[1])
        end
    end
end

local function pointerFromCodepoint(codepoint)
    local low, high = 1, #ranges
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local range = ranges[middle]
        if codepoint < range[3] then
            high = middle - 1
        elseif codepoint > range[4] then
            low = middle + 1
        else
            return range[1] + (codepoint - range[3])
        end
    end
end

function GB18030.toUTF8(value)
    local output, index, length = {}, 1, #value
    while index <= length do
        local first = value:byte(index)
        if first < 0x80 then
            output[#output + 1] = string.char(first)
            index = index + 1
        else
            local second = value:byte(index + 1)
            local third = value:byte(index + 2)
            local fourth = value:byte(index + 3)
            local codepoint
            if second and second >= 0x30 and second <= 0x39
                and third and third >= 0x81 and third <= 0xFE
                and fourth and fourth >= 0x30 and fourth <= 0x39 then
                codepoint = codepointFromPointer(pointer(first, second, third, fourth))
                output[#output + 1] = codepoint and GBK.codepointToUtf8(codepoint) or "?"
                index = index + 4
            else
                codepoint = second and GBK.codepoint(first, second)
                output[#output + 1] = codepoint and GBK.codepointToUtf8(codepoint) or "?"
                index = index + (second and 2 or 1)
            end
        end
    end
    return table.concat(output)
end

function GB18030.fromUTF8(value)
    local output, index, length = {}, 1, #value
    while index <= length do
        local codepoint
        codepoint, index = GBK.utf8Codepoint(value, index)
        local encoded = codepoint and GBK.encodeCodepoint(codepoint)
        if not encoded and codepoint then
            local range_pointer = pointerFromCodepoint(codepoint)
            encoded = range_pointer and bytesFromPointer(range_pointer)
        end
        output[#output + 1] = encoded or "?"
    end
    return table.concat(output)
end

return GB18030

