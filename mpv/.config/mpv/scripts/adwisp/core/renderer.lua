-- Adwisp renderer: ASS OSD drawing only.
-- Copyright (c) 2026 Adwisp contributors
-- MIT License. See LICENSE.

local Layout = require "core.layout"
local Theme = require "core.theme"
local I18n = require "core.i18n"

local Renderer = {}
Renderer.__index = Renderer

local function escape_ass(value)
    return tostring(value or "")
        :gsub("\\", "\\\\")
        :gsub("{", "\\{")
        :gsub("}", "\\}")
        :gsub("\r", " ")
        :gsub("\n", " ")
end

local function truncate_title(value, max_chars)
    value = tostring(value or "")
    if max_chars < 2 then return "…" end

    -- Count UTF-8 code points without depending on Lua's optional utf8 library.
    local count, index = 0, 1
    while index <= #value do
        local byte = value:byte(index)
        local step = 1
        if byte >= 240 then step = 4
        elseif byte >= 224 then step = 3
        elseif byte >= 192 then step = 2 end
        index = index + step
        count = count + 1
    end
    if count <= max_chars then return value end

    local keep = max_chars - 1
    local chars, pos = 0, 1
    while pos <= #value and chars < keep do
        local byte = value:byte(pos)
        local step = 1
        if byte >= 240 then step = 4
        elseif byte >= 224 then step = 3
        elseif byte >= 192 then step = 2 end
        pos = pos + step
        chars = chars + 1
    end
    return value:sub(1, pos - 1) .. "…"
end

local function is_finite_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function translate(state, key, fallback)
    return I18n.t(state and state.translations, key, fallback)
end

local function translate_format(state, key, fallback, ...)
    local template = translate(state, key, fallback)
    local ok, formatted = pcall(string.format, template, ...)
    if ok then return formatted end
    return string.format(fallback, ...)
end

local function safe_font_family(value)
    if type(value) ~= "string" then return "Sans" end
    value = value:sub(1, 48):gsub("[^%w _%-]", "")
    value = value:match("^%s*(.-)%s*$")
    return value ~= "" and value or "Sans"
end

local function fmt_time(seconds)
    if not is_finite_number(seconds) or seconds < 0 then return "--:--" end
    -- mpv timestamps are normally small; cap hostile metadata before integer formatting.
    seconds = math.floor(math.min(seconds, 2147483647))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
    return string.format("%d:%02d", minutes, secs)
end

local function render_menu_panel(menu, width, height, colors, font_family, font_scale)
    if type(menu) ~= "table" or type(menu.lines) ~= "table" or #menu.lines == 0 then
        return ""
    end

    local lines = menu.lines
    local available_height = math.max(1, height - 16)
    local line_height = math.max(6, math.min(22,
        math.floor(math.max(1, available_height - 20) / #lines)))
    local panel_width = math.max(1, math.min(520, width - 16))
    local panel_height = math.min(available_height, 20 + #lines * line_height)
    local x = math.max(0, width - panel_width - 8)
    local y = math.max(0, math.floor((height - panel_height) / 2))
    local font_size = math.max(8, math.min(17,
        math.floor(line_height * 0.72 * font_scale + 0.5)))
    local max_chars = math.max(1, math.floor((panel_width - 28) / (font_size * 0.56)))
    local ass = string.format(
        "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\alpha&H18&\\p1}"
            .. "m 0 0 l %d 0 %d %d 0 %d{\\p0}\\N",
        x, y, colors.background, panel_width, panel_width, panel_height, panel_height
    )

    for index, line in ipairs(lines) do
        local selected = menu.selected_line == index
        local color = selected and colors.on_accent
            or (index == 1 and colors.accent or (index == 2 and colors.muted or colors.text))
        local bold = (index == 1 or selected) and 1 or 0
        local line_y = y + 10 + (index - 1) * line_height
        if selected then
            ass = ass .. string.format(
                "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\alpha&H30&\\p1}"
                    .. "m 0 0 l %d 0 %d %d 0 %d{\\p0}\\N",
                x + 8, line_y - 2, colors.accent, panel_width - 16,
                panel_width - 16, line_height, line_height
            )
        end
        ass = ass .. string.format(
            "{\\an7\\pos(%d,%d)\\fn%s\\fs%d\\b%d\\1c%s}%s\\N",
            x + 14, line_y, font_family, font_size, bold, color,
            escape_ass(truncate_title(line, max_chars))
        )
    end
    return ass
end

function Renderer.new(mp, state)
    local self = setmetatable({}, Renderer)
    self.mp = mp
    self.state = state
    self.overlay = mp.create_osd_overlay("ass-events")
    self.overlay.z = 20
    self.last_size = nil
    self.last_data = nil
    return self
end

function Renderer:set_palette(palette)
    self.state.palette = palette
    self.last_data = nil
end

function Renderer:clear()
    if self.last_data == "" then return end
    self.overlay.data = ""
    self.overlay:update()
    self.last_data = ""
end

function Renderer:render()
    local state = self.state
    if not state.visible then
        self:clear()
        return
    end

    local width, height = self.mp.get_osd_size()
    if not width or not height or width <= 0 or height <= 0 then return end

    local time_pos = is_finite_number(state.time_pos) and state.time_pos or 0
    local duration = is_finite_number(state.duration) and state.duration or 0
    local volume_value = is_finite_number(state.volume) and state.volume or 0
    volume_value = math.max(0, math.min(100, volume_value))
    local now = fmt_time(state.time_pos)
    local total = fmt_time(state.duration)
    local progress = 0
    if duration > 0 then
        progress = math.max(0, math.min(1, time_pos / duration))
    end

    local layout_options = type(state.layout_options) == "table"
        and state.layout_options or {}
    local layout = Layout.compute(width, height, layout_options)
    if not layout then return end
    local top_zone_visible = not layout.top_zone
        or layout_options.top_zone_visibility ~= "hover"
        or state.hover_zone == "top" or state.focus_target == "playlist"
    local bottom_zone_visible = not layout.top_zone
        or layout_options.bottom_zone_visibility ~= "hover"
        or state.hover_zone == "bottom" or state.focus_target == "playback"
        or state.focus_target == "volume" or state.focus_target == "timeline"
    local panel = layout.panel
    local title_pos = layout.title
    local title_font_size = layout.compact and 18 or 22
    local status_labels = {}
    if state.buffering == true then
        local buffering_progress = is_finite_number(state.buffering_progress)
            and math.max(0, math.min(100, state.buffering_progress)) or 0
        if layout.compact and title_pos.width < 240 then
            status_labels[#status_labels + 1] = translate(state, "buffering", "Buffering")
        else
            status_labels[#status_labels + 1] = translate_format(state, "buffering_percent", "Buffering %d%%",
                math.floor(buffering_progress + 0.5))
        end
    end
    local loop_file = state.loop_file
    if loop_file == "inf" or (is_finite_number(tonumber(loop_file)) and tonumber(loop_file) > 0) then
        status_labels[#status_labels + 1] = translate(state, "loop", "Loop")
    end
    local loop_a = is_finite_number(state.ab_loop_a) and state.ab_loop_a or -1
    local loop_b = is_finite_number(state.ab_loop_b) and state.ab_loop_b or -1
    if loop_a >= 0 and loop_b >= 0 then
        status_labels[#status_labels + 1] = "A–B"
    elseif loop_a >= 0 then
        status_labels[#status_labels + 1] = "A"
    elseif loop_b >= 0 then
        status_labels[#status_labels + 1] = "B"
    end
    if state.image_mode == true then
        local image_zoom = is_finite_number(state.image_zoom)
            and math.max(-4, math.min(4, state.image_zoom)) or 0
        status_labels[#status_labels + 1] = translate_format(state, "image_zoom",
            "Image · Zoom %d%%", math.floor(100 * (2 ^ image_zoom) + 0.5))
    end
    if type(state.chapter_title) == "string" and state.chapter_title ~= "" then
        status_labels[#status_labels + 1] = translate_format(state, "chapter_status", "Chapter: %s", truncate_title(state.chapter_title, 14))
    end
    if (tonumber(state.audio_track_count) or 0) > 0 then
        local audio_label = type(state.audio_track_label) == "string"
            and state.audio_track_label ~= "" and state.audio_track_label or "—"
        status_labels[#status_labels + 1] = translate_format(state, "audio_status", "A: %s", truncate_title(audio_label, 10))
    end
    if (tonumber(state.subtitle_track_count) or 0) > 0 then
        local subtitle_label = type(state.subtitle_track_label) == "string"
            and state.subtitle_track_label ~= "" and state.subtitle_track_label or "Off"
        if subtitle_label == "Off" then
            subtitle_label = translate(state, "off", "Off")
        end
        status_labels[#status_labels + 1] = translate_format(state, "subtitle_status", "S: %s", truncate_title(subtitle_label, 10))
    end
    local buffering_label = escape_ass(truncate_title(table.concat(status_labels, " · "), 54))
    local buffering_status_width = 0
    if buffering_label ~= "" and title_pos.width >= 140 then
        buffering_status_width = math.min(140,
            math.max(64, math.floor(title_pos.width * 0.38)))
    elseif title_pos.width < 140 then
        buffering_label = ""
    end
    local available_title_width = math.max(1,
        title_pos.width - buffering_status_width - (buffering_status_width > 0 and 12 or 0))
    local title_chars = math.max(buffering_status_width > 0 and 4 or 8,
        math.floor(available_title_width / (title_font_size * 0.56)))
    local title = escape_ass(truncate_title(
        state.title ~= "" and state.title or "Adwisp", title_chars
    ))
    local playback = layout.playback
    local volume = layout.volume
    local volume_track_geometry = volume.track
    local timeline = layout.timeline
    local progress_label = layout.progress_label
    local time_label = layout.time_label
    local playlist = layout.playlist
    local playlist_label = ""
    local playlist_count = is_finite_number(state.playlist_count)
        and math.max(0, math.floor(state.playlist_count)) or 0
    if playlist_count >= 2 then
        playlist_label = translate(state, "playlist_controls", "‹    Previous       Next    ›")
        if is_finite_number(state.playlist_pos) and state.playlist_pos >= 0 then
            local playlist_pos = math.floor(state.playlist_pos)
            if playlist_pos < playlist_count then
                playlist_label = translate_format(state, "playlist_controls_position", "‹    Previous      %d / %d      Next    ›",
                    playlist_pos + 1, playlist_count)
            end
        end
    end
    playlist_label = escape_ass(playlist_label)
    local filled = math.floor(timeline.width * progress)
    local pause_label = state.paused and translate(state, "play", "Play") or translate(state, "pause", "Pause")
    local playback_label = escape_ass(string.format("%s  %.2g×", pause_label,
        is_finite_number(state.speed) and math.max(0.01, math.min(100, state.speed)) or 1))
    local volume_label = state.mute and translate(state, "muted", "Muted")
        or (volume_value <= 20 and translate_format(state, "low_volume", "Low volume %d%%", math.floor(volume_value + 0.5))
            or translate_format(state, "volume", "Volume %d%%", math.floor(volume_value + 0.5)))
    volume_label = escape_ass(volume_label)
    local progress_text = progress_label.visible
        and string.format("%d%%", math.floor(progress * 100 + 0.5)) or ""
    local time_text = ""
    if time_label.visible then
        if time_label.current_only then
            time_text = now
        elseif time_label.compact then
            time_text = now .. "/" .. total
        else
            time_text = now .. " / " .. total
        end
    end

    local preview_label = ""
    local preview_label_x, preview_label_y
    if state.preview_visible == true and is_finite_number(state.preview_time) then
        preview_label = fmt_time(state.preview_time)
        local preview_width = is_finite_number(state.preview_width)
            and math.max(0, state.preview_width) or 0
        local preview_height = is_finite_number(state.preview_height)
            and math.max(0, state.preview_height) or 0
        if preview_width > 0 and preview_height > 0 then
            local preview_x = is_finite_number(state.preview_x) and state.preview_x or 0
            local preview_y = is_finite_number(state.preview_y) and state.preview_y or 0
            local horizontal_margin = math.min(40, width / 2)
            preview_label_x = math.max(horizontal_margin, math.min(
                width - horizontal_margin, preview_x + preview_width / 2))
            preview_label_y = preview_y - 20
            if preview_label_y < 8 then
                preview_label_y = preview_y + preview_height + 8
            end
            local vertical_margin = math.min(8, height / 2)
            preview_label_y = math.max(vertical_margin, math.min(
                height - vertical_margin, preview_label_y))
        else
            preview_label = ""
        end
    end

    local font_family = safe_font_family(layout_options.font_family)
    local font_scale = layout_options.font_scale
    if not is_finite_number(font_scale) then font_scale = 1 end
    font_scale = math.max(0.75, math.min(1.25, font_scale))

    local colors = Theme.to_ass(state.palette)
    local focus_geometry
    if state.focus_target == "playback" then
        focus_geometry = layout.playback
    elseif state.focus_target == "volume" then
        focus_geometry = layout.volume
    elseif state.focus_target == "playlist" and playlist_count >= 2 then
        focus_geometry = layout.playlist
    elseif state.focus_target == "timeline" then
        focus_geometry = {
            x = layout.timeline.x,
            y = layout.timeline.y - 4,
            width = layout.timeline.width,
            height = layout.timeline.height + 8,
        }
    end
    local focus_ass = ""
    if focus_geometry and ((state.focus_target == "playlist" and top_zone_visible)
        or (state.focus_target ~= "playlist" and bottom_zone_visible)) then
        local focus_panel = state.focus_target == "playlist" and layout.top_zone or panel
        local focus_x = math.max(focus_panel.x, focus_geometry.x - 4)
        local focus_y = math.max(focus_panel.y, focus_geometry.y - 4)
        local focus_right = math.min(focus_panel.x + focus_panel.width,
            focus_geometry.x + focus_geometry.width + 4)
        local focus_bottom = math.min(focus_panel.y + focus_panel.height,
            focus_geometry.y + focus_geometry.height + 4)
        local focus_width = focus_right - focus_x
        local focus_height = focus_bottom - focus_y
        if focus_width > 4 and focus_height > 4 then
            focus_ass = string.format(
                "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\alpha&H40&\\p1}"
                    .. "m 0 0 l %d 0 %d %d 0 %d{\\p0}\\n"
                    .. "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\alpha&H18&\\p1}"
                    .. "m 0 0 l %d 0 %d %d 0 %d{\\p0}\\n",
                focus_x, focus_y, colors.accent, focus_width, focus_width,
                focus_height, focus_height,
                focus_x + 2, focus_y + 2, colors.background,
                focus_width - 4, focus_width - 4,
                focus_height - 4, focus_height - 4
            )
        end
    end
    if not top_zone_visible then
        title = ""
        buffering_label = ""
        playlist_label = ""
    end
    if not bottom_zone_visible then
        playback_label = ""
        volume_label = ""
        progress_text = ""
        time_text = ""
        preview_label = ""
    end
    local volume_label_color = (state.mute or volume_value <= 20)
        and colors.accent or colors.muted
    local top_zone_ass = ""
    if layout.top_zone and top_zone_visible then
        local top = layout.top_zone
        local top_color = state.hover_zone == "top" and colors.surface or colors.background
        top_zone_ass = string.format(
            "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\alpha&H1A&\\p1}m 0 0 l %d 0 %d %d 0 %d{\\p0}\\n",
            top.x, top.y, top_color, top.width, top.width, top.height, top.height
        )
    end
    local panel_background = layout.top_zone and state.hover_zone == "bottom"
        and colors.surface or colors.background
    local ass = top_zone_ass .. string.format([[
{\an7\pos(%d,%d)\bord0\shad0\1c%s\alpha&H18&\p1}m 0 0 l %d 0 %d %d 0 %d{\p0}
%s
{\an7\pos(%d,%d)\fnSans\fs22\b1\1c%s}%s
{\an9\pos(%d,%d)\fnSans\fs13\b1\1c%s}%s
{\an8\pos(%d,%d)\fnSans\fs13\b1\1c%s}%s
{\an7\pos(%d,%d)\fnSans\fs14\1c%s}%s
{\an7\pos(%d,%d)\fnSans\fs14\1c%s}%s
{\an7\pos(%d,%d)\bord0\shad0\1c%s\p1}m 0 0 l %d 0 %d 6 0 6{\p0}
{\an7\pos(%d,%d)\bord0\shad0\1c%s\p1}m 0 0 l %d 0 %d 6 0 6{\p0}
{\an7\pos(%d,%d)\fnSans\fs13\1c%s}%s
{\an7\pos(%d,%d)\fnSans\fs%d\b1\1c%s}%s
{\an7\pos(%d,%d)\fnSans\fs15\1c%s}%s
]],
        panel.x, panel.y, panel_background, panel.width, panel.width, panel.height, panel.height,
        focus_ass,
        title_pos.x, title_pos.y, colors.text, title,
        title_pos.x + title_pos.width, title_pos.y, colors.accent, buffering_label,
        preview_label_x or 0, preview_label_y or 0, colors.accent, preview_label,
        playback.x, playback.y, colors.muted, playback_label,
        volume.x, volume.y, volume_label_color, volume_label,
        timeline.x, timeline.y, colors.muted, timeline.width, timeline.width,
        timeline.x, timeline.y, colors.accent, filled, filled,
        progress_label.x, progress_label.y, colors.muted, progress_text,
        time_label.x, time_label.y, time_label.font_size, colors.text, time_text,
        playlist.x, playlist.y, colors.text, playlist_label
    )

    if layout.compact then
        -- Keep text legible without letting labels dominate short windows.
        ass = ass:gsub("\\fs22", "\\fs18")
            :gsub("\\fs14", "\\fs12")
            :gsub("\\fs13", "\\fs11")
            :gsub("\\fs15", "\\fs12")
    end

    ass = ass:gsub("\\fnSans", function() return "\\fn" .. font_family end)
    ass = ass:gsub("\\fs(%d+)", function(size)
        return "\\fs" .. math.max(1, math.floor(tonumber(size) * font_scale + 0.5))
    end)

    local volume_fraction = volume_value / 100
    local volume_fill = math.floor(volume_track_geometry.width * volume_fraction)
    local volume_track_ass = string.format([[
{\an7\pos(%d,%d)\bord0\shad0\1c%s\p1}m 0 0 l %d 0 %d %d 0 %d{\p0}
{\an7\pos(%d,%d)\bord0\shad0\1c%s\p1}m 0 0 l %d 0 %d %d 0 %d{\p0}
]], volume_track_geometry.x, volume_track_geometry.y, colors.muted,
        volume_track_geometry.width, volume_track_geometry.width,
        volume_track_geometry.height, volume_track_geometry.height,
        volume_track_geometry.x, volume_track_geometry.y, colors.accent,
        volume_fill, volume_fill, volume_track_geometry.height, volume_track_geometry.height)
    if bottom_zone_visible then ass = ass .. volume_track_ass end

    local chapter_markers = {}
    local chapters = type(state.chapter_list) == "table" and state.chapter_list or {}
    if bottom_zone_visible and not timeline.minimal
        and is_finite_number(duration) and duration > 0 then
        local seen_markers = {}
        for _, chapter in ipairs(chapters) do
            local chapter_time = type(chapter) == "table" and chapter.time or nil
            if is_finite_number(chapter_time) and chapter_time > 0
                and chapter_time < duration then
                local marker_x = math.floor(timeline.x
                    + chapter_time / duration * timeline.width + 0.5)
                if marker_x > timeline.x and marker_x < timeline.x + timeline.width
                    and not seen_markers[marker_x] then
                    seen_markers[marker_x] = true
                    chapter_markers[#chapter_markers + 1] = string.format(
                        "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\p1}"
                            .. "m 0 0 l 2 0 2 8 0 8{\\p0}",
                        marker_x, timeline.y - 1, colors.accent)
                end
            end
        end
    end
    ass = ass .. table.concat(chapter_markers, "\\n")
    ass = ass .. render_menu_panel(state.library_menu or state.playlist_menu or state.recent_menu, width, height,
        colors, font_family, font_scale)

    if state.hover_target == "playback" or state.hover_target == "volume"
        or state.hover_target == "playlist" or state.hover_target == "timeline" then
        local target
        if state.hover_target == "playback" then target = playback
        elseif state.hover_target == "volume" then target = volume
        elseif state.hover_target == "playlist" then target = playlist
        else
            target = {
                x = timeline.x,
                y = timeline.y - 5,
                width = timeline.width,
                height = timeline.height + 10,
            }
        end
        local hover_bg = string.format(
            "{\\an7\\pos(%d,%d)\\bord0\\shad0\\1c%s\\alpha&H30&\\p1}"
                .. "m 0 0 l %d 0 %d %d 0 %d{\\p0}\\n",
            target.x - 6, target.y - 5, colors.surface,
            target.width + 12, target.width + 12,
            target.height + 10, target.height + 10
        )
        ass = hover_bg .. ass
    end

    local opacity = is_finite_number(state.opacity)
        and math.max(0, math.min(1, state.opacity)) or 1
    local fade_alpha = math.floor((1 - opacity) * 255 + 0.5)
    local panel_alpha = bottom_zone_visible and math.min(255, 24 + fade_alpha) or 255
    local top_panel_alpha = top_zone_visible and math.min(255, 24 + fade_alpha) or 255
    local hover_alpha = math.min(255, 48 + fade_alpha)
    local focus_alpha = math.min(255, 64 + fade_alpha)
    ass = ass:gsub("{\\", "{\\alpha&H" .. string.format("%02X", fade_alpha) .. "&\\")
    ass = ass:gsub("\\alpha&H18&", "\\alpha&H" .. string.format("%02X", panel_alpha) .. "&")
    ass = ass:gsub("\\alpha&H1A&", "\\alpha&H" .. string.format("%02X", top_panel_alpha) .. "&")
    ass = ass:gsub("\\alpha&H30&", "\\alpha&H" .. string.format("%02X", hover_alpha) .. "&")
    ass = ass:gsub("\\alpha&H40&", "\\alpha&H" .. string.format("%02X", focus_alpha) .. "&")

    local size_key = width .. "x" .. height
    if self.last_data == ass and self.last_size == size_key then return end
    self.overlay.res_x = width
    self.overlay.res_y = height
    self.overlay.data = ass
    self.overlay:update()
    self.last_data = ass
    self.last_size = size_key
end

return Renderer
