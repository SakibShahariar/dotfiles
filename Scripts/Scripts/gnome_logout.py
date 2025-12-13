#!/usr/bin/env python

import sys
import subprocess
import re
import gi

gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib, Gdk

# CSS styles embedded as a Python string
CSS = """
.logout-box {
    padding: 24px;
    border-radius: 12px;
}

.logout-box button {
    font-size: 1.1rem;
    min-height: 60px;
    min-width: 120px;
    margin: 8px;
}
"""

class OSSelectionDialog(Adw.Dialog):
    """A dialog window to show the list of discovered operating systems."""
    def __init__(self, parent, entries, is_efi=False, **kwargs):
        super().__init__(transient_for=parent, **kwargs)
        self.set_title("Select Operating System")
        self.is_efi = is_efi

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)
        self.set_child(box)

        for entry in entries:
            button = Gtk.Button(label=entry["title"])
            if is_efi:
                button.connect("clicked", self.on_efi_os_selected, entry["id"])
            else:
                button.connect("clicked", self.on_os_selected, entry["id"])
            button.add_css_class("pill")
            box.append(button)

        self.add_response("cancel", "Cancel")
        self.set_default_response("cancel")
        self.connect("response", lambda d, r: d.close())

    def on_os_selected(self, button, entry_id):
        self.close()
        command = ["systemctl", "reboot", "--boot-loader-entry", entry_id]
        privileged_command = ["pkexec"] + command
        self.get_transient_for().on_action_clicked(None, privileged_command)

    def on_efi_os_selected(self, button, entry_id):
        self.close()
        parent_window = self.get_transient_for()
        # Use pkexec for consistency and broader compatibility.
        # Combine setting bootnext and rebooting into a single shell command
        # to ensure pkexec is only called once.
        combined_command = f"efibootmgr --bootnext {entry_id} && systemctl reboot"
        command = ["pkexec", "bash", "-c", combined_command]
        parent_window.on_action_clicked(None, command)

class LogoutWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("System Actions")
        self.set_default_size(400, 300)
        self.set_resizable(False)
        self.set_modal(True)

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        main_box.add_css_class("logout-box")
        self.set_content(main_box)

        grid = Gtk.Grid(
            column_spacing=12, row_spacing=12,
            halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER
        )
        main_box.append(grid)

        actions = [
            ("Lock", "system-lock-screen-symbolic", ["loginctl", "lock-session"]),
            ("Log Out", "system-log-out-symbolic", ["gnome-session-quit", "--logout", "--no-prompt"]),
            ("Switch User", "system-users-symbolic", ["gdmflexiserver"]),
            ("Suspend", "weather-clear-night-symbolic", ["systemctl", "suspend"]),
            ("Reboot", "system-reboot-symbolic", ["systemctl", "reboot"]),
            ("Shutdown", "system-shutdown-symbolic", ["systemctl", "poweroff"]),
            # ("Reboot to OS...", "go-next-symbolic", "select_os"),
        ]

        for i, (label, icon, cmd) in enumerate(actions):
            button = Gtk.Button()
            content = Adw.ButtonContent(label=label, icon_name=icon)
            button.set_child(content)
            if cmd == "select_os":
                button.connect("clicked", self.on_select_os_clicked)
            else:
                button.connect("clicked", self.on_action_clicked, cmd)
            button.add_css_class("pill")
            grid.attach(button, i % 2, i // 2, 1, 1)

        cancel_button = Gtk.Button(label="Cancel")
        cancel_button.connect("clicked", lambda _: self.close())
        cancel_button.add_css_class("pill")
        main_box.append(cancel_button)

        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

    def show_error_dialog(self, message, heading="Error"):
        """Shows an Adwaita error dialog."""
        dialog = Adw.MessageDialog(
            transient_for=self,
            heading=heading,
            body=message,
        )
        dialog.add_response("ok", "OK")
        dialog.set_default_response("ok")
        dialog.connect("response", lambda d, r: d.close())
        dialog.present()

    def _parse_bootctl_output(self, output):
        entries = []
        current_entry = {}
        for line in output.splitlines():
            clean_line = line.strip()
            if not clean_line or clean_line.startswith("---"):
                if current_entry.get("id") and current_entry.get("title"):
                    entries.append(current_entry)
                current_entry = {}
                continue
            if ":" in clean_line:
                key, value = clean_line.split(":", 1)
                key = key.strip().lower()
                value = value.strip()
                if key in ["title", "id"]:
                    current_entry[key] = value
        if current_entry.get("id") and current_entry.get("title"):
            entries.append(current_entry)
        return [e for e in entries if "id" in e and "title" in e]

    def _parse_efibootmgr_output(self, output):
        entries = []
        # Regex to find active boot entries, e.g., "Boot0001* Windows Boot Manager"
        boot_entry_regex = re.compile(r"^(Boot(\d{4})\*\s)(.*)")
        for line in output.splitlines():
            match = boot_entry_regex.match(line)
            if match:
                boot_id = match.group(2)
                description = match.group(3).strip()

                # Heuristic to clean up the description
                if "HD(" in description:
                    description = description.split("HD(")[0].strip()
                elif "/" in description:
                    description = description.split("/")[0].strip()
                
                if boot_id and description:
                    entries.append({"id": boot_id, "title": description})
        return entries

    def _get_boot_entries(self):
        """
        Tries to get boot entries from bootctl, falling back to efibootmgr.
        Returns a tuple of (entries, method), or raises an error.
        """
        # 1. Try bootctl
        try:
            proc = subprocess.run(
                ["bootctl", "list"],
                capture_output=True,
                text=True,
                check=False
            )
            if proc.returncode == 0 and "No boot loader entries found" not in proc.stdout:
                entries = self._parse_bootctl_output(proc.stdout)
                if entries:
                    return entries, "bootctl"
        except FileNotFoundError:
            pass  # bootctl not found, proceed to efibootmgr
        except Exception as e:
            print(f"Warning: bootctl failed, trying efibootmgr. Error: {e}")

        # 2. Fallback to efibootmgr
        try:
            proc = subprocess.run(
                ["efibootmgr"],
                capture_output=True,
                text=True,
                check=False
            )
            if proc.returncode != 0:
                raise subprocess.CalledProcessError(
                    proc.returncode, proc.args, proc.stdout, proc.stderr
                )
            
            entries = self._parse_efibootmgr_output(proc.stdout)
            if not entries:
                raise ValueError("No boot entries found in efibootmgr output.")
            return entries, "efi"
        
        except FileNotFoundError:
            raise FileNotFoundError("Neither `bootctl` nor `efibootmgr` could be found.")
        except (subprocess.CalledProcessError, ValueError) as e:
            raise RuntimeError(f"Failed to get boot entries from efibootmgr.\n\nDetails: {e}") from e

    def on_select_os_clicked(self, button):
        try:
            entries, boot_method = self._get_boot_entries()
            is_efi = (boot_method == "efi")
            dialog = OSSelectionDialog(parent=self, entries=entries, is_efi=is_efi)
            dialog.present()
        except Exception as e:
            self.show_error_dialog(f"Could not retrieve boot entries:\n{e}")

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def on_action_clicked(self, button, command):
        try:
            subprocess.run(command, check=True)
            self.close()
        except (subprocess.CalledProcessError, FileNotFoundError) as e:
            self.show_error_dialog(f"Failed to execute command: {' '.join(command)}.\nError: {e}")

class GnomeLogoutApp(Adw.Application):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.application_id = "dev.gemini.GnomeLogout"
        GLib.set_application_name("Gnome Logout")

    def do_startup(self):
        Adw.Application.do_startup(self)
        css_provider = Gtk.CssProvider()
        css_provider.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = LogoutWindow(application=self)
        win.present()

if __name__ == "__main__":
    app = GnomeLogoutApp()
    sys.exit(app.run(sys.argv))