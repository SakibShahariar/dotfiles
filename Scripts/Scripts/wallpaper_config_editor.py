#!/usr/bin/env python3
import gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, Gio, GLib

import json
from pathlib import Path

class WallpaperConfigEditor(Gtk.Application):
    def __init__(self):
        super().__init__(application_id="com.example.WallpaperConfigEditor")
        self.config_path = Path.home() / ".config" / "matugen" / "wallpaper_map.json"
        self.config_path.parent.mkdir(parents=True, exist_ok=True)

    def do_activate(self):
        self.window = Gtk.ApplicationWindow(application=self, title="Wallpaper Configuration")
        self.window.set_default_size(700, 520)

        header = Gtk.HeaderBar()
        self.window.set_titlebar(header)

        save_button = Gtk.Button(label="Save")
        save_button.connect("clicked", self.on_save_clicked)
        header.pack_end(save_button)

        add_button = Gtk.Button(label="+")
        add_button.connect("clicked", self.on_add_clicked)
        header.pack_start(add_button)

        scrolled_window = Gtk.ScrolledWindow()
        self.window.set_child(scrolled_window)

        self.list_box = Gtk.ListBox()
        scrolled_window.set_child(self.list_box)

        self.load_config()
        self.window.present()

    def load_config(self):
        try:
            if self.config_path.exists():
                with open(self.config_path, "r") as f:
                    self.config_data = json.load(f)
            else:
                self.config_data = {}
        except Exception:
            self.config_data = {}

        for theme, wallpaper in sorted(self.config_data.items()):
            self._add_row_plain(theme, wallpaper)

    def _add_row_plain(self, theme, wallpaper):
        # use the plain Gtk.ListBoxRow (no subclassing, no custom names)
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL,
                      spacing=10,
                      margin_top=6, margin_bottom=6,
                      margin_start=10, margin_end=10)

        theme_label = Gtk.Label(label=theme, xalign=0)
        theme_label.set_valign(Gtk.Align.CENTER)
        theme_label.set_hexpand(False)

        wallpaper_button = Gtk.Button(label=wallpaper if wallpaper else "Select Wallpaper")
        wallpaper_button.set_hexpand(True)

        remove_btn = Gtk.Button(label="🗑")
        remove_btn.set_tooltip_text("Remove this theme")
        remove_btn.connect("clicked", self._on_remove_row_clicked, row)

        box.append(theme_label)
        box.append(wallpaper_button)
        box.append(remove_btn)
        row.set_child(box)

        # store metadata safely using GObject data slots
        row.set_data("theme_name", theme)
        row.set_data("wallpaper_button", wallpaper_button)

        wallpaper_button.connect("clicked", self._on_wallpaper_button_clicked, row)
        self.list_box.append(row)

    def on_add_clicked(self, button):
        dialog = Gtk.MessageDialog(
            transient_for=self.window,
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text="New theme name:",
        )

        entry = Gtk.Entry()
        entry.set_margin_top(6)
        entry.set_margin_bottom(6)
        entry.set_hexpand(True)
        dialog.get_content_area().append(entry)

        def on_resp(dlg, resp):
            if resp == Gtk.ResponseType.OK:
                name = entry.get_text().strip()
                if name:
                    exists = any(row.get_data("theme_name") == name for row in self.list_box.get_children())
                    if exists:
                        info = Gtk.MessageDialog(transient_for=self.window, modal=True,
                                                 message_type=Gtk.MessageType.INFO,
                                                 buttons=Gtk.ButtonsType.OK,
                                                 text=f"Theme '{name}' already exists.")
                        info.connect("response", lambda _d, _r: _d.destroy())
                        info.present()
                    else:
                        self._add_row_plain(name, "")
            dlg.destroy()

        dialog.connect("response", on_resp)
        dialog.present()

    def _on_remove_row_clicked(self, button, row):
        self.list_box.remove(row)

    def _on_wallpaper_button_clicked(self, button, row):
        file_dialog = Gtk.FileChooserDialog(
            title="Select a Wallpaper",
            transient_for=self.window,
            modal=True,
            action=Gtk.FileChooserAction.OPEN,
        )
        file_dialog.add_buttons("_Cancel", Gtk.ResponseType.CANCEL, "_Open", Gtk.ResponseType.ACCEPT)

        file_filter = Gtk.FileFilter()
        file_filter.set_name("Images")
        file_filter.add_pixbuf_formats()
        file_dialog.add_filter(file_filter)

        def on_dialog_response(dialog, response):
            if response == Gtk.ResponseType.ACCEPT:
                gfile = dialog.get_file()
                if gfile is not None:
                    path = gfile.get_path()
                    if path:
                        button.set_label(path)
            dialog.destroy()

        file_dialog.connect("response", on_dialog_response)
        file_dialog.present()

    def on_save_clicked(self, button):
        new_config = {}
        for row in self.list_box.get_children():
            theme = row.get_data("theme_name")
            wallpaper_btn = row.get_data("wallpaper_button")
            wallpaper = wallpaper_btn.get_label() if wallpaper_btn else ""
            if wallpaper and wallpaper != "Select Wallpaper":
                new_config[theme] = wallpaper
            else:
                new_config[theme] = ""

        with open(self.config_path, "w") as f:
            json.dump(new_config, f, indent=2)

        dialog = Gtk.MessageDialog(
            transient_for=self.window,
            modal=True,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text="Configuration Saved",
        )
        dialog.connect("response", lambda d, r: d.destroy())
        dialog.present()

def main():
    app = WallpaperConfigEditor()
    app.run(None)

if __name__ == "__main__":
    main()

