-- One-directory-at-a-time local video browsing model.
local MenuFilter = require "core.menu_filter"
local VideoLibrary = {}

local extensions = {
    ["3gp"] = true, ["asf"] = true, ["avi"] = true, ["divx"] = true,
    ["flv"] = true, ["m2t"] = true, ["m2ts"] = true, ["m2v"] = true,
    ["m4v"] = true, ["mkv"] = true, ["mov"] = true, ["mp4"] = true,
    ["mpeg"] = true, ["mpg"] = true, ["mts"] = true, ["ogm"] = true,
    ["ogv"] = true, ["rm"] = true, ["rmvb"] = true, ["ts"] = true,
    ["vob"] = true, ["webm"] = true, ["wmv"] = true,
}

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function VideoLibrary.is_supported_video(name)
    if type(name) ~= "string" then return false end
    local extension = name:match("%.([^%.]+)$")
    return extension ~= nil and extensions[extension:lower()] == true
end

local function safe_name(name)
    return type(name) == "string" and name ~= "" and name ~= "."
        and name ~= ".." and not name:find("[%c]")
        and not name:find("/", 1, true) and not name:find("\\", 1, true)
end

function VideoLibrary.begin_scan(path, deps, max_entries)
    if type(path) ~= "string" or path == "" or #path > 4096
        or path:find("[%c]") or path:find("://", 1, true) then
        return nil, "invalid local directory path"
    end
    if type(deps) ~= "table" or type(deps.readdir) ~= "function"
        or type(deps.file_info) ~= "function" or type(deps.join_path) ~= "function" then
        return nil, "filesystem APIs are unavailable"
    end
    local ok_info, info = pcall(deps.file_info, path)
    if not ok_info or type(info) ~= "table" or info.is_dir ~= true then
        return nil, "directory is unavailable or not readable"
    end
    local ok_read, names, read_error = pcall(deps.readdir, path, "normal")
    if not ok_read or type(names) ~= "table" then
        return nil, tostring(read_error or names or "could not enumerate directory")
    end

    local limit = finite(max_entries) and math.floor(max_entries) or 500
    limit = math.max(1, math.min(5000, limit))
    local candidates = {}
    local truncated = false
    for _, name in ipairs(names) do
        if safe_name(name) then
            if #candidates >= limit then
                truncated = true
                break
            end
            candidates[#candidates + 1] = name
        end
    end

    return {
        path = path,
        names = candidates,
        next_index = 1,
        entries = {},
        truncated = truncated,
        done = false,
    }
end

local function entry_less(left, right)
    if left.kind ~= right.kind then return left.kind == "directory" end
    local a, b = left.name:lower(), right.name:lower()
    if a ~= b then return a < b end
    return left.name < right.name
end

function VideoLibrary.scan_chunk(scan, deps, chunk_size)
    if type(scan) ~= "table" or type(scan.names) ~= "table"
        or type(scan.entries) ~= "table" or type(deps) ~= "table"
        or type(deps.file_info) ~= "function" or type(deps.join_path) ~= "function" then
        return true, "invalid scan state"
    end
    if scan.done then return true end
    local limit = finite(chunk_size) and math.floor(chunk_size) or 32
    limit = math.max(1, math.min(256, limit))
    local processed = 0
    while scan.next_index <= #scan.names and processed < limit do
        local name = scan.names[scan.next_index]
        scan.next_index = scan.next_index + 1
        processed = processed + 1
        local ok_path, path = pcall(deps.join_path, scan.path, name)
        if ok_path and type(path) == "string" then
            local ok_info, info = pcall(deps.file_info, path)
            if ok_info and type(info) == "table" then
                local kind
                if info.is_dir == true then
                    kind = "directory"
                elseif info.is_file == true and VideoLibrary.is_supported_video(name) then
                    kind = "video"
                end
                if kind then
                    scan.entries[#scan.entries + 1] = {
                        name = name,
                        path = path,
                        kind = kind,
                        size = finite(info.size) and math.max(0, info.size) or nil,
                        mtime = finite(info.mtime) and info.mtime or nil,
                    }
                end
            end
        end
    end
    if scan.next_index > #scan.names then
        table.sort(scan.entries, entry_less)
        scan.done = true
    end
    return scan.done
end

function VideoLibrary.parent_path(path, deps)
    if type(path) ~= "string" or path == "" or type(deps) ~= "table"
        or type(deps.split_path) ~= "function" then
        return nil
    end
    local normalized = path
    if normalized ~= "/" and not normalized:match("^%a:[/\\]$") then
        normalized = normalized:gsub("[/\\]+$", "")
    end
    local ok, parent = pcall(deps.split_path, normalized)
    if not ok or type(parent) ~= "string" or parent == "" or parent == normalized then
        return nil
    end
    return parent
end

function VideoLibrary.selection(scan, index)
    if type(scan) ~= "table" or type(scan.entries) ~= "table"
        or not finite(index) then
        return nil
    end
    return scan.entries[math.floor(index)]
end

function VideoLibrary.sort_modes()
    return { "name", "recent", "modified", "size" }
end

-- Counts describe only this scan snapshot; they never trigger another scan.
function VideoLibrary.summary(entries, loading, truncated)
    local summary = { videos = 0, folders = 0, complete = loading ~= true and truncated ~= true,
        loading = loading == true, truncated = truncated == true }
    if type(entries) ~= "table" then return summary end
    for _, entry in ipairs(entries) do
        if type(entry) == "table" then
            if entry.kind == "video" then summary.videos = summary.videos + 1
            elseif entry.kind == "directory" then summary.folders = summary.folders + 1 end
        end
    end
    return summary
end

-- Return a new view containing original entry references. Directories stay
-- first; unavailable metadata sorts after known values, with name as tie-break.
function VideoLibrary.view(entries, query, sort_mode)
    if type(entries) ~= "table" then return {} end
    if sort_mode ~= "modified" and sort_mode ~= "recent" and sort_mode ~= "size" then sort_mode = "name" end
    local results = MenuFilter.filter(entries, query, { "title", "name" })
    table.sort(results, function(left, right)
        local a, b = left.item, right.item
        if a.kind ~= b.kind then return a.kind == "directory" end
        if sort_mode ~= "name" and a.kind == "video" then
            local field = (sort_mode == "modified" or sort_mode == "recent") and "mtime" or "size"
            local av, bv = a[field], b[field]
            if av == nil and bv ~= nil then return false end
            if av ~= nil and bv == nil then return true end
            if av ~= nil and bv ~= nil and av ~= bv then return av > bv end
        end
        local an, bn = tostring(a.name or ""), tostring(b.name or "")
        local af, bf = an:lower(), bn:lower()
        if af ~= bf then return af < bf end
        if an ~= bn then return an < bn end
        return left.index < right.index
    end)
    local visible = {}
    for index, result in ipairs(results) do visible[index] = result.item end
    return visible
end

return VideoLibrary
