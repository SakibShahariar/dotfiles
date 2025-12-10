#!/usr/bin/env python3

import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib, Gio, Gdk

import os
import subprocess
from pathlib import Path

class ThemeSwitcher(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="com.example.ThemeSwitcher",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_activate(self):
        # Create a new window
        self.window = Gtk.ApplicationWindow(application=self, title="Theme Switcher")
        self.window.set_default_size(300, 400)

        header = Gtk.HeaderBar()
        self.window.set_titlebar(header)

        config_button = Gtk.Button.new_from_icon_name("preferences-system-symbolic")
        config_button.connect("clicked", self.on_config_clicked)
        header.pack_start(config_button)

        # Add key controller to close on escape
        controller = Gtk.EventControllerKey()
        controller.connect("key-pressed", self.on_key_pressed)
        self.window.add_controller(controller)

        # --- Gtk.ListView Implementation ---

        # 1. Create a model
        self.string_list = Gtk.StringList()
        self.load_themes_to_model()

        # 2. Create a factory
        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", self.on_factory_setup)
        factory.connect("bind", self.on_factory_bind)

        # 3. Create a selection model
        selection_model = Gtk.SingleSelection(model=self.string_list)

        # 4. Create the list view
        list_view = Gtk.ListView(model=selection_model, factory=factory)
        list_view.set_can_focus(True) # Make focusable for keyboard navigation
        list_view.connect("activate", self.on_list_activate) # Handle activation
        list_view.add_css_class("theme-list")

        # Add CSS to make the list look clean
        css_provider = Gtk.CssProvider()
        css_data = """
        .theme-list listitem {
            padding: 8px 12px;
        }
        """
        css_provider.load_from_data(css_data.encode())
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        # 5. Put it in a ScrolledWindow
        scrolled_window = Gtk.ScrolledWindow()
        scrolled_window.set_child(list_view)
        scrolled_window.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled_window.set_vexpand(True)

        # Create a main box layout
        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        main_box.set_margin_top(10)
        main_box.set_margin_bottom(10)
        main_box.set_margin_start(10)
        main_box.set_margin_end(10)
        main_box.append(Gtk.Label(label="Select a Theme:"))
        main_box.append(scrolled_window)

        self.window.set_child(main_box)
        self.window.present()

    def on_config_clicked(self, button):
        script_path = Path.home() / "wallpaper-config-editor" / "target" / "debug" / "wallpaper-config-editor"
        if script_path.exists():
            subprocess.Popen([str(script_path)])
        else:
            self.show_error_dialog(f"Wallpaper config editor not found at {script_path}")

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.window.close()

    def load_themes_to_model(self):
        try:
            theme_dir = Path.home() / ".config" / "matugen" / "themes"
            if not theme_dir.exists():
                self.show_error_dialog(f"Theme directory not found: {theme_dir}")
                return
            theme_names = sorted([f.stem for f in theme_dir.glob("*.json")])
            self.string_list.splice(0, self.string_list.get_n_items(), theme_names)
        except Exception as e:
            self.show_error_dialog(f"An error occurred while loading themes: {e}")

    def on_factory_setup(self, factory, list_item):
        label = Gtk.Label(xalign=0)
        list_item.set_child(label)

    def on_factory_bind(self, factory, list_item):
        label = list_item.get_child()
        string_object = list_item.get_item()
        label.set_label(string_object.get_string())

    def on_list_activate(self, list_view, position):
        model = list_view.get_model()
        item = model.get_item(position)
        if not item:
            return

        theme_name = item.get_string()
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
