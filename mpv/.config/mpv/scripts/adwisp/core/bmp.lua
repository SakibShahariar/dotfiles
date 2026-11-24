-- Minimal 32-bit BMP encoder for thumbfast's BGRA preview frames.
-- A negative height stores rows top-down, matching the preview buffer order.

local M = {}

local MAX_DIMENSION = 4096
local MAX_IMAGE_BYTES = 64 * 1024 * 1024
local UINT32_MOD = 4294967296

local function uint16(value)
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function uint32(value)
    value = value % UINT32_MOD
    return string.char(
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    )
end

local function valid_dimension(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
        and value >= 1 and value <= MAX_DIMENSION and value == math.floor(value)
end

function M.encode_bgra(width, height, pixels)
    if not valid_dimension(width) or not valid_dimension(height) then
        return nil, "invalid thumbnail dimensions"
    end
    if type(pixels) ~= "string" then
        return nil, "thumbnail pixel data is unavailable"
    end

    local image_size = width * height * 4
    if image_size > MAX_IMAGE_BYTES then
        return nil, "thumbnail is too large to export"
    end
    if #pixels ~= image_size then
        return nil, "thumbnail pixel data is incomplete"
    end

    local file_size = 54 + image_size
    local header = "BM"
        .. uint32(file_size)
        .. uint16(0) .. uint16(0)
        .. uint32(54)
        .. uint32(40)
        .. uint32(width)
        .. uint32(UINT32_MOD - height)
        .. uint16(1)
        .. uint16(32)
        .. uint32(0)
        .. uint32(image_size)
        .. uint32(0) .. uint32(0)
        .. uint32(0) .. uint32(0)

    return header .. pixels
end

return M
