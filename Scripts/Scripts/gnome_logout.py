#!/usr/bin/env python

import sys
import subprocess
import shutil
import gi

gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib, Gdk

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

class LogoutWindow(Adw.ApplicationWindow):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.set_title("System Actions")
        self.set_default_size(420, 360)
        self.set_resizable(False)
        self.set_modal(True)

        self.action_map = {}

        main_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
        main_box.add_css_class("logout-box")
        self.set_content(main_box)

        title = Gtk.Label(label="System Actions")
        title.add_css_class("title-1")
        main_box.append(title)

        grid = Gtk.Grid(
            column_spacing=12,
            row_spacing=12,
            halign=Gtk.Align.CENTER,
            valign=Gtk.Align.CENTER
        )
        main_box.append(grid)

        actions = self._get_available_actions()

        first_button = None
        row = col = 0
        for label, icon, cmd, destructive, shortcut in actions:
            button = Gtk.Button()
            button.set_child(Adw.ButtonContent(label=label, icon_name=icon))
            button.connect("clicked", self.on_action_clicked, cmd)

            button.add_css_class("pill")
            # Only keep destructive-action if NOT reboot/shutdown
            if destructive and label not in ("Reboot", "Shutdown"):
                button.add_css_class("destructive-action")

            # Set tooltip for keyboard shortcut
            if shortcut:
                button.set_tooltip_text(f"{label} ({chr(shortcut).upper()})")
                self.action_map[shortcut] = cmd

            grid.attach(button, col, row, 1, 1)

            if first_button is None:
                first_button = button  # remember first button for auto-focus

            col += 1
            if col >= 2:
                col = 0
                row += 1

        # Auto-focus first button
        if first_button:
            first_button.grab_focus()

        cancel = Gtk.Button(label="Cancel")
        cancel.add_css_class("pill")
        cancel.connect("clicked", lambda *_: self.close())
        main_box.append(cancel)

        key_controller = Gtk.EventControllerKey()
        key_controller.connect("key-pressed", self.on_key_pressed)
        self.add_controller(key_controller)

    def _get_available_actions(self):
        actions = []

        if shutil.which("loginctl"):
            actions.append((
                "Lock",
                "system-lock-screen-symbolic",
                ["loginctl", "lock-session"],
                False,
                Gdk.KEY_l
            ))

        if shutil.which("gnome-session-quit"):
            actions.append((
                "Log Out",
                "system-log-out-symbolic",
                ["gnome-session-quit", "--logout", "--no-prompt"],
                False,
                Gdk.KEY_o
            ))

        if shutil.which("gdmflexiserver"):
            actions.append((
                "Switch User",
                "system-users-symbolic",
                ["gdmflexiserver"],
                False,
                Gdk.KEY_u
            ))
        elif shutil.which("dm-tool"):
            actions.append((
                "Switch User",
                "system-users-symbolic",
                ["dm-tool", "switch-to-greeter"],
                False,
                Gdk.KEY_u
            ))

        if shutil.which("systemctl"):
            actions.append((
                "Suspend",
                "weather-clear-night-symbolic",
                ["systemctl", "suspend"],
                False,
                Gdk.KEY_s
            ))

            try:
                r = subprocess.run(
                    ["systemctl", "can-hibernate"],
                    capture_output=True,
                    text=True
                )
                if "yes" in r.stdout:
                    actions.append((
                        "Hibernate",
                        "night-light-symbolic",
                        ["systemctl", "hibernate"],
                        False,
                        Gdk.KEY_h
                    ))
            except Exception:
                pass

            actions.append((
                "Reboot",
                "system-reboot-symbolic",
                ["systemctl", "reboot"],
                True,  # normal button, no destructive-action class
                Gdk.KEY_r
            ))

            actions.append((
                "Shutdown",
                "system-shutdown-symbolic",
                ["systemctl", "poweroff"],
                True,  # normal button
                Gdk.KEY_p
            ))

        return actions

    def on_key_pressed(self, controller, keyval, keycode, state):
        if keyval == Gdk.KEY_Escape:
            self.close()
            return True

        if keyval in self.action_map:
            self.on_action_clicked(None, self.action_map[keyval])
            return True

        return False

    def on_action_clicked(self, button, command):
        try:
            subprocess.run(command, check=True)
            self.close()
        except Exception as e:
            dialog = Adw.MessageDialog(
                transient_for=self,
                heading="Error",
                body=str(e),
            )
            dialog.add_response("ok", "OK")
            dialog.present()

class GnomeLogoutApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="dev.gemini.GnomeLogout")
        GLib.set_application_name("System Actions")

    def do_startup(self):
        Adw.Application.do_startup(self)
        css = Gtk.CssProvider()
        css.load_from_string(CSS)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            css,
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

