-- Adwisp layout calculations.
-- Pure geometry: no mpv dependency, so hit-testing can share these values later.

local Layout = {}

function Layout.compute(width, height, options)
    if type(width) ~= "number" or type(height) ~= "number"
        or width ~= width or height ~= height
        or width == math.huge or width == -math.huge
        or height == math.huge or height == -math.huge
        or width <= 0 or height <= 0 then
        return nil
    end

    -- OSD dimensions are pixel counts; normalize fractional inputs before geometry.
    width = math.floor(width)
    height = math.floor(height)
    if width < 1 or height < 1 then return nil end

    local panel_width = math.min(560, math.max(1, width - 32))
    local compact = height < 240
    local panel_height = math.min(156, math.max(1, height - (compact and 16 or 32)))
    -- Very short windows need a denser row arrangement, not merely a shorter panel.
    local dense_compact = compact and panel_height < 144
    local x = math.floor((width - panel_width) / 2)
    local layout_options = type(options) == "table" and options or {}
    local minimal_timeline = layout_options.minimal_timeline == true
        and layout_options.timeline_expanded ~= true
    local position = layout_options.osd_position
    if position ~= "top" and position ~= "bottom" and position ~= "custom" then
        position = "bottom"
    end

    local margin = layout_options.osd_margin
    if type(margin) ~= "number" or margin ~= margin
        or margin == math.huge or margin == -math.huge or margin < 0 then
        margin = compact and 8 or 42
    end
    local max_y = math.max(0, height - panel_height)
    margin = math.min(math.floor(margin), max_y)

    local y
    if position == "top" then
        y = margin
    elseif position == "custom" then
        local offset = layout_options.osd_custom_offset
        if type(offset) == "number" and offset == offset
            and offset ~= math.huge and offset ~= -math.huge and offset >= 0 then
            y = math.max(0, math.min(max_y, math.floor(offset)))
        else
            position = "bottom"
            y = max_y - margin
        end
    else
        y = max_y - margin
    end
    local split_zones = layout_options.control_zones == "split" and not compact and position == "bottom"
    local top_zone
    local top_margin = layout_options.top_zone_margin
    if type(top_margin) ~= "number" or top_margin ~= top_margin
        or top_margin == math.huge or top_margin == -math.huge or top_margin < 0 then
        top_margin = 24
    end
    top_margin = math.min(math.floor(top_margin), math.max(0, height - 44))
    if split_zones then
        if y >= top_margin + 76 then
            top_zone = { x = x, y = top_margin, width = panel_width, height = 64 }
        end
    end
    local padding = math.min(22, math.floor(panel_width * 0.06))
    local inner_x = x + padding
    local inner_width = math.max(1, panel_width - padding * 2)

    -- Keep both controls inside the panel even in narrow mpv windows.
    local control_gap = math.min(16, math.max(6, math.floor(inner_width * 0.06)))
    local playback_width = math.min(96,
        math.max(1, math.floor((inner_width - control_gap) * 0.45)))
    local volume_width = math.min(120,
        math.max(1, inner_width - playback_width - control_gap))
    local control_y = y + (dense_compact and 22 or (compact and 34 or 51))
    local bar_y = y + (dense_compact and 59 or (compact and 78 or math.min(104, math.floor(panel_height * 0.67))))
    local bar_x = inner_x
    local bar_width = inner_width
    local label_y = bar_y + (dense_compact and 8 or (compact and 14 or 22))
    local labels_have_room = bar_width >= 164
    local progress_label = {
        x = bar_x, y = label_y, width = 36, visible = labels_have_room and not minimal_timeline,
    }
    local time_label = {
        x = labels_have_room and (bar_x + bar_width - 120) or bar_x,
        y = label_y,
        width = labels_have_room and 120 or bar_width,
        visible = bar_width >= 40 and not minimal_timeline,
        compact = not labels_have_room,
        current_only = bar_width < 120,
        font_size = labels_have_room and 15 or 11,
    }

    local volume_x = inner_x + playback_width + control_gap
    local volume_track = {
        x = volume_x, y = control_y + (dense_compact and 17 or 25),
        width = volume_width, height = 4,
    }
    local volume_hit = {
        x = volume_x, y = volume_track.y - 2, width = volume_width, height = 8,
    }

    local title_geometry = top_zone and { x = inner_x, y = top_zone.y + 12, width = inner_width }
        or { x = inner_x, y = y + (dense_compact and 5 or (compact and 10 or 18)), width = inner_width }

    local playlist_geometry = top_zone and {
        x = inner_x, y = top_zone.y + 40, width = inner_width, height = 18,
    } or {
        x = inner_x, y = y + (dense_compact and 80 or (compact and 116 or 132)),
        width = inner_width, height = dense_compact and 14 or 20,
    }

    return {
        width = width,
        height = height,
        compact = compact,
        position = position,
        panel = { x = x, y = y, width = panel_width, height = panel_height },
        top_zone = top_zone,
        title = title_geometry,
        playback = { x = inner_x, y = control_y, width = playback_width,
            height = dense_compact and 18 or (compact and 24 or 32) },
        volume = {
            x = volume_x,
            y = control_y,
            width = volume_width,
            height = dense_compact and 24 or 32,
            track = volume_track,
            hit = volume_hit,
        },
        timeline = {
            x = bar_x, y = bar_y, width = bar_width,
            height = minimal_timeline and 2 or 6,
            minimal = minimal_timeline,
            hit_x = bar_x, hit_y = bar_y - 10, hit_width = bar_width, hit_height = 26,
        },
        progress_label = progress_label,
        time_label = time_label,
        playlist = playlist_geometry,
    }
end

return Layout
