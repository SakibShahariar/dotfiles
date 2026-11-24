-- Unicode Default Full Case Folding (Unicode 15.1.0).
-- Generated from the Unicode Character Database; no runtime dependency.
-- Invalid UTF-8 bytes are preserved unchanged.
local UnicodeCasefold = {}

local RANGE_DATA = ([[
41,5A,1,32;B5,B5,1,775;C0,D6,1,32;D8,DE,1,32;100,12E,2,1;132,136,2,1;139,147,2,1;
14A,176,2,1;178,178,1,-121;179,17D,2,1;17F,17F,1,-268;181,181,1,210;182,184,2,1;
186,186,1,206;187,187,1,1;189,18A,1,205;18B,18B,1,1;18E,18E,1,79;18F,18F,1,202;
190,190,1,203;191,191,1,1;193,193,1,205;194,194,1,207;196,196,1,211;197,197,1,209;
198,198,1,1;19C,19C,1,211;19D,19D,1,213;19F,19F,1,214;1A0,1A4,2,1;1A6,1A6,1,218;1A7,1A7,1,1;
1A9,1A9,1,218;1AC,1AC,1,1;1AE,1AE,1,218;1AF,1AF,1,1;1B1,1B2,1,217;1B3,1B5,2,1;1B7,1B7,1,219;
1B8,1B8,1,1;1BC,1BC,1,1;1C4,1C4,1,2;1C5,1C5,1,1;1C7,1C7,1,2;1C8,1C8,1,1;1CA,1CA,1,2;
1CB,1DB,2,1;1DE,1EE,2,1;1F1,1F1,1,2;1F2,1F4,2,1;1F6,1F6,1,-97;1F7,1F7,1,-56;1F8,21E,2,1;
220,220,1,-130;222,232,2,1;23A,23A,1,10795;23B,23B,1,1;23D,23D,1,-163;23E,23E,1,10792;
241,241,1,1;243,243,1,-195;244,244,1,69;245,245,1,71;246,24E,2,1;345,345,1,116;370,372,2,1;
376,376,1,1;37F,37F,1,116;386,386,1,38;388,38A,1,37;38C,38C,1,64;38E,38F,1,63;391,3A1,1,32;
3A3,3AB,1,32;3C2,3C2,1,1;3CF,3CF,1,8;3D0,3D0,1,-30;3D1,3D1,1,-25;3D5,3D5,1,-15;
3D6,3D6,1,-22;3D8,3EE,2,1;3F0,3F0,1,-54;3F1,3F1,1,-48;3F4,3F4,1,-60;3F5,3F5,1,-64;
3F7,3F7,1,1;3F9,3F9,1,-7;3FA,3FA,1,1;3FD,3FF,1,-130;400,40F,1,80;410,42F,1,32;460,480,2,1;
48A,4BE,2,1;4C0,4C0,1,15;4C1,4CD,2,1;4D0,52E,2,1;531,556,1,48;10A0,10C5,1,7264;
10C7,10C7,1,7264;10CD,10CD,1,7264;13F8,13FD,1,-8;1C80,1C80,1,-6222;1C81,1C81,1,-6221;
1C82,1C82,1,-6212;1C83,1C84,1,-6210;1C85,1C85,1,-6211;1C86,1C86,1,-6204;1C87,1C87,1,-6180;
1C88,1C88,1,35267;1C90,1CBA,1,-3008;1CBD,1CBF,1,-3008;1E00,1E94,2,1;1E9B,1E9B,1,-58;
1EA0,1EFE,2,1;1F08,1F0F,1,-8;1F18,1F1D,1,-8;1F28,1F2F,1,-8;1F38,1F3F,1,-8;1F48,1F4D,1,-8;
1F59,1F5F,2,-8;1F68,1F6F,1,-8;1FB8,1FB9,1,-8;1FBA,1FBB,1,-74;1FBE,1FBE,1,-7173;
1FC8,1FCB,1,-86;1FD8,1FD9,1,-8;1FDA,1FDB,1,-100;1FE8,1FE9,1,-8;1FEA,1FEB,1,-112;
1FEC,1FEC,1,-7;1FF8,1FF9,1,-128;1FFA,1FFB,1,-126;2126,2126,1,-7517;212A,212A,1,-8383;
212B,212B,1,-8262;2132,2132,1,28;2160,216F,1,16;2183,2183,1,1;24B6,24CF,1,26;2C00,2C2F,1,48;
2C60,2C60,1,1;2C62,2C62,1,-10743;2C63,2C63,1,-3814;2C64,2C64,1,-10727;2C67,2C6B,2,1;
2C6D,2C6D,1,-10780;2C6E,2C6E,1,-10749;2C6F,2C6F,1,-10783;2C70,2C70,1,-10782;2C72,2C72,1,1;
2C75,2C75,1,1;2C7E,2C7F,1,-10815;2C80,2CE2,2,1;2CEB,2CED,2,1;2CF2,2CF2,1,1;A640,A66C,2,1;
A680,A69A,2,1;A722,A72E,2,1;A732,A76E,2,1;A779,A77B,2,1;A77D,A77D,1,-35332;A77E,A786,2,1;
A78B,A78B,1,1;A78D,A78D,1,-42280;A790,A792,2,1;A796,A7A8,2,1;A7AA,A7AA,1,-42308;
A7AB,A7AB,1,-42319;A7AC,A7AC,1,-42315;A7AD,A7AD,1,-42305;A7AE,A7AE,1,-42308;
A7B0,A7B0,1,-42258;A7B1,A7B1,1,-42282;A7B2,A7B2,1,-42261;A7B3,A7B3,1,928;A7B4,A7C2,2,1;
A7C4,A7C4,1,-48;A7C5,A7C5,1,-42307;A7C6,A7C6,1,-35384;A7C7,A7C9,2,1;A7D0,A7D0,1,1;
A7D6,A7D8,2,1;A7F5,A7F5,1,1;AB70,ABBF,1,-38864;FF21,FF3A,1,32;10400,10427,1,40;
104B0,104D3,1,40;10570,1057A,1,39;1057C,1058A,1,39;1058C,10592,1,39;10594,10595,1,39;
10C80,10CB2,1,64;118A0,118BF,1,32;16E40,16E5F,1,32;1E900,1E921,1,34
]]):gsub("%s+", "")
local EXPANSION_DATA = ([[
DF=73,73;130=69,307;149=2BC,6E;1F0=6A,30C;390=3B9,308,301;3B0=3C5,308,301;587=565,582;
1E96=68,331;1E97=74,308;1E98=77,30A;1E99=79,30A;1E9A=61,2BE;1E9E=73,73;1F50=3C5,313;
1F52=3C5,313,300;1F54=3C5,313,301;1F56=3C5,313,342;1F80=1F00,3B9;1F81=1F01,3B9;
1F82=1F02,3B9;1F83=1F03,3B9;1F84=1F04,3B9;1F85=1F05,3B9;1F86=1F06,3B9;1F87=1F07,3B9;
1F88=1F00,3B9;1F89=1F01,3B9;1F8A=1F02,3B9;1F8B=1F03,3B9;1F8C=1F04,3B9;1F8D=1F05,3B9;
1F8E=1F06,3B9;1F8F=1F07,3B9;1F90=1F20,3B9;1F91=1F21,3B9;1F92=1F22,3B9;1F93=1F23,3B9;
1F94=1F24,3B9;1F95=1F25,3B9;1F96=1F26,3B9;1F97=1F27,3B9;1F98=1F20,3B9;1F99=1F21,3B9;
1F9A=1F22,3B9;1F9B=1F23,3B9;1F9C=1F24,3B9;1F9D=1F25,3B9;1F9E=1F26,3B9;1F9F=1F27,3B9;
1FA0=1F60,3B9;1FA1=1F61,3B9;1FA2=1F62,3B9;1FA3=1F63,3B9;1FA4=1F64,3B9;1FA5=1F65,3B9;
1FA6=1F66,3B9;1FA7=1F67,3B9;1FA8=1F60,3B9;1FA9=1F61,3B9;1FAA=1F62,3B9;1FAB=1F63,3B9;
1FAC=1F64,3B9;1FAD=1F65,3B9;1FAE=1F66,3B9;1FAF=1F67,3B9;1FB2=1F70,3B9;1FB3=3B1,3B9;
1FB4=3AC,3B9;1FB6=3B1,342;1FB7=3B1,342,3B9;1FBC=3B1,3B9;1FC2=1F74,3B9;1FC3=3B7,3B9;
1FC4=3AE,3B9;1FC6=3B7,342;1FC7=3B7,342,3B9;1FCC=3B7,3B9;1FD2=3B9,308,300;1FD3=3B9,308,301;
1FD6=3B9,342;1FD7=3B9,308,342;1FE2=3C5,308,300;1FE3=3C5,308,301;1FE4=3C1,313;1FE6=3C5,342;
1FE7=3C5,308,342;1FF2=1F7C,3B9;1FF3=3C9,3B9;1FF4=3CE,3B9;1FF6=3C9,342;1FF7=3C9,342,3B9;
1FFC=3C9,3B9;FB00=66,66;FB01=66,69;FB02=66,6C;FB03=66,66,69;FB04=66,66,6C;FB05=73,74;
FB06=73,74;FB13=574,576;FB14=574,565;FB15=574,56B;FB16=57E,576;FB17=574,56D
]]):gsub("%s+", "")
local RANGES = {}
local EXPANSIONS = {}

for first, last, step, delta in RANGE_DATA:gmatch("([^,;]+),([^,;]+),([^,;]+),([^;]+)") do
    RANGES[#RANGES + 1] = {
        tonumber(first, 16), tonumber(last, 16), tonumber(step), tonumber(delta),
    }
end

for codepoint, values in EXPANSION_DATA:gmatch("([^=;]+)=([^;]+)") do
    local expansion = {}
    for value in values:gmatch("[^,]+") do
        expansion[#expansion + 1] = tonumber(value, 16)
    end
    EXPANSIONS[tonumber(codepoint, 16)] = expansion
end

local function decode_utf8(value, index)
    local first = value:byte(index)
    if not first then return nil, index end
    if first < 0x80 then return first, index + 1 end

    local count, minimum, codepoint
    if first >= 0xC2 and first <= 0xDF then
        count, minimum, codepoint = 1, 0x80, first - 0xC0
    elseif first >= 0xE0 and first <= 0xEF then
        count, minimum, codepoint = 2, 0x800, first - 0xE0
    elseif first >= 0xF0 and first <= 0xF4 then
        count, minimum, codepoint = 3, 0x10000, first - 0xF0
    else
        return nil, index + 1
    end

    for offset = 1, count do
        local byte = value:byte(index + offset)
        if not byte or byte < 0x80 or byte > 0xBF then
            return nil, index + 1
        end
        codepoint = codepoint * 0x40 + byte - 0x80
    end
    if codepoint < minimum or codepoint > 0x10FFFF
        or (codepoint >= 0xD800 and codepoint <= 0xDFFF) then
        return nil, index + 1
    end
    return codepoint, index + count + 1
end

local function encode_utf8(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(0xC0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40)
    elseif codepoint < 0x10000 then
        return string.char(0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40)
    end
    return string.char(0xF0 + math.floor(codepoint / 0x40000),
        0x80 + math.floor(codepoint / 0x1000) % 0x40,
        0x80 + math.floor(codepoint / 0x40) % 0x40,
        0x80 + codepoint % 0x40)
end

local function fold_codepoint(codepoint)
    local expansion = EXPANSIONS[codepoint]
    if expansion then
        local output = {}
        for index, folded in ipairs(expansion) do
            output[index] = encode_utf8(folded)
        end
        return table.concat(output)
    end

    local low, high = 1, #RANGES
    while low <= high do
        local middle = math.floor((low + high) / 2)
        local range = RANGES[middle]
        if codepoint < range[1] then
            high = middle - 1
        elseif codepoint > range[2] then
            low = middle + 1
        else
            if (codepoint - range[1]) % range[3] == 0 then
                return encode_utf8(codepoint + range[4])
            end
            break
        end
    end
    return encode_utf8(codepoint)
end

function UnicodeCasefold.fold(value)
    if type(value) ~= "string" then return "" end
    local output, index = {}, 1
    while index <= #value do
        local codepoint, next_index = decode_utf8(value, index)
        if codepoint then
            output[#output + 1] = fold_codepoint(codepoint)
        else
            output[#output + 1] = value:sub(index, index)
        end
        index = next_index
    end
    return table.concat(output)
end

return UnicodeCasefold
