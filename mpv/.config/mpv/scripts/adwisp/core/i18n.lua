-- Small key=value translation loader with English fallbacks at call sites.
local I18n = {}

local MAX_FILE_SIZE = 64 * 1024
local MAX_KEY_LENGTH = 64
local MAX_VALUE_LENGTH = 256

function I18n.parse(contents)
    local translations = {}
    if type(contents) ~= "string" or #contents > MAX_FILE_SIZE then
        return translations
    end

    for line in (contents .. "\n"):gmatch("(.-)\n") do
        line = line:gsub("\r$", "")
        local trimmed = line:match("^%s*(.-)%s*$") or ""
        if trimmed ~= "" and not trimmed:match("^[#;]") then
            local key, value = trimmed:match("^([%w_.%-]+)%s*=%s*(.*)$")
            if key and #key <= MAX_KEY_LENGTH and value and value ~= "" then
                value = value:gsub("[%c]", " "):gsub("%s+", " ")
                value = value:match("^%s*(.-)%s*$") or ""
                if value ~= "" and #value <= MAX_VALUE_LENGTH then
                    translations[key] = value
                end
            end
        end
    end
    return translations
end

function I18n.load(path, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.open) ~= "function" then
        return {}
    end

    if type(deps.file_info) == "function" then
        local ok_info, info = pcall(deps.file_info, path)
        if not ok_info or type(info) ~= "table" or info.is_file ~= true
            or type(info.size) ~= "number" or info.size < 0
            or info.size > MAX_FILE_SIZE then
            return {}
        end
    end

    local ok_open, file = pcall(deps.open, path, "rb")
    if not ok_open or not file or type(file.read) ~= "function" then
        return {}
    end
    local ok_read, contents = pcall(file.read, file, "*a")
    if type(file.close) == "function" then pcall(file.close, file) end
    if not ok_read or type(contents) ~= "string" or #contents > MAX_FILE_SIZE then
        return {}
    end
    return I18n.parse(contents)
end

function I18n.t(translations, key, fallback)
    if type(translations) == "table" then
        local value = translations[key]
        if type(value) == "string" and value ~= "" then return value end
    end
    return fallback or key
end

return I18n
