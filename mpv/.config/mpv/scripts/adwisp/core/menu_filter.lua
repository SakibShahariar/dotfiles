-- Pure filtering for Adwisp selection menus.
-- Unicode Default Full Case Folding is shared by menu text and queries.
local UnicodeCasefold = require "core.unicode_casefold"
local MenuFilter = {}

local DEFAULT_FIELDS = {
    "title",
    "label",
    "name",
    "filename",
    "lang",
    "codec",
    "time",
}

local function normalize(value)
    if type(value) ~= "string" and type(value) ~= "number" then
        return ""
    end

    local normalized = tostring(value)
        :gsub("[%c]", " ")
        :gsub("%s+", " ")
    normalized = normalized:match("^%s*(.-)%s*$") or ""
    return UnicodeCasefold.fold(normalized)
end

local function searchable_text(item, fields)
    if type(item) == "string" or type(item) == "number" then
        return normalize(item)
    end
    if type(item) ~= "table" then
        return ""
    end

    local names = type(fields) == "table" and fields or DEFAULT_FIELDS
    local values = {}
    for _, field in ipairs(names) do
        if type(field) == "string" and field ~= "" then
            local value = item[field]
            if type(value) == "string" or type(value) == "number" then
                values[#values + 1] = tostring(value)
            end
        end
    end
    return normalize(table.concat(values, " "))
end

function MenuFilter.matches(item, query, fields)
    local normalized_query = normalize(query)
    if normalized_query == "" then
        return true
    end

    local haystack = searchable_text(item, fields)
    for token in normalized_query:gmatch("%S+") do
        if not haystack:find(token, 1, true) then
            return false
        end
    end
    return true
end

-- Results retain the original 1-based source index so filtered rows can map
-- back to mpv's unfiltered playlist, chapter, or track list without mutation.
function MenuFilter.filter(items, query, fields)
    local results = {}
    if type(items) ~= "table" then
        return results
    end

    for index, item in ipairs(items) do
        if MenuFilter.matches(item, query, fields) then
            results[#results + 1] = {
                item = item,
                index = index,
            }
        end
    end
    return results
end

return MenuFilter
