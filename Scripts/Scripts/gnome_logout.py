#!/usr/bin/env python

import sys
import subprocess
import shutil
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

.destructive-action {
    background: alpha(@error_color, 0.1);
}
"""

class LogoutWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("System Actions")
        self.set_default_size(450, 350)
        self.set_resizable(False)
        self.set_modal(True)

        # Detect available desktop environment
        self.desktop = self._detect_desktop_environment()

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        main_box.add_css_class("logout-box")
        self.set_content(main_box)

        # Title
        title = Gtk.Label(label="System Actions")
        title.add_css_class("title-1")
        main_box.append(title)

        grid = Gtk.Grid(
            column_spacing=12, row_spacing=12,
            halign=Gtk.Align.CENTER, valign=Gtk.Align.CENTER
        )
        main_box.append(grid)

        # Define actions with desktop-specific commands
        actions = self._get_available_actions()

        row = 0
        col = 0
        for action in actions:
            label, icon, cmd, is_destructive = action

            button = Gtk.Button()
            content = Adw.ButtonContent(label=label, icon_name=icon)
            button.set_child(content)
            button.connect("clicked", self.on_action_clicked, cmd)

            button.add_css_class("pill")
            if is_destructive:
                button.add_css_class("destructive-action")

            grid.attach(button, col, row, 1, 1)

            col += 1
            if col >= 2:
                col = 0
                row += 1

        # Cancel button
        cancel_button = Gtk.Button(label="Cancel")
        cancel_button.connect("clicked", lambda _: self.close())
        cancel_button.add_css_class("pill")
        main_box.append(cancel_button)

        # Keyboard shortcuts
        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

    def _detect_desktop_environment(self):
        """Detect the current desktop environment."""
        desktop = GLib.getenv("XDG_CURRENT_DESKTOP") or ""
        session = GLib.getenv("DESKTOP_SESSION") or ""

        desktop_lower = desktop.lower()
        session_lower = session.lower()

        if "gnome" in desktop_lower or "gnome" in session_lower:
            return "gnome"
        elif "kde" in desktop_lower or "plasma" in desktop_lower:
            return "kde"
        elif "xfce" in desktop_lower or "xfce" in session_lower:
            return "xfce"
        elif "mate" in desktop_lower:
            return "mate"
        elif "cinnamon" in desktop_lower:
            return "cinnamon"
        else:
            return "generic"

    def _get_available_actions(self):
        """Return available actions based on desktop environment and available commands."""
        actions = []

        # Lock
        if shutil.which("loginctl"):
            actions.append(("Lock", "system-lock-screen-symbolic", ["loginctl", "lock-session"], False))
        elif shutil.which("xdg-screensaver"):
            actions.append(("Lock", "system-lock-screen-symbolic", ["xdg-screensaver", "lock"], False))

        # Logout - desktop-specific
        logout_cmd = None
        if self.desktop == "gnome" and shutil.which("gnome-session-quit"):
            logout_cmd = ["gnome-session-quit", "--logout", "--no-prompt"]
        elif self.desktop == "kde" and shutil.which("qdbus"):
            logout_cmd = ["qdbus", "org.kde.ksmserver", "/KSMServer", "logout", "0", "0", "0"]
        elif self.desktop == "xfce" and shutil.which("xfce4-session-logout"):
            logout_cmd = ["xfce4-session-logout", "--logout"]
        elif self.desktop == "mate" and shutil.which("mate-session-save"):
            logout_cmd = ["mate-session-save", "--logout"]
        elif self.desktop == "cinnamon" and shutil.which("cinnamon-session-quit"):
            logout_cmd = ["cinnamon-session-quit", "--logout", "--no-prompt"]
        elif shutil.which("loginctl"):
            logout_cmd = ["loginctl", "terminate-user", GLib.get_user_name()]

        if logout_cmd:
            actions.append(("Log Out", "system-log-out-symbolic", logout_cmd, False))

        # Switch User - desktop-specific
        switch_user_cmd = None
        if self.desktop == "gnome" and shutil.which("gdmflexiserver"):
            switch_user_cmd = ["gdmflexiserver"]
        elif self.desktop == "gnome" and shutil.which("dm-tool"):
            switch_user_cmd = ["dm-tool", "switch-to-greeter"]
        elif self.desktop == "kde" and shutil.which("qdbus"):
            switch_user_cmd = ["qdbus", "org.kde.ksmserver", "/KSMServer", "org.kde.KSMServerInterface.openSwitchUserDialog"]
        elif shutil.which("dm-tool"):
            switch_user_cmd = ["dm-tool", "switch-to-greeter"]

        if switch_user_cmd:
            actions.append(("Switch User", "system-users-symbolic", switch_user_cmd, False))

        # Suspend
        if shutil.which("systemctl"):
            actions.append(("Suspend", "weather-clear-night-symbolic", ["systemctl", "suspend"], False))

        # Hibernate (if available)
        if shutil.which("systemctl"):
            try:
                result = subprocess.run(
                    ["systemctl", "can-hibernate"],
                    capture_output=True,
                    text=True,
                    check=False
                )
                if result.returncode == 0 and "yes" in result.stdout:
                    actions.append(("Hibernate", "night-light-symbolic", ["systemctl", "hibernate"], False))
            except Exception:
                pass

        # Reboot
        if shutil.which("systemctl"):
            actions.append(("Reboot", "system-reboot-symbolic", ["systemctl", "reboot"], True))

        # Shutdown
        if shutil.which("systemctl"):
            actions.append(("Shutdown", "system-shutdown-symbolic", ["systemctl", "poweroff"], True))

        return actions

    def show_error_dialog(self, message, heading="Error"):
        """Shows an Adwaita error dialog."""
        dialog = Adw.MessageDialog(
            transient_for=self,
            heading=heading,
            body=message,
        )
        dialog.add_response("ok", "OK")
        dialog.set_default_response("ok")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.connect("response", lambda d, r: d.close())
        dialog.present()

    def on_key_pressed(self, controller, keyval, keycode, state):
        """Handle keyboard shortcuts."""
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True
        return False

    def on_action_clicked(self, button, command):
        """Execute system action command."""
        try:
            subprocess.run(command, check=True, timeout=30)
            self.close()
        except subprocess.TimeoutExpired:
            self.show_error_dialog(
                f"Command timed out: {' '.join(command)}",
                heading="Timeout"
            )
        except subprocess.CalledProcessError as e:
            self.show_error_dialog(
                f"Command failed: {' '.join(command)}\n\nExit code: {e.returncode}",
                heading="Command Failed"
            )
        except FileNotFoundError:
            self.show_error_dialog(
                f"Command not found: {command[0]}\n\nPlease install the required package.",
                heading="Command Not Found"
            )
        except Exception as e:
            self.show_error_dialog(
                f"Failed to execute: {' '.join(command)}\n\n{e}",
                heading="Error"
            )

class GnomeLogoutApp(Adw.Application):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.application_id = "dev.gemini.GnomeLogout"
        GLib.set_application_name("System Actions")

    def do_startup(self):
        Adw.Application.do_startup(self)
        css_provider = Gtk.CssProvider()
        css_provider.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = LogoutWindow(application=self)
        win.present()

if __name__ == "__main__":
    app = GnomeLogoutApp()
    sys.exit(app.run(sys.argv))
