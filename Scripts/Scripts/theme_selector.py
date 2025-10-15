#!/usr/bin/env python

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib, Gdk

import os
import subprocess
import sys

# --- Configuration ---
THEMES_DIR = os.path.expanduser("~/.config/matugen/themes")
MATUGEN_CONFIG = os.path.expanduser("~/.config/matugen/config.toml")


def get_destinations_from_config(config_path):
    """Parses the matugen config.toml to get a map of source filenames to destination paths."""
    if not os.path.exists(config_path):
        print(f"Error: Matugen config not found at {config_path}")
        return {}

    template_map = {}
    current_template = None
    with open(config_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('[templates.'):
                current_template = line[len('[templates.'):-1]
                template_map[current_template] = {}
            elif current_template and '=' in line:
                key, value = line.split('=', 1)
                template_map[current_template][key.strip()] = value.strip().strip('\'"')

    destinations = {}
    for template_name, data in template_map.items():
        if 'input_path' in data and 'output_path' in data:
            source_filename = os.path.basename(os.path.expanduser(data['input_path']))
            dest_path = os.path.expanduser(data['output_path'])
            destinations[source_filename] = dest_path
    destinations["qt5ct/colors/colors.conf"] = os.path.expanduser("~/.config/qt5ct/colors/colors.conf")
    destinations["qt6ct/colors/colors.conf"] = os.path.expanduser("~/.config/qt6ct/colors/colors.conf")
    return destinations

def apply_theme(theme_name):
    """Copies theme files and reloads UI elements."""
    print(f"Applying theme: {theme_name}")
    theme_path = os.path.join(THEMES_DIR, theme_name)
    destinations = get_destinations_from_config(MATUGEN_CONFIG)

    if not destinations:
        print("Could not determine file destinations. Aborting.")
        return

    # 1. Copy files
    for filename, dest_path in destinations.items():
        source_path = os.path.join(theme_path, filename)
        if os.path.exists(source_path):
            print(f"Copying {filename} to {dest_path}...")
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)
            subprocess.run(['cp', source_path, dest_path])
        else:
            print(f"Warning: Source file {filename} not found in theme '{theme_name}'.")

    # 2. Reload GNOME Settings (replicates apply_gnome_settings from fish script)
    print("Reloading GNOME settings...")
    try:
        # Reload GTK theme
        subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/user-theme/name', "'default'"])
        subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/user-theme/name', "'Material-Gnome'"])

        # Reload Kitty
        subprocess.run(['kitty', '+kitten', 'themes', '--reload-in=all', 'colors'])
        subprocess.run(['kitty', '@', 'set-colors', '--all', os.path.expanduser('~/.config/kitty/themes/colors.conf')])

        # Reload Pop Shell hint color
        pop_shell_css = os.path.expanduser('~/.config/colors/pop-shell.css')
        if os.path.exists(pop_shell_css):
            with open(pop_shell_css, 'r') as f:
                pop_hint_color = f.read().strip()
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/pop-shell/hint-color-rgba', "'{}'".format(pop_hint_color)])

        # Apply accent color to Clock extension elements
        accent_color_css = os.path.expanduser('~/.config/colors/accent-color.css')
        if os.path.exists(accent_color_css):
            with open(accent_color_css, 'r') as f:
                rgba_color = f.read().strip()
                for key in ['time-font-color', 'date-font-color', 'hint-font-color', 'command-output-font-color']:
                    subprocess.run(['dconf', 'write', f'/org/gnome/shell/extensions/customize-clock-on-lockscreen/{key}', "'{}'".format(rgba_color)])

        # Space Bar Extension: Apply colors from file
        space_bar_css = os.path.expanduser('~/.config/colors/space-bar.css')
        if os.path.exists(space_bar_css):
            space_bar_colors = {}
            with open(space_bar_css, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        parts = line.split('=', 1)
                        if len(parts) == 2:
                            space_bar_colors[parts[0].strip()] = parts[1].strip().strip('\'"')
            if space_bar_colors:
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/space-bar/appearance/active-workspace-background-color', "'{}'".format(space_bar_colors.get('active_bg', ''))])
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/space-bar/appearance/active-workspace-text-color', "'{}'".format(space_bar_colors.get('active_fg', ''))])
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/space-bar/appearance/inactive-workspace-text-color', "'{}'".format(space_bar_colors.get('inactive_fg', ''))])

        # Search-light Extension: Apply colors from file
        search_light_css = os.path.expanduser('~/.config/colors/search-light.css')
        if os.path.exists(search_light_css):
            search_light_colors = {}
            with open(search_light_css, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        parts = line.split('=', 1)
                        if len(parts) == 2:
                            search_light_colors[parts[0].strip()] = parts[1].strip()
            if search_light_colors:
                # Note: The fish script adds (color, 0.75) and (color, 1.0) for rgba values
                bg_color = search_light_colors.get('background', '')
                fg_color = search_light_colors.get('foreground', '')
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/search-light/background-color', f"('{bg_color}', 0.75)"])
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/search-light/text-color', f"('{fg_color}', 1.0)"])
                subprocess.run(['dconf', 'write', '/org/gnome/shell/extensions/search-light/panel-icon-color', f"('{fg_color}', 1.0)"])

    except Exception as e:
        print(f"An error occurred while reloading UI: {e}")

    print("Theme applied successfully!")


class ThemeSelectorWindow(Gtk.ApplicationWindow):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self.set_title("Theme Selector")
        self.set_title("Theme Selector")
        self.set_default_size(300, 400)

        header = Gtk.HeaderBar()
        header.set_show_title_buttons(False)
        self.set_titlebar(header)

        # --- Layout and Widgets ---
        self.main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.main_box.set_margin_top(10)
        self.main_box.set_margin_bottom(10)
        self.main_box.set_margin_start(10)
        self.main_box.set_margin_end(10)
        self.set_child(self.main_box)

        # Scrolled Window for ListBox
        scrolled_window = Gtk.ScrolledWindow()
        scrolled_window.set_has_frame(True)
        scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled_window.set_vexpand(True)
        self.main_box.append(scrolled_window)

        # ListBox for themes
        self.theme_list_box = Gtk.ListBox()
        self.theme_list_box.set_selection_mode(Gtk.SelectionMode.SINGLE)
        scrolled_window.set_child(self.theme_list_box)

        # Connect key press event
        key_controller = Gtk.EventControllerKey.new()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

        self.populate_themes()

        # Apply Button
        self.apply_button = Gtk.Button(label="Apply Theme")
        self.apply_button.connect('clicked', self.on_apply_clicked)
        self.apply_button.add_css_class("suggested-action")
        self.main_box.append(self.apply_button)

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Return:
            self.on_apply_clicked(self.apply_button)
        elif keyval == Gdk.KEY_Escape:
            self.close()

    def populate_themes(self):
        """Scans the themes directory and adds themes to the list box."""
        try:
            themes = [d for d in os.listdir(THEMES_DIR) if os.path.isdir(os.path.join(THEMES_DIR, d))]
            for theme_name in sorted(themes):
                label = Gtk.Label(label=theme_name, xalign=0)
                self.theme_list_box.append(label)
        except FileNotFoundError:
            label = Gtk.Label(label=f"Error: Directory not found\n{THEMES_DIR}", xalign=0)
            self.theme_list_box.append(label)

    def on_apply_clicked(self, widget):
        """Handle the apply button click event."""
        selected_row = self.theme_list_box.get_selected_row()
        if selected_row:
            theme_name = selected_row.get_child().get_label()
            # Run the apply logic in a separate thread to avoid freezing the GUI
            GLib.idle_add(self.show_spinner)
            GLib.timeout_add(100, self.run_apply_thread, theme_name)
        else:
            print("No theme selected.")

    def show_spinner(self):
        self.spinner = Gtk.Spinner()
        self.spinner.start()
        self.main_box.append(self.spinner)

    def run_apply_thread(self, theme_name):
        apply_theme(theme_name)
        self.spinner.stop()
        self.main_box.remove(self.spinner)
        self.close()  # Close the window after applying the theme
        # We return False so the timeout does not run again
        return False

class ThemeSelectorApp(Adw.Application):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.win = None

    def do_activate(self):
        self.win = ThemeSelectorWindow(application=self)
        self.win.present()

if __name__ == "__main__":
    app = ThemeSelectorApp(application_id="com.sakib.ThemeSelector")
    exit_status = app.run(sys.argv)
    sys.exit(exit_status)
