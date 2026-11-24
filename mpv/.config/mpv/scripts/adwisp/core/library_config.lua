-- Local-only configured library roots and pinned folders.
local LibraryConfig = {}

local MAX_FILE_SIZE = 128 * 1024
local MAX_PATH_LENGTH = 4096
local MAX_ROOTS = 20
local MAX_FAVORITES = 50

local function clean_path(path)
    if type(path) ~= "string" then return nil end
    path = path:match("^%s*(.-)%s*$") or ""
    if path == "" or #path > MAX_PATH_LENGTH or path:find("[%c]")
        or path:find("://", 1, true) then
        return nil
    end
    local absolute = path:sub(1, 1) == "/"
        or path:match("^%a:[/\\\\]") ~= nil
        or path:match("^\\\\") ~= nil
    if not absolute then return nil end
    return path
end

local function basename(path)
    return path:match("([^/\\\\]+)[/\\\\]*$") or path
end

local function append_unique(target, seen, value, limit)
    local path = clean_path(value)
    if path and not seen[path] and #target < limit then
        seen[path] = true
        target[#target + 1] = path
    end
end

function LibraryConfig.is_valid_path(path)
    return clean_path(path) ~= nil
end

function LibraryConfig.normalize(payload)
    local result = { roots = {}, favorites = {} }
    if type(payload) ~= "table" or payload.version ~= 1 then return result end
    local roots_seen, favorites_seen = {}, {}
    if type(payload.roots) == "table" then
        for _, path in ipairs(payload.roots) do
            append_unique(result.roots, roots_seen, path, MAX_ROOTS)
        end
    end
    if type(payload.favorites) == "table" then
        for _, path in ipairs(payload.favorites) do
            append_unique(result.favorites, favorites_seen, path, MAX_FAVORITES)
        end
    end
    return result
end

function LibraryConfig.add_root(config, path)
    path = clean_path(path)
    if not path then return config, false, "root must be an absolute local directory path" end
    local result = LibraryConfig.normalize({ version = 1, roots = config and config.roots,
        favorites = config and config.favorites })
    for _, existing in ipairs(result.roots) do
        if existing == path then return result, false, "root is already configured" end
    end
    if #result.roots >= MAX_ROOTS then return result, false, "maximum of 20 library roots reached" end
    result.roots[#result.roots + 1] = path
    return result, true
end

function LibraryConfig.remove_root(config, path)
    path = clean_path(path)
    local result = LibraryConfig.normalize({ version = 1, roots = config and config.roots,
        favorites = config and config.favorites })
    if not path then return result, false end
    for index, existing in ipairs(result.roots) do
        if existing == path then
            table.remove(result.roots, index)
            return result, true
        end
    end
    return result, false
end

function LibraryConfig.toggle_favorite(config, path)
    path = clean_path(path)
    local result = LibraryConfig.normalize({ version = 1, roots = config and config.roots,
        favorites = config and config.favorites })
    if not path then return result, false, "folder must be an absolute local directory path" end
    for index, existing in ipairs(result.favorites) do
        if existing == path then
            table.remove(result.favorites, index)
            return result, false
        end
    end
    if #result.favorites >= MAX_FAVORITES then
        return result, false, "maximum of 50 pinned folders reached"
    end
    result.favorites[#result.favorites + 1] = path
    return result, true
end

function LibraryConfig.locations(config)
    local normalized = LibraryConfig.normalize({ version = 1, roots = config and config.roots,
        favorites = config and config.favorites })
    local result, seen = {}, {}
    for _, path in ipairs(normalized.roots) do
        seen[path] = true
        result[#result + 1] = {
            path = path, kind = "directory", location_type = "root",
            name = basename(path), title = path, label = basename(path) .. " — " .. path,
        }
    end
    for _, path in ipairs(normalized.favorites) do
        if not seen[path] then
            seen[path] = true
            result[#result + 1] = {
                path = path, kind = "directory", location_type = "favorite",
                name = basename(path), title = path, label = basename(path) .. " — " .. path,
            }
        end
    end
    return result
end

function LibraryConfig.load(path, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.file_info) ~= "function" or type(deps.open) ~= "function"
        or type(deps.parse_json) ~= "function" then
        return { roots = {}, favorites = {} }
    end
    local ok_info, info = pcall(deps.file_info, path)
    if not ok_info or type(info) ~= "table" or info.is_file ~= true
        or type(info.size) ~= "number" or info.size < 0 or info.size > MAX_FILE_SIZE then
        return { roots = {}, favorites = {} }
    end
    local ok_open, file = pcall(deps.open, path, "rb")
    if not ok_open or not file or type(file.read) ~= "function" then
        return { roots = {}, favorites = {} }
    end
    local ok_read, raw = pcall(file.read, file, "*a")
    if type(file.close) == "function" then pcall(file.close, file) end
    if not ok_read or type(raw) ~= "string" or #raw > MAX_FILE_SIZE then
        return { roots = {}, favorites = {} }
    end
    local ok_parse, payload = pcall(deps.parse_json, raw)
    if not ok_parse then return { roots = {}, favorites = {} } end
    return LibraryConfig.normalize(payload)
end

function LibraryConfig.save(path, config, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.open) ~= "function" or type(deps.format_json) ~= "function"
        or type(deps.rename) ~= "function" or type(deps.remove) ~= "function" then
        return false, "library configuration storage is unavailable"
    end
    local normalized = LibraryConfig.normalize({ version = 1,
        roots = config and config.roots, favorites = config and config.favorites })
    local ok_encode, encoded = pcall(deps.format_json, {
        version = 1, roots = normalized.roots, favorites = normalized.favorites,
    })
    if not ok_encode or type(encoded) ~= "string" or #encoded > MAX_FILE_SIZE then
        return false, "could not encode library configuration"
    end
    local temporary_path = path .. ".tmp"
    local ok_open, file = pcall(deps.open, temporary_path, "wb")
    if not ok_open or not file or type(file.write) ~= "function"
        or type(file.close) ~= "function" then
        return false, "could not open the temporary library configuration file"
    end
    local ok_write, write_result = pcall(file.write, file, encoded)
    local ok_close, close_result = pcall(file.close, file)
    if not ok_write or not write_result or not ok_close or close_result == nil then
        pcall(deps.remove, temporary_path)
        return false, "could not write library configuration"
    end
    local ok_rename, renamed = pcall(deps.rename, temporary_path, path)
    if not ok_rename or not renamed then
        pcall(deps.remove, temporary_path)
        return false, "could not replace library configuration"
    end
    return true
end

return LibraryConfig
