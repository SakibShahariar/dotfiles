-- Adwisp: GTK-inspired OSD prototype for mpv
-- Copyright (c) 2026 Adwisp contributors
-- Licensed under the MIT License. See LICENSE.

local mp = require "mp"
local options = require "mp.options"

-- Allow project-local modules to be loaded when this script is installed as a folder.
local script_dir = mp.get_script_directory()
package.path = script_dir .. "/?.lua;" .. script_dir .. "/?/init.lua;" .. package.path

local MenuFilter = require "core.menu_filter"
local RecentHistory = require "core.recent_history"
local Preferences = require "core.preferences"
local VideoLibrary = require "core.video_library"
local LibraryConfig = require "core.library_config"
local I18n = require "core.i18n"

local opts = {
    seek_step = 5,
    volume_step = 5,
    speed_step = 0.1,
    loop_toggle_key = "CTRL+ALT+L",
    ab_loop_key = "CTRL+ALT+A",
    screenshot_key = "CTRL+ALT+S",
    toggle_key = "g",
    dismiss_key = "q",
    dismiss_escape_key = "ESC",
    seek_back_key = "LEFT",
    seek_forward_key = "RIGHT",
    volume_up_key = "CTRL+UP",
    volume_down_key = "CTRL+DOWN",
    mute_toggle_key = "m",
    playlist_prev_key = "CTRL+LEFT",
    playlist_next_key = "CTRL+RIGHT",
    idle_hide_timeout = 0,
    fade_duration = 0.25,
    theme_file = "",
    thumbnail_preview = true,
    thumbnail_export_directory = "~~/",
    thumbnail_export_prefix = "adwisp-thumbnail",
    time_pos_render_interval = 0.15,
    minimal_timeline = false,
    osd_position = "bottom",
    osd_margin = -1,
    control_zones = "single",
    top_zone_margin = 24,
    top_zone_visibility = "always",
    bottom_zone_visibility = "always",
    osd_custom_offset = 120,
    font_family = "Sans",
    font_scale = 1.0,
    log_level = "info",
    recent_history = false,
    recent_history_limit = 20,
    recent_history_file = "~~/adwisp-recent.json",
    preferences_file = "~~/adwisp-preferences.json",
    locale_file = "",
    library_max_entries = 500,
    library_config_file = "~~/adwisp-library.json",
}
options.read_options(opts, "adwisp")
opts.recent_history = opts.recent_history == true
local recent_history_limit = tonumber(opts.recent_history_limit)
if type(recent_history_limit) ~= "number" or recent_history_limit ~= recent_history_limit
    or recent_history_limit == math.huge or recent_history_limit == -math.huge then
    recent_history_limit = 20
end
opts.recent_history_limit = math.max(1, math.min(100, math.floor(recent_history_limit)))
if type(opts.recent_history_file) ~= "string"
    or opts.recent_history_file:match("^%s*$") then
    opts.recent_history_file = "~~/adwisp-recent.json"
end
opts.recent_history_file = opts.recent_history_file:sub(1, 512)
if type(opts.preferences_file) ~= "string" or opts.preferences_file:match("^%s*$") then
    opts.preferences_file = "~~/adwisp-preferences.json"
end
opts.preferences_file = opts.preferences_file:sub(1, 512)
if type(opts.theme_file) ~= "string" then opts.theme_file = "" end
opts.theme_file = opts.theme_file:sub(1, 512)
if type(opts.locale_file) ~= "string" then opts.locale_file = "" end
opts.locale_file = opts.locale_file:sub(1, 512)
local library_max_entries = tonumber(opts.library_max_entries)
if type(library_max_entries) ~= "number" or library_max_entries ~= library_max_entries
    or library_max_entries == math.huge or library_max_entries == -math.huge then
    library_max_entries = 500
end
opts.library_max_entries = math.max(50, math.min(5000, math.floor(library_max_entries)))
if type(opts.library_config_file) ~= "string" or opts.library_config_file:match("^%s*$") then
    opts.library_config_file = "~~/adwisp-library.json"
end
opts.library_config_file = opts.library_config_file:sub(1, 512)
if type(opts.font_family) ~= "string" then opts.font_family = "Sans" end
opts.font_family = opts.font_family:sub(1, 48):gsub("[^%w _%-]", "")
opts.font_family = opts.font_family:match("^%s*(.-)%s*$")
if opts.font_family == "" then opts.font_family = "Sans" end
local configured_font_scale = tonumber(opts.font_scale)
if type(configured_font_scale) ~= "number" or configured_font_scale ~= configured_font_scale
    or configured_font_scale == math.huge or configured_font_scale == -math.huge then
    configured_font_scale = 1
end
opts.font_scale = math.max(0.75, math.min(1.25, configured_font_scale))
local idle_hide_timeout = tonumber(opts.idle_hide_timeout)
if type(idle_hide_timeout) ~= "number" or idle_hide_timeout ~= idle_hide_timeout
    or idle_hide_timeout == math.huge or idle_hide_timeout == -math.huge then
    idle_hide_timeout = 0
end
opts.idle_hide_timeout = math.max(0, math.min(600, idle_hide_timeout))
local fade_duration = tonumber(opts.fade_duration)
if type(fade_duration) ~= "number" or fade_duration ~= fade_duration
    or fade_duration == math.huge or fade_duration == -math.huge then
    fade_duration = 0.25
end
opts.fade_duration = math.max(0.05, math.min(1, fade_duration))
if opts.log_level ~= "quiet" and opts.log_level ~= "debug" then
    opts.log_level = "info"
end
if type(opts.thumbnail_export_directory) ~= "string"
    or opts.thumbnail_export_directory:match("^%s*$") then
    opts.thumbnail_export_directory = "~~/"
end
opts.thumbnail_export_directory = opts.thumbnail_export_directory:sub(1, 512)
if type(opts.thumbnail_export_prefix) ~= "string" then
    opts.thumbnail_export_prefix = "adwisp-thumbnail"
end
opts.thumbnail_export_prefix = opts.thumbnail_export_prefix:gsub("[^%w_.%-]", ""):sub(1, 48)
if opts.thumbnail_export_prefix == "" then
    opts.thumbnail_export_prefix = "adwisp-thumbnail"
end

local state = require "core.state"
local Renderer = require "core.renderer"
local Layout = require "core.layout"
local Theme = require "core.theme"
local utils = require "mp.utils"

local preference_defaults = {
    seek_step = opts.seek_step,
    volume_step = opts.volume_step,
    thumbnail_preview = opts.thumbnail_preview,
    theme_file = opts.theme_file,
}
local preference_path = opts.preferences_file
local ok_preferences_path, expanded_preferences_path = pcall(mp.command_native,
    { "expand-path", preference_path })
if ok_preferences_path and type(expanded_preferences_path) == "string"
    and expanded_preferences_path ~= "" then
    preference_path = expanded_preferences_path
end
local preference_dependencies = {
    file_info = utils.file_info,
    open = io.open,
    rename = os.rename,
    remove = os.remove,
    parse_json = utils.parse_json,
    format_json = utils.format_json,
}
local stored_preferences = Preferences.load(preference_path, preference_dependencies)
for key, value in pairs(stored_preferences) do
    if key == "theme_file" then
        local palette = Theme.load(value)
        if palette then
            opts.theme_file = value
        else
            mp.msg.warn("Adwisp: ignoring an invalid saved theme_file preference.")
        end
    else
        opts[key] = value
    end
end
state.layout_options = opts
local locale_path = opts.locale_file
if locale_path ~= "" then
    local ok, expanded = pcall(mp.command_native, { "expand-path", locale_path })
    if ok and type(expanded) == "string" and expanded ~= "" then
        locale_path = expanded
    end
end
state.translations = I18n.load(locale_path, {
    file_info = utils.file_info,
    open = io.open,
})
local function tr(key, fallback)
    return I18n.t(state.translations, key, fallback)
end
local function tr_format(key, fallback, ...)
    local template = tr(key, fallback)
    local ok, formatted = pcall(string.format, template, ...)
    if ok then return formatted end
    return string.format(fallback, ...)
end

local BMP = require "core.bmp"
local renderer = Renderer.new(mp, state)

local function log_info(message)
    if opts.log_level ~= "quiet" then
        mp.msg.info("Adwisp: " .. message)
    end
end

local function log_debug(message)
    if opts.log_level == "debug" then
        mp.msg.info("Adwisp [debug]: " .. message)
    end
end

local recent_items = {}
local recent_history_path
local current_history_path
local recent_progress_dirty = false
local recent_progress_timer
local resume_prompt_path
local resume_prompt_position
local flush_recent_progress
local history_dependencies = {
    file_info = utils.file_info,
    open = io.open,
    rename = os.rename,
    remove = os.remove,
    parse_json = utils.parse_json,
    format_json = utils.format_json,
}

local library_config_path = opts.library_config_file
local ok_library_config_path, expanded_library_config_path = pcall(mp.command_native,
    { "expand-path", library_config_path })
if ok_library_config_path and type(expanded_library_config_path) == "string"
    and expanded_library_config_path ~= "" then
    library_config_path = expanded_library_config_path
end
local library_config_dependencies = history_dependencies
local library_config = LibraryConfig.load(library_config_path, library_config_dependencies)
local function save_library_config()
    local saved, err = LibraryConfig.save(library_config_path, library_config,
        library_config_dependencies)
    if not saved then
        mp.msg.warn("Adwisp: could not save local library configuration: " .. tostring(err))
    end
    return saved
end

if opts.recent_history then
    local ok, expanded = pcall(mp.command_native, { "expand-path", opts.recent_history_file })
    recent_history_path = ok and type(expanded) == "string" and expanded ~= ""
        and expanded or opts.recent_history_file
    recent_items = RecentHistory.load(recent_history_path,
        opts.recent_history_limit, history_dependencies)
end

local function resolve_recent_path(path)
    if not RecentHistory.is_local_path(path) then return nil end
    local ok, expanded = pcall(mp.command_native, { "expand-path", path })
    if ok and type(expanded) == "string" and expanded ~= "" then path = expanded end

    local absolute = path:sub(1, 1) == "/" or path:match("^%a:[/\\]")
        or path:sub(1, 2) == "\\\\"
    if not absolute then
        local working_directory = mp.get_property("working-directory")
        if type(working_directory) == "string" and working_directory ~= "" then
            local separator = working_directory:find("\\", 1, true) and "\\" or "/"
            path = working_directory:gsub("[/\\]+$", "") .. separator .. path
        end
    end
    return RecentHistory.is_local_path(path) and path or nil
end

local function find_recent_item(path)
    for _, item in ipairs(recent_items) do
        if item.path == path then return item end
    end
    return nil
end

local function save_recent_history()
    if not opts.recent_history or not recent_history_path then return false end
    local saved = RecentHistory.save(recent_history_path, recent_items,
        opts.recent_history_limit, history_dependencies)
    if saved then
        recent_progress_dirty = false
        log_debug("saved local recent-file history")
    else
        mp.msg.warn("Adwisp: could not save local recent-file history.")
    end
    return saved
end

local function cancel_recent_progress_timer()
    if recent_progress_timer and type(recent_progress_timer.kill) == "function" then
        recent_progress_timer:kill()
    end
    recent_progress_timer = nil
end

local function schedule_recent_progress_save()
    if recent_progress_timer or type(mp.add_timeout) ~= "function" then return end
    recent_progress_timer = mp.add_timeout(30, function()
        recent_progress_timer = nil
        if recent_progress_dirty and not save_recent_history() then
            schedule_recent_progress_save()
        end
    end)
end

local function update_recent_progress(force)
    if not opts.recent_history or not current_history_path then return end
    local position, duration = state.time_pos, state.duration
    if type(position) ~= "number" or position ~= position or position < 0
        or position == math.huge or position == -math.huge
        or type(duration) ~= "number" or duration ~= duration or duration <= 0
        or duration == math.huge or duration == -math.huge then
        return
    end
    local previous = find_recent_item(current_history_path)
    if not previous then return end
    if not force and position / duration < 0.95 then
        if not previous.position and position < 30 then return end
        if previous.position and math.abs(position - previous.position) < 30 then return end
    end
    local updated, changed = RecentHistory.update_progress(recent_items,
        current_history_path, position, duration, opts.recent_history_limit)
    if changed then
        recent_items = updated
        recent_progress_dirty = true
        schedule_recent_progress_save()
    end
end

flush_recent_progress = function(force_update)
    if force_update then update_recent_progress(true) end
    cancel_recent_progress_timer()
    if recent_progress_dirty then save_recent_history() end
end

local function format_resume_time(seconds)
    seconds = math.max(0, math.floor(seconds))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remainder)
    end
    return string.format("%d:%02d", minutes, remainder)
end

local function record_recent_file()
    if not opts.recent_history or not recent_history_path then return end
    flush_recent_progress(false)
    local path = resolve_recent_path(mp.get_property("path"))
    current_history_path = path
    resume_prompt_path, resume_prompt_position = nil, nil
    if not path then return end
    local updated, recorded = RecentHistory.record(recent_items, path,
        mp.get_property("media-title"), opts.recent_history_limit)
    if not recorded then return end
    recent_items = updated
    recent_progress_dirty = true
    if not save_recent_history() then schedule_recent_progress_save() end
    local item = find_recent_item(path)
    local resume_position = RecentHistory.resume_position(item)
    if resume_position then
        resume_prompt_path, resume_prompt_position = path, resume_position
        mp.commandv("show-text", string.format(
            "Adwisp: Resume %s from %s? Press Ctrl+Alt+R.",
            item.title, format_resume_time(resume_position)), 5000)
    end
end

local function resume_current_file()
    if not resume_prompt_path or not resume_prompt_position then return end
    if resolve_recent_path(mp.get_property("path")) ~= resume_prompt_path then
        resume_prompt_path, resume_prompt_position = nil, nil
        return
    end
    local position = resume_prompt_position
    resume_prompt_path, resume_prompt_position = nil, nil
    mp.commandv("seek", position, "absolute+exact")
    mp.commandv("show-text", "Adwisp: Resumed playback.", 1800)
end


-- thumbfast owns thumbnail generation and display. Adwisp only requests previews.
local thumbfast = {
    width = 0, height = 0, source_width = 0, source_height = 0,
    disabled = true, available = false, thumbnail_path = nil,
}
local thumbnail_active = false
local last_thumbnail_request = nil
local cached_layout = nil
local cached_layout_width, cached_layout_height
local cached_layout_position, cached_layout_margin, cached_layout_custom_offset
local cached_layout_minimal_timeline, cached_layout_timeline_expanded
local cached_layout_control_zones, cached_layout_top_zone_margin
local active_drag = nil
local last_mouse_x, last_mouse_y
local active_track_menu
local active_playlist_menu
local active_recent_menu
local close_library_menu
local library_scan_timer
local library_scan_generation = 0
local library_binding_names = {}
local open_playlist_menu
local refresh_playlist_menu
local open_recent_menu
local refresh_recent_menu
local open_audio_device_menu
local track_menu_binding_names = {}
local track_menu_timer

local function clear_track_menu()
    local had_playlist_menu = active_playlist_menu ~= nil or active_recent_menu ~= nil
    for _, name in ipairs(track_menu_binding_names) do
        if type(mp.remove_key_binding) == "function" then
            mp.remove_key_binding(name)
        end
    end
    track_menu_binding_names = {}
    if track_menu_timer and type(track_menu_timer.kill) == "function" then
        track_menu_timer:kill()
    end
    track_menu_timer = nil
    active_track_menu = nil
    active_playlist_menu = nil
    active_recent_menu = nil
    if had_playlist_menu then
        state.playlist_menu = nil
        state.recent_menu = nil
        renderer:render()
    end
end

local function clear_interaction_state()
    if close_library_menu then close_library_menu(true) end
    active_drag = nil
    last_mouse_x, last_mouse_y = nil, nil
    state.hover_target = nil
    state.focus_target = nil
    clear_track_menu()
end

local function clear_thumbnail()
    if thumbnail_active and thumbfast.available then
        mp.commandv("script-message-to", "thumbfast", "clear")
    end
    local was_visible = state.preview_visible == true
    state.preview_visible = false
    state.preview_time = 0
    state.preview_x, state.preview_y = 0, 0
    state.preview_width, state.preview_height = 0, 0
    thumbnail_active = false
    last_thumbnail_request = nil
    return was_visible
end

local thumbnail_export_sequence = 0

local function export_thumbnail()
    if not thumbnail_active or not thumbfast.available
        or type(thumbfast.thumbnail_path) ~= "string"
        or thumbfast.thumbnail_path == "" then
        mp.commandv("show-text", "Adwisp: no thumbfast preview is ready to export.", 3000)
        return
    end
    if thumbfast.source_width < 1 or thumbfast.source_width > 4096
        or thumbfast.source_height < 1 or thumbfast.source_height > 4096 then
        mp.commandv("show-text", "Adwisp: thumbfast preview dimensions are unsupported.", 3000)
        return
    end

    local source_path = thumbfast.thumbnail_path .. ".bgra"
    local source_info = utils.file_info(source_path)
    local expected_size = thumbfast.source_width * thumbfast.source_height * 4
    if not source_info or source_info.size ~= expected_size then
        mp.commandv("show-text", "Adwisp: thumbnail preview is not ready; try again.", 3000)
        return
    end

    local source = io.open(source_path, "rb")
    if not source then
        mp.commandv("show-text", "Adwisp: could not read the thumbfast preview.", 3000)
        return
    end
    local pixels = source:read("*a")
    source:close()
    local bitmap, encode_error = BMP.encode_bgra(
        thumbfast.source_width, thumbfast.source_height, pixels)
    if not bitmap then
        mp.msg.warn("Adwisp: thumbnail export failed: " .. tostring(encode_error))
        mp.commandv("show-text", "Adwisp: thumbnail export failed.", 3000)
        return
    end

    local directory = mp.command_native({ "expand-path", opts.thumbnail_export_directory })
    if type(directory) ~= "string" or directory == "" then
        mp.commandv("show-text", "Adwisp: thumbnail export directory is invalid.", 3000)
        return
    end
    local directory_info = utils.file_info(directory)
    if not directory_info or not directory_info.is_dir then
        mp.commandv("show-text", "Adwisp: export directory does not exist.", 3000)
        return
    end

    local separator = package.config:sub(1, 1)
    directory = directory:gsub("[/\\]+$", "")
    if directory == "" then directory = separator end
    local filename
    local output_path
    for _ = 1, 100 do
        thumbnail_export_sequence = thumbnail_export_sequence + 1
        filename = opts.thumbnail_export_prefix .. "-"
            .. os.date("%Y%m%d-%H%M%S") .. "-" .. thumbnail_export_sequence .. ".bmp"
        output_path = directory
            .. (directory:sub(-1) == separator and "" or separator) .. filename
        if not utils.file_info(output_path) then break end
        output_path = nil
    end
    if not output_path then
        mp.commandv("show-text", "Adwisp: could not choose a unique thumbnail filename.", 3000)
        return
    end

    local output, open_error = io.open(output_path, "wb")
    if not output then
        mp.msg.warn("Adwisp: could not write thumbnail: " .. tostring(open_error))
        mp.commandv("show-text", "Adwisp: could not write the thumbnail file.", 3000)
        return
    end
    local wrote, write_error = output:write(bitmap)
    local closed, close_error = output:close()
    if not wrote or not closed then
        os.remove(output_path)
        mp.msg.warn("Adwisp: thumbnail write failed: "
            .. tostring(write_error or close_error))
        mp.commandv("show-text", "Adwisp: thumbnail export failed while writing.", 3000)
        return
    end

    log_info("thumbnail exported to " .. output_path)
    mp.commandv("show-text", "Adwisp: exported " .. filename, 4000)
end

local time_pos_render_pending = false
local time_pos_render_generation = 0
local time_pos_render_timer

local function cancel_time_pos_render()
    if time_pos_render_timer and type(time_pos_render_timer.kill) == "function" then
        time_pos_render_timer:kill()
    end
    time_pos_render_timer = nil
end

local function render()
    if opts.minimal_timeline == true then
        opts.timeline_expanded = state.hover_target == "timeline"
            or state.focus_target == "timeline" or active_drag == "timeline"
    else
        opts.timeline_expanded = nil
    end
    -- Any immediate render supersedes and cancels a queued playback-position update.
    cancel_time_pos_render()
    time_pos_render_generation = time_pos_render_generation + 1
    time_pos_render_pending = false
    renderer:render()
end

local function finite_number(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

local idle_timer
local fade_timer
local idle_generation = 0
local fade_generation = 0
local start_fade_out

local function kill_timer(timer)
    if timer and type(timer.kill) == "function" then
        timer:kill()
    end
end

local function schedule_idle_hide()
    idle_generation = idle_generation + 1
    local generation = idle_generation
    kill_timer(idle_timer)
    idle_timer = nil
    if not state.visible or opts.idle_hide_timeout <= 0
        or type(mp.add_timeout) ~= "function" then
        return
    end
    idle_timer = mp.add_timeout(opts.idle_hide_timeout, function()
        if generation ~= idle_generation or not state.visible then return end
        idle_timer = nil
        if active_drag ~= nil then return end
        start_fade_out()
    end)
end

local function cancel_fade()
    fade_generation = fade_generation + 1
    kill_timer(fade_timer)
    fade_timer = nil
end

local function animate_opacity(target, on_complete)
    cancel_fade()
    local generation = fade_generation
    local start = finite_number(state.opacity) and math.max(0, math.min(1, state.opacity)) or 1
    local duration = opts.fade_duration
    if not finite_number(duration) or duration <= 0
        or type(mp.add_timeout) ~= "function" then
        state.opacity = target
        render()
        if on_complete then on_complete() end
        return
    end

    local steps = 6
    local step = 0
    local function advance()
        if generation ~= fade_generation or not state.visible then return end
        fade_timer = nil
        step = step + 1
        state.opacity = start + (target - start) * (step / steps)
        render()
        if step >= steps then
            state.opacity = target
            if on_complete then on_complete() end
        else
            fade_timer = mp.add_timeout(duration / steps, advance)
        end
    end
    fade_timer = mp.add_timeout(duration / steps, advance)
end

start_fade_out = function()
    if not state.visible then return end
    idle_generation = idle_generation + 1
    animate_opacity(0, function()
        state.visible = false
        state.opacity = 1
        clear_interaction_state()
        clear_thumbnail()
        render()
    end)
end

local function show_osd()
    idle_generation = idle_generation + 1
    cancel_fade()
    state.visible = true
    if opts.idle_hide_timeout > 0 then
        state.opacity = 0
        render()
        schedule_idle_hide()
        animate_opacity(1)
    else
        state.opacity = 1
        render()
    end
end

local function hide_osd()
    idle_generation = idle_generation + 1
    kill_timer(idle_timer)
    idle_timer = nil
    cancel_fade()
    state.visible = false
    state.opacity = 1
    clear_interaction_state()
    clear_thumbnail()
    render()
end


-- Cancel deferred work and release UI/thumbnail state before mpv exits.
local function cleanup_on_shutdown()
    if flush_recent_progress then flush_recent_progress(true) end
    idle_generation = idle_generation + 1
    kill_timer(idle_timer)
    idle_timer = nil
    cancel_fade()
    cancel_time_pos_render()
    time_pos_render_generation = time_pos_render_generation + 1
    time_pos_render_pending = false
    clear_interaction_state()
    clear_thumbnail()
    state.visible = false
    state.opacity = 1
    renderer:clear()
end
local function note_activity()
    if not state.visible then return end
    idle_generation = idle_generation + 1
    kill_timer(idle_timer)
    idle_timer = nil
    cancel_fade()
    local was_faded = state.opacity ~= 1
    state.opacity = 1
    if was_faded then render() end
    schedule_idle_hide()
end

local active_palette

local function reload_theme()
    local palette, source, err, diagnostics = Theme.load(opts.theme_file)
    if palette then
        active_palette = palette
    elseif not active_palette then
        active_palette = Theme.load("")
    end

    renderer:set_palette(active_palette)
    local contrast = Theme.contrast_report(active_palette)
    if contrast.text_background and contrast.text_background < 4.5 then
        mp.msg.warn("Adwisp: theme text/background contrast is below 4.5:1 (WCAG AA).")
    end
    if contrast.muted_background and contrast.muted_background < 4.5 then
        mp.msg.warn("Adwisp: theme muted-text/background contrast is below 4.5:1 (WCAG AA).")
    end
    if contrast.on_accent and contrast.on_accent < 3 then
        mp.msg.warn("Adwisp: theme accent-label contrast is below 3:1.")
    end
    render()

    for _, diagnostic in ipairs(diagnostics or {}) do
        mp.msg.warn("Adwisp: theme " .. diagnostic)
    end

    if source == "file" then
        log_info("theme reloaded from file.")
    elseif source == "fallback" then
        log_info("using the built-in fallback theme.")
    else
        mp.msg.warn("Adwisp: theme reload failed; keeping the previous palette: "
            .. tostring(err))
    end
end

reload_theme()

local function preference_values()
    return {
        seek_step = opts.seek_step,
        volume_step = opts.volume_step,
        thumbnail_preview = opts.thumbnail_preview,
        theme_file = opts.theme_file,
    }
end

local function show_preferences()
    local lines = {
        "Adwisp preferences",
        "seek_step = " .. tostring(opts.seek_step) .. " seconds",
        "volume_step = " .. tostring(opts.volume_step) .. " percent",
        "thumbnail_preview = " .. (opts.thumbnail_preview and "yes" or "no"),
        "theme_file = " .. (opts.theme_file ~= "" and opts.theme_file or "(built-in theme)"),
        "Set: script-message adwisp-setting-set <key> <value>",
        "Reset: script-message adwisp-setting-reset <key>",
    }
    mp.commandv("show-text", table.concat(lines, "\n"), 7000)
end

local function set_preference(key, raw_value)
    local value, validation_error = Preferences.validate(key, raw_value)
    if value == nil then
        mp.commandv("show-text", "Adwisp: rejected setting — " .. tostring(validation_error), 3500)
        return false
    end
    if key == "theme_file" then
        local palette, _, theme_error = Theme.load(value)
        if not palette then
            mp.commandv("show-text", "Adwisp: rejected theme_file — " .. tostring(theme_error), 4000)
            return false
        end
    end

    opts[key] = value
    if key == "theme_file" then
        reload_theme()
    elseif key == "thumbnail_preview" then
        if not value then clear_thumbnail() end
        render()
    end

    local saved, save_error = Preferences.save(preference_path,
        preference_values(), preference_dependencies)
    if saved then
        mp.commandv("show-text", "Adwisp: saved " .. key .. " = " .. tostring(value), 3000)
    else
        mp.msg.warn("Adwisp: preference applied for this session but could not be saved: "
            .. tostring(save_error))
        mp.commandv("show-text", "Adwisp: applied " .. key
            .. " for this session; save failed.", 4000)
    end
    return true
end

local function reset_preference(key)
    if preference_defaults[key] == nil then
        mp.commandv("show-text", "Adwisp: unknown editable setting " .. tostring(key), 3000)
        return
    end
    set_preference(key, preference_defaults[key])
end

mp.register_script_message("adwisp-settings", show_preferences)
mp.register_script_message("adwisp-setting-set", set_preference)
mp.register_script_message("adwisp-setting-reset", reset_preference)

log_debug("options loaded; seek_step=" .. tostring(opts.seek_step)
    .. ", volume_step=" .. tostring(opts.volume_step)
    .. ", thumbnail_preview=" .. tostring(opts.thumbnail_preview)
    .. ", osd_position=" .. tostring(opts.osd_position))

local function toggle()
    if state.visible then hide_osd() else show_osd() end
end

local function option_step(value, fallback)
    value = tonumber(value)
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then
        return fallback
    end
    return math.max(1, math.min(3600, value))
end

local function seek(delta)
    mp.commandv("seek", delta, "relative", "keyframes")
end

local function change_volume(delta)
    note_activity()
    local current = tonumber(state.volume) or 100
    local step = option_step(opts.volume_step, 5)
    local volume = math.max(0, math.min(100, current + delta * step))
    state.volume = volume
    state.mute = false
    mp.commandv("set", "volume", volume)
    mp.commandv("set", "mute", "no")
end

local function speed_step()
    local value = tonumber(opts.speed_step)
    if not finite_number(value) then value = 0.1 end
    return math.max(0.01, math.min(5, value))
end

local function set_speed(value)
    note_activity()
    value = tonumber(value)
    if not finite_number(value) then value = 1 end
    value = math.max(0.01, math.min(100, value))
    state.speed = value
    mp.commandv("set", "speed", value)
end

local function change_speed(delta)
    local current = finite_number(state.speed) and state.speed or 1
    set_speed(current + delta * speed_step())
end

local function set_image_zoom(value)
    if not state.image_mode then return false end
    local zoom = finite_number(value) and value or 0
    zoom = math.max(-4, math.min(4, zoom))
    note_activity()
    state.image_zoom = zoom
    mp.commandv("set", "video-zoom", zoom)
    render()
    return true
end

local function change_image_zoom(delta)
    if not state.image_mode then return false end
    local current = finite_number(state.image_zoom) and state.image_zoom or 0
    return set_image_zoom(current + delta)
end

local function fit_image_to_window()
    if not state.image_mode then return false end
    note_activity()
    mp.commandv("set", "video-unscaled", "no")
    mp.commandv("set", "video-zoom", 0)
    mp.commandv("set", "video-pan-x", 0)
    mp.commandv("set", "video-pan-y", 0)
    state.image_zoom = 0
    render()
    return true
end

local function reset_speed()
    set_speed(1)
end

local function set_volume_at(mouse_x, track)
    if type(track.width) ~= "number" or track.width <= 0 then return end
    local fraction = math.max(0, math.min(1,
        (mouse_x - track.x) / track.width))
    local value = math.floor(fraction * 100 + 0.5)
    state.volume = value
    state.mute = false
    mp.commandv("set", "volume", value)
    mp.commandv("set", "mute", "no")
    render()
end

local function seek_at(mouse_x, timeline)
    if type(timeline.width) ~= "number" or timeline.width <= 0 then return end
    local fraction = math.max(0, math.min(1,
        (mouse_x - timeline.x) / timeline.width))
    mp.commandv("seek", fraction * 100, "absolute-percent")
end

local function seek_chapter_marker(mouse_x, timeline)
    if not finite_number(state.duration) or state.duration <= 0
        or type(timeline.width) ~= "number" or timeline.width <= 0 then
        return false
    end
    local closest_time
    local closest_distance = 6
    for _, chapter in ipairs(state.chapter_list) do
        local chapter_time = type(chapter) == "table" and chapter.time or nil
        if finite_number(chapter_time) and chapter_time > 0
            and chapter_time < state.duration then
            local marker_x = timeline.x + chapter_time / state.duration * timeline.width
            local distance = math.abs(mouse_x - marker_x)
            if distance <= closest_distance then
                closest_distance = distance
                closest_time = chapter_time
            end
        end
    end
    if closest_time ~= nil then
        mp.commandv("seek", closest_time, "absolute")
        return true
    end
    return false
end

local function has_playlist_navigation()
    local count = state.playlist_count
    return type(count) == "number" and count == count
        and count ~= math.huge and count ~= -math.huge and math.floor(count) >= 2
end

local function set_focus(target)
    if state.focus_target ~= target then
        state.focus_target = target
        render()
    end
end

local function focus_targets()
    local targets = { "playback", "volume" }
    if opts.minimal_timeline == true then
        targets[#targets + 1] = "timeline"
    end
    if has_playlist_navigation() then
        targets[#targets + 1] = "playlist"
    end
    return targets
end

local function cycle_focus(reverse)
    if not state.visible then return end
    note_activity()
    local targets = focus_targets()
    local current = 0
    for index, target in ipairs(targets) do
        if target == state.focus_target then
            current = index
            break
        end
    end
    if reverse then
        current = current <= 1 and #targets or current - 1
    else
        current = current >= #targets and 1 or current + 1
    end
    set_focus(targets[current])
end

local function activate_focus()
    if not state.visible then return end
    note_activity()
    if state.focus_target == "playback" then
        mp.commandv("cycle", "pause")
    elseif state.focus_target == "volume" then
        mp.commandv("cycle", "mute")
    elseif state.focus_target == "playlist" and has_playlist_navigation() then
        mp.commandv("playlist-next", "weak")
    end
end

local function handle_left()
    note_activity()
    if state.focus_target == "volume" then
        change_volume(-1)
    elseif state.focus_target == "playlist" and has_playlist_navigation() then
        mp.commandv("playlist-prev", "weak")
    else
        seek(-option_step(opts.seek_step, 5))
    end
end

local function handle_right()
    note_activity()
    if state.focus_target == "volume" then
        change_volume(1)
    elseif state.focus_target == "playlist" and has_playlist_navigation() then
        mp.commandv("playlist-next", "weak")
    else
        seek(option_step(opts.seek_step, 5))
    end
end

local function request_time_pos_render()
    if not state.visible then return end
    if type(mp.add_timeout) ~= "function" then
        render()
        return
    end
    if time_pos_render_pending then return end

    local interval = tonumber(opts.time_pos_render_interval)
    if not finite_number(interval) then interval = 0.15 end
    interval = math.max(0.05, math.min(0.5, interval))

    time_pos_render_pending = true
    time_pos_render_generation = time_pos_render_generation + 1
    local generation = time_pos_render_generation
    time_pos_render_timer = mp.add_timeout(interval, function()
        if generation ~= time_pos_render_generation or not time_pos_render_pending then
            return
        end
        time_pos_render_timer = nil
        time_pos_render_pending = false
        if state.visible then render() end
    end)
end

local function contains(rect, mouse_x, mouse_y)
    return mouse_x >= rect.x and mouse_x <= rect.x + rect.width
        and mouse_y >= rect.y and mouse_y <= rect.y + rect.height
end

local function get_layout(width, height)
    if not cached_layout or width ~= cached_layout_width
        or height ~= cached_layout_height
        or opts.osd_position ~= cached_layout_position
        or opts.osd_margin ~= cached_layout_margin
        or opts.osd_custom_offset ~= cached_layout_custom_offset
        or opts.control_zones ~= cached_layout_control_zones
        or opts.top_zone_margin ~= cached_layout_top_zone_margin
        or opts.minimal_timeline ~= cached_layout_minimal_timeline
        or opts.timeline_expanded ~= cached_layout_timeline_expanded then
        cached_layout = Layout.compute(width, height, opts)
        cached_layout_width, cached_layout_height = width, height
        cached_layout_position = opts.osd_position
        cached_layout_margin = opts.osd_margin
        cached_layout_custom_offset = opts.osd_custom_offset
        cached_layout_control_zones = opts.control_zones
        cached_layout_top_zone_margin = opts.top_zone_margin
        cached_layout_minimal_timeline = opts.minimal_timeline
        cached_layout_timeline_expanded = opts.timeline_expanded
    end
    return cached_layout
end

local function contains_timeline(timeline, mouse_x, mouse_y)
    return mouse_x >= timeline.hit_x
        and mouse_x <= timeline.hit_x + timeline.hit_width
        and mouse_y >= timeline.hit_y
        and mouse_y <= timeline.hit_y + timeline.hit_height
end

local function handle_mouse_move()
    if not state.visible or type(mp.get_mouse_pos) ~= "function" then return end
    local mouse_x, mouse_y = mp.get_mouse_pos()
    if not finite_number(mouse_x) or not finite_number(mouse_y) then return end
    -- mpv may emit repeated mouse_move callbacks at an unchanged position.
    -- They cannot change hover, preview, or drag state, so avoid the rest of
    -- the layout/hit-test work (and avoid resetting the idle timer).
    if mouse_x == last_mouse_x and mouse_y == last_mouse_y then return end
    last_mouse_x, last_mouse_y = mouse_x, mouse_y
    note_activity()
    local width, height = mp.get_osd_size()
    local layout = get_layout(width, height)
    if not layout then return end

    if active_drag == "volume" then
        set_volume_at(mouse_x, layout.volume.track)
    elseif active_drag == "timeline" then
        seek_at(mouse_x, layout.timeline)
    end

    local hover_zone
    if layout.top_zone and contains(layout.top_zone, mouse_x, mouse_y) then
        hover_zone = "top"
    elseif layout.top_zone and contains(layout.panel, mouse_x, mouse_y) then
        hover_zone = "bottom"
    end
    local zone_changed = state.hover_zone ~= hover_zone
    state.hover_zone = hover_zone

    local hover_target
    if contains(layout.playback, mouse_x, mouse_y) then
        hover_target = "playback"
    elseif contains(layout.volume, mouse_x, mouse_y) then
        hover_target = "volume"
    elseif has_playlist_navigation() and contains(layout.playlist, mouse_x, mouse_y) then
        hover_target = "playlist"
    elseif contains_timeline(layout.timeline, mouse_x, mouse_y) then
        hover_target = "timeline"
    end

    local timeline = layout.timeline
    local on_timeline = active_drag == nil
        and opts.thumbnail_preview ~= false
        and contains_timeline(timeline, mouse_x, mouse_y)
    local preview_changed = false
    local preview_cleared = false
    if on_timeline and not thumbfast.disabled and state.duration > 0
        and thumbfast.width > 0 and thumbfast.height > 0 then
        local fraction = math.max(0, math.min(1,
            (mouse_x - layout.timeline.x) / layout.timeline.width))
        local seconds = math.floor(fraction * state.duration * 10 + 0.5) / 10
        local osd_width = width
        local x = math.floor(math.max(8, math.min(
            osd_width - thumbfast.width - 8, mouse_x - thumbfast.width / 2)))
        local y = math.floor(math.max(0, layout.timeline.y - thumbfast.height - 12))
        local request = { seconds = seconds, x = x, y = y }
        preview_changed = not state.preview_visible
            or seconds ~= state.preview_time
            or x ~= state.preview_x or y ~= state.preview_y
        state.preview_visible = true
        state.preview_time = seconds
        state.preview_x, state.preview_y = x, y
        state.preview_width, state.preview_height = thumbfast.width, thumbfast.height
        if not last_thumbnail_request
            or request.seconds ~= last_thumbnail_request.seconds
            or request.x ~= last_thumbnail_request.x
            or request.y ~= last_thumbnail_request.y then
            mp.commandv("script-message-to", "thumbfast", "thumb", seconds, x, y)
            last_thumbnail_request = request
        end
        thumbnail_active = true
    else
        preview_cleared = clear_thumbnail()
    end

    if state.hover_target ~= hover_target then
        state.hover_target = hover_target
        render()
    elseif zone_changed or preview_changed or preview_cleared then
        render()
    end
end

local function handle_mouse_click(event)
    if event and event.event == "up" then
        local was_timeline_drag = active_drag == "timeline"
        active_drag = nil
        note_activity()
        if opts.minimal_timeline == true and was_timeline_drag then render() end
        return
    end
    if not state.visible or type(mp.get_mouse_pos) ~= "function" then return end
    note_activity()

    local mouse_x, mouse_y = mp.get_mouse_pos()
    if not finite_number(mouse_x) or not finite_number(mouse_y) then return end

    local width, height = mp.get_osd_size()
    local layout = get_layout(width, height)
    if not layout then return end

    local volume = layout.volume
    local volume_hit = volume.hit
    local timeline = layout.timeline

    if event and event.event == "down" then
        -- A new press replaces any previous drag, so the two interactions
        -- can never become active together.
        active_drag = nil
        if contains(volume_hit, mouse_x, mouse_y) then
            active_drag = "volume"
            set_volume_at(mouse_x, volume.track)
            return
        end
        if contains_timeline(timeline, mouse_x, mouse_y) then
            if state.duration > 0 then
                active_drag = "timeline"
                if opts.minimal_timeline == true then render() end
                if not seek_chapter_marker(mouse_x, timeline) then
                    seek_at(mouse_x, timeline)
                end
            end
            return
        end
    end

    if contains_timeline(timeline, mouse_x, mouse_y) then
        if opts.minimal_timeline == true and state.hover_target ~= "timeline" then
            state.hover_target = "timeline"
            render()
        end
        if state.duration > 0 and not seek_chapter_marker(mouse_x, timeline) then
            seek_at(mouse_x, timeline)
        end
        return
    end

    local playback = layout.playback
    if mouse_x >= playback.x and mouse_x <= playback.x + playback.width
        and mouse_y >= playback.y and mouse_y <= playback.y + playback.height then
        mp.commandv("cycle", "pause")
        return
    end

    local playlist = layout.playlist
    if has_playlist_navigation() and mouse_x >= playlist.x
        and mouse_x <= playlist.x + playlist.width
        and mouse_y >= playlist.y and mouse_y <= playlist.y + playlist.height then
        if mouse_x < playlist.x + playlist.width / 2 then
            mp.commandv("playlist-prev", "weak")
        else
            mp.commandv("playlist-next", "weak")
        end
        return
    end

    if contains(volume_hit, mouse_x, mouse_y) then
        set_volume_at(mouse_x, volume.track)
    end
end

-- Ignore invalid numeric property values instead of letting NaN or infinity
-- leak into interaction math or state used by the renderer.
local function finite_property(value, fallback)
    if type(value) ~= "number" or value ~= value
        or value == math.huge or value == -math.huge then
        return fallback
    end
    return value
end

-- Keep the chapter title in sync with mpv's zero-based chapter index and metadata.
local function update_chapter_title()
    local index = finite_property(state.chapter, -1)
    local chapters = state.chapter_list
    local chapter = type(chapters) == "table" and chapters[math.floor(index) + 1] or nil
    state.chapter_title = type(chapter) == "table" and type(chapter.title) == "string"
        and chapter.title or ""
end

local function describe_track(track)
    local parts = {}
    for _, field in ipairs({ "lang", "title", "codec" }) do
        local value = track[field]
        if type(value) == "string" then
            value = value:match("^%s*(.-)%s*$")
            if value ~= "" then parts[#parts + 1] = value end
        end
    end
    if #parts == 0 and track.id ~= nil then
        parts[#parts + 1] = "Track " .. tostring(track.id)
    end
    return table.concat(parts, " ")
end

local function update_playlist_state(value)
    clear_track_menu()
    local items = {}
    if type(value) == "table" then
        for index, item in ipairs(value) do
            if type(item) == "table" then
                local title = type(item.title) == "string" and item.title or ""
                if title == "" and type(item.filename) == "string" then
                    title = item.filename:match("([^/\\]+)$") or item.filename
                end
                title = title:gsub("[%c{}]", " "):gsub("\\", " "):gsub("%s+", " ")
                    :match("^%s*(.-)%s*$")
                if title == "" then title = "Playlist item " .. index end
                items[#items + 1] = {
                    title = title:sub(1, 120),
                    filename = type(item.filename) == "string" and item.filename or "",
                    current = item.current == true or item.playing == true,
                }
            end
        end
    end
    state.playlist_items = items
    state.playlist_count = #items
end

local function update_track_state(value)
    clear_track_menu()
    local audio_tracks, subtitle_tracks = {}, {}
    local audio_label, subtitle_label = "", "Off"
    local image_mode = false
    if type(value) == "table" then
        for _, track in ipairs(value) do
            if type(track) == "table" then
                if track.type == "video" and track.selected == true
                    and (track.image == true or track.albumart == true) then
                    image_mode = true
                end
                if track.id ~= nil then
                    local entry = {
                        id = track.id,
                        label = describe_track(track),
                        selected = track.selected == true,
                    }
                    if track.type == "audio" then
                        audio_tracks[#audio_tracks + 1] = entry
                        if entry.selected then audio_label = entry.label end
                    elseif track.type == "sub" then
                        subtitle_tracks[#subtitle_tracks + 1] = entry
                        if entry.selected then subtitle_label = entry.label end
                    end
                end
            end
        end
    end
    state.audio_tracks = audio_tracks
    state.audio_track_count = #audio_tracks
    state.audio_track_label = audio_label
    state.subtitle_tracks = subtitle_tracks
    state.subtitle_track_count = #subtitle_tracks
    state.subtitle_track_label = subtitle_label
    state.image_mode = image_mode
end

local function refresh_audio_device_menu()
    if active_track_menu and active_track_menu.kind == "audio-device"
        and type(open_audio_device_menu) == "function" then
        open_audio_device_menu(active_track_menu.offset)
    end
end

local function update_audio_device_list(value)
    local devices = {}
    if type(value) == "table" then
        for _, device in ipairs(value) do
            if type(device) == "table" and type(device.name) == "string" then
                local name = device.name:match("^%s*(.-)%s*$")
                if name ~= "" and #name <= 512 and not name:find("[%c]") then
                    local label = type(device.description) == "string"
                        and device.description or ""
                    label = label:gsub("[%c{}]", " "):gsub("\\", " ")
                        :gsub("%s+", " "):match("^%s*(.-)%s*$")
                    if label == "" then label = name end
                    devices[#devices + 1] = {
                        id = name,
                        label = label:sub(1, 120),
                        selected = name == state.audio_device,
                    }
                end
            end
        end
    end
    state.audio_devices = devices
    refresh_audio_device_menu()
end

local function update_audio_device(value)
    state.audio_device = type(value) == "string" and value or "auto"
    for _, device in ipairs(state.audio_devices) do
        device.selected = device.id == state.audio_device
    end
    refresh_audio_device_menu()
end

-- Playback properties update the shared state and invalidate the renderer.
local observers = {
    { "pause", "bool", function(value) state.paused = value == true end },
    { "time-pos", "number", function(value) state.time_pos = finite_property(value, 0) end },
    { "duration", "number", function(value) state.duration = math.max(0, finite_property(value, 0)) end },
    { "media-title", "string", function(value) state.title = type(value) == "string" and value or "" end },
    { "volume", "number", function(value) state.volume = math.max(0, math.min(100, finite_property(value, 100))) end },
    { "speed", "number", function(value) state.speed = math.max(0.01, math.min(100, finite_property(value, 1))) end },
    { "loop-file", "string", function(value) state.loop_file = type(value) == "string" and value or "no" end },
    { "ab-loop-a", "number", function(value) state.ab_loop_a = finite_property(value, -1) end },
    { "ab-loop-b", "number", function(value) state.ab_loop_b = finite_property(value, -1) end },
    { "mute", "bool", function(value) state.mute = value == true end },
    { "paused-for-cache", "bool", function(value) state.buffering = value == true end },
    { "cache-buffering-state", "number", function(value)
        state.buffering_progress = math.max(0, math.min(100, finite_property(value, 0)))
    end },
    { "playlist-pos", "number", function(value) state.playlist_pos = finite_property(value, -1) end },
    { "playlist", "native", update_playlist_state },
    { "playlist-count", "number", function(value)
        if type(state.playlist_items) ~= "table" or #state.playlist_items == 0 then
            state.playlist_count = math.max(0, finite_property(value, 0))
        end
    end },
    { "chapter", "number", function(value)
        state.chapter = finite_property(value, -1)
        update_chapter_title()
    end },
    { "chapter-list", "native", function(value)
        local chapters = {}
        if type(value) == "table" then
            for _, item in ipairs(value) do
                if type(item) == "table" then
                    chapters[#chapters + 1] = {
                        title = type(item.title) == "string" and item.title or "",
                        time = finite_property(item.time, 0),
                    }
                end
            end
        end
        state.chapter_list = chapters
        update_chapter_title()
    end },
    { "track-list", "native", update_track_state },
    { "video-zoom", "number", function(value) state.image_zoom = finite_property(value, 0) end },
    { "audio-device-list", "native", update_audio_device_list },
    { "audio-device", "string", update_audio_device },
}

for _, observer in ipairs(observers) do
    local property, property_type, apply = observer[1], observer[2], observer[3]
    mp.observe_property(property, property_type, function(_, value)
        apply(value)
        -- Invalidate the pointer cache only when a property can change
        -- hit-test eligibility. Playback position and presentation-only state
        -- updates must not turn a stationary pointer into repeated hit-test work.
        if property == "duration" or property == "playlist"
            or property == "playlist-count" then
            last_mouse_x, last_mouse_y = nil, nil
        end
        if property ~= "time-pos" then
            log_debug("property " .. property .. " updated")
        end
        if property == "time-pos" then
            update_recent_progress(false)
            request_time_pos_render()
        else
            render()
        end
    end)
end

mp.register_event("file-loaded", function()
    log_debug("file loaded")
    clear_interaction_state()
    clear_thumbnail()
    record_recent_file()
    show_osd()
end)

mp.register_event("end-file", function()
    log_debug("file ended")
    if flush_recent_progress then flush_recent_progress(true) end
    current_history_path = nil
    resume_prompt_path, resume_prompt_position = nil, nil
    hide_osd()
end)

-- mpv emits shutdown before terminating Lua script event loops.
mp.register_event("shutdown", cleanup_on_shutdown)

mp.register_event("video-reconfig", function()
    last_mouse_x, last_mouse_y = nil, nil
    if active_playlist_menu and refresh_playlist_menu then
        refresh_playlist_menu()
    elseif active_recent_menu and refresh_recent_menu then
        refresh_recent_menu()
    else
        render()
    end
end)
mp.observe_property("osd-dimensions", "native", function()
    last_mouse_x, last_mouse_y = nil, nil
    if active_playlist_menu and refresh_playlist_menu then
        refresh_playlist_menu()
    elseif active_recent_menu and refresh_recent_menu then
        refresh_recent_menu()
    else
        render()
    end
end)

local function remove_last_utf8_character(value)
    local index = #value
    while index > 0 do
        local byte = value:byte(index)
        if byte < 0x80 or byte >= 0xC0 then
            return value:sub(1, index - 1)
        end
        index = index - 1
    end
    return ""
end

local function playlist_search_source_index(menu)
    local selected = menu and menu.results[menu.selected_index]
    return selected and selected.index or nil
end

open_playlist_menu = function(offset, query, selected_source_index)
    clear_track_menu()
    local items = type(state.playlist_items) == "table" and state.playlist_items or {}
    if #items == 0 then
        mp.commandv("show-text", tr("playlist_empty", "Adwisp: the playlist is empty."), 2500)
        return
    end

    query = type(query) == "string" and query or ""
    local results = MenuFilter.filter(items, query, { "title", "filename" })
    local _, osd_height = mp.get_osd_size()
    osd_height = finite_property(osd_height, 720)
    local page_size = math.max(1, math.min(9, math.floor((osd_height - 40) / 22)))
    local selected_index = 0
    if #results > 0 then
        if type(selected_source_index) == "number" then
            for index, result in ipairs(results) do
                if result.index == selected_source_index then
                    selected_index = index
                    break
                end
            end
        end
        if selected_index == 0 then
            for index, result in ipairs(results) do
                if result.item.current or result.index - 1 == state.playlist_pos then
                    selected_index = index
                    break
                end
            end
        end
        if selected_index == 0 then selected_index = 1 end
    end

    local max_offset = math.max(0, math.floor((#results - 1) / page_size) * page_size)
    offset = math.max(0, math.min(max_offset, math.floor(finite_property(offset, 0))))
    if selected_index > 0 and (selected_index <= offset or selected_index > offset + page_size) then
        offset = math.floor((selected_index - 1) / page_size) * page_size
    end
    local first = #results > 0 and offset + 1 or 1
    local last = #results > 0 and math.min(#results, first + page_size - 1) or 0
    local safe_query = query:gsub("[%c{}]", " "):gsub("\\", " ")
        :gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    local search_line = safe_query == "" and tr("search_prompt", "Search: type to filter")
        or tr_format("search_query", "Search: %s", safe_query)
    local lines
    if #results == 0 then
        lines = {
            tr_format("playlist_empty_header", "Playlist  0 / 0 matches (%d items)", #items),
            search_line,
            tr("playlist_no_matches", "No matching playlist items"),
            tr("search_clear_hint", "Ctrl+Backspace clears search; Esc closes"),
        }
    else
        lines = {
            tr_format("playlist_header", "Playlist  %d–%d / %d", first, last, #results),
            search_line,
            tr("menu_navigation_hint", "Up/Down move; Enter selects; Ctrl+Backspace clears"),
        }
    end
    active_playlist_menu = {
        items = items,
        results = results,
        offset = offset,
        query = query,
        selected_index = selected_index,
    }

    for index = first, last do
        local result = results[index]
        local item = result.item
        local local_index = index - offset
        local current_marker = (item.current or result.index - 1 == state.playlist_pos)
            and ">" or " "
        local focus_marker = index == selected_index and "*" or " "
        lines[#lines + 1] = string.format("%d. %s%s %s",
            local_index, current_marker, focus_marker, item.title)

        local filtered_index = index
        local select_name = "adwisp-playlist-menu-select-" .. local_index
        track_menu_binding_names[#track_menu_binding_names + 1] = select_name
        mp.add_key_binding("CTRL+ALT+" .. local_index, select_name, function()
            local menu = active_playlist_menu
            local selected = menu and menu.results[filtered_index]
            if not selected then return end
            note_activity()
            clear_track_menu()
            mp.commandv("set", "playlist-pos", selected.index - 1)
            mp.commandv("show-text", tr_format("playlist_playing", "Adwisp: playing %s", selected.item.title), 2500)
        end)

        local remove_name = "adwisp-playlist-menu-remove-" .. local_index
        track_menu_binding_names[#track_menu_binding_names + 1] = remove_name
        mp.add_key_binding("CTRL+ALT+SHIFT+" .. local_index, remove_name, function()
            local menu = active_playlist_menu
            local selected = menu and menu.results[filtered_index]
            if not selected then return end
            note_activity()
            clear_track_menu()
            mp.commandv("playlist-remove", selected.index - 1)
            mp.commandv("show-text", tr_format("playlist_removed", "Adwisp: removed %s", selected.item.title), 2500)
        end)
    end

    if offset > 0 then
        local previous_name = "adwisp-playlist-menu-previous"
        track_menu_binding_names[#track_menu_binding_names + 1] = previous_name
        mp.add_key_binding("CTRL+ALT+PGUP", previous_name, function()
            local target = results[math.max(1, first - page_size)]
            open_playlist_menu(0, query, target and target.index)
        end)
    end
    if last < #results then
        local next_name = "adwisp-playlist-menu-next"
        track_menu_binding_names[#track_menu_binding_names + 1] = next_name
        mp.add_key_binding("CTRL+ALT+PGDWN", next_name, function()
            local target = results[last + 1]
            open_playlist_menu(0, query, target and target.index)
        end)
    end

    local function add_search_binding(key, name, callback)
        if type(mp.add_forced_key_binding) ~= "function" then
            return false
        end
        local ok, err = pcall(mp.add_forced_key_binding, key, name, callback, { complex = true })
        if not ok then
            mp.msg.warn("Adwisp: unable to register playlist menu key " .. key
                .. ": " .. tostring(err))
            return false
        end
        track_menu_binding_names[#track_menu_binding_names + 1] = name
        return true
    end
    local function current_source_index()
        return playlist_search_source_index(active_playlist_menu)
    end
    local function update_search(next_query)
        local source_index
        if next_query ~= "" then source_index = current_source_index() end
        open_playlist_menu(0, next_query, source_index)
    end
    local function is_key_down(event)
        return type(event) == "table" and event.event == "down"
    end

    add_search_binding("WHEEL_UP", "adwisp-playlist-menu-wheel-up", function(event)
        if not is_key_down(event) then return end
        local menu = active_playlist_menu
        if not menu or #menu.results == 0 then return end
        local index = math.max(1, menu.selected_index - 1)
        if index ~= menu.selected_index then
            open_playlist_menu(0, menu.query, menu.results[index].index)
        end
    end)
    add_search_binding("WHEEL_DOWN", "adwisp-playlist-menu-wheel-down", function(event)
        if not is_key_down(event) then return end
        local menu = active_playlist_menu
        if not menu or #menu.results == 0 then return end
        local index = math.min(#menu.results, menu.selected_index + 1)
        if index ~= menu.selected_index then
            open_playlist_menu(0, menu.query, menu.results[index].index)
        end
    end)

    local text_input_available = add_search_binding(
        "ANY_UNICODE", "adwisp-playlist-menu-search-input", function(event)
        if not is_key_down(event) then return end
        local key_name = type(event.key_name) == "string" and event.key_name:upper() or ""
        if key_name:find("CTRL", 1, true) or key_name:find("ALT", 1, true)
            or key_name:find("META", 1, true) then
            return
        end
        if type(event.key_text) == "string" and event.key_text ~= "" then
            local menu = active_playlist_menu
            if menu then update_search(menu.query .. event.key_text) end
        end
    end)
    add_search_binding("BS", "adwisp-playlist-menu-search-backspace", function(event)
        if not is_key_down(event) then return end
        local menu = active_playlist_menu
        if menu then update_search(remove_last_utf8_character(menu.query)) end
    end)
    add_search_binding("CTRL+BACKSPACE", "adwisp-playlist-menu-search-clear", function(event)
        if is_key_down(event) then open_playlist_menu(0, "", nil) end
    end)
    add_search_binding("ESC", "adwisp-playlist-menu-search-escape", function(event)
        if not is_key_down(event) then return end
        clear_track_menu()
        mp.commandv("show-text", "", 0)
    end)
    add_search_binding("ENTER", "adwisp-playlist-menu-search-enter", function(event)
        if not is_key_down(event) then return end
        local menu = active_playlist_menu
        local selected = menu and menu.results[menu.selected_index]
        if not selected then return end
        note_activity()
        clear_track_menu()
        mp.commandv("set", "playlist-pos", selected.index - 1)
        mp.commandv("show-text", tr_format("playlist_playing", "Adwisp: playing %s", selected.item.title), 2500)
    end)
    add_search_binding("UP", "adwisp-playlist-menu-search-up", function(event)
        if not is_key_down(event) then return end
        local menu = active_playlist_menu
        if not menu or #menu.results == 0 then return end
        local index = math.max(1, menu.selected_index - 1)
        open_playlist_menu(0, menu.query, menu.results[index].index)
    end)
    add_search_binding("DOWN", "adwisp-playlist-menu-search-down", function(event)
        if not is_key_down(event) then return end
        local menu = active_playlist_menu
        if not menu or #menu.results == 0 then return end
        local index = math.min(#menu.results, menu.selected_index + 1)
        open_playlist_menu(0, menu.query, menu.results[index].index)
    end)
    if not text_input_available then
        lines[#lines + 1] = tr("filter_unavailable", "Text filtering is unavailable on this mpv build")
    end

    if not state.visible then show_osd() end
    state.playlist_menu = {
        lines = lines,
        page_size = page_size,
        offset = offset,
        result_count = #results,
    }
    track_menu_timer = nil
    note_activity()
    render()
end


refresh_playlist_menu = function()
    local menu = active_playlist_menu
    if not menu then
        render()
        return
    end
    local selected = menu.results[menu.selected_index]
    open_playlist_menu(menu.offset, menu.query, selected and selected.index)
end


open_recent_menu = function(offset, selected_index, continue_only)
    clear_track_menu()
    if not opts.recent_history then
        mp.commandv("show-text",
            tr("recent_disabled", "Adwisp: recent history is disabled; set recent_history=yes to enable it."), 3500)
        return
    end
    if #recent_items == 0 then
        mp.commandv("show-text", tr("recent_empty", "Adwisp: no recent local files yet."), 2500)
        return
    end
    if not state.visible then show_osd() end

    local items = {}
    for _, item in ipairs(recent_items) do
        if not continue_only or RecentHistory.resume_position(item) then
            items[#items + 1] = item
        end
    end
    if #items == 0 then
        local message = continue_only and "Adwisp: nothing to continue watching."
            or tr("recent_empty", "Adwisp: no recent local files yet.")
        mp.commandv("show-text", message, 2500)
        return
    end
    local _, osd_height = mp.get_osd_size()
    osd_height = finite_property(osd_height, 720)
    local page_size = math.max(1, math.min(9, math.floor((osd_height - 40) / 22)))
    local current_path = resolve_recent_path(mp.get_property("path"))
    if type(selected_index) ~= "number" then
        selected_index = 1
        for index, item in ipairs(items) do
            if item.path == current_path then
                selected_index = index
                break
            end
        end
    end
    selected_index = math.max(1, math.min(#items, math.floor(selected_index)))
    local max_offset = math.max(0, math.floor((#items - 1) / page_size) * page_size)
    offset = math.max(0, math.min(max_offset, math.floor(finite_property(offset, 0))))
    if selected_index <= offset or selected_index > offset + page_size then
        offset = math.floor((selected_index - 1) / page_size) * page_size
    end
    local first = offset + 1
    local last = math.min(#items, first + page_size - 1)
    local lines = {
        continue_only and tr_format("continue_header", "Continue watching  %d–%d / %d", first, last, #items)
            or tr_format("recent_header", "Recently played  %d–%d / %d", first, last, #items),
        tr("recent_navigation_hint", "Wheel or Up/Down moves; Enter opens; Esc closes"),
        tr("recent_clear_hint", "Ctrl+Alt+Shift+F3 clears local history"),
    }

    active_recent_menu = {
        items = items,
        offset = offset,
        page_size = page_size,
        selected_index = selected_index,
        continue_only = continue_only == true,
    }

    local function add_recent_binding(key, name, callback, forced)
        track_menu_binding_names[#track_menu_binding_names + 1] = name
        local ok
        if forced then
            ok = pcall(mp.add_forced_key_binding, key, name, callback, { complex = true })
        else
            ok = pcall(mp.add_key_binding, key, name, callback)
        end
        if not ok then
            table.remove(track_menu_binding_names)
            log_debug("could not register temporary recent-menu binding " .. name)
        end
    end

    local function select_recent_item(index)
        local menu = active_recent_menu
        local selected = menu and menu.items[index]
        if not selected then return end
        local ok_info, info = pcall(utils.file_info, selected.path)
        if not ok_info or type(info) ~= "table" or info.is_file ~= true then
            mp.commandv("show-text", "Adwisp: this recent file is unavailable.", 2500)
            return
        end
        note_activity()
        clear_track_menu()
        mp.commandv("loadfile", selected.path, "replace")
    end

    for index = first, last do
        local item = items[index]
        local local_index = index - offset
        local current_marker = item.path == current_path and ">" or " "
        local focus_marker = index == selected_index and "*" or " "
        local resume = RecentHistory.resume_position(item)
        local resume_label = continue_only and resume
            and (" · " .. format_resume_time(resume)) or ""
        lines[#lines + 1] = string.format("%d. %s%s %s%s",
            local_index, current_marker, focus_marker, item.title, resume_label)
        local binding_name = "adwisp-recent-menu-select-" .. local_index
        local selected_index_for_binding = index
        add_recent_binding("CTRL+ALT+" .. local_index, binding_name, function()
            select_recent_item(selected_index_for_binding)
        end, false)
    end

    if offset > 0 then
        add_recent_binding("CTRL+ALT+PGUP", "adwisp-recent-menu-previous", function()
            open_recent_menu(0, math.max(1, first - page_size), continue_only)
        end, true)
    end
    if last < #items then
        add_recent_binding("CTRL+ALT+PGDWN", "adwisp-recent-menu-next", function()
            open_recent_menu(0, math.min(#items, last + 1), continue_only)
        end, true)
    end

    local function move_selection(delta)
        local menu = active_recent_menu
        if not menu then return end
        local index = math.max(1, math.min(#menu.items, menu.selected_index + delta))
        if index ~= menu.selected_index then open_recent_menu(0, index, continue_only) end
    end
    add_recent_binding("WHEEL_UP", "adwisp-recent-menu-wheel-up", function(event)
        if type(event) == "table" and event.event == "down" then move_selection(-1) end
    end, true)
    add_recent_binding("WHEEL_DOWN", "adwisp-recent-menu-wheel-down", function(event)
        if type(event) == "table" and event.event == "down" then move_selection(1) end
    end, true)
    add_recent_binding("UP", "adwisp-recent-menu-up", function(event)
        if type(event) == "table" and event.event == "down" then move_selection(-1) end
    end, true)
    add_recent_binding("DOWN", "adwisp-recent-menu-down", function(event)
        if type(event) == "table" and event.event == "down" then move_selection(1) end
    end, true)
    add_recent_binding("ENTER", "adwisp-recent-menu-enter", function(event)
        if type(event) == "table" and event.event == "down" then
            local menu = active_recent_menu
            if menu then select_recent_item(menu.selected_index) end
        end
    end, true)
    add_recent_binding("ESC", "adwisp-recent-menu-escape", function(event)
        if type(event) == "table" and event.event == "down" then clear_track_menu() end
    end, true)

    state.recent_menu = {
        lines = lines,
        page_size = page_size,
        offset = offset,
        result_count = #items,
    }
    track_menu_timer = nil
    note_activity()
    render()
end

refresh_recent_menu = function()
    local menu = active_recent_menu
    if not menu then
        render()
        return
    end
    open_recent_menu(menu.offset, menu.selected_index, menu.continue_only)
end

local function clear_recent_history()
    if not opts.recent_history then
        mp.commandv("show-text",
            tr("recent_disabled", "Adwisp: recent history is disabled; set recent_history=yes to enable it."), 3500)
        return
    end
    recent_items = {}
    cancel_recent_progress_timer()
    recent_progress_dirty = false
    resume_prompt_path, resume_prompt_position = nil, nil
    local cleared = RecentHistory.clear(recent_history_path, history_dependencies)
    if active_recent_menu then clear_track_menu() end
    if not cleared then
        mp.msg.warn(tr("recent_clear_failed", "Adwisp: could not clear local recent-file history."))
    else
        mp.commandv("show-text", tr("recent_cleared", "Adwisp: recent history cleared."), 2500)
    end
end

local function open_track_menu(kind, query, selected_source_id)
    if close_library_menu then close_library_menu(true) end
    clear_track_menu()
    local tracks = kind == "audio" and state.audio_tracks or state.subtitle_tracks
    if type(tracks) ~= "table" or #tracks == 0 then
        mp.commandv("show-text", tr_format("no_tracks_available", "Adwisp: no %s tracks are available.", kind), 2500)
        return
    end

    local items = {}
    if kind == "subtitle" then
        items[#items + 1] = {
            id = "no",
            label = tr("off", "Off"),
            selected = state.subtitle_track_label == "Off",
        }
    end
    for _, track in ipairs(tracks) do
        items[#items + 1] = track
    end

    query = type(query) == "string" and query or ""
    local results = MenuFilter.filter(items, query, { "label" })
    local selected_index = 0
    if #results > 0 then
        if selected_source_id ~= nil then
            for index, result in ipairs(results) do
                if result.item.id == selected_source_id then
                    selected_index = index
                    break
                end
            end
        end
        if selected_index == 0 then
            for index, result in ipairs(results) do
                if result.item.selected then
                    selected_index = index
                    break
                end
            end
        end
        if selected_index == 0 then selected_index = 1 end
    end

    local title = kind == "audio" and tr("audio_tracks", "Audio tracks") or tr("subtitle_tracks", "Subtitle tracks")
    local safe_query = query:gsub("[%c{}]", " "):gsub("\\", " ")
        :gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    local search_line = safe_query == "" and tr("search_prompt", "Search: type to filter")
        or tr_format("search_query", "Search: %s", safe_query)
    local lines = { title, search_line }
    if #results == 0 then
        lines[#lines + 1] = tr_format("no_matching_tracks", "No matching %s tracks", kind)
        lines[#lines + 1] = tr("search_clear_hint", "Ctrl+Backspace clears search; Esc closes")
    else
        lines[#lines + 1] = tr("menu_navigation_hint", "Up/Down move; Enter selects; Ctrl+Backspace clears")
    end

    local property = kind == "audio" and "aid" or "sid"
    active_track_menu = {
        kind = kind,
        property = property,
        items = items,
        results = results,
        query = query,
        selected_index = selected_index,
    }

    for index, result in ipairs(results) do
        local item = result.item
        local marker = item.selected and ">" or " "
        local focus_marker = index == selected_index and "*" or " "
        lines[#lines + 1] = string.format("%d. %s%s %s", index, marker, focus_marker, item.label)
        if index <= 9 then
            local filtered_index = index
            local binding_name = "adwisp-track-menu-select-" .. index
            track_menu_binding_names[#track_menu_binding_names + 1] = binding_name
            mp.add_key_binding("CTRL+ALT+" .. index, binding_name, function()
                local menu = active_track_menu
                local selected = menu and menu.kind == kind and menu.results[filtered_index]
                if not selected then return end
                note_activity()
                mp.commandv("set", menu.property, selected.item.id)
                clear_track_menu()
                mp.commandv("show-text", tr_format("track_selected", "Adwisp: selected %s", selected.item.label), 2500)
            end)
        end
    end

    local function add_search_binding(key, name, callback)
        if type(mp.add_forced_key_binding) ~= "function" then return false end
        local ok, err = pcall(mp.add_forced_key_binding, key, name, callback, { complex = true })
        if not ok then
            mp.msg.warn("Adwisp: unable to register track menu key " .. key .. ": " .. tostring(err))
            return false
        end
        track_menu_binding_names[#track_menu_binding_names + 1] = name
        return true
    end
    local function current_source_id()
        local menu = active_track_menu
        local selected = menu and menu.results[menu.selected_index]
        return selected and selected.item.id or nil
    end
    local function update_search(next_query)
        local source_id
        if next_query ~= "" then source_id = current_source_id() end
        open_track_menu(kind, next_query, source_id)
    end
    local function is_key_down(event)
        return type(event) == "table" and event.event == "down"
    end

    local text_input_available = add_search_binding(
        "ANY_UNICODE", "adwisp-track-menu-search-input", function(event)
            if not is_key_down(event) then return end
            local key_name = type(event.key_name) == "string" and event.key_name:upper() or ""
            if key_name:find("CTRL", 1, true) or key_name:find("ALT", 1, true)
                or key_name:find("META", 1, true) then
                return
            end
            if type(event.key_text) == "string" and event.key_text ~= "" then
                local menu = active_track_menu
                if menu then update_search(menu.query .. event.key_text) end
            end
        end)
    add_search_binding("BS", "adwisp-track-menu-search-backspace", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        if menu then update_search(remove_last_utf8_character(menu.query)) end
    end)
    add_search_binding("CTRL+BACKSPACE", "adwisp-track-menu-search-clear", function(event)
        if is_key_down(event) then open_track_menu(kind, "", nil) end
    end)
    add_search_binding("ESC", "adwisp-track-menu-search-escape", function(event)
        if not is_key_down(event) then return end
        clear_track_menu()
        mp.commandv("show-text", "", 0)
    end)
    add_search_binding("ENTER", "adwisp-track-menu-search-enter", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        local selected = menu and menu.kind == kind and menu.results[menu.selected_index]
        if not selected then return end
        note_activity()
        mp.commandv("set", menu.property, selected.item.id)
        clear_track_menu()
        mp.commandv("show-text", "Adwisp: selected " .. selected.item.label, 2500)
    end)
    add_search_binding("UP", "adwisp-track-menu-search-up", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        if not menu or menu.kind ~= kind or #menu.results == 0 then return end
        local index = math.max(1, menu.selected_index - 1)
        open_track_menu(kind, menu.query, menu.results[index].item.id)
    end)
    add_search_binding("DOWN", "adwisp-track-menu-search-down", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        if not menu or menu.kind ~= kind or #menu.results == 0 then return end
        local index = math.min(#menu.results, menu.selected_index + 1)
        open_track_menu(kind, menu.query, menu.results[index].item.id)
    end)
    if not text_input_available then
        lines[#lines + 1] = tr("filter_unavailable", "Text filtering is unavailable on this mpv build")
    end

    track_menu_timer = mp.add_timeout(8, clear_track_menu)
    note_activity()
    mp.commandv("show-text", table.concat(lines, "\n"), 8000)
end

open_audio_device_menu = function(offset)
    clear_track_menu()
    local devices = type(state.audio_devices) == "table" and state.audio_devices or {}
    if #devices == 0 then
        mp.commandv("show-text", tr("no_audio_devices", "Adwisp: no audio output devices are available."), 2500)
        return
    end

    local page_size = 9
    local max_offset = math.max(0, math.floor((#devices - 1) / page_size) * page_size)
    offset = math.max(0, math.min(max_offset, math.floor(finite_property(offset, 0))))
    local first = offset + 1
    local last = math.min(#devices, first + page_size - 1)
    local lines = { tr_format("audio_devices_header", "Audio output devices  %d–%d / %d", first, last, #devices) }
    local current_found = false
    active_track_menu = {
        kind = "audio-device",
        property = "audio-device",
        items = {},
        offset = offset,
    }

    for index = first, last do
        local device = devices[index]
        local item = {
            id = device.id,
            label = device.label,
            selected = device.id == state.audio_device,
        }
        if item.selected then current_found = true end
        active_track_menu.items[#active_track_menu.items + 1] = item
        local local_index = index - offset
        local marker = item.selected and ">" or " "
        lines[#lines + 1] = string.format("%d. %s %s", local_index, marker, item.label)

        local binding_name = "adwisp-audio-device-select-" .. local_index
        track_menu_binding_names[#track_menu_binding_names + 1] = binding_name
        mp.add_key_binding("CTRL+ALT+" .. local_index, binding_name, function()
            local menu = active_track_menu
            local selected = menu and menu.items[local_index]
            if not selected or menu.kind ~= "audio-device" then return end
            note_activity()
            mp.commandv("set", "audio-device", selected.id)
            clear_track_menu()
            mp.commandv("show-text", tr_format("audio_device_requested", "Adwisp: requested audio output %s", selected.label), 2500)
        end)
    end

    if not current_found then
        lines[#lines + 1] = tr("audio_device_unavailable", "Configured output is not in the available device list.")
    end
    if offset > 0 then
        local previous_name = "adwisp-audio-device-menu-previous"
        track_menu_binding_names[#track_menu_binding_names + 1] = previous_name
        mp.add_key_binding("CTRL+ALT+PGUP", previous_name, function()
            open_audio_device_menu(offset - page_size)
        end)
    end
    if last < #devices then
        local next_name = "adwisp-audio-device-menu-next"
        track_menu_binding_names[#track_menu_binding_names + 1] = next_name
        mp.add_key_binding("CTRL+ALT+PGDWN", next_name, function()
            open_audio_device_menu(offset + page_size)
        end)
    end

    track_menu_timer = mp.add_timeout(8, clear_track_menu)
    note_activity()
    mp.commandv("show-text", table.concat(lines, "\n"), 8000)
end

local function chapter_timestamp(value)
    local seconds = math.max(0, math.floor(finite_property(value, 0)))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local remainder = seconds % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remainder)
    end
    return string.format("%02d:%02d", minutes, remainder)
end

local function open_chapter_menu(offset, query, selected_source_index)
    clear_track_menu()
    local chapters = type(state.chapter_list) == "table" and state.chapter_list or {}
    if #chapters == 0 then
        mp.commandv("show-text", tr("no_chapters", "Adwisp: this media has no chapters."), 2500)
        return
    end

    query = type(query) == "string" and query or ""
    local results = MenuFilter.filter(chapters, query, { "title", "time" })
    local page_size = 9
    local current_index = math.floor(finite_property(state.chapter, -1)) + 1
    local selected_index = 0
    if #results > 0 then
        if type(selected_source_index) == "number" then
            for index, result in ipairs(results) do
                if result.index == selected_source_index then
                    selected_index = index
                    break
                end
            end
        end
        if selected_index == 0 then
            for index, result in ipairs(results) do
                if result.index == current_index then
                    selected_index = index
                    break
                end
            end
        end
        if selected_index == 0 then selected_index = 1 end
    end

    local max_offset = math.max(0, math.floor((#results - 1) / page_size) * page_size)
    offset = math.max(0, math.min(max_offset, math.floor(finite_property(offset, 0))))
    if selected_index > 0 and (selected_index <= offset or selected_index > offset + page_size) then
        offset = math.floor((selected_index - 1) / page_size) * page_size
    end
    local first = #results > 0 and offset + 1 or 1
    local last = #results > 0 and math.min(#results, first + page_size - 1) or 0
    local safe_query = query:gsub("[%c{}]", " "):gsub("\\", " ")
        :gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    local search_line = safe_query == "" and tr("search_prompt", "Search: type to filter")
        or tr_format("search_query", "Search: %s", safe_query)
    local lines = {
        tr_format("chapter_header", "Chapters  %d / %d", #results, #chapters),
        search_line,
    }
    if #results == 0 then
        lines[#lines + 1] = tr("no_matching_chapters", "No matching chapters")
        lines[#lines + 1] = tr("search_clear_hint", "Ctrl+Backspace clears search; Esc closes")
    else
        lines[#lines + 1] = tr("menu_navigation_hint", "Up/Down move; Enter selects; Ctrl+Backspace clears")
    end

    active_track_menu = {
        kind = "chapter",
        property = "chapter",
        items = chapters,
        results = results,
        query = query,
        selected_index = selected_index,
        offset = offset,
    }

    for index = first, last do
        local result = results[index]
        local chapter = result.item
        local title = type(chapter.title) == "string" and chapter.title or ""
        title = title:gsub("[%c{}]", " "):gsub("\\", " "):gsub("%s+", " ")
            :match("^%s*(.-)%s*$")
        if title == "" then title = "Chapter " .. result.index end
        title = title:sub(1, 100)
        local local_index = index - offset
        local current_marker = result.index == current_index and ">" or " "
        local focus_marker = index == selected_index and "*" or " "
        lines[#lines + 1] = string.format("%d. %s%s %s  %s",
            local_index, current_marker, focus_marker,
            chapter_timestamp(chapter.time), title)

        local filtered_index = index
        local binding_name = "adwisp-chapter-menu-select-" .. local_index
        track_menu_binding_names[#track_menu_binding_names + 1] = binding_name
        mp.add_key_binding("CTRL+ALT+" .. local_index, binding_name, function()
            local menu = active_track_menu
            local selected = menu and menu.kind == "chapter" and menu.results[filtered_index]
            if not selected then return end
            note_activity()
            mp.commandv("set", "chapter", selected.index - 1)
            clear_track_menu()
            mp.commandv("show-text", "Adwisp: selected chapter " .. selected.index, 2500)
        end)
    end

    if offset > 0 then
        local previous_name = "adwisp-chapter-menu-previous"
        track_menu_binding_names[#track_menu_binding_names + 1] = previous_name
        mp.add_key_binding("CTRL+ALT+PGUP", previous_name, function()
            local target = results[math.max(1, first - page_size)]
            open_chapter_menu(0, query, target and target.index)
        end)
    end
    if last < #results then
        local next_name = "adwisp-chapter-menu-next"
        track_menu_binding_names[#track_menu_binding_names + 1] = next_name
        mp.add_key_binding("CTRL+ALT+PGDWN", next_name, function()
            local target = results[last + 1]
            open_chapter_menu(0, query, target and target.index)
        end)
    end

    local function add_search_binding(key, name, callback)
        if type(mp.add_forced_key_binding) ~= "function" then return false end
        local ok, err = pcall(mp.add_forced_key_binding, key, name, callback, { complex = true })
        if not ok then
            mp.msg.warn("Adwisp: unable to register chapter menu key " .. key .. ": " .. tostring(err))
            return false
        end
        track_menu_binding_names[#track_menu_binding_names + 1] = name
        return true
    end
    local function current_source_index()
        local menu = active_track_menu
        local selected = menu and menu.kind == "chapter" and menu.results[menu.selected_index]
        return selected and selected.index or nil
    end
    local function update_search(next_query)
        local source_index
        if next_query ~= "" then source_index = current_source_index() end
        open_chapter_menu(0, next_query, source_index)
    end
    local function is_key_down(event)
        return type(event) == "table" and event.event == "down"
    end

    local text_input_available = add_search_binding(
        "ANY_UNICODE", "adwisp-chapter-menu-search-input", function(event)
            if not is_key_down(event) then return end
            local key_name = type(event.key_name) == "string" and event.key_name:upper() or ""
            if key_name:find("CTRL", 1, true) or key_name:find("ALT", 1, true)
                or key_name:find("META", 1, true) then
                return
            end
            if type(event.key_text) == "string" and event.key_text ~= "" then
                local menu = active_track_menu
                if menu and menu.kind == "chapter" then
                    update_search(menu.query .. event.key_text)
                end
            end
        end)
    add_search_binding("BS", "adwisp-chapter-menu-search-backspace", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        if menu and menu.kind == "chapter" then
            update_search(remove_last_utf8_character(menu.query))
        end
    end)
    add_search_binding("CTRL+BACKSPACE", "adwisp-chapter-menu-search-clear", function(event)
        if is_key_down(event) then open_chapter_menu(0, "", nil) end
    end)
    add_search_binding("ESC", "adwisp-chapter-menu-search-escape", function(event)
        if not is_key_down(event) then return end
        clear_track_menu()
        mp.commandv("show-text", "", 0)
    end)
    add_search_binding("ENTER", "adwisp-chapter-menu-search-enter", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        local selected = menu and menu.kind == "chapter" and menu.results[menu.selected_index]
        if not selected then return end
        note_activity()
        mp.commandv("set", "chapter", selected.index - 1)
        clear_track_menu()
        mp.commandv("show-text", "Adwisp: selected chapter " .. selected.index, 2500)
    end)
    add_search_binding("UP", "adwisp-chapter-menu-search-up", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        if not menu or menu.kind ~= "chapter" or #menu.results == 0 then return end
        local index = math.max(1, menu.selected_index - 1)
        open_chapter_menu(0, menu.query, menu.results[index].index)
    end)
    add_search_binding("DOWN", "adwisp-chapter-menu-search-down", function(event)
        if not is_key_down(event) then return end
        local menu = active_track_menu
        if not menu or menu.kind ~= "chapter" or #menu.results == 0 then return end
        local index = math.min(#menu.results, menu.selected_index + 1)
        open_chapter_menu(0, menu.query, menu.results[index].index)
    end)
    if not text_input_available then
        lines[#lines + 1] = tr("filter_unavailable", "Text filtering is unavailable on this mpv build")
    end

    track_menu_timer = mp.add_timeout(8, clear_track_menu)
    note_activity()
    mp.commandv("show-text", table.concat(lines, "\n"), 8000)
end

local function show_chapter_list()
    open_chapter_menu(0, "", nil)
end

local registered_key_bindings = {
    ["TAB"] = "adwisp-focus-next",
    ["SHIFT+TAB"] = "adwisp-focus-previous",
    ["ENTER"] = "adwisp-focus-activate",
    ["SPACE"] = "adwisp-play-pause",
    ["CTRL+ALT+UP"] = "adwisp-speed-up",
    ["CTRL+ALT+DOWN"] = "adwisp-speed-down",
    ["CTRL+ALT+BACKSPACE"] = "adwisp-speed-reset",
    ["CTRL+ALT+HOME"] = "adwisp-image-fit",
    ["CTRL+ALT+KP_ADD"] = "adwisp-image-zoom-in",
    ["CTRL+ALT+KP_SUBTRACT"] = "adwisp-image-zoom-out",
    ["CTRL+PGUP"] = "adwisp-chapter-prev",
    ["CTRL+PGDWN"] = "adwisp-chapter-next",
    ["CTRL+ALT+F2"] = "adwisp-library",
    ["CTRL+ALT+F3"] = "adwisp-recent-menu",
    ["CTRL+ALT+F4"] = "adwisp-settings",
    ["CTRL+ALT+SHIFT+F3"] = "adwisp-clear-recent",
    ["CTRL+ALT+F5"] = "adwisp-audio-cycle",
    ["CTRL+ALT+F6"] = "adwisp-subtitle-cycle",
    ["CTRL+ALT+F7"] = "adwisp-thumbnail-export",
    ["CTRL+ALT+F8"] = "adwisp-chapter-list",
    ["CTRL+ALT+F9"] = "adwisp-audio-device-menu",
    ["CTRL+ALT+F10"] = "adwisp-audio-menu",
    ["CTRL+ALT+F11"] = "adwisp-subtitle-menu",
    ["CTRL+ALT+F12"] = "adwisp-playlist-menu",
    ["CTRL+ALT+PGUP"] = "temporary playlist page-up",
    ["CTRL+ALT+PGDWN"] = "temporary playlist page-down",
}
for index = 1, 9 do
    registered_key_bindings["CTRL+ALT+" .. index] = "temporary menu selection"
    registered_key_bindings["CTRL+ALT+SHIFT+" .. index] = "temporary playlist removal"
end

local function register_configurable_key_binding(option_name, binding_name, callback, fallback)
    local key = opts[option_name]
    local invalid = type(key) ~= "string" or key:match("^%s*$") or #key > 64
    if invalid then key = fallback end

    local function try_register(candidate)
        if registered_key_bindings[candidate] then
            return false, "conflicts with " .. registered_key_bindings[candidate]
        end
        local ok, err = pcall(mp.add_key_binding, candidate, binding_name, callback)
        if not ok then return false, err end
        registered_key_bindings[candidate] = binding_name
        return true
    end

    local ok, reason = try_register(key)
    if not ok and key ~= fallback then
        local fallback_ok, fallback_reason = try_register(fallback)
        if fallback_ok then
            mp.msg.warn("Adwisp: " .. option_name .. " is invalid or conflicts ("
                .. tostring(reason) .. "); using " .. fallback .. ".")
            return
        end
        reason = tostring(reason) .. "; fallback failed: " .. tostring(fallback_reason)
    elseif not ok and invalid then
        mp.msg.warn("Adwisp: invalid " .. option_name .. "; fallback " .. fallback .. " is unavailable.")
        return
    end
    if not ok then
        mp.msg.warn("Adwisp: could not register " .. option_name .. ": " .. tostring(reason))
    elseif invalid then
        mp.msg.warn("Adwisp: invalid " .. option_name .. "; using " .. fallback .. ".")
    end
end

register_configurable_key_binding("toggle_key", "adwisp-toggle", toggle, "g")
register_configurable_key_binding("seek_back_key", "adwisp-seek-back", handle_left, "LEFT")
register_configurable_key_binding("seek_forward_key", "adwisp-seek-forward", handle_right, "RIGHT")
mp.add_key_binding("TAB", "adwisp-focus-next", function()
    cycle_focus(false)
end)
mp.add_key_binding("SHIFT+TAB", "adwisp-focus-previous", function()
    cycle_focus(true)
end)
mp.add_key_binding("ENTER", "adwisp-focus-activate", activate_focus)
register_configurable_key_binding("dismiss_key", "adwisp-dismiss", hide_osd, "q")
register_configurable_key_binding("dismiss_escape_key", "adwisp-dismiss-escape", hide_osd, "ESC")
mp.add_key_binding("SPACE", "adwisp-play-pause", function()
    note_activity()
    mp.commandv("cycle", "pause")
end)
register_configurable_key_binding("mute_toggle_key", "adwisp-mute-toggle", function()
    note_activity()
    mp.commandv("cycle", "mute")
end, "m")
register_configurable_key_binding("playlist_prev_key", "adwisp-playlist-prev", function()
    if has_playlist_navigation() then
        note_activity()
        mp.commandv("playlist-prev", "weak")
    end
end, "CTRL+LEFT")
register_configurable_key_binding("playlist_next_key", "adwisp-playlist-next", function()
    if has_playlist_navigation() then
        note_activity()
        mp.commandv("playlist-next", "weak")
    end
end, "CTRL+RIGHT")
mp.add_key_binding("CTRL+PGUP", "adwisp-chapter-prev", function()
    if #state.chapter_list > 0 then
        note_activity()
        mp.commandv("add", "chapter", -1)
    end
end)
mp.add_key_binding("CTRL+PGDWN", "adwisp-chapter-next", function()
    if #state.chapter_list > 0 then
        note_activity()
        mp.commandv("add", "chapter", 1)
    end
end)
mp.add_key_binding("CTRL+ALT+F8", "adwisp-chapter-list", show_chapter_list)
mp.add_key_binding("CTRL+ALT+F9", "adwisp-audio-device-menu", function()
    open_audio_device_menu(0)
end)
mp.add_key_binding("CTRL+ALT+F5", "adwisp-audio-cycle", function()
    if state.audio_track_count > 1 then
        note_activity()
        mp.commandv("cycle", "audio")
    end
end)
mp.add_key_binding("CTRL+ALT+F6", "adwisp-subtitle-cycle", function()
    if state.subtitle_track_count > 0 then
        note_activity()
        mp.commandv("cycle", "sub")
    end
end)
mp.add_key_binding("CTRL+ALT+F10", "adwisp-audio-menu", function()
    open_track_menu("audio")
end)
mp.add_key_binding("CTRL+ALT+F11", "adwisp-subtitle-menu", function()
    open_track_menu("subtitle")
end)
mp.add_key_binding("CTRL+ALT+F4", "adwisp-settings", show_preferences)
mp.add_key_binding("CTRL+ALT+F3", "adwisp-recent-menu", function()
    if active_recent_menu then
        clear_track_menu()
        return
    end
    open_recent_menu(0)
end)
mp.add_key_binding("CTRL+ALT+SHIFT+F3", "adwisp-clear-recent", clear_recent_history)
mp.add_key_binding("CTRL+ALT+F1", "adwisp-continue-menu", function()
    if active_recent_menu and active_recent_menu.continue_only then
        clear_track_menu()
        return
    end
    open_recent_menu(0, nil, true)
end)
mp.add_key_binding("CTRL+ALT+R", "adwisp-resume-current", resume_current_file)
mp.add_key_binding("CTRL+ALT+F12", "adwisp-playlist-menu", function()
    if active_playlist_menu then
        clear_track_menu()
        return
    end
    open_playlist_menu(0)
end)
register_configurable_key_binding("volume_up_key", "adwisp-volume-up", function()
    change_volume(1)
end, "CTRL+UP")
register_configurable_key_binding("volume_down_key", "adwisp-volume-down", function()
    change_volume(-1)
end, "CTRL+DOWN")
mp.add_key_binding("CTRL+ALT+UP", "adwisp-speed-up", function()
    change_speed(1)
end)
mp.add_key_binding("CTRL+ALT+DOWN", "adwisp-speed-down", function()
    change_speed(-1)
end)
mp.add_key_binding("CTRL+ALT+BACKSPACE", "adwisp-speed-reset", function()
    if not fit_image_to_window() then reset_speed() end
end)
mp.add_key_binding("CTRL+ALT+HOME", "adwisp-image-fit", fit_image_to_window)
mp.add_key_binding("CTRL+ALT+KP_ADD", "adwisp-image-zoom-in", function()
    change_image_zoom(0.25)
end)
mp.add_key_binding("CTRL+ALT+KP_SUBTRACT", "adwisp-image-zoom-out", function()
    change_image_zoom(-0.25)
end)
mp.add_key_binding("CTRL+ALT+F7", "adwisp-thumbnail-export", export_thumbnail)

register_configurable_key_binding("loop_toggle_key", "adwisp-loop-toggle", function()
    note_activity()
    mp.commandv("cycle-values", "loop-file", "inf", "no")
end, "CTRL+ALT+L")
register_configurable_key_binding("ab_loop_key", "adwisp-ab-loop", function()
    note_activity()
    mp.commandv("ab-loop")
end, "CTRL+ALT+A")
register_configurable_key_binding("screenshot_key", "adwisp-screenshot", function()
    note_activity()
    mp.commandv("screenshot")
end, "CTRL+ALT+S")
mp.add_key_binding("MBTN_LEFT", "adwisp-mouse-click", handle_mouse_click, { complex = true })
mp.add_key_binding("mouse_move", "adwisp-mouse-move", handle_mouse_move, { complex = true })

local library_dependencies = {
    readdir = utils.readdir,
    file_info = utils.file_info,
    join_path = utils.join_path,
    split_path = utils.split_path,
}

local function refresh_library_view(menu, preferred_path)
    if not menu then return end
    if preferred_path == nil then
        local selected = menu.entries and menu.entries[menu.selected_index]
        preferred_path = selected and selected.path or nil
    end
    menu.entries = VideoLibrary.view(menu.source_entries or {}, menu.query, menu.sort_mode)
    menu.selected_index = 1
    if preferred_path then
        for index, entry in ipairs(menu.entries) do
            if entry.path == preferred_path then menu.selected_index = index break end
        end
    end
    menu.selected_index = math.max(1, math.min(menu.selected_index, math.max(1, #menu.entries)))
end

local function format_library_file_size(size)
    if type(size) ~= "number" or size ~= size or size < 0
        or size == math.huge or size == -math.huge then
        return nil
    end
    if size >= 1024 * 1024 * 1024 then
        return string.format("%.1f GB", size / (1024 * 1024 * 1024))
    elseif size >= 1024 * 1024 then
        return string.format("%.1f MB", size / (1024 * 1024))
    elseif size >= 1024 then
        return string.format("%.1f KB", size / 1024)
    end
    return string.format("%d B", math.floor(size))
end

local function format_library_modified(timestamp)
    if type(timestamp) ~= "number" or timestamp ~= timestamp
        or timestamp < 0 or timestamp == math.huge or timestamp == -math.huge then
        return nil
    end
    local ok, formatted = pcall(os.date, "%Y-%m-%d", timestamp)
    return ok and formatted or nil
end

local function refresh_library_menu()
    local menu = state.library_menu
    if not menu then return end
    local labels = { name = "Name", recent = "Recently added", modified = "Recently modified", size = "Largest first" }
    local query = type(menu.query) == "string" and menu.query or ""
    local lines = { menu.location_mode and "Library locations" or "Video Library", menu.path,
        query == "" and "Search: type to filter" or "Search: " .. query,
        "Sort: " .. (labels[menu.sort_mode] or "Name") .. " (Tab / Shift+Tab)" }
    menu.selected_line = nil
    if not menu.location_mode then
        local summary = VideoLibrary.summary(menu.source_entries or {}, menu.loading, menu.truncated)
        local video_word = summary.videos == 1 and "video" or "videos"
        local folder_word = summary.folders == 1 and "folder" or "folders"
        local count_label = tostring(summary.videos) .. " " .. video_word .. " · "
            .. tostring(summary.folders) .. " " .. folder_word
        if summary.loading then
            lines[#lines + 1] = "Folder counts unavailable until scan completes"
        elseif summary.truncated then
            lines[#lines + 1] = "Partial scan: at least " .. count_label .. " (entry limit reached)"
        else
            lines[#lines + 1] = "This folder: " .. count_label
        end
    end
    if menu.loading then
        lines[#lines + 1] = "Scanning this folder…"
    elseif menu.error then
        lines[#lines + 1] = "Cannot browse folder: " .. tostring(menu.error)
    elseif #menu.entries == 0 then
        if menu.location_mode then
            lines[#lines + 1] = "No configured roots or pinned folders. Add one with adwisp-library-root-add."
        else
            lines[#lines + 1] = query ~= "" and "No matches. Ctrl+Backspace clears search."
                or "No supported videos or folders"
        end
    else
        local page_size = menu.page_size or 12
        local first = math.floor((menu.selected_index - 1) / page_size) * page_size + 1
        local last = math.min(#menu.entries, first + page_size - 1)
        for index = first, last do
            local entry = menu.entries[index]
            local prefix
            if entry.location_type == "root" then
                prefix = entry.available == false and "[OFFLINE] " or "[ROOT] "
            elseif entry.location_type == "favorite" then
                prefix = entry.available == false and "[OFFLINE] " or "[PIN] "
            else
                prefix = entry.kind == "directory" and "[DIR] " or "[VID] "
            end
            local label = entry.label or entry.name
            if entry.kind == "video" then
                local details = {}
                local size_label = format_library_file_size(entry.size)
                local modified_label = format_library_modified(entry.mtime)
                if size_label then details[#details + 1] = size_label end
                if modified_label then details[#details + 1] = modified_label end
                if #details > 0 then
                    label = label .. " · " .. table.concat(details, " · ")
                end
            end
            lines[#lines + 1] = prefix .. label
            if index == menu.selected_index then menu.selected_line = #lines end
        end
        if menu.truncated then
            lines[#lines + 1] = "Showing first " .. tostring(#menu.source_entries) .. " entries (limit)"
        end
        if #menu.entries > page_size then
            lines[#lines + 1] = "Page " .. tostring(math.floor((first - 1) / page_size) + 1)
                .. " / " .. tostring(math.ceil(#menu.entries / page_size))
        end
    end
    if menu.search_available == false then
        lines[#lines + 1] = "Text filtering unavailable on this mpv build"
    end
    lines[#lines + 1] = menu.location_mode and "Enter open · Ctrl+Alt+F2 locations · Esc close"
        or "Type to search · Tab sort · Ctrl+R refresh · Enter open/play · A queue · Backspace up · Esc close"
    menu.lines = lines
    render()
end

local function update_library_search(query)
    local menu = state.library_menu
    if not menu then return end
    local selected = menu.entries and menu.entries[menu.selected_index]
    menu.query = type(query) == "string" and query:sub(1, 256) or ""
    refresh_library_view(menu, selected and selected.path or nil)
    refresh_library_menu()
end

local function set_library_sort(mode)
    local menu = state.library_menu
    if not menu or (mode ~= "name" and mode ~= "recent" and mode ~= "modified" and mode ~= "size") then return end
    local selected = menu.entries and menu.entries[menu.selected_index]
    menu.sort_mode = mode
    refresh_library_view(menu, selected and selected.path or nil)
    refresh_library_menu()
end

local function cycle_library_sort(direction)
    local menu = state.library_menu
    if not menu then return end
    local modes = VideoLibrary.sort_modes()
    local current = 1
    for index, mode in ipairs(modes) do
        if mode == menu.sort_mode then current = index break end
    end
    set_library_sort(modes[((current - 1 + direction) % #modes) + 1])
end

close_library_menu = function(silent)
    library_scan_generation = library_scan_generation + 1
    if library_scan_timer and type(library_scan_timer.kill) == "function" then
        library_scan_timer:kill()
    end
    library_scan_timer = nil
    for _, name in ipairs(library_binding_names) do
        if type(mp.remove_key_binding) == "function" then
            mp.remove_key_binding(name)
        end
    end
    library_binding_names = {}
    state.library_menu = nil
    if not silent then render() end
end

local function add_library_binding(key, name, callback)
    mp.add_forced_key_binding(key, name, function(event)
        if type(event) == "table" and event.event and event.event ~= "down" then
            return
        end
        callback(event)
    end, { repeatable = true })
    library_binding_names[#library_binding_names + 1] = name
end

local open_library
local open_library_locations

local function move_library_selection(delta)
    local menu = state.library_menu
    if not menu or menu.loading or #menu.entries == 0 then return end
    menu.selected_index = math.max(1, math.min(#menu.entries, menu.selected_index + delta))
    refresh_library_menu()
end

local function queue_library_selection()
    local menu = state.library_menu
    local entry = menu and VideoLibrary.selection({ entries = menu.entries }, menu.selected_index)
    if not entry then return end
    if entry.kind ~= "video" then
        mp.commandv("show-text", "Select a video file to add to the playlist.", 2500)
        return
    end
    note_activity()
    mp.commandv("loadfile", entry.path, "append")
end

local function play_library_selection()
    local menu = state.library_menu
    local entry = menu and VideoLibrary.selection({ entries = menu.entries }, menu.selected_index)
    if not entry then return end
    if entry.kind == "directory" then
        open_library(entry.path)
        return
    end
    close_library_menu(true)
    note_activity()
    mp.commandv("loadfile", entry.path, "replace")
end

local function go_to_library_parent()
    local menu = state.library_menu
    if not menu then return end
    if menu.location_mode then
        close_library_menu(false)
        return
    end
    local parent = VideoLibrary.parent_path(menu.path, library_dependencies)
    if not parent then
        mp.commandv("show-text", "Already at the filesystem root.", 2500)
        return
    end
    open_library(parent)
end

local function install_library_bindings()
    if #library_binding_names > 0 then return end
    add_library_binding("UP", "adwisp-library-up-selection", function()
        move_library_selection(-1)
    end)
    add_library_binding("DOWN", "adwisp-library-down-selection", function()
        move_library_selection(1)
    end)
    add_library_binding("WHEEL_UP", "adwisp-library-wheel-up", function()
        move_library_selection(-1)
    end)
    add_library_binding("WHEEL_DOWN", "adwisp-library-wheel-down", function()
        move_library_selection(1)
    end)
    add_library_binding("CTRL+ALT+PGUP", "adwisp-library-page-up", function()
        local menu = state.library_menu
        if menu then move_library_selection(-(menu.page_size or 12)) end
    end)
    add_library_binding("CTRL+ALT+PGDWN", "adwisp-library-page-down", function()
        local menu = state.library_menu
        if menu then move_library_selection(menu.page_size or 12) end
    end)
    add_library_binding("CTRL+ALT+P", "adwisp-library-favorite-toggle", function()
        local menu = state.library_menu
        if not menu or menu.location_mode then return end
        local updated, pinned, err = LibraryConfig.toggle_favorite(library_config, menu.path)
        if err then
            mp.commandv("show-text", "Adwisp: " .. err, 2500)
            return
        end
        library_config = updated
        save_library_config()
        mp.commandv("show-text", pinned and "Adwisp: folder pinned." or "Adwisp: folder unpinned.", 2500)
    end)
    add_library_binding("ENTER", "adwisp-library-enter", play_library_selection)
    add_library_binding("a", "adwisp-library-queue", queue_library_selection)
    add_library_binding("BS", "adwisp-library-parent", function()
        local menu = state.library_menu
        if menu and menu.query ~= "" then
            update_library_search(remove_last_utf8_character(menu.query))
        else
            go_to_library_parent()
        end
    end)
    add_library_binding("CTRL+BACKSPACE", "adwisp-library-search-clear", function(event)
        if type(event) == "table" and event.event and event.event ~= "down" then return end
        update_library_search("")
    end)
    add_library_binding("TAB", "adwisp-library-sort-next", function() cycle_library_sort(1) end)
    add_library_binding("SHIFT+TAB", "adwisp-library-sort-previous", function() cycle_library_sort(-1) end)
    add_library_binding("CTRL+R", "adwisp-library-refresh", function()
        local menu = state.library_menu
        if menu and not menu.location_mode and not menu.loading then open_library(menu.path) end
    end)
    local search_ok = false
    if type(mp.add_forced_key_binding) == "function" then
        local ok = pcall(mp.add_forced_key_binding, "ANY_UNICODE",
            "adwisp-library-search-input", function(event)
                if type(event) ~= "table" or event.event ~= "down" then return end
                local key_name = type(event.key_name) == "string" and event.key_name:upper() or ""
                if key_name:find("CTRL", 1, true) or key_name:find("ALT", 1, true)
                    or key_name:find("META", 1, true) then return end
                if type(event.key_text) == "string" and event.key_text ~= "" then
                    local menu = state.library_menu
                    if menu and #menu.query < 256 then
                        update_library_search(menu.query .. event.key_text)
                    end
                end
            end, { complex = true })
        if ok then
            library_binding_names[#library_binding_names + 1] = "adwisp-library-search-input"
            search_ok = true
        end
    end
    if state.library_menu then state.library_menu.search_available = search_ok end
    add_library_binding("ESC", "adwisp-library-close", function()
        close_library_menu(false)
    end)
end

open_library_locations = function()
    close_library_menu(true)
    clear_track_menu()
    local entries = LibraryConfig.locations(library_config)
    for _, entry in ipairs(entries) do
        local ok_info, info = pcall(utils.file_info, entry.path)
        entry.available = ok_info and type(info) == "table" and info.is_dir == true
    end
    state.library_menu = {
        path = "Configured roots and pinned folders",
        source_entries = entries,
        entries = entries,
        query = "",
        sort_mode = "name",
        selected_index = 1,
        page_size = 12,
        loading = false,
        truncated = false,
        location_mode = true,
    }
    install_library_bindings()
    show_osd()
    refresh_library_menu()
    return true
end

local function add_library_root(path)
    if type(path) ~= "string" or path == "" then
        mp.commandv("show-text", "Adwisp: supply an absolute local directory path.", 3000)
        return false
    end
    local ok_expand, expanded = pcall(mp.command_native, { "expand-path", path })
    if ok_expand and type(expanded) == "string" and expanded ~= "" then path = expanded end
    if not LibraryConfig.is_valid_path(path) then
        mp.commandv("show-text", "Adwisp: library roots must be absolute local paths.", 3000)
        return false
    end
    local ok_info, info = pcall(utils.file_info, path)
    if not ok_info or type(info) ~= "table" or info.is_dir ~= true then
        mp.commandv("show-text", "Adwisp: library root is unavailable or not a directory.", 3000)
        return false
    end
    local updated, added, err = LibraryConfig.add_root(library_config, path)
    if not added then
        mp.commandv("show-text", "Adwisp: " .. tostring(err or "root was not added"), 2500)
        return false
    end
    library_config = updated
    if not save_library_config() then return false end
    mp.commandv("show-text", "Adwisp: library root added.", 2500)
    if state.library_menu and state.library_menu.location_mode then open_library_locations() end
    return true
end

local function remove_library_root(path)
    local updated, removed = LibraryConfig.remove_root(library_config, path)
    if not removed then
        mp.commandv("show-text", "Adwisp: configured library root was not found.", 2500)
        return false
    end
    library_config = updated
    if not save_library_config() then return false end
    mp.commandv("show-text", "Adwisp: library root removed.", 2500)
    if state.library_menu and state.library_menu.location_mode then open_library_locations() end
    return true
end

open_library = function(path)
    if (type(path) ~= "string" or path == "")
        and (#library_config.roots > 0 or #library_config.favorites > 0) then
        return open_library_locations()
    end
    if type(path) ~= "string" or path == "" then
        path = mp.get_property("working-directory")
        if type(path) ~= "string" or path == "" then
            local ok_cwd, cwd = pcall(utils.getcwd)
            path = ok_cwd and cwd or nil
        end
    end
    if type(path) ~= "string" or path == "" then
        mp.commandv("show-text", "Adwisp: no local directory was supplied.", 3000)
        return false
    end
    local ok_expand, expanded = pcall(mp.command_native, { "expand-path", path })
    if ok_expand and type(expanded) == "string" and expanded ~= "" then
        path = expanded
    end

    close_library_menu(true)
    clear_track_menu()
    local scan, scan_error = VideoLibrary.begin_scan(path, library_dependencies,
        opts.library_max_entries)
    local menu_error
    if not scan then menu_error = tostring(scan_error) end
    state.library_menu = {
        path = path,
        source_entries = {},
        entries = {},
        query = "",
        sort_mode = "name",
        selected_index = 1,
        page_size = 12,
        loading = scan ~= nil,
        truncated = false,
        error = menu_error,
    }
    install_library_bindings()
    show_osd()
    refresh_library_menu()
    if not scan then return false end

    local generation = library_scan_generation
    local function process_chunk()
        if generation ~= library_scan_generation or not state.library_menu then return end
        library_scan_timer = nil
        local done, chunk_error = VideoLibrary.scan_chunk(scan, library_dependencies, 32)
        if chunk_error then
            state.library_menu.loading = false
            state.library_menu.error = chunk_error
            refresh_library_menu()
        elseif done then
            state.library_menu.loading = false
            state.library_menu.source_entries = scan.entries
            state.library_menu.truncated = scan.truncated
            refresh_library_view(state.library_menu)
            refresh_library_menu()
        else
            library_scan_timer = mp.add_timeout(0.01, process_chunk)
        end
    end
    process_chunk()
    return true
end

local function register_no_argument_message(name, callback)
    mp.register_script_message(name, function(...)
        if select("#", ...) > 0 then
            mp.msg.warn("Adwisp: script message " .. name .. " does not accept arguments.")
            return
        end
        callback()
    end)
end

register_no_argument_message("adwisp-recent", function() open_recent_menu(0) end)
register_no_argument_message("adwisp-continue", function() open_recent_menu(0, nil, true) end)
mp.register_script_message("adwisp-library-open", function(path) open_library(path) end)
mp.register_script_message("adwisp-library-close", function() close_library_menu(false) end)
mp.register_script_message("adwisp-library-up", go_to_library_parent)
mp.register_script_message("adwisp-library-queue", queue_library_selection)
mp.register_script_message("adwisp-library-search", update_library_search)
mp.register_script_message("adwisp-library-sort", set_library_sort)
mp.register_script_message("adwisp-library-locations", open_library_locations)
mp.register_script_message("adwisp-library-root-add", add_library_root)
mp.register_script_message("adwisp-library-root-remove", remove_library_root)
mp.add_key_binding("CTRL+ALT+F2", "adwisp-library", function() open_library() end)
register_no_argument_message("adwisp-clear-recent", clear_recent_history)
register_no_argument_message("adwisp-toggle", toggle)
register_no_argument_message("adwisp-show", show_osd)
register_no_argument_message("adwisp-hide", hide_osd)
register_no_argument_message("adwisp-reload-theme", reload_theme)
register_no_argument_message("adwisp-query", function()
    local payload = {
        visible = state.visible == true,
        paused = state.paused == true,
        time_pos = finite_property(state.time_pos, 0),
        duration = finite_property(state.duration, 0),
        volume = finite_property(state.volume, 100),
        speed = finite_property(state.speed, 1),
        loop_file = state.loop_file == "inf" and "inf" or state.loop_file,
        ab_loop_a = finite_property(state.ab_loop_a, -1),
        ab_loop_b = finite_property(state.ab_loop_b, -1),
        mute = state.mute == true,
        playlist_pos = finite_property(state.playlist_pos, -1),
        playlist_count = finite_property(state.playlist_count, 0),
        chapter = finite_property(state.chapter, -1),
        chapter_title = type(state.chapter_title) == "string" and state.chapter_title or "",
        audio_track_count = state.audio_track_count,
        audio_track_label = state.audio_track_label,
        subtitle_track_count = state.subtitle_track_count,
        subtitle_track_label = state.subtitle_track_label,
        buffering = state.buffering == true,
        buffering_progress = finite_property(state.buffering_progress, 0),
        focus_target = type(state.focus_target) == "string" and state.focus_target or "",
        image_mode = state.image_mode == true,
        image_zoom = finite_property(state.image_zoom, 0),
    }
    local json = utils.format_json(payload)
    if type(json) ~= "string" then
        mp.msg.warn("Adwisp: could not serialize state query.")
        return
    end
    -- A query is an explicit response, so it remains visible even at log_level=quiet.
    mp.msg.info("Adwisp state: " .. json)
end)
mp.register_script_message("thumbfast-info", function(json)
    last_mouse_x, last_mouse_y = nil, nil
    local data = utils.parse_json(json)
    local function positive_finite(value)
        return type(value) == "number" and value == value
            and value ~= math.huge and value ~= -math.huge and value > 0
    end
    if type(data) == "table" and positive_finite(data.width)
        and positive_finite(data.height) and data.width <= 8192 and data.height <= 8192
        and type(data.disabled) == "boolean" and type(data.available) == "boolean" then
        local preview_cleared = false
        local scale_factor = positive_finite(data.scale_factor) and data.scale_factor or 1
        local source_width = data.width / scale_factor
        local source_height = data.height / scale_factor
        if not positive_finite(source_width) or source_width > 4096 then source_width = 0
        else source_width = math.floor(source_width + 0.5) end
        if not positive_finite(source_height) or source_height > 4096 then source_height = 0
        else source_height = math.floor(source_height + 0.5) end
        local thumbnail_path = type(data.thumbnail) == "string"
            and #data.thumbnail <= 1024 and not data.thumbnail:find("\0", 1, true)
            and data.thumbnail ~= "" and data.thumbnail or nil
        local dimensions_changed = math.floor(data.width) ~= thumbfast.width
            or math.floor(data.height) ~= thumbfast.height
        local path_changed = thumbnail_path ~= thumbfast.thumbnail_path
        if data.disabled or not data.available
            or (thumbnail_active and (dimensions_changed or path_changed)) then
            preview_cleared = clear_thumbnail()
        end
        last_thumbnail_request = nil
        thumbfast = {
            width = math.floor(data.width),
            height = math.floor(data.height),
            source_width = source_width,
            source_height = source_height,
            disabled = data.disabled,
            available = data.available,
            thumbnail_path = thumbnail_path,
        }
        if preview_cleared then render() end
        if thumbfast.width < 1 or thumbfast.height < 1 then
            thumbfast = {
                width = 0, height = 0, source_width = 0, source_height = 0,
                disabled = true, available = false, thumbnail_path = nil,
            }
        end
        log_debug("thumbfast info: available=" .. tostring(thumbfast.available)
            .. ", disabled=" .. tostring(thumbfast.disabled)
            .. ", size=" .. thumbfast.width .. "x" .. thumbfast.height)
    else
        mp.msg.warn("Adwisp: received invalid thumbfast info; previews disabled.")
        local preview_cleared = clear_thumbnail()
        thumbfast = {
                width = 0, height = 0, source_width = 0, source_height = 0,
                disabled = true, available = false, thumbnail_path = nil,
            }
        if preview_cleared then render() end
    end
end)

local mpv_version = type(mp.get_property) == "function"
    and mp.get_property("mpv-version") or "unknown"
log_info("loaded on " .. tostring(mpv_version) .. ". Press g to toggle the OSD.")
