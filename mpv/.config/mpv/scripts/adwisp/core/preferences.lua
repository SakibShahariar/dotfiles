-- Validated, local-only preferences overrides for Adwisp.
local Preferences = {}

local MAX_FILE_SIZE = 64 * 1024
local MAX_PATH_LENGTH = 512

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function Preferences.validate(key, value)
    if key == "seek_step" or key == "volume_step" then
        local number = tonumber(value)
        if not finite(number) then
            return nil, key .. " must be a finite number"
        end
        local minimum = 1
        local maximum = key == "seek_step" and 3600 or 100
        if number < minimum or number > maximum then
            return nil, key .. " must be between " .. minimum .. " and " .. maximum
        end
        if key == "volume_step" and number ~= math.floor(number) then
            return nil, "volume_step must be a whole number"
        end
        return number
    end

    if key == "thumbnail_preview" then
        if value == true or value == "yes" or value == "on" or value == "1" then
            return true
        end
        if value == false or value == "no" or value == "off" or value == "0" then
            return false
        end
        return nil, "thumbnail_preview must be yes or no"
    end

    if key == "theme_file" then
        if type(value) ~= "string" or #value > MAX_PATH_LENGTH
            or value:find("[%c]") then
            return nil, "theme_file must be a path of at most 512 characters"
        end
        return value
    end

    return nil, "unknown editable setting: " .. tostring(key)
end

function Preferences.normalize(payload)
    local settings = {}
    if type(payload) ~= "table" or payload.version ~= 1
        or type(payload.settings) ~= "table" then
        return settings
    end
    for key, value in pairs(payload.settings) do
        local normalized = Preferences.validate(key, value)
        if normalized ~= nil then settings[key] = normalized end
    end
    return settings
end

function Preferences.load(path, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.file_info) ~= "function" or type(deps.open) ~= "function"
        or type(deps.parse_json) ~= "function" then
        return {}
    end
    local ok_info, info = pcall(deps.file_info, path)
    if not ok_info or type(info) ~= "table" or info.is_file ~= true
        or type(info.size) ~= "number" or info.size < 0 or info.size > MAX_FILE_SIZE then
        return {}
    end
    local ok_open, file = pcall(deps.open, path, "rb")
    if not ok_open or not file or type(file.read) ~= "function" then return {} end
    local ok_read, raw = pcall(file.read, file, "*a")
    if type(file.close) == "function" then pcall(file.close, file) end
    if not ok_read or type(raw) ~= "string" or #raw > MAX_FILE_SIZE then return {} end
    local ok_parse, payload = pcall(deps.parse_json, raw)
    if not ok_parse then return {} end
    return Preferences.normalize(payload)
end

function Preferences.save(path, settings, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.open) ~= "function" or type(deps.format_json) ~= "function"
        or type(deps.rename) ~= "function" or type(deps.remove) ~= "function" then
        return false, "preference storage is unavailable"
    end
    local normalized = Preferences.normalize({ version = 1, settings = settings })
    local ok_encode, encoded = pcall(deps.format_json, {
        version = 1,
        settings = normalized,
    })
    if not ok_encode or type(encoded) ~= "string" or #encoded > MAX_FILE_SIZE then
        return false, "could not encode preferences"
    end
    local temporary_path = path .. ".tmp"
    local ok_open, file = pcall(deps.open, temporary_path, "wb")
    if not ok_open or not file or type(file.write) ~= "function"
        or type(file.close) ~= "function" then
        return false, "could not open the temporary preferences file"
    end
    local ok_write, write_result = pcall(file.write, file, encoded)
    local ok_close, close_result = pcall(file.close, file)
    if not ok_write or not write_result or not ok_close or close_result == nil then
        pcall(deps.remove, temporary_path)
        return false, "could not write preferences"
    end
    local ok_rename, renamed = pcall(deps.rename, temporary_path, path)
    if not ok_rename or not renamed then
        pcall(deps.remove, temporary_path)
        return false, "could not replace the preferences file"
    end
    return true
end

return Preferences
