-- Adwisp palette loading and ASS color conversion.
-- Palette files use semantic key=value pairs with #RRGGBB values.

local Theme = {}

Theme.fallback = {
    background = "#30251E",
    surface = "#30251E",
    text = "#FAF7F3",
    muted = "#DBD2C8",
    accent = "#9B7653",
    on_accent = "#FFFFFF",
}

local allowed = {
    background = true,
    surface = true,
    text = true,
    muted = true,
    accent = true,
    on_accent = true,
}

local function valid_hex(value)
    return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

local function ass_color(hex)
    local red = hex:sub(2, 3)
    local green = hex:sub(4, 5)
    local blue = hex:sub(6, 7)
    return "&H" .. blue .. green .. red .. "&"
end

local function fallback_palette()
    local palette = {}
    for key, value in pairs(Theme.fallback) do
        palette[key] = value
    end
    return palette
end

function Theme.load(path)
    if type(path) ~= "string" or path == "" then
        return fallback_palette(), "fallback"
    end

    local file, err = io.open(path, "r")
    if not file then
        return nil, "error", err
    end

    local palette = fallback_palette()
    local diagnostics = {}
    local valid_entries = 0
    local line_number = 0

    for line in file:lines() do
        line_number = line_number + 1
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^#") and not line:match("^;") then
            local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
            if not key then
                diagnostics[#diagnostics + 1] = string.format(
                    "line %d: malformed palette entry", line_number)
            elseif not allowed[key] then
                diagnostics[#diagnostics + 1] = string.format(
                    "line %d: unknown palette key '%s'", line_number, key)
            elseif not valid_hex(value) then
                diagnostics[#diagnostics + 1] = string.format(
                    "line %d: invalid color for '%s'", line_number, key)
            else
                palette[key] = value:upper()
                valid_entries = valid_entries + 1
            end
        end
    end
    file:close()

    if valid_entries == 0 then
        return nil, "invalid", "no valid palette entries found", diagnostics
    end

    return palette, "file", nil, diagnostics
end

function Theme.to_ass(palette)
    local result = {}
    for key, fallback in pairs(Theme.fallback) do
        local value = palette and palette[key] or fallback
        if not valid_hex(value) then value = fallback end
        result[key] = ass_color(value)
    end
    return result
end


local function linear_channel(value)
    value = value / 255
    if value <= 0.04045 then return value / 12.92 end
    return ((value + 0.055) / 1.055) ^ 2.4
end

local function luminance(hex)
    if not valid_hex(hex) then return nil end
    local red = linear_channel(tonumber(hex:sub(2, 3), 16))
    local green = linear_channel(tonumber(hex:sub(4, 5), 16))
    local blue = linear_channel(tonumber(hex:sub(6, 7), 16))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
end

function Theme.contrast_ratio(foreground, background)
    local foreground_luminance = luminance(foreground)
    local background_luminance = luminance(background)
    if not foreground_luminance or not background_luminance then return nil end
    local lighter = math.max(foreground_luminance, background_luminance)
    local darker = math.min(foreground_luminance, background_luminance)
    return (lighter + 0.05) / (darker + 0.05)
end

function Theme.contrast_report(palette)
    palette = palette or Theme.fallback
    return {
        text_background = Theme.contrast_ratio(palette.text, palette.background),
        muted_background = Theme.contrast_ratio(palette.muted, palette.background),
        on_accent = Theme.contrast_ratio(palette.on_accent, palette.accent),
    }
end

return Theme
