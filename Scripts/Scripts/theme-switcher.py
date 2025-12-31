#!/usr/bin/env python3

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, GLib, Gio, Gdk, Adw, GObject
import cairo

import os
import subprocess
import random
import json
from pathlib import Path

# Custom GObject to hold theme data
class Theme(GObject.Object):
    __gtype_name__ = 'Theme'
    
    name = GObject.Property(type=str)
    primary_color = GObject.Property(type=str)
    surface_color = GObject.Property(type=str)

    def __init__(self, name, primary_color, surface_color):
        super().__init__()
        self.name = name
        self.primary_color = primary_color
        self.surface_color = surface_color

class ThemeSwitcher(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.example.ThemeSwitcher",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_startup(self):
        Gtk.Application.do_startup(self)
        Adw.init()

        # Add CSS provider for styling color swatches
        css_provider = Gtk.CssProvider()
        css_provider.load_from_data("""
        .color-swatch {
            border-radius: 5px;
            border: 1px solid rgba(0,0,0,0.2);
        }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def do_activate(self):
        # Create a new window
        self.window = Adw.ApplicationWindow(application=self, title="Theme Switcher")
        self.window.set_default_size(300, 400)

        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(False)
        
        config_button = Gtk.Button.new_from_icon_name("preferences-system-symbolic")
        config_button.connect("clicked", self.on_config_clicked)
        header.pack_start(config_button)

        random_button = Gtk.Button.new_from_icon_name("media-playlist-shuffle-symbolic")
        random_button.connect("clicked", self.on_random_clicked)
        header.pack_end(random_button)

        # Add key controller to close on escape
        controller = Gtk.EventControllerKey()
        controller.connect("key-pressed", self.on_key_pressed)
        self.window.add_controller(controller)

        # --- Gtk.ListView Implementation ---

        # 1. Create a model
        self.theme_store = Gio.ListStore(item_type=Theme)
        self.load_themes_to_model()

        # 2. Create a factory
        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", self.on_factory_setup)
        factory.connect("bind", self.on_factory_bind)

        # 3. Create a selection model
        selection_model = Gtk.SingleSelection(model=self.theme_store)
        # Set the first item as selected if available
        if self.theme_store.get_n_items() > 0:
            selection_model.set_selected(0)

        # 4. Create the list view
        list_view = Gtk.ListView(model=selection_model, factory=factory)
        list_view.set_can_focus(True) # Make focusable for keyboard navigation
        list_view.connect("activate", self.on_list_activate) # Handle activation
        list_view.add_css_class("theme-list")

        self.window.set_default_widget(list_view)

        # 5. Put it in a ScrolledWindow
        scrolled_window = Gtk.ScrolledWindow()
        scrolled_window.set_child(list_view)
        scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled_window.set_vexpand(True)

        # Create a main box layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        main_box.append(header) # Append header to main_box
        main_box.set_margin_top(10)
        main_box.set_margin_bottom(10)
        main_box.set_margin_start(10)
        main_box.set_margin_end(10)
        theme_label = Gtk.Label(label="Select a Theme:")
        theme_label.add_css_class("title-1")
        main_box.append(theme_label)
        main_box.append(scrolled_window)

        self.window.set_content(main_box)
        self.window.present()
        list_view.grab_focus()

    def on_config_clicked(self, button):
        script_path = Path.home() / "wallpaper-config-editor" / "target" / "debug" / "wallpaper-config-editor"
        if script_path.exists():
            subprocess.Popen([str(script_path)])
        else:
            self.show_error_dialog(f"Wallpaper config editor not found at {script_path}")

    def on_random_clicked(self, button):
        n_themes = self.theme_store.get_n_items()
        if n_themes > 0:
            random_index = random.randint(0, n_themes - 1)
            theme_object = self.theme_store.get_item(random_index)
            self.apply_theme(theme_object.name)

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()

    def load_themes_to_model(self):
        try:
            theme_dir = Path.home() / ".config" / "matugen" / "themes"
            if not theme_dir.exists():
                self.show_error_dialog(f"Theme directory not found: {theme_dir}")
                return
            
            themes = []
            for theme_file in sorted(theme_dir.glob("*.json")):
                with open(theme_file, 'r') as f:
                    data = json.load(f)
                    primary_color = data.get("colors", {}).get("primary", {}).get("default", {}).get("color", "#FFFFFF")
                    surface_color = data.get("colors", {}).get("surface", {}).get("default", {}).get("color", "#000000")
                    themes.append(Theme(theme_file.stem, primary_color, surface_color))
            
            self.theme_store.splice(0, self.theme_store.get_n_items(), themes)

        except Exception as e:
            self.show_error_dialog(f"An error occurred while loading themes: {e}")

    def draw_color_swatch(self, area, cr, width, height, color_str):
        rgba = Gdk.RGBA()
        rgba.parse(color_str)
        
        cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha)
        cr.paint()

    def on_factory_setup(self, factory, list_item):
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        box.set_margin_top(5)
        box.set_margin_bottom(5)
        box.set_margin_start(5)
        box.set_margin_end(5)
        
        primary_color_area = Gtk.DrawingArea()
        primary_color_area.set_content_width(20)
        primary_color_area.set_content_height(20)
        primary_color_area.add_css_class("color-swatch")
        
        surface_color_area = Gtk.DrawingArea()
        surface_color_area.set_content_width(20)
        surface_color_area.set_content_height(20)
        surface_color_area.add_css_class("color-swatch")

        label = Gtk.Label(xalign=0)
        label.set_hexpand(True)
        
        box.append(label)
        box.append(surface_color_area)
        box.append(primary_color_area)
        
        list_item.set_child(box)

    def on_factory_bind(self, factory, list_item):
        box = list_item.get_child()
        theme_object = list_item.get_item()
        
        label = box.get_first_child()
        surface_color_area = label.get_next_sibling()
        primary_color_area = surface_color_area.get_next_sibling()
        
        label.set_label(theme_object.name)
        
        primary_color_area.set_draw_func(self.draw_color_swatch, theme_object.primary_color)
        surface_color_area.set_draw_func(self.draw_color_swatch, theme_object.surface_color)

    def on_list_activate(self, list_view, position):
        model = list_view.get_model()
        theme_object = model.get_item(position)
        if not theme_object:
            return
        self.apply_theme(theme_object.name)

    def apply_theme(self, theme_name):
        print(f"Selected theme: {theme_name}")

        # Execute the apply-theme.fish script
        script_path = Path.home() / "Scripts" / "apply-theme.fish"
        if not script_path.exists():
            self.show_error_dialog(f"Error: apply-theme.fish not found at {script_path}")
            return

        try:
            subprocess.run(["fish", "-c", f"{script_path} {theme_name}"], check=True)
            print(f"Successfully applied theme: {theme_name}")
            self.window.close()
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(f"Error applying theme {theme_name}: {e}")
        except FileNotFoundError:
            self.show_error_dialog(f"Error: 'fish' command not found. Is fish shell installed?")

    def show_error_dialog(self, message):
        dialog = Gtk.MessageDialog(
            transient_for=self.window,
            modal=True,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text="Error",
            secondary_text=str(message)
        )
        dialog.connect("response", lambda d, r: d.destroy())
        dialog.present()

def main():
    app = ThemeSwitcher()
    app.run(None)

if __name__ == "__main__":
    main()
