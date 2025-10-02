#!/usr/bin/env python3
import sys
import os
import json
import humanize
import threading
import hashlib
from pathlib import Path
import subprocess
import logging
import warnings
from concurrent.futures import ThreadPoolExecutor

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
gi.require_version('Gdk', '4.0')
gi.require_version('GdkPixbuf', '2.0')

from gi.repository import Gtk, Gio, Gdk, GdkPixbuf, Adw, GLib, Pango

# --------------------------- 
# Helper: write CSS for highlight
# --------------------------- 
def install_css():
    css = b"""
    .thumbnail {
        border-radius: 12px;
        transition: all 200ms cubic-bezier(0.25, 0.46, 0.45, 0.94);
        background-color: transparent;
        border: 1px solid transparent;
    }
    .thumbnail:hover {
        transform: translateY(-2px);
        box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15);
    }
    .thumbnail:focus {
        outline: 3px solid rgba(130,211,227,0.95);
        outline-offset: 2px;
    }
    .thumbnail-label {
        font-size: 11px;
    }
    """
    provider = Gtk.CssProvider()
    provider.load_from_data(css)
    display = Gdk.Display.get_default()
    Gtk.StyleContext.add_provider_for_display(display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

class SettingsDialog(Adw.Window): # Inherit from Adw.Window
    def __init__(self, parent_window, config, **kwargs):
        super().__init__(**kwargs)
        self.set_transient_for(parent_window)
        self.set_modal(True)
        self.set_title("Wallpaper Picker Settings") # Adw.Window uses set_title
        self.set_default_size(400, 300)

        self.config = config
class SettingsDialog(Adw.Window): # Inherit from Adw.Window
    def __init__(self, parent_app, config, **kwargs): # Renamed parent_window to parent_app
        super().__init__(**kwargs)
        self.set_transient_for(parent_app.window) # Use parent_app.window for transient
        self.set_modal(True)
        self.set_title("Wallpaper Picker Settings") # Adw.Window uses set_title
        self.set_default_size(400, 300)

        self.config = config
        self.parent_app = parent_app # Store the WallpaperPicker instance

        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(self.main_box)

        # Header bar for title and close button
        header_bar = Adw.HeaderBar()
        header_bar.set_title_widget(Adw.WindowTitle(title="Wallpaper Picker Settings"))
        self.main_box.append(header_bar)

        # Scrollable content area
        scrolled_window = Gtk.ScrolledWindow()
        scrolled_window.set_vexpand(True)
        self.main_box.append(scrolled_window)

        # Main content box for settings
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        content_box.set_margin_top(12)
        content_box.set_margin_bottom(12)
        content_box.set_margin_start(12)
        content_box.set_margin_end(12)
        scrolled_window.set_child(content_box) # Set content_box as child of scrolled_window

        settings_group = Adw.PreferencesGroup(title="General Settings")
        content_box.append(settings_group)

        # Wallpaper Directory
        dir_row = Adw.ActionRow(title="Wallpaper Directory")
        
        dir_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        self.dir_entry = Gtk.Entry()
        self.dir_entry.set_text(self.config.get('wallpaper_dir', GLib.get_user_special_dir(GLib.UserDirectory.DIRECTORY_PICTURES)))
        self.dir_entry.set_hexpand(True)
        dir_box.append(self.dir_entry)

        dir_button = Gtk.Button(label="Browse")
        dir_button.connect("clicked", self.on_browse_dir_clicked)
        dir_box.append(dir_button)

        dir_row.add_suffix(dir_box)
        settings_group.add(dir_row) # Add to preferences group

        # Thumbnail Width
        width_row = Adw.ActionRow(title="Thumbnail Width")
        self.width_spin = Gtk.SpinButton(adjustment=Gtk.Adjustment.new(self.config.get('thumbnail_width', 200), 50, 500, 10, 0, 0), numeric=True)
        width_row.add_suffix(self.width_spin)
        settings_group.add(width_row) # Add to preferences group

        # Thumbnail Height
        height_row = Adw.ActionRow(title="Thumbnail Height")
        self.height_spin = Gtk.SpinButton(adjustment=Gtk.Adjustment.new(self.config.get('thumbnail_height', 150), 50, 500, 10, 0, 0), numeric=True)
        height_row.add_suffix(self.height_spin)
        settings_group.add(height_row) # Add to preferences group

        # Columns
        columns_row = Adw.ActionRow(title="Columns")
        self.columns_spin = Gtk.SpinButton(adjustment=Gtk.Adjustment.new(self.config.get('columns', 4), 1, 10, 1, 0, 0), numeric=True)
        columns_row.add_suffix(self.columns_spin)
        settings_group.add(columns_row) # Add to preferences group

        # Extensions
        extensions_row = Adw.ActionRow(title="Extensions (comma-separated)")
        self.extensions_entry = Gtk.Entry()
        self.extensions_entry.set_text(self.config.get('extensions', 'jpg,jpeg,png'))
        extensions_row.add_suffix(self.extensions_entry)
        settings_group.add(extensions_row) # Add to preferences group

        # Thumbnail Quality
        quality_row = Adw.ActionRow(title="Thumbnail Quality")
        self.quality_spin = Gtk.SpinButton(adjustment=Gtk.Adjustment.new(self.config.get('thumbnail_quality', 95), 1, 100, 1, 0, 0), numeric=True)
        quality_row.add_suffix(self.quality_spin)
        settings_group.add(quality_row)

        # Buttons
        button_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        button_box.set_halign(Gtk.Align.END)
        button_box.set_margin_top(12)
        button_box.set_margin_bottom(12)
        button_box.set_margin_start(12)
        button_box.set_margin_end(12)

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", lambda btn: self.close())
        button_box.append(cancel_btn)

        save_btn = Gtk.Button(label="Save")
        save_btn.add_css_class('suggested-action')
        save_btn.connect("clicked", lambda btn: self.on_save_clicked())
        button_box.append(save_btn)

        self.main_box.append(button_box)

    def on_save_clicked(self):
        self.save_settings()
        self.close()

    def on_browse_dir_clicked(self, button):
        dialog = Gtk.FileDialog.new()
        dialog.set_title("Select Wallpaper Directory")
        dialog.set_modal(True)
        dialog.set_initial_folder(Gio.File.new_for_path(self.dir_entry.get_text()))

        def on_folder_selected(dialog, result):
            try:
                folder = dialog.select_folder_finish(result)
                if folder:
                    self.dir_entry.set_text(folder.get_path())
            except GLib.Error as e:
                print(f"Error selecting folder: {e}", file=sys.stderr)

        dialog.select_folder(self.parent_app.window, None, on_folder_selected)

    def save_settings(self):
        new_config = {
            'wallpaper_dir': self.dir_entry.get_text(),
            'thumbnail_width': self.width_spin.get_value_as_int(),
            'thumbnail_height': self.height_spin.get_value_as_int(),
            'columns': self.columns_spin.get_value_as_int(),
            'extensions': self.extensions_entry.get_text(),
            'thumbnail_quality': self.quality_spin.get_value_as_int()
        }

        # Update the main app's config
        self.parent_app.config.update(new_config)

        # Write to config file
        config_dir = Path(GLib.get_user_config_dir()) / 'wallpicker'
        config_file = config_dir / 'config.json'
        try:
            with open(config_file, 'w') as f:
                json.dump(self.parent_app.config, f, indent=4)
        except OSError as e:
            print(f"Error writing config file: {e}", file=sys.stderr)

        # Trigger main window to reload/update if necessary
        self.parent_app.reload_ui_after_settings_change()

class AboutDialog(Gtk.AboutDialog):
    def __init__(self, parent_window, **kwargs):
        super().__init__(**kwargs) # Gtk.AboutDialog doesn't take transient_for/modal in constructor
        self.set_transient_for(parent_window)
        self.set_modal(True)
        self.set_program_name("Wallpaper Picker")
        self.set_version("1.0.0") # Placeholder version
        self.set_authors(["Your Name Here"]) # Placeholder name, Gtk.AboutDialog uses set_authors
        self.set_copyright("© 2023 Your Name Here") # Placeholder copyright
        self.set_license_type(Gtk.License.MIT_X11) # Example license
        self.set_website("https://github.com/yourusername/wallpaper-picker") # Placeholder website
        self.set_comments("A simple wallpaper picker for GNOME.")
        # Gtk.AboutDialog does not have set_designers or set_artists (use set_authors for general credits)
        self.set_translator_credits("Your Name Here") # Placeholder translator
        # Gtk.AboutDialog does not have set_release_notes

# --------------------------- 
# Main Application
# --------------------------- 
class WallpaperPicker(Adw.Application):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.selected_wallpaper = None
        self.wallpapers = []
        self.file_info = {} # Dict to store info like size and dimensions
        self.thumbnail_widgets = []    # ordered list of thumbnail buttons
        self.selected_index = -1       # for keyboard navigation
        self.config = self.load_config()
        cache_dir_str = GLib.get_user_cache_dir()
        self.cache_dir = Path(cache_dir_str) / "wallpicker" / "thumbs"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.preview_window = None
        self.search_text = "" # For search functionality
        self.search_timeout = None # For debouncing search
        self.executor = ThreadPoolExecutor(max_workers=os.cpu_count())
        install_css()
        self.connect('activate', self.on_activate)

    # ----------- 
    # Config
    # ----------- 
    def load_config(self):
        config_dir = Path(GLib.get_user_config_dir()) / 'wallpicker'
        config_file = config_dir / 'config.json'
        config_dir.mkdir(parents=True, exist_ok=True)

        default_config = {
            'wallpaper_dir': '/mnt/data/Wallpapers',
            'thumbnail_width': 200,
            'thumbnail_height': 150,
            'columns': 4,
            'extensions': 'jpg,jpeg,png',
            'thumbnail_quality': 95
        }

        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    config = json.load(f)
                    # Merge with defaults to ensure all keys are present
                    return {**default_config, **config}
            except (json.JSONDecodeError, TypeError) as e:
                print(f"Error reading config file, falling back to defaults: {e}", file=sys.stderr)
                return default_config
        else:
            try:
                with open(config_file, 'w') as f:
                    json.dump(default_config, f, indent=4)
            except OSError as e:
                print(f"Error writing default config file: {e}", file=sys.stderr)
            return default_config

    # ----------- 
    # Startup + UI
    # ----------- 
    def on_activate(self, app):
        # Main window
        self.window = Adw.ApplicationWindow(application=app)
        self.window.set_title('Wallpaper Picker')
        self.window.set_default_size(1000, 700)

        # Header bar (Cancel left, Select right)
        header_bar = Adw.HeaderBar()

        # Search Entry as title widget
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search wallpapers...")
        self.search_entry.connect("search-changed", self.on_search_changed)
        header_bar.set_title_widget(self.search_entry)

        

        cancel_btn = Gtk.Button(label="Cancel")
        cancel_btn.connect("clicked", self.on_cancel)
        header_bar.pack_start(cancel_btn)

        settings_btn = Gtk.Button(label="Settings")
        settings_btn.connect("clicked", self.on_settings_clicked)
        header_bar.pack_start(settings_btn)

        about_btn = Gtk.Button(label="About")
        about_btn.connect("clicked", self.on_about_clicked)
        header_bar.pack_start(about_btn)

        self.select_btn = Gtk.Button(label="Select")
        self.select_btn.add_css_class('suggested-action')
        self.select_btn.set_sensitive(False)
        self.select_btn.connect("clicked", self.on_select)
        header_bar.pack_end(self.select_btn)

        # Main vertical layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        main_box.append(header_bar)

        # Status label
        self.status_label = Gtk.Label(label="Loading wallpapers...")
        main_box.append(self.status_label)

        # Scrolled window + FlowBox
        self.scrolled = Gtk.ScrolledWindow()
        self.scrolled.set_hexpand(True)
        self.scrolled.set_vexpand(True)

        self.flow_box = Gtk.FlowBox()
        self.flow_box.set_selection_mode(Gtk.SelectionMode.NONE)  # we manage selection ourselves
        columns = self.config.get('columns', 4)
        self.flow_box.set_max_children_per_line(columns)
        self.flow_box.set_homogeneous(False)
        self.flow_box.set_margin_start(16)
        self.flow_box.set_margin_end(16)
        self.flow_box.set_filter_func(self.filter_func) # Set filter function

        self.scrolled.set_child(self.flow_box)
        main_box.append(self.scrolled)

        self.window.set_content(main_box)
        self.window.present()

        # Controller for navigation, attached to the flowbox
        nav_key_controller = Gtk.EventControllerKey.new()
        nav_key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        nav_key_controller.connect("key-pressed", self.on_key_pressed)
        self.flow_box.add_controller(nav_key_controller)

        # Controller for global actions like Escape, attached to the window
        window_key_controller = Gtk.EventControllerKey.new()
        window_key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE) # Set to CAPTURE
        window_key_controller.connect("key-pressed", self.on_window_key_pressed)
        self.window.add_controller(window_key_controller)

        # Start background loading of wallpaper list and placeholders
        self.start_loading()

    # --- Search Methods ---
    def on_search_changed(self, entry):
        self.search_text = entry.get_text().lower()
        if self.search_timeout:
            GLib.source_remove(self.search_timeout)
        self.search_timeout = GLib.timeout_add(300, self._perform_search)

    def _perform_search(self):
        self.flow_box.invalidate_filter()
        self.search_timeout = None
        return False # Stop the timeout

    def filter_func(self, child, data=None): # Corrected signature with optional data
        button = child.get_child() # Get the Gtk.Button from the FlowBoxChild
        if self.search_text:
            return self.search_text in os.path.basename(button.wallpaper_path).lower()
        return True # Show all if no search text

    def on_settings_clicked(self, button):
        self.settings_dialog = SettingsDialog(self, self.config) # Pass self (WallpaperPicker instance)
        self.settings_dialog.present()

    def on_about_clicked(self, button):
        about_dialog = AboutDialog(self.window)
        about_dialog.present()

    # ----------- 
    # Loading / threading
    # ----------- 
    def start_loading(self):
        thread = threading.Thread(target=self.load_wallpapers_thread, daemon=True)
        thread.start()

    def find_wallpapers_fast(self):
        wallpaper_dir = self.config.get('wallpaper_dir')
        if not os.path.isdir(wallpaper_dir):
            return []
        extensions = tuple(f".{e.strip().lower()}" for e in self.config.get('extensions', 'jpg,jpeg,png').split(','))
        wallpapers_with_info = []
        try:
            for root, _, files in os.walk(wallpaper_dir):
                for name in files:
                    if name.lower().endswith(extensions):
                        path = os.path.join(root, name)
                        try:
                            stat = os.stat(path)
                            wallpapers_with_info.append({
                                'path': path,
                                'size': stat.st_size
                            })
                        except OSError:
                            continue # Skip files we can't stat
        except (PermissionError, OSError) as e:
            logging.warning(f"Permission or OS error during wallpaper search: {e}")
        return sorted(wallpapers_with_info, key=lambda x: x['path'])

    def _get_visible_flowbox_children(self):
        visible_children = []
        child = self.flow_box.get_first_child()
        while child:
            # The child here is a Gtk.FlowBoxChild
            if self.filter_func(child): # Apply the same filter function
                visible_children.append(child)
            child = child.get_next_sibling()
        return visible_children

    def load_wallpapers_thread(self):
        self.wallpapers = self.find_wallpapers_fast()
        if not self.wallpapers:
            GLib.idle_add(self.show_error_dialog, "No wallpapers found!")
            return
        GLib.idle_add(self.update_status, f"Found {len(self.wallpapers)} wallpapers...")
        for wall_info in self.wallpapers:
            self.file_info[wall_info['path']] = {'size': wall_info['size']}
            GLib.idle_add(self.add_wallpaper_placeholder, wall_info['path'])
        GLib.idle_add(self.loading_complete)

    # ----------- 
    # UI element creation + placeholders
    # ----------- 
    def add_wallpaper_placeholder(self, wallpaper):
        # The root widget is a Gtk.Button
        btn = Gtk.Button()
        btn.add_css_class('thumbnail')
        btn.connect('clicked', self.on_thumbnail_button_clicked)

        # The box goes inside the button
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        box.set_margin_top(6)
        box.set_margin_bottom(6)
        box.set_margin_start(6)
        box.set_margin_end(6)
        btn.set_child(box)

        spinner = Gtk.Spinner()
        spinner.start()
        spinner.set_size_request(
            self.config.get('thumbnail_width', 200),
            self.config.get('thumbnail_height', 150)
        )
        box.append(spinner)

        label = Gtk.Label(label=os.path.basename(wallpaper))
        label.add_css_class('thumbnail-label')
        label.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        label.set_max_width_chars(22)
        box.append(label)

        # Store data on the button itself
        btn.wallpaper_path = wallpaper
        btn.spinner = spinner
        btn.set_focusable(True)
        btn.set_has_tooltip(True)
        btn.connect("query-tooltip", self.on_query_tooltip)

        self.flow_box.append(btn)
        self.thumbnail_widgets.append(btn)  # The list now holds buttons

        GLib.idle_add(self.load_thumbnail, btn, wallpaper)

    # ----------- 
    # Thumbnail loading + caching
    # ----------- 
    def load_thumbnail(self, btn, wallpaper):
        self.executor.submit(self._load_thumbnail_thread, btn, wallpaper)

    def _load_thumbnail_thread(self, btn, wallpaper):
        thumb_width = self.config.get('thumbnail_width', 200)
        thumb_height = self.config.get('thumbnail_height', 150)
        h = hashlib.sha1(wallpaper.encode()).hexdigest()
        cache_file = self.cache_dir / f"{h}.jpg"

        try:
            # Always try to get dimensions from the original file.
            try:
                _, orig_width, orig_height = GdkPixbuf.Pixbuf.get_file_info(wallpaper)
                if self.file_info.get(wallpaper):
                    self.file_info[wallpaper]['width'] = orig_width
                    self.file_info[wallpaper]['height'] = orig_height
            except GLib.Error:
                # Ignore if we can't get file info, e.g. for a broken file
                pass

            if cache_file.exists() and os.path.getmtime(cache_file) >= os.path.getmtime(wallpaper):
                pixbuf = GdkPixbuf.Pixbuf.new_from_file(cache_file.as_posix())
            else:
                pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(wallpaper, thumb_width, thumb_height)
                try:
                    thumb_quality = str(self.config.get('thumbnail_quality', 95))
                    pixbuf.savev(cache_file.as_posix(), "jpeg", ["quality"], [thumb_quality])
                except Exception as e:
                    logging.warning(f"Could not save thumbnail cache for {wallpaper}: {e}")
            
            # Now schedule the UI update on the main thread
            GLib.idle_add(self._update_thumbnail_ui, btn, pixbuf)

        except Exception as e:
            logging.error(f"Error loading {wallpaper}: {e}")

    def _update_thumbnail_ui(self, btn, pixbuf):
        thumb_width = self.config.get('thumbnail_width', 200)
        thumb_height = self.config.get('thumbnail_height', 150)
        
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", DeprecationWarning)
            texture = Gdk.Texture.new_for_pixbuf(pixbuf)
            
        picture = Gtk.Picture.new_for_paintable(texture)
        picture.set_size_request(thumb_width, thumb_height)

        box = btn.get_child()
        if hasattr(btn, "spinner") and btn.spinner is not None:
            try:
                box.remove(btn.spinner)
            except Exception as e:
                logging.warning(f"Could not remove spinner: {e}")
            del btn.spinner

        box.prepend(picture)
        return False

    # ----------- 
    # Status / errors
    # ----------- 
    def update_status(self, message):
        self.status_label.set_label(message)

    def loading_complete(self):
        self.status_label.set_visible(False)
        if not self.thumbnail_widgets:
            self.show_error_dialog("No wallpapers could be loaded!")

    def reload_ui_after_settings_change(self):
        # Clear existing thumbnails
        child = self.flow_box.get_first_child()
        while child:
            next_child = child.get_next_sibling() # Get next before removing current
            self.flow_box.remove(child)
            child = next_child
        self.thumbnail_widgets = []
        self.selected_index = -1
        self.selected_wallpaper = None
        self.select_btn.set_sensitive(False)
        self.status_label.set_visible(True)
        self.status_label.set_label("Reloading wallpapers...")

        # Update flowbox columns
        self.flow_box.set_max_children_per_line(self.config.get('columns', 4))

        # Restart loading process
        self.start_loading()

    def show_error_dialog(self, message):
        dialog = Adw.MessageDialog(
            transient_for=self.window,
            heading="Error",
            body=message
        )
        dialog.add_response("ok", "OK")
        dialog.connect("response", lambda d, r: self.window.close())
        dialog.present()

    def on_query_tooltip(self, widget, x, y, keyboard_mode, tooltip):
        path = widget.wallpaper_path
        info = self.file_info.get(path)
        if not info:
            return False

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        main_box.set_margin_top(8)
        main_box.set_margin_bottom(8)
        main_box.set_margin_start(8)
        main_box.set_margin_end(8)

        name_label = Gtk.Label()
        name_label.set_markup(f"<b>{GLib.markup_escape_text(os.path.basename(path))}</b>")
        name_label.set_xalign(0)
        main_box.append(name_label)

        if 'size' in info:
            size_str = humanize.naturalsize(info['size'], binary=True)
            size_label = Gtk.Label(label=f"Size: {size_str}")
            size_label.set_xalign(0)
            main_box.append(size_label)

        if 'width' in info and 'height' in info:
            dim_label = Gtk.Label(label=f"Dimensions: {info['width']} × {info['height']}")
            dim_label.set_xalign(0)
            main_box.append(dim_label)
        
        tooltip.set_custom(main_box)
        return True

    # ----------- 
    # Selection / Navigation
    # ----------- 
    def _select_item_by_index(self, visible_index): # Renamed parameter for clarity
        visible_children = self._get_visible_flowbox_children() # Use helper
        if not (0 <= visible_index < len(visible_children)):
            return

        self.selected_index = visible_index # Store index in visible list
        flowbox_child = visible_children[visible_index]
        widget = flowbox_child.get_child() # This is the Gtk.Button

        # Just grab focus. The CSS :focus selector will handle the highlight.
        widget.grab_focus()

        # Scrolling logic
        # Check if the widget is visible and only scroll if it's not.
        coords = widget.translate_coordinates(self.flow_box, 0, 0)
        if coords:
            x, y = coords
            widget_height = widget.get_height()

            vadj = self.scrolled.get_vadjustment()
            viewport_top = vadj.get_value()
            viewport_height = vadj.get_page_size()
            viewport_bottom = viewport_top + viewport_height

            # Only scroll if the widget is not fully visible
            if not (y >= viewport_top and (y + widget_height) <= viewport_bottom):
                # If widget is above, align its top with the viewport top
                if y < viewport_top:
                    vadj.set_value(y - 20) # With margin
                # If widget is below, align its bottom with the viewport bottom
                else:
                    vadj.set_value(y + widget_height - viewport_height + 20) # With margin

        self.selected_wallpaper = widget.wallpaper_path
        self.select_btn.set_sensitive(True)

    def on_thumbnail_button_clicked(self, btn):
        # A single click will now open the preview
        self.open_preview(btn.wallpaper_path)

    def on_wallpaper_activated(self, flowbox, child):
        # This is now handled by the button click
        pass

    def on_window_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            # Check if search entry has focus and text
            if self.search_entry.has_focus() and self.search_entry.get_text():
                self.search_entry.set_text("")
                # Invalidate filter immediately, don't wait for debouncing
                if self.search_timeout:
                    GLib.source_remove(self.search_timeout)
                    self.search_timeout = None
                self.flow_box.invalidate_filter()
                return True # Consume the event (cleared search, don't close window)
            else:
                # If search entry doesn't have focus, or has focus but no text, close the window
                self.window.close()
                return True # Consume the event (closed window)
        
        # New logic for "type to search"
        # Check if the keyval corresponds to a printable character
        # and if the search entry is not currently focused.
        if not self.search_entry.has_focus():
            unicode_char = Gdk.keyval_to_unicode(keyval)
            # Only append if it's a printable character (not control keys like Backspace, Enter, etc.)
            if unicode_char and chr(unicode_char).isprintable():
                # Set focus to the search entry
                self.search_entry.grab_focus()
                # Append the character to the search entry
                current_text = self.search_entry.get_text()
                self.search_entry.set_text(current_text + chr(unicode_char))
                self.search_entry.set_position(-1) # Set cursor to end
                # Manually trigger search update, as set_text doesn't always trigger "search-changed" immediately
                self.on_search_changed(self.search_entry)
                return True # Consume the event
        
        return False # Allow other keys to propagate

    def on_key_pressed(self, controller, keyval, keycode, state):
        if not self.thumbnail_widgets: # Still need this check for initial load
            return False  # Not handled

        visible_children = self._get_visible_flowbox_children() # Use helper
        visible_count = len(visible_children)

        if visible_count == 0:
            self.selected_index = -1 # No selection if no visible items
            self.select_btn.set_sensitive(False)
            return False # No items to navigate

        # If nothing is selected, or previously selected item is no longer visible,
        # select the first visible item.
        if self.selected_index == -1 or self.selected_index >= visible_count:
            self._select_item_by_index(0)
            return True

        current_visible_index = self.selected_index
        new_visible_index = current_visible_index

        columns = self.flow_box.get_max_children_per_line()

        if keyval == Gdk.KEY_Right:
            new_visible_index = (current_visible_index + 1) % visible_count
        elif keyval == Gdk.KEY_Left:
            new_visible_index = (current_visible_index - 1 + visible_count) % visible_count
        elif keyval == Gdk.KEY_Down:
            new_visible_index = min(current_visible_index + columns, visible_count - 1)
        elif keyval == Gdk.KEY_Up:
            new_visible_index = max(current_visible_index - columns, 0)
        elif keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            self.open_preview(visible_children[current_visible_index].get_child().wallpaper_path)
            return True  # Handled
        else:
            return False # Not a navigation key

        if new_visible_index != current_visible_index:
            self._select_item_by_index(new_visible_index)
            return True # Handled navigation
        
        return False # Not handled

    def _handle_preview_apply(self, wallpaper_path):
        # The calling script (matugen.fish) is responsible for setting the wallpaper.
        # This function just needs to print the selected path to stdout and close.
        if self.preview_window:
            self.preview_window.destroy()
            self.preview_window = None
        
        print(wallpaper_path)
        self.window.close()

    # ----------- 
    # Preview modal
    # ----------- 
    def open_preview(self, wallpaper_path):
        if self.preview_window:
            self.preview_window.destroy()

        self.preview_window = Adw.Window(transient_for=self.window, modal=True)
        self.preview_window.set_title("Preview")
        self.preview_window.set_default_size(900, 600)

        # Define the key handler locally so it has access to wallpaper_path
        def on_key_press(controller, keyval, keycode, state):
            if keyval == Gdk.KEY_Escape:
                if self.preview_window:
                    self.preview_window.destroy()
                    self.preview_window = None
                return True
            elif keyval in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self._handle_preview_apply(wallpaper_path)
                return True
            return False

        key_controller = Gtk.EventControllerKey.new()
        key_controller.connect("key-pressed", on_key_press)
        self.preview_window.add_controller(key_controller)

        dialog_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.preview_window.set_content(dialog_box)

        try:
            pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_size(wallpaper_path, 1600, 900)
            texture = Gdk.Texture.new_for_pixbuf(pixbuf)
            picture = Gtk.Picture.new_for_paintable(texture)
            picture.set_hexpand(True)
            picture.set_vexpand(True)
            content = Gtk.ScrolledWindow()
            content.set_child(picture)
            dialog_box.append(content)
        except Exception as e:
            lbl = Gtk.Label(label=f"Could not load preview:\n{e}")
            dialog_box.append(lbl)

        action_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        action_bar.set_halign(Gtk.Align.CENTER)
        action_bar.set_margin_top(6)
        action_bar.set_margin_bottom(6)
        dialog_box.append(action_bar)

        apply_btn = Gtk.Button(label="Apply")
        apply_btn.add_css_class("suggested-action")
        action_bar.append(apply_btn)

        close_btn = Gtk.Button(label="Close")
        action_bar.append(close_btn)

        apply_btn.connect("clicked", lambda btn: self._handle_preview_apply(wallpaper_path))
        close_btn.connect("clicked", lambda btn: self.preview_window.destroy())

        self.preview_window.present()

    # ----------- 
    # Select / Cancel
    # ----------- 
    def on_select(self, button):
        if self.selected_wallpaper:
            print(self.selected_wallpaper)
        else:
            print("No wallpaper selected", file=sys.stderr)
        self.window.close()

    def on_cancel(self, button):
        print("Selection cancelled", file=sys.stderr)
        self.window.close()


if __name__ == "__main__":
    app = WallpaperPicker(application_id="com.github.WallpaperPicker")
    sys.exit(app.run(sys.argv))
