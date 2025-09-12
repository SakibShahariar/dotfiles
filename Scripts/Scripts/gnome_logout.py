#!/usr/bin/env python

import sys
import subprocess
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

class OSSelectionDialog(Gtk.Dialog):
    """A dialog window to show the list of discovered operating systems."""
    def __init__(self, parent, entries, is_efi=False, **kwargs):
        super().__init__(**kwargs)
        self.set_transient_for(parent)
        self.set_title("Select Operating System")
        self.is_efi = is_efi  # Flag to indicate if we're using EFI entries

        # Create dialog content
        box = self.get_content_area()
        box.set_orientation(Gtk.Orientation.VERTICAL)
        box.set_spacing(12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        for entry in entries:
            button = Gtk.Button(label=entry["title"])
            if is_efi:
                button.connect("clicked", self.on_efi_os_selected, entry["id"])
            else:
                button.connect("clicked", self.on_os_selected, entry["id"])
            button.add_css_class("pill")
            box.append(button)

    def on_os_selected(self, button, entry_id):
        self.destroy()
        command = ["systemctl", "reboot", "--boot-loader-entry", entry_id]
        # Use pkexec to run the final reboot command with privileges
        privileged_command = ["pkexec"] + command
        self.get_transient_for().on_action_clicked(None, privileged_command)

    def on_efi_os_selected(self, button, entry_id):
        self.destroy()
        parent_window = self.get_transient_for()
        # Combine setting bootnext and rebooting into a single shell command
        # to ensure pkexec is only called once.
        combined_command = "efibootmgr --bootnext " + entry_id + " && systemctl reboot"
        command = ["pkexec", "bash", "-c", combined_command]
        # Delegate the execution to the main action handler
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
            ("Suspend", "weather-clear-night-symbolic", ["systemctl", "suspend"]),
            ("Reboot", "system-reboot-symbolic", ["systemctl", "reboot"]),
            ("Shutdown", "system-shutdown-symbolic", ["systemctl", "poweroff"]),
            ("Reboot to OS...", "go-next-symbolic", "select_os"),
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

        # The "Reboot to OS..." button has been moved into the grid.

        cancel_button = Gtk.Button(label="Cancel")
        cancel_button.connect("clicked", lambda _: self.close())
        cancel_button.add_css_class("pill")
        main_box.append(cancel_button)

        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

    def show_error_dialog(self, message):
        dialog = Gtk.MessageDialog(
            transient_for=self,
            flags=0,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=message
        )
        dialog.run()
        dialog.destroy()

    def on_select_os_clicked(self, button):
        try:
            # First try bootctl
            command = ["bootctl", "list"]
            result = subprocess.run(command, capture_output=True, text=True, check=False)

            output = result.stdout.strip()
            stderr = result.stderr.strip()

            # If bootctl shows no entries or fails, try efibootmgr
            if ("No boot loader entries found" in output or
                "No boot loader entries found" in stderr or
                not output or
                result.returncode != 0):

                command = ["efibootmgr"]
                result = subprocess.run(command, capture_output=True, text=True, check=False)

                if result.returncode != 0:
                    if result.returncode in [126, 127]:  # User cancelled pkexec
                        return
                    self.show_error_dialog("No boot entries found using either bootctl or efibootmgr.\n\n"
                                          "Make sure your system uses UEFI boot and that you have appropriate permissions.")
                    return

                output = result.stdout
                entries = []

                for line in output.splitlines():
                    if line.startswith("Boot") and "*" in line and not line.startswith("BootOrder"):
                        # Extract boot ID (e.g., 0000 from "Boot0000*")
                        boot_id = line.split()[0].replace("Boot", "").replace("*", "").strip()

                        # Extract the description - everything after the boot ID
                        description = line.split("*", 1)[1].strip()

                        # Clean up the description by removing any file path parts
                        if "HD(" in description and ".efi" in description:
                            # This is a typical EFI entry format, extract just the OS name
                            description = description.split("HD(")[0].strip()
                        elif "/" in description:
                            # Remove any path components
                            description = description.split("/")[0].strip()

                        entries.append({
                            "id": boot_id,
                            "title": description
                        })

                if not entries:
                    self.show_error_dialog("No UEFI boot entries found.\n\nRaw efibootmgr output:\n" + output)
                    return

                dialog = OSSelectionDialog(parent=self, entries=entries, is_efi=True)
                dialog.show()
                return

            # Original bootctl parsing code for when it works
            entries = []
            current_entry = {}

            for line in output.splitlines():
                clean_line = line.strip()

                # Skip empty lines and separator lines
                if not clean_line or clean_line.startswith("---"):
                    if current_entry:
                        entries.append(current_entry)
                        current_entry = {}
                    continue

                # Parse key-value pairs
                if ":" in clean_line:
                    key, value = clean_line.split(":", 1)
                    key = key.strip().lower()
                    value = value.strip()

                    if key == "title":
                        current_entry["title"] = value
                    elif key == "id":
                        current_entry["id"] = value

            # Add the last entry if exists
            if current_entry:
                entries.append(current_entry)

            # Filter only entries with both id and title
            entries = [e for e in entries if "id" in e and "title" in e]

            if not entries:
                self.show_error_dialog("No bootable OS entries found in the output.\n\nRaw output:\n" + output)
                return

            dialog = OSSelectionDialog(parent=self, entries=entries)
            dialog.show()

        except FileNotFoundError:
            self.show_error_dialog("Could not execute command. Is `pkexec` installed?")
        except Exception as e:
            self.show_error_dialog(f"Unexpected error: {str(e)}")

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
            self.show_error_dialog(f"Failed to execute command: {' '.join(command)}. Error: {e}")

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
