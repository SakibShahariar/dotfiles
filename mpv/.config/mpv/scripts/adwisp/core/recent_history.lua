-- Opt-in, local-only recent-file history.
local History = {}

local MAX_ITEMS = 100
local MAX_FILE_SIZE = 512 * 1024
local MAX_PATH_LENGTH = 4096
local MAX_TITLE_LENGTH = 256

local function normalized_limit(value)
    local limit = tonumber(value) or 20
    if limit ~= limit or limit == math.huge or limit == -math.huge then
        limit = 20
    end
    return math.max(1, math.min(MAX_ITEMS, math.floor(limit)))
end

local function clean_path(path)
    if type(path) ~= "string" or path == "" or #path > MAX_PATH_LENGTH
        or path:find("[%c]") or path:find("://", 1, true) then
        return nil
    end
    if path:match("^[%a][%w+.-]*:") and not path:match("^%a:[/\\]") then
        return nil
    end
    return path
end

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

local function clean_title(title, path)
    if type(title) ~= "string" or title:match("^%s*$") then
        title = basename(path)
    end
    title = tostring(title):gsub("[%c]", " "):gsub("%s+", " ")
    title = title:match("^%s*(.-)%s*$") or ""
    if title:sub(1, 1) == "/" or title:match("^%a:[/\\]")
        or title:sub(1, 2) == "\\\\" then
        title = basename(title)
    end
    if title == "" then title = basename(path) end
    return title:sub(1, MAX_TITLE_LENGTH)
end

function History.is_local_path(path)
    return clean_path(path) ~= nil
end

function History.normalize(payload, limit)
    local items = {}
    if type(payload) ~= "table" or (payload.version ~= 1 and payload.version ~= 2)
        or type(payload.items) ~= "table" then
        return items
    end
    local has_progress = payload.version == 2

    local seen = {}
    local maximum = normalized_limit(limit)
    for _, item in ipairs(payload.items) do
        if type(item) == "table" then
            local path = clean_path(item.path)
            if path and not seen[path] then
                seen[path] = true
                local normalized = {
                    path = path,
                    title = clean_title(item.title, path),
                }
                if has_progress and type(item.position) == "number"
                    and item.position == item.position and item.position >= 0
                    and item.position < math.huge
                    and type(item.duration) == "number"
                    and item.duration == item.duration and item.duration > 0
                    and item.duration < math.huge
                    and item.position < item.duration * 0.95 then
                    normalized.position = math.min(item.position, item.duration)
                    normalized.duration = item.duration
                end
                items[#items + 1] = normalized
                if #items >= maximum then break end
            end
        end
    end
    return items
end

function History.record(items, path, title, limit)
    path = clean_path(path)
    if not path then
        return History.normalize({ version = 2, items = items }, limit), false
    end

    local existing = History.normalize({ version = 2, items = items }, MAX_ITEMS)
    local previous = nil
    for _, item in ipairs(existing) do
        if item.path == path then previous = item; break end
    end
    local first = { path = path, title = clean_title(title, path) }
    if previous then
        first.position = previous.position
        first.duration = previous.duration
    end
    local result = { first }
    local seen = { [path] = true }
    local maximum = normalized_limit(limit)
    for _, item in ipairs(existing) do
        if not seen[item.path] then
            seen[item.path] = true
            result[#result + 1] = item
            if #result >= maximum then break end
        end
    end
    return result, true
end

-- Update progress in memory; callers decide when to persist it. A video is
-- considered complete at 95%, at which point its resume marker is cleared.
function History.update_progress(items, path, position, duration, limit)
    path = clean_path(path)
    if not path or type(position) ~= "number" or position ~= position
        or position < 0 or position == math.huge
        or type(duration) ~= "number" or duration ~= duration
        or duration <= 0 or duration == math.huge then
        return History.normalize({ version = 2, items = items }, limit), false
    end

    local result = History.normalize({ version = 2, items = items }, limit)
    for _, item in ipairs(result) do
        if item.path == path then
            if position / duration >= 0.95 then
                item.position, item.duration = nil, nil
                return result, true, "completed"
            end
            item.position = math.min(position, duration)
            item.duration = duration
            return result, true, "updated"
        end
    end
    return result, false
end

function History.resume_position(item)
    if type(item) ~= "table" or type(item.position) ~= "number"
        or item.position ~= item.position or item.position < 0
        or item.position == math.huge or type(item.duration) ~= "number"
        or item.duration ~= item.duration or item.duration <= 0
        or item.duration == math.huge or item.position / item.duration >= 0.95 then
        return nil
    end
    if item.position < 30 then return nil end
    return item.position
end

function History.load(path, limit, deps)
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
    if not ok_open or not file or type(file.read) ~= "function" then
        return {}
    end
    local ok_read, raw = pcall(file.read, file, "*a")
    if type(file.close) == "function" then pcall(file.close, file) end
    if not ok_read or type(raw) ~= "string" or #raw > MAX_FILE_SIZE then
        return {}
    end

    local ok_parse, payload = pcall(deps.parse_json, raw)
    if not ok_parse then return {} end
    return History.normalize(payload, limit)
end

function History.save(path, items, limit, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.open) ~= "function" or type(deps.format_json) ~= "function"
        or type(deps.rename) ~= "function" or type(deps.remove) ~= "function" then
        return false
    end

    local payload = {
        version = 2,
        items = History.normalize({ version = 2, items = items }, limit),
    }
    local ok_encode, encoded = pcall(deps.format_json, payload)
    if not ok_encode or type(encoded) ~= "string" or #encoded > MAX_FILE_SIZE then
        return false
    end

    local temporary_path = path .. ".tmp"
    local ok_open, file = pcall(deps.open, temporary_path, "wb")
    if not ok_open or not file or type(file.write) ~= "function"
        or type(file.close) ~= "function" then
        return false
    end

    local ok_write, write_result = pcall(file.write, file, encoded)
    local ok_close, close_result = pcall(file.close, file)
    if not ok_write or not write_result or not ok_close or close_result == nil then
        pcall(deps.remove, temporary_path)
        return false
    end

    local ok_rename, renamed = pcall(deps.rename, temporary_path, path)
    if not ok_rename or not renamed then
        pcall(deps.remove, temporary_path)
        return false
    end
    return true
end

function History.clear(path, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.file_info) ~= "function" or type(deps.remove) ~= "function" then
        return false
    end
    local ok_info, info = pcall(deps.file_info, path)
    if ok_info and info == nil then return true end
    local ok_remove, removed = pcall(deps.remove, path)
    return ok_remove and removed == true
end

return History
