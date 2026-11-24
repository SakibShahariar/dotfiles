#!/usr/bin/env python3
"""Theme switcher: a libadwaita preferences-style picker for matugen themes.

Every theme file is one row. Files are split across five pages by variant
(Dark, Light, Dark HC, Light HC, AMOLED) shown with an Adw.ViewSwitcher.

Performance notes:
  * Theme metadata comes from ~/.cache/matugen/theme_index.json (mtime+size
    validated) instead of parsing every JSON file on every launch.
  * Pages build their rows lazily: only the visible page is populated, the
    others are filled when first shown or when a search touches them.
  * The first page is populated one idle after the window is mapped, so the
    window appears before ~100 rows are laid out.
  * Search is debounced and rows are rebuilt off the keystroke path; matching
    only needs the cached metadata.
  * Applying a theme spawns apply-theme.fish asynchronously (Gio), so the
    window keeps animating instead of freezing for the whole pipeline.
"""

import json
import os
import random
import re
import subprocess
import sys
import time
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, Gio, GLib, GObject, Gtk

THEMES_DIR = Path.home() / ".config" / "matugen" / "themes"
APPLY_SCRIPT = Path.home() / "Scripts" / "apply-theme.fish"
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) \
    / "matugen"
INDEX_FILE = CACHE_DIR / "theme_index.json"
SETTINGS_FILE = Path.home() / ".config" / "matugen" / "switcher.json"
SEARCH_DEBOUNCE_MS = 120
# Pages are re-stacked when a variant is hidden.  AdwViewStack keeps a
# pointer to the page a crossfade is leaving (last_visible_child) and
# stack_remove() does not clear it, so removing pages while
# transition-running is set is a use-after-free in libadwaita.  The restack
# therefore polls for the transition to finish instead of guessing a delay.
RESTACK_POLL_MS = 25
# Rows added inline before the first frame, then a few more every 16 ms
# (below the fold, so they never visibly pop in).
FIRST_BATCH = 40
DRAIN_BATCH = 25
DRAIN_INTERVAL_MS = 16

# (stack name, page label, searchable variant name, symbolic icon)
PAGE_ORDER = [
    ("dark", "Dark", "Dark", "weather-clear-night-symbolic"),
    ("light", "Light", "Light", "weather-clear-symbolic"),
    ("dark-high-contrast", "Dark HC", "Dark High Contrast", "contrast-symbolic"),
    ("light-high-contrast", "Light HC", "Light High Contrast",
     "display-brightness-symbolic"),
    ("amoled", "AMOLED", "AMOLED", "night-light-symbolic"),
]

VARIANT_RE = re.compile(
    r"^(?P<base>.+)-(?P<variant>dark-high-contrast|light-high-contrast|dark|light|amoled)$",
    re.IGNORECASE)


class Theme:
    """Plain data holder; it never enters a GObject model, so keep it cheap."""

    __slots__ = ("name", "apply_name", "variant", "primary_color",
                 "surface_color")

    def __init__(self, name, primary_color, surface_color,
                 apply_name=None, variant=""):
        self.name = name
        self.apply_name = apply_name or name
        self.variant = variant
        self.primary_color = primary_color
        self.surface_color = surface_color


# ------------------------------------------------------------------ helpers
def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback


def write_atomic(path, text):
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def load_settings():
    data = read_json(SETTINGS_FILE, {})
    return data if isinstance(data, dict) else {}


def save_settings(settings):
    SETTINGS_FILE.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(SETTINGS_FILE, json.dumps(settings, indent=2) + "\n")


def extract_color(data, key, fallback):
    node = data.get("colors", {}).get(key, fallback)
    if isinstance(node, str):
        return node
    if isinstance(node, dict):
        default = node.get("default", None)
        if isinstance(default, str):
            return default
        if isinstance(default, dict):
            color = default.get("color")
            if isinstance(color, str):
                return color
        color = node.get("color")
        if isinstance(color, str):
            return color
    return fallback


def variant_label(key):
    for page_key, _label, searchable, _icon in PAGE_ORDER:
        if page_key == key:
            return searchable
    return key


def scan_theme_files(cached):
    """Yield (stem, base, variant_key, primary, surface) using a metadata cache.

    The cache format is shared with wallpaper-config-editor.py:
        stem -> [mtime_ns, size, base, variant label, primary, surface]
    Entries are reused while the file's mtime and size are unchanged.
    """
    updated = {}
    for path in sorted(THEMES_DIR.glob("*.json"), key=lambda p: p.stem.lower()):
        match = VARIANT_RE.match(path.stem)
        if not match:
            print(f"[WARN] Skipping {path.name}: unknown variant")
            continue
        try:
            stat = path.stat()
        except OSError:
            continue

        # The stem always defines base and variant, so only the colours are
        # worth caching; that also keeps old cache labels from leaking in.
        variant_key = match.group("variant").lower()
        label = variant_label(variant_key)
        base = match.group("base")
        record = cached.get(path.stem)
        if (record and len(record) == 6
                and record[0] == stat.st_mtime_ns and record[1] == stat.st_size):
            primary, surface = record[4], record[5]
        else:
            data = read_json(path, None)
            if data is None:
                print(f"[WARN] Skipping unreadable {path.name}")
                continue
            primary = extract_color(data, "primary", "#FFFFFF")
            surface = extract_color(data, "surface", "#000000")

        updated[path.stem] = [stat.st_mtime_ns, stat.st_size,
                              base, label, primary, surface]
        yield path.stem, base, variant_key, primary, surface

    if updated != cached:
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        write_atomic(INDEX_FILE, json.dumps(updated, ensure_ascii=False))


class ThemeSwitcher(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.example.ThemeSwitcher",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.pages = []
        self.pages_by_name = {}
        self.theme_count = 0
        self.theme_objects = []
        self.needle = ""
        self.search_timeout = 0
        self.applying = False
        self.drain_id = 0
        self.settings = load_settings()
        self.settings.pop("show_tabs", None)   # superseded by hidden_tabs
        known = {key for key, *_rest in PAGE_ORDER}
        self.hidden_tabs = {key for key in self.settings.get("hidden_tabs", [])
                            if key in known}
        self.prefs_dialog = None
        self.prefs_rows = {}
        self.restack_id = 0

    # ------------------------------------------------------------------ setup
    def do_startup(self):
        Gtk.Application.do_startup(self)
        Adw.init()

    def do_activate(self):
        self.window = Adw.ApplicationWindow(application=self,
                                            title="Theme Switcher")
        self.window.set_default_size(620, 700)

        self.toast_overlay = Adw.ToastOverlay()

        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(False)

        self.stack = Adw.ViewStack()
        self.stack.set_hexpand(True)
        self.stack.set_vexpand(True)
        self.stack.connect("notify::visible-child", self.on_page_changed)

        # One tab per variant; Preferences can hide individual variants.
        self.view_switcher = Adw.ViewSwitcher(
            stack=self.stack, policy=Adw.ViewSwitcherPolicy.WIDE)
        self.view_switcher.set_halign(Gtk.Align.CENTER)
        header.set_title_widget(self.view_switcher)
        self.stack.set_enable_transitions(True)
        self.stack.set_transition_duration(120)

        # Narrow windows fall back to icon-only tabs, like GNOME apps do.
        breakpoint = Adw.Breakpoint.new(
            Adw.BreakpointCondition.parse("max-width: 560px"))
        breakpoint.add_setter(self.view_switcher, "policy",
                              Adw.ViewSwitcherPolicy.NARROW)
        self.window.add_breakpoint(breakpoint)
        self.breakpoint = breakpoint

        # Search lives in the header, like every libadwaita app.
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search themes…")
        # "changed" instead of "search-changed": the latter adds its own
        # 150 ms delay and is only emitted while the entry is mapped.
        self.search_entry.connect("changed", self.on_search_changed)

        self.search_bar = Gtk.SearchBar()
        self.search_bar.set_child(self.search_entry)
        self.search_bar.connect_entry(self.search_entry)
        self.search_bar.set_key_capture_widget(self.window)

        self.search_button = Gtk.ToggleButton()
        self.search_button.set_icon_name("system-search-symbolic")
        self.search_button.set_tooltip_text("Search themes (Ctrl+F)")
        self.search_button.bind_property(
            "active", self.search_bar, "search-mode-enabled",
            GObject.BindingFlags.BIDIRECTIONAL)

        self.spinner = Gtk.Spinner()
        self.spinner.set_visible(False)
        self.spinner.set_tooltip_text("Applying theme…")

        # HIG: only the primary actions get a button; everything else lives
        # in the primary menu.  HeaderBar packs "end" right to left.
        menu = Gio.Menu()
        menu.append("Apply Random Theme", "win.random")
        menu.append("Edit Wallpapers & Colours…", "win.editor")
        menu.append("Preferences", "win.preferences")
        self.menu_button = Gtk.MenuButton(icon_name="open-menu-symbolic",
                                          menu_model=menu)
        self.menu_button.set_tooltip_text("Main Menu")

        self.random_button = Gtk.Button.new_from_icon_name(
            "media-playlist-shuffle-symbolic")
        self.random_button.set_tooltip_text(
            "Apply a random theme for the current colour scheme (Ctrl+R)")
        self.random_button.connect("clicked", self.on_random_clicked)

        header.pack_end(self.menu_button)
        header.pack_end(self.spinner)
        header.pack_end(self.random_button)
        header.pack_end(self.search_button)
        self.header = header

        # Menu entries are plain actions, so they show their accelerators.
        for name, handler in (("random", self.on_random_clicked),
                              ("editor", self.on_config_clicked),
                              ("preferences", self.on_preferences_clicked)):
            action = Gio.SimpleAction.new(name, None)
            action.connect("activate",
                           lambda _action, _param, fn=handler: fn(None))
            self.window.add_action(action)
        self.set_accels_for_action("win.random", ["<Control>r"])
        self.set_accels_for_action("win.editor", ["<Control>e"])
        self.set_accels_for_action("win.preferences", ["<Control>comma"])

        # Content is either the five pages or an empty-state page.
        self.content_stack = Gtk.Stack()
        self.content_stack.set_transition_type(
            Gtk.StackTransitionType.CROSSFADE)
        self.content_stack.set_transition_duration(120)
        self.content_stack.add_named(self.stack, "pages")

        self.empty_page = Adw.StatusPage(
            icon_name="system-search-symbolic",
            title="No Results",
            description="No themes match your search.")
        clear_button = Gtk.Button(label="Clear Search")
        clear_button.add_css_class("pill")
        clear_button.set_halign(Gtk.Align.CENTER)
        clear_button.connect("clicked", lambda *_: self.clear_search())
        self.empty_page.set_child(clear_button)
        self.content_stack.add_named(self.empty_page, "empty")

        toolbar_view = Adw.ToolbarView()
        toolbar_view.add_top_bar(header)
        toolbar_view.add_top_bar(self.search_bar)
        toolbar_view.set_content(self.content_stack)
        self.toast_overlay.set_child(toolbar_view)
        self.window.set_content(self.toast_overlay)

        controller = Gtk.EventControllerKey()
        controller.connect("key-pressed", self.on_key_pressed)
        self.window.add_controller(controller)

        self.load_themes()
        self.window.present()

    # ------------------------------------------------------------------ data
    def load_themes(self):
        if not THEMES_DIR.exists():
            self.show_error(f"Theme directory not found: {THEMES_DIR}")
            return

        started = time.monotonic()
        grouped = {key: [] for key, *_rest in PAGE_ORDER}

        for stem, base, key, primary, surface in scan_theme_files(
                read_json(INDEX_FILE, {})):
            grouped[key].append(Theme(base, primary, surface,
                                      apply_name=stem,
                                      variant=variant_label(key)))

        for key, label, _variant, icon in PAGE_ORDER:
            themes = sorted(grouped[key], key=lambda t: t.name.lower())
            if not themes:
                continue
            self.add_page(key, label, icon, themes)

        self.theme_count = sum(len(page["themes"]) for page in self.pages)
        self.theme_objects = [t for page in self.pages for t in page["themes"]]

        self.apply_hidden_tabs()
        first = self.visible_pages()
        if first:
            self.stack.set_visible_child_name(first[0]["name"])
            self.sync_page(first[0])

        elapsed = (time.monotonic() - started) * 1000
        print(f"[INFO] Loaded {self.theme_count} themes in "
              f"{len(self.pages)} pages in {elapsed:.0f} ms "
              f"({len(self.visible_pages())} shown)")

    def add_page(self, key, label, icon, themes):
        page = {
            "name": key,
            "title": label,
            "icon": icon,
            "themes": themes,
            "rows": [],
            "shown": len(themes),
            "built_needle": None,   # None = no rows built yet
            "queue": [],            # rows still waiting for a frame
        }

        group = Adw.PreferencesGroup(
            title=label,
            description=f"{len(themes)} themes")
        page["group"] = group

        preferences_page = Adw.PreferencesPage()
        preferences_page.add(group)
        page["widget"] = preferences_page

        self.pages.append(page)
        self.pages_by_name[key] = page

    # ------------------------------------------------------------- visibility
    def visible_pages(self):
        return [page for page in self.pages
                if page["name"] not in self.hidden_tabs]

    def apply_hidden_tabs(self):
        """Re-stack the visible variants in canonical order.

        Adw.ViewStack has no per-page "hidden" flag, so pages are removed and
        the visible ones re-added in one pass; the page widgets (and their
        built rows) survive the round trip.  A page change that is still
        crossfading defers the work until transition-running clears.
        """
        if self.restack_id:
            GLib.source_remove(self.restack_id)
            self.restack_id = 0
        if self.stack.get_transition_running():
            self.restack_id = GLib.timeout_add(RESTACK_POLL_MS,
                                               self._restack_when_idle)
        else:
            self._restack_pages()

    def _restack_when_idle(self):
        if self.stack.get_transition_running():
            return True          # still crossfading, poll again
        self.restack_id = 0
        self._restack_pages()
        return False

    def _restack_pages(self):
        self.restack_id = 0
        visible = self.visible_pages()
        current = self.stack.get_visible_child_name()
        for page in self.pages:
            widget = page["widget"]
            if widget.get_parent() is self.stack:
                self.stack.remove(widget)
        for page in visible:
            stack_page = self.stack.add_titled(page["widget"],
                                               page["name"], page["title"])
            stack_page.set_icon_name(page["icon"])

        if visible:
            keep = {page["name"] for page in visible}
            self.stack.set_visible_child_name(
                current if current in keep else visible[0]["name"])
        return False

    def build_row(self, theme):
        row = Adw.ActionRow(title=theme.name)
        row.set_activatable(True)
        row.connect("activated", self.on_row_activated, theme)

        # One canvas paints both chips: fewer widgets than two DrawingAreas.
        swatches = Gtk.DrawingArea()
        swatches.set_content_width(46)
        swatches.set_content_height(18)
        swatches.set_valign(Gtk.Align.CENTER)
        swatches.set_draw_func(self.draw_swatches, theme)
        row.add_suffix(swatches)
        return row

    # ------------------------------------------------------------------ pages
    def matches(self, theme, needle):
        return (not needle
                or needle in theme.name.lower()
                or needle in theme.apply_name.lower()
                or needle in theme.variant.lower())

    def count_matches(self, page):
        return sum(1 for theme in page["themes"]
                   if self.matches(theme, self.needle))

    def sync_page(self, page):
        """(Re)build this page's rows for the current search text if needed.

        Only the first screenful is built inline; the rest is appended over
        the next few frames so the window shows content sooner.
        """
        needle = self.needle
        if page["built_needle"] == needle:
            if page["queue"]:
                self.start_drain()
            return

        group = page["group"]
        for _theme, row in page["rows"]:
            group.remove(row)
        page["rows"] = []
        page["queue"] = []

        matching = [theme for theme in page["themes"]
                    if self.matches(theme, needle)]
        page["shown"] = len(matching)
        page["built_needle"] = needle

        if needle:
            group.set_description(
                f"{len(matching)} of {len(page['themes'])} themes")
            group.set_visible(bool(matching))
        else:
            group.set_description(f"{len(page['themes'])} themes")
            group.set_visible(True)

        self.add_rows(page, matching[:FIRST_BATCH])
        page["queue"] = matching[FIRST_BATCH:]
        if page["queue"]:
            self.start_drain()

    def add_rows(self, page, themes):
        group = page["group"]
        rows = page["rows"]
        for theme in themes:
            row = self.build_row(theme)
            group.add(row)
            rows.append((theme, row))

    def start_drain(self):
        if not self.drain_id:
            self.drain_id = GLib.timeout_add(DRAIN_INTERVAL_MS, self.drain_rows)

    def drain_rows(self):
        """Append the rest of every pending page, a batch at a time.

        Draining all pages means leaving a half-filled page (by switching
        away mid-fill) never leaves it stuck; the leftovers finish quietly.
        """
        pending = False
        for page in self.pages:
            queue = page["queue"]
            if not queue:
                continue
            if page["built_needle"] != self.needle:
                page["queue"] = []
                continue
            batch = queue[:DRAIN_BATCH]
            del queue[:DRAIN_BATCH]
            self.add_rows(page, batch)
            pending = pending or bool(queue)

        if pending:
            return True
        self.drain_id = 0
        return False

    def on_page_changed(self, stack, _pspec):
        page = self.pages_by_name.get(stack.get_visible_child_name())
        if page is None:
            return
        if page["built_needle"] != self.needle:
            self.sync_page(page)
        elif page["queue"]:
            self.start_drain()

    # ------------------------------------------------------------------ search
    def on_search_changed(self, entry):
        if self.search_timeout:
            GLib.source_remove(self.search_timeout)
        self.search_timeout = GLib.timeout_add(
            SEARCH_DEBOUNCE_MS, self.run_debounced_search)

    def run_debounced_search(self):
        self.search_timeout = 0
        self.rebuild_view(self.search_entry.get_text())
        return False

    def clear_search(self):
        self.search_entry.set_text("")

    def rebuild_view(self, search_text=""):
        needle = search_text.strip().lower()
        visible = self.visible_pages()
        if (needle == self.needle
                and self.content_stack.get_visible_child_name() == "pages"):
            page = self.pages_by_name.get(self.stack.get_visible_child_name())
            if page is not None:
                self.sync_page(page)
            return sum(page["shown"] for page in visible)

        self.needle = needle
        shown_total = 0
        for page in visible:
            page["shown"] = self.count_matches(page)
            shown_total += page["shown"]

        if self.needle and shown_total == 0:
            self.empty_page.set_description(
                f"No themes match “{search_text.strip()}”.")
            self.content_stack.set_visible_child_name("empty")
            return 0

        self.content_stack.set_visible_child_name("pages")
        if self.needle:
            current = self.pages_by_name.get(self.stack.get_visible_child_name())
            if current is None or current not in visible or not current["shown"]:
                for page in visible:
                    if page["shown"]:
                        self.stack.set_visible_child_name(page["name"])
                        break

        current = self.pages_by_name.get(self.stack.get_visible_child_name())
        if current is not None:
            self.sync_page(current)
        return shown_total

    # ------------------------------------------------------------------ actions
    def on_row_activated(self, row, theme):
        self.apply_theme(theme.apply_name)

    def system_is_dark(self):
        return Adw.StyleManager.get_default().get_dark()

    def random_pool(self):
        """Themes for the current colour scheme: dark+AMOLED, or light.

        Variants hidden in Preferences never win; if that leaves nothing,
        any visible variant is fair game.
        """
        wanted = {"dark", "amoled"} if self.system_is_dark() else {"light"}
        visible = self.visible_pages()
        pool = [theme for page in visible if page["name"] in wanted
                for theme in page["themes"]]
        return pool or [theme for page in visible
                        for theme in page["themes"]]

    def on_random_clicked(self, button):
        if self.applying:
            return
        pool = self.random_pool()
        if not pool:
            self.show_error("No themes available to select.")
            return
        self.apply_theme(random.choice(pool).apply_name)

    def apply_theme(self, theme_name):
        if self.applying:
            return
        if not APPLY_SCRIPT.exists():
            self.show_error(f"apply-theme.fish not found at {APPLY_SCRIPT}")
            return

        self.applying = True
        self.set_busy(True)
        self.notify_toast(f"Applying “{theme_name}”…")

        try:
            process = Gio.Subprocess.new(
                ["fish", str(APPLY_SCRIPT), theme_name],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE)
        except GLib.Error as error:
            self.on_apply_finished(theme_name, f"Could not run apply-theme.fish: "
                                               f"{error.message}")
            return

        process.communicate_utf8_async(None, None, self.on_apply_output,
                                       theme_name)

    def on_apply_output(self, process, result, theme_name):
        failure = None
        try:
            _ok, stdout, stderr = process.communicate_utf8_finish(result)
        except GLib.Error as error:
            stdout, stderr = "", error.message

        if not process.get_successful():
            detail = (stderr or stdout or "").strip()
            if len(detail) > 1200:
                detail = "…" + detail[-1200:]
            failure = (f"apply-theme.fish exited with status "
                       f"{process.get_exit_status()}.")
            if detail:
                failure += f"\n\n{detail}"
        self.on_apply_finished(theme_name, failure)

    def on_apply_finished(self, theme_name, failure):
        self.applying = False
        if failure is None:
            self.window.close()
            return False

        self.set_busy(False)
        self.show_error(f"Could not apply “{theme_name}”.\n\n{failure}")
        return False

    def set_busy(self, busy):
        self.content_stack.set_sensitive(not busy)
        self.search_button.set_sensitive(not busy)
        self.random_button.set_sensitive(not busy)
        self.menu_button.set_sensitive(not busy)
        self.spinner.set_visible(busy)
        if busy:
            self.spinner.start()
        else:
            self.spinner.stop()

    def on_preferences_clicked(self, button):
        if self.prefs_dialog is not None:
            self.prefs_dialog.present(self.window)
            return
        dialog = Adw.PreferencesDialog(title="Preferences")
        page = Adw.PreferencesPage()

        group = Adw.PreferencesGroup(
            title="Tabs",
            description="Pick which variants appear in the switcher. "
                        "Hidden variants are also skipped by Search and by "
                        "the random theme action.")
        self.prefs_rows = {}
        for info in self.pages:
            row = Adw.ActionRow(
                title=info["title"],
                subtitle=f"{len(info['themes'])} themes")
            switch = Gtk.Switch(active=info["name"] not in self.hidden_tabs,
                                valign=Gtk.Align.CENTER)
            switch.connect("notify::active", self.on_variant_toggled,
                           info["name"])
            row.add_suffix(switch)
            row.set_activatable(True)
            row.connect("activated",
                        lambda *_args, sw=switch: sw.set_active(
                            not sw.get_active()))
            group.add(row)
            self.prefs_rows[info["name"]] = (row, switch)
        page.add(group)
        dialog.add(page)

        self.prefs_dialog = dialog
        dialog.present(self.window)

    def on_variant_toggled(self, switch, _param, key):
        show = switch.get_active()
        if show == (key not in self.hidden_tabs):
            return
        if show:
            self.hidden_tabs.discard(key)
        else:
            hidden = self.hidden_tabs | {key}
            if not any(page["name"] not in hidden for page in self.pages):
                switch.set_active(True)
                self.notify_toast("Keep at least one variant visible")
                return
            self.hidden_tabs = hidden

        self.apply_hidden_tabs()
        page = self.pages_by_name.get(self.stack.get_visible_child_name())
        if page is not None:
            self.sync_page(page)
        self.settings["hidden_tabs"] = sorted(self.hidden_tabs)
        try:
            save_settings(self.settings)
        except OSError as error:
            self.show_error(f"Could not save settings: {error}")

    def on_config_clicked(self, button):
        editor = Path.home() / "Scripts" / "wallpaper-config-editor.py"
        if not editor.exists():
            self.show_error(f"Wallpaper config editor not found at {editor}")
            return
        try:
            subprocess.Popen([sys.executable, str(editor)])
        except OSError as error:
            self.show_error(f"Could not launch the config editor: {error}")
            return
        self.notify_toast("Configuration editor launched")

    # ------------------------------------------------------------------ keys
    def on_key_pressed(self, controller, keyval, keycode, state):
        ctrl = state & Gdk.ModifierType.CONTROL_MASK
        if keyval == Gdk.KEY_Escape:
            if self.search_bar.get_search_mode():
                # Close search and restore the full list; never close the app
                # on the same keypress that dismisses the search bar.
                self.search_button.set_active(False)
                self.search_entry.set_text("")
            else:
                self.window.close()
            return True
        if ctrl and keyval == Gdk.KEY_f:
            self.search_button.set_active(True)
            self.search_entry.grab_focus()
            return True
        if ctrl and keyval in (Gdk.KEY_Page_Down, Gdk.KEY_Page_Up):
            self.cycle_page(1 if keyval == Gdk.KEY_Page_Down else -1)
            return True
        return False

    def cycle_page(self, delta):
        names = [page["name"] for page in self.visible_pages()]
        if not names:
            return
        current = self.stack.get_visible_child_name()
        index = names.index(current) if current in names else 0
        self.stack.set_visible_child_name(names[(index + delta) % len(names)])

    # ------------------------------------------------------------------ drawing
    def draw_swatches(self, area, cr, width, height, theme):
        size = min(height, 18)
        radius = 5
        for index, color_str in enumerate((theme.primary_color,
                                           theme.surface_color)):
            rgba = Gdk.RGBA()
            if not rgba.parse(color_str):
                rgba.parse("#808080")
            x = index * (size + 10)
            rounded_rect(cr, x, (height - size) / 2, size, size, radius)
            cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha)
            cr.fill()
        cr.set_line_width(1)
        cr.set_source_rgba(1, 1, 1, 0.25)
        for index in range(2):
            x = index * (size + 10)
            rounded_rect(cr, x, (height - size) / 2, size, size, radius)
            cr.stroke()

    # ------------------------------------------------------------------ dialogs
    def show_error(self, message):
        dialog = Adw.AlertDialog(heading="Error", body=str(message))
        dialog.add_response("close", "OK")
        dialog.set_default_response("close")
        dialog.present(self.window)

    def notify_toast(self, message):
        self.toast_overlay.add_toast(Adw.Toast.new(message))


def rounded_rect(cr, x, y, width, height, radius):
    radius = min(radius, width / 2, height / 2)
    cr.new_sub_path()
    cr.arc(x + width - radius, y + radius, radius, -1.5708, 0)
    cr.arc(x + width - radius, y + height - radius, radius, 0, 1.5708)
    cr.arc(x + radius, y + height - radius, radius, 1.5708, 3.1416)
    cr.arc(x + radius, y + radius, radius, 3.1416, 4.7124)
    cr.close_path()


def main():
    app = ThemeSwitcher()
    app.run(None)


if __name__ == "__main__":
    main()
