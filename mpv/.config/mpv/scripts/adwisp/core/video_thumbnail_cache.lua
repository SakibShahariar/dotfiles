local Cache = {}
Cache.__index = Cache

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function remove_from_order(order, key)
    for index = #order, 1, -1 do
        if order[index] == key then table.remove(order, index) end
    end
end

local function remove_entry(cache, key)
    local entry = cache.entries[key]
    if not entry then return false end
    cache.entries[key] = nil
    cache.bytes = math.max(0, cache.bytes - entry.bytes)
    remove_from_order(cache.order, key)
    if type(entry.thumbnail_path) == "string" and type(cache.remove) == "function" then
        pcall(cache.remove, entry.thumbnail_path)
    end
    return true
end

function Cache.new(max_entries, max_bytes, deps)
    max_entries = finite(max_entries) and math.floor(max_entries) or 64
    max_bytes = finite(max_bytes) and math.floor(max_bytes) or 2 * 1024 * 1024
    return setmetatable({
        max_entries = math.max(1, math.min(256, max_entries)),
        max_bytes = math.max(1, math.min(16 * 1024 * 1024, max_bytes)),
        entries = {},
        order = {},
        bytes = 0,
        remove = type(deps) == "table" and deps.remove or os.remove,
    }, Cache)
end

-- Metadata is part of the key so changed files never reuse stale artwork.
function Cache.key(path, size, mtime)
    if type(path) ~= "string" or path == "" or path:find("%z")
        or not finite(size) or size < 0 or not finite(mtime) or mtime < 0 then
        return nil
    end
    return path .. "\n" .. tostring(size) .. "\n" .. tostring(mtime)
end

function Cache.get(cache, key)
    if type(cache) ~= "table" or type(key) ~= "string" then return nil end
    local entry = cache.entries[key]
    if not entry then return nil end
    remove_from_order(cache.order, key)
    table.insert(cache.order, 1, key)
    return entry
end

function Cache.invalidate_stale(cache, path, expected_key)
    if type(cache) ~= "table" or type(path) ~= "string" then return 0 end
    local keys = {}
    for _, key in ipairs(cache.order) do
        local entry = cache.entries[key]
        if entry and entry.source_path == path and key ~= expected_key then
            keys[#keys + 1] = key
        end
    end
    for _, key in ipairs(keys) do remove_entry(cache, key) end
    return #keys
end

function Cache.put(cache, key, entry)
    if type(cache) ~= "table" or type(key) ~= "string" or key == ""
        or type(entry) ~= "table" or type(entry.source_path) ~= "string"
        or type(entry.thumbnail_path) ~= "string" or entry.thumbnail_path == ""
        or not finite(entry.bytes) or entry.bytes <= 0
        or entry.bytes > cache.max_bytes then
        return false
    end
    local byte_count = math.floor(entry.bytes)
    if byte_count < 1 then return false end

    Cache.invalidate_stale(cache, entry.source_path, key)
    remove_entry(cache, key)
    cache.entries[key] = {
        source_path = entry.source_path,
        thumbnail_path = entry.thumbnail_path,
        bytes = byte_count,
        width = finite(entry.width) and entry.width > 0 and math.floor(entry.width) or nil,
        height = finite(entry.height) and entry.height > 0 and math.floor(entry.height) or nil,
    }
    cache.bytes = cache.bytes + cache.entries[key].bytes
    table.insert(cache.order, 1, key)

    while #cache.order > cache.max_entries or cache.bytes > cache.max_bytes do
        local oldest = cache.order[#cache.order]
        if not oldest then break end
        remove_entry(cache, oldest)
    end
    return cache.entries[key] ~= nil
end

function Cache.invalidate_path(cache, path)
    return Cache.invalidate_stale(cache, path, nil)
end

function Cache.clear(cache)
    if type(cache) ~= "table" then return end
    while #cache.order > 0 do
        remove_entry(cache, cache.order[#cache.order])
    end
    cache.bytes = 0
end

function Cache.stats(cache)
    if type(cache) ~= "table" then return 0, 0 end
    return #cache.order, cache.bytes
end

return Cache
