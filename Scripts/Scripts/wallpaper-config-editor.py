#!/usr/bin/env python3
"""Wallpaper & colour editor for matugen themes.

Sidebar: every theme file. Right side: the wallpapers assigned to that theme
in wallpaper_map.json and editable colour roles in the theme JSON.

Performance notes:
  * The sidebar is a virtualised Gtk.ListView over a Gtk.StringList, so there
    are no 500 custom GObjects and no 500-row ListBox layout.
  * Startup uses a metadata cache (~/.cache/matugen/theme_index.json) built
    from mtime+size; a theme's JSON is parsed only when it is selected.
  * Wallpaper thumbnails are decoded on background threads, cached on disk in
    ~/.cache/matugen/thumbs and re-used across selections and runs.
"""

import copy
import hashlib
import json
import os
import queue
import re
import shutil
import threading
from pathlib import Path

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Adw, Gdk, GdkPixbuf, Gio, GLib, GObject, Gtk, Pango

THEMES_DIR = Path.home() / ".config" / "matugen" / "themes"
MAP_FILE = Path.home() / ".config" / "matugen" / "wallpaper_map.json"
WALLPAPER_DIR = Path("/mnt/Storage/Wallpapers")
CACHE_DIR = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) \
    / "matugen"
INDEX_FILE = CACHE_DIR / "theme_index.json"
THUMB_DIR = CACHE_DIR / "thumbs"
THUMB_WIDTH = 128
THUMB_HEIGHT = 72

VARIANT_RE = re.compile(
    r"^(?P<base>.+)-(?P<variant>dark-high-contrast|light-high-contrast|dark|light|amoled)$",
    re.IGNORECASE)
VARIANT_SUFFIX_RE = re.compile(
    r"-(dark-high-contrast|light-high-contrast|dark|light|amoled)$",
    re.IGNORECASE)

VARIANT_LABELS = {
    "dark": "Dark",
    "light": "Light",
    "dark-high-contrast": "Dark High Contrast",
    "light-high-contrast": "Light High Contrast",
    "amoled": "AMOLED",
}

ROLES = [
    ("primary", "Primary", "Accent for text and controls"),
    ("secondary", "Secondary", "Secondary accent"),
    ("tertiary", "Tertiary", "Contrasting accent"),
    ("background", "Background", "Window background"),
    ("surface", "Surface", "Cards, bars and menus"),
]


# ---------------------------------------------------------------- helpers
def extract_color(data, role, fallback="#808080"):
    node = data.get("colors", {}).get(role)
    if isinstance(node, str):
        return node
    if isinstance(node, dict):
        default = node.get("default")
        if isinstance(default, str):
            return default
        if isinstance(default, dict) and isinstance(default.get("color"), str):
            return default["color"]
        if isinstance(node.get("color"), str):
            return node["color"]
    return fallback


def store_color(data, role, hex_color):
    """Write a colour back without flattening the {default: {color: …}} schema."""
    colors = data.setdefault("colors", {})
    node = colors.get(role)
    if isinstance(node, dict):
        default = node.get("default")
        if isinstance(default, dict):
            default["color"] = hex_color
            return
        if isinstance(default, str):
            node["default"] = hex_color
            return
        node["color"] = hex_color
        return
    colors[role] = {"default": {"color": hex_color}}


def parse_hex(text):
    text = (text or "").strip()
    if not re.fullmatch(r"#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", text):
        return None
    rgba = Gdk.RGBA()
    return rgba if rgba.parse(text) else None


def rgba_to_hex(rgba):
    return "#{:02x}{:02x}{:02x}".format(
        round(rgba.red * 255), round(rgba.green * 255), round(rgba.blue * 255))


def write_atomic(path, text):
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text)
    os.replace(tmp, path)


def write_map(mapping):
    """Rewrite the map keeping its readable one-entry-per-block layout."""
    blocks = []
    for key, value in mapping.items():
        paths = ",\n".join(f'      "{p}"' for p in value.get("wallpapers", []))
        blocks.append(f'  "{key}": {{\n    "wallpapers": [\n{paths}\n    ]\n  }}')
    text = "{\n" + ",\n\n".join(blocks) + "\n}\n"
    json.loads(text)  # never write invalid JSON
    if MAP_FILE.exists():
        shutil.copy2(MAP_FILE, MAP_FILE.with_name(MAP_FILE.name + ".bak"))
    write_atomic(MAP_FILE, text)


def read_json(path, fallback):
    try:
        return json.loads(path.read_text())
    except Exception:
        return fallback


# ---------------------------------------------------------------- theme index
def load_index():
    """Cached per-file metadata: stem -> [mtime_ns, size, base, variant, p, s]."""
    raw = read_json(INDEX_FILE, {})
    return raw if isinstance(raw, dict) else {}


def save_index(index):
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    write_atomic(INDEX_FILE, json.dumps(index, ensure_ascii=False))


def scan_themes(cached):
    """Return (stems, meta, index) reusing cached metadata for unchanged files."""
    stems = []
    meta = {}
    index = {}
    for path in sorted(THEMES_DIR.glob("*.json"), key=lambda p: p.stem.lower()):
        match = VARIANT_RE.match(path.stem)
        if not match:
            continue
        try:
            stat = path.stat()
        except OSError:
            continue

        record = cached.get(path.stem)
        if (record and len(record) == 6
                and record[0] == stat.st_mtime_ns and record[1] == stat.st_size):
            base, variant, primary, surface = record[2:]
        else:
            data = read_json(path, None)
            if data is None:
                print(f"[WARN] Skipping unreadable {path.name}")
                continue
            base = match.group("base")
            variant = VARIANT_LABELS.get(match.group("variant").lower(),
                                         match.group("variant"))
            primary = extract_color(data, "primary", "#ffffff")
            surface = extract_color(data, "surface", "#000000")

        stems.append(path.stem)
        meta[path.stem] = (base, variant, primary, surface)
        index[path.stem] = [stat.st_mtime_ns, stat.st_size,
                            base, variant, primary, surface]
    return stems, meta, index


class EditorWindow(Adw.ApplicationWindow):
    def __init__(self, application):
        super().__init__(application=application, title="Wallpaper Config Editor")
        self.set_default_size(1040, 720)

        self.stems = []
        self.meta = {}          # stem -> (base, variant, primary, surface)
        self.index = {}
        self.mapping = {}
        self.current = None     # file stem of the theme being edited
        self.current_data = None
        self.wallpapers = []
        self.wallpaper_key = None
        self.dirty = False
        self.suppress_selection = False
        self.syncing = False
        self.needle = ""
        self.texture_cache = {}
        self.thumb_waiters = {}
        self.queued_thumbs = set()
        self.failed_thumbs = set()
        self.thumb_queue = queue.Queue()
        self.color_entries = {}
        self.color_buttons = {}
        self.wallpaper_rows = []

        for _ in range(2):
            threading.Thread(target=self.thumb_worker, daemon=True,
                             name="thumb-decode").start()

        self.color_dialog = Gtk.ColorDialog(with_alpha=False,
                                            title="Choose a colour")

        self.toast_overlay = Adw.ToastOverlay()
        self.set_content(self.toast_overlay)

        self.build_ui()
        self.load_data()

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self.on_key_pressed)
        self.add_controller(keys)
        self.connect("close-request", self.on_close_request)

    # ------------------------------------------------------------- UI
    def build_ui(self):
        toolbar = Adw.ToolbarView()
        self.toast_overlay.set_child(toolbar)

        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(False)

        sidebar_button = Gtk.ToggleButton()
        sidebar_button.set_icon_name("sidebar-show-symbolic")
        sidebar_button.set_tooltip_text("Toggle theme list")
        sidebar_button.set_active(True)
        header.pack_start(sidebar_button)

        self.title_widget = Adw.WindowTitle(title="Wallpaper Config Editor",
                                            subtitle="")
        header.set_title_widget(self.title_widget)

        self.revert_button = Gtk.Button.new_from_icon_name("edit-undo-symbolic")
        self.revert_button.set_tooltip_text("Reload this theme (revert)")
        self.revert_button.set_sensitive(False)
        self.revert_button.connect("clicked", self.on_revert_clicked)
        header.pack_end(self.revert_button)

        self.save_button = Gtk.Button(label="Save")
        self.save_button.add_css_class("suggested-action")
        self.save_button.set_tooltip_text("Save changes (Ctrl+S)")
        self.save_button.set_sensitive(False)
        self.save_button.connect("clicked", self.on_save_clicked)
        header.pack_end(self.save_button)

        toolbar.add_top_bar(header)

        # --- sidebar -------------------------------------------------
        sidebar = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search themes…")
        self.search_entry.set_margin_top(6)
        self.search_entry.set_margin_bottom(6)
        self.search_entry.set_margin_start(8)
        self.search_entry.set_margin_end(8)
        self.search_entry.connect("search-changed", self.on_search_changed)
        sidebar.append(self.search_entry)

        self.model = Gtk.StringList.new([])
        self.filter = Gtk.CustomFilter.new(self.filter_item)
        self.filter_model = Gtk.FilterListModel(model=self.model,
                                                filter=self.filter)
        self.selection = Gtk.SingleSelection(model=self.filter_model)
        self.selection.set_autoselect(False)
        self.selection.set_can_unselect(True)
        self.selection.connect("notify::selected", self.on_selected_changed)

        factory = Gtk.SignalListItemFactory()
        factory.connect("setup", self.on_item_setup)
        factory.connect("bind", self.on_item_bind)
        factory.connect("unbind", self.on_item_unbind)

        self.list_view = Gtk.ListView(model=self.selection, factory=factory)
        self.list_view.add_css_class("navigation-sidebar")
        self.list_view.set_single_click_activate(True)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_vexpand(True)
        scroller.set_child(self.list_view)
        sidebar.append(scroller)

        self.split_view = Adw.OverlaySplitView()
        self.split_view.set_sidebar(sidebar)
        self.split_view.set_min_sidebar_width(300)
        self.split_view.set_max_sidebar_width(380)
        self.split_view.set_sidebar_width_fraction(0.32)
        self.split_view.set_show_sidebar(True)
        sidebar_button.bind_property(
            "active", self.split_view, "show-sidebar",
            GObject.BindingFlags.BIDIRECTIONAL)

        # --- editor --------------------------------------------------
        self.editor_stack = Gtk.Stack()
        self.editor_stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.editor_stack.add_named(self.build_editor_page(), "editor")
        self.editor_stack.add_named(self.build_empty_page(), "empty")
        self.editor_stack.set_visible_child_name("empty")

        self.split_view.set_content(self.editor_stack)
        toolbar.set_content(self.split_view)

    def build_editor_page(self):
        page = Adw.PreferencesPage()

        self.wallpaper_group = Adw.PreferencesGroup(
            title="Wallpapers",
            description="One is picked at random each time the theme is applied.")
        self.add_wallpaper_row = Adw.ActionRow(
            title="Add wallpaper…",
            subtitle=f"Choose an image from {WALLPAPER_DIR}")
        self.add_wallpaper_row.set_activatable(True)
        self.add_wallpaper_row.add_prefix(
            Gtk.Image.new_from_icon_name("list-add-symbolic"))
        self.add_wallpaper_row.connect("activated", self.on_add_wallpaper)
        page.add(self.wallpaper_group)

        self.color_group = Adw.PreferencesGroup(
            title="Colors",
            description="Written to the theme JSON with its original schema.")
        page.add(self.color_group)

        for role, label, hint in ROLES:
            row = Adw.ActionRow(title=label, subtitle=hint)

            entry = Gtk.Entry()
            entry.set_width_chars(9)
            entry.set_max_width_chars(9)
            entry.add_css_class("monospace")
            entry.set_valign(Gtk.Align.CENTER)
            entry.connect("changed", self.on_hex_changed, role)
            row.add_suffix(entry)
            self.color_entries[role] = entry

            button = Gtk.ColorDialogButton(dialog=self.color_dialog)
            button.set_valign(Gtk.Align.CENTER)
            button.set_tooltip_text(f"Pick {label.lower()} colour")
            button.connect("notify::rgba", self.on_color_picked, role)
            row.add_suffix(button)
            self.color_buttons[role] = button

            self.color_group.add(row)

        preview_group = Adw.PreferencesGroup(title="Preview")
        preview_row = Adw.ActionRow()
        preview_row.set_activatable(False)
        self.preview_area = Gtk.DrawingArea()
        self.preview_area.set_content_height(132)
        self.preview_area.set_draw_func(self.draw_preview)
        preview_row.set_child(self.preview_area)
        preview_group.add(preview_row)
        page.add(preview_group)

        return page

    def build_empty_page(self):
        return Adw.StatusPage(
            icon_name="applications-graphics-symbolic",
            title="Select a Theme",
            description="Pick a theme on the left to edit its wallpapers and colours.")

    # ------------------------------------------------------------- data
    def load_data(self):
        started = GLib.get_monotonic_time()
        cached = load_index()
        self.stems, self.meta, self.index = scan_themes(cached)
        if cached != self.index:
            save_index(self.index)

        self.mapping = read_json(MAP_FILE, {})
        if not isinstance(self.mapping, dict):
            self.mapping = {}

        self.model.splice(0, 0, self.stems)
        self.apply_filter(select_stem=None)

        elapsed = (GLib.get_monotonic_time() - started) / 1000
        print(f"[INFO] {len(self.stems)} themes, {len(self.mapping)} map keys "
              f"in {elapsed:.0f} ms")

    def filter_item(self, item):
        stem = item.get_string()
        needle = self.needle
        if not needle:
            return True
        if needle in stem.lower():
            return True
        meta = self.meta.get(stem)
        if meta is None:
            return False
        return needle in meta[0].lower() or needle in meta[1].lower()

    def apply_filter(self, select_stem=None):
        """Re-run the sidebar filter and keep the edited theme selected."""
        wanted = select_stem or self.current

        # Filtering can move the selection to whatever lands on the old index;
        # suppress that so typing never loads a different theme.
        self.suppress_selection = True
        self.filter.changed(Gtk.FilterChange.DIFFERENT)

        position = (self.position_of(wanted)
                    if wanted is not None else Gtk.INVALID_LIST_POSITION)
        self.selection.set_selected(position)
        self.suppress_selection = False

    def position_of(self, stem):
        for position in range(self.filter_model.get_n_items()):
            if self.filter_model.get_item(position).get_string() == stem:
                return position
        return Gtk.INVALID_LIST_POSITION

    # ------------------------------------------------------------- sidebar rows
    def on_item_setup(self, factory, item):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add_css_class("theme-row")

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        text.set_hexpand(True)

        title = Gtk.Label(xalign=0)
        title.set_ellipsize(Pango.EllipsizeMode.END)

        subtitle = Gtk.Label(xalign=0)
        subtitle.add_css_class("dim-label")
        subtitle.add_css_class("caption")
        subtitle.set_ellipsize(Pango.EllipsizeMode.END)

        text.append(title)
        text.append(subtitle)
        row.append(text)

        primary = Gtk.DrawingArea()
        primary.set_content_width(14)
        primary.set_content_height(14)
        primary.set_valign(Gtk.Align.CENTER)
        primary.add_css_class("color-swatch")
        row.append(primary)

        surface = Gtk.DrawingArea()
        surface.set_content_width(14)
        surface.set_content_height(14)
        surface.set_valign(Gtk.Align.CENTER)
        surface.add_css_class("color-swatch")
        row.append(surface)

        row.title_label = title
        row.subtitle_label = subtitle
        row.primary_swatch = primary
        row.surface_swatch = surface
        item.set_child(row)
        item.connect("notify::selected", self.on_item_selected)

    def on_item_bind(self, factory, item):
        stem = item.get_item().get_string()
        meta = self.meta.get(stem)
        row = item.get_child()
        if meta is None:
            row.title_label.set_text(stem)
            row.subtitle_label.set_text("")
        else:
            row.title_label.set_text(meta[0])
            row.subtitle_label.set_text(meta[1])
        row.primary_swatch.set_draw_func(self.draw_row_swatch, stem, 0)
        row.surface_swatch.set_draw_func(self.draw_row_swatch, stem, 1)
        self.on_item_selected(item)

    def on_item_unbind(self, factory, item):
        row = item.get_child()
        row.title_label.set_text("")
        row.subtitle_label.set_text("")
        row.primary_swatch.set_draw_func(None)
        row.surface_swatch.set_draw_func(None)

    def draw_row_swatch(self, area, cr, width, height, stem, index):
        meta = self.meta.get(stem)
        color_str = "#808080"
        if meta is not None:
            color_str = meta[2] if index == 0 else meta[3]
        rgba = parse_hex(color_str) or parse_hex("#808080")
        rounded_rect(cr, 0, 0, width, height, min(width, height) / 2)
        cr.set_source_rgba(rgba.red, rgba.green, rgba.blue, rgba.alpha)
        cr.fill()

    def on_item_selected(self, item, _pspec=None):
        row = item.get_child()
        if row is None:
            return
        if item.get_selected():
            row.add_css_class("selected")
        else:
            row.remove_css_class("selected")

    # ------------------------------------------------------------- search
    def on_search_changed(self, entry):
        self.needle = entry.get_text().strip().lower()
        self.apply_filter()

    # ------------------------------------------------------------- selection
    def on_selected_changed(self, selection, _param):
        if self.suppress_selection:
            return

        item = selection.get_selected_item()
        if item is None:
            # Filtering can clear the selection; keep editing the current theme.
            if self.current is None:
                self.show_empty_editor()
            return

        stem = item.get_string()
        if self.current == stem:
            return

        if self.dirty and self.current is not None:
            self.ask_discard(stem)
            return

        self.load_theme(stem)

    def ask_discard(self, stem):
        previous = self.current
        base = self.meta.get(previous, (previous,))[0]
        dialog = Adw.AlertDialog(
            heading="Discard changes?",
            body=f"Unsaved changes to “{base}” will be lost.")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("discard", "Discard")
        dialog.set_response_appearance("discard",
                                       Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_default_response("cancel")
        dialog.set_close_response("cancel")
        dialog.connect("response", self.on_discard_response, stem, previous)
        dialog.present(self)

    def on_discard_response(self, dialog, response, stem, previous):
        if response == "discard":
            self.dirty = False
            self.load_theme(stem)
            return

        self.suppress_selection = True
        position = self.position_of(previous)
        if position != Gtk.INVALID_LIST_POSITION:
            self.selection.set_selected(position)
        self.suppress_selection = False

    def load_theme(self, stem):
        self.current = stem
        self.dirty = False

        path = THEMES_DIR / f"{stem}.json"
        self.current_data = read_json(path, {}) or {}

        key = stem
        if key not in self.mapping:
            family = VARIANT_SUFFIX_RE.sub("", stem)
            key = family if family in self.mapping else stem
        self.wallpaper_key = key
        self.wallpapers = list(self.mapping.get(key, {}).get("wallpapers", []))

        self.syncing = True
        for role, _label, _hint in ROLES:
            value = extract_color(self.current_data, role, "#808080")
            self.color_entries[role].set_text(value)
            rgba = parse_hex(value) or parse_hex("#808080")
            self.color_buttons[role].set_rgba(rgba)
        self.syncing = False

        self.rebuild_wallpaper_rows()
        self.preview_area.queue_draw()
        self.editor_stack.set_visible_child_name("editor")
        base, variant = self.meta.get(stem, (stem, ""))[:2]
        self.title_widget.set_title(base)
        self.title_widget.set_subtitle(variant)
        self.update_header_state()

    def show_empty_editor(self):
        self.current = None
        self.current_data = None
        self.editor_stack.set_visible_child_name("empty")
        self.title_widget.set_title("Wallpaper Config Editor")
        self.title_widget.set_subtitle("")
        self.update_header_state()

    def update_header_state(self):
        self.save_button.set_sensitive(self.dirty)
        self.revert_button.set_sensitive(self.current is not None)

    def mark_dirty(self):
        if not self.dirty:
            self.dirty = True
            self.update_header_state()

    # ------------------------------------------------------------- wallpapers
    def rebuild_wallpaper_rows(self):
        for row in self.wallpaper_rows:
            self.wallpaper_group.remove(row)
        self.wallpaper_rows = []
        self.thumb_waiters = {}
        if self.add_wallpaper_row.get_parent() is not None:
            self.wallpaper_group.remove(self.add_wallpaper_row)

        for path in self.wallpapers:
            self.wallpaper_group.add(self.build_wallpaper_row(path))

        self.wallpaper_group.add(self.add_wallpaper_row)

        if self.wallpapers:
            self.wallpaper_group.set_description(
                f"{len(self.wallpapers)} wallpapers, picked at random on apply "
                f"(stored as “{self.wallpaper_key}”)")
        else:
            self.wallpaper_group.set_description(
                f"No wallpapers yet — apply uses a random one from the pool "
                f"(stored as “{self.wallpaper_key}”)")

    def build_wallpaper_row(self, path):
        row = Adw.ActionRow(title=Path(path).name, subtitle=path)

        thumbnail = Gtk.Stack()
        thumbnail.set_size_request(64, 36)
        thumbnail.set_valign(Gtk.Align.CENTER)
        thumbnail.add_css_class("wallpaper-thumb")

        icon = Gtk.Image.new_from_icon_name("image-loading-symbolic")
        picture = Gtk.Picture()
        picture.set_content_fit(Gtk.ContentFit.COVER)
        picture.set_can_shrink(True)
        thumbnail.add_named(icon, "placeholder")
        thumbnail.add_named(picture, "image")

        texture = self.texture_for(path)
        if texture is not None:
            picture.set_paintable(texture)
            thumbnail.set_visible_child_name("image")
        elif not Path(path).exists():
            icon.set_from_icon_name("image-missing-symbolic")
        else:
            self.thumb_waiters.setdefault(path, []).append((thumbnail, picture))
            self.request_thumbnail(path)

        row.add_prefix(thumbnail)
        row.thumbnail_stack = thumbnail

        remove = Gtk.Button.new_from_icon_name("user-trash-symbolic")
        remove.add_css_class("flat")
        remove.set_valign(Gtk.Align.CENTER)
        remove.set_tooltip_text("Remove wallpaper")
        remove.connect("clicked", self.on_remove_wallpaper, path)
        row.add_suffix(remove)

        self.wallpaper_rows.append(row)
        return row

    # ------------------------------------------------------------- thumbnails
    def thumb_cache_path(self, path):
        try:
            stat = os.stat(path)
        except OSError:
            return None
        key = hashlib.sha1(str(path).encode("utf-8")).hexdigest()[:20]
        return THUMB_DIR / (f"{key}-{stat.st_mtime_ns}"
                            f"-{THUMB_WIDTH}x{THUMB_HEIGHT}.png")

    def texture_for(self, path):
        texture = self.texture_cache.get(path)
        if texture:
            return texture
        if texture is False:  # decoding failed earlier
            return None
        cache_path = self.thumb_cache_path(path)
        if cache_path is None or not cache_path.exists():
            return None
        try:
            texture = Gdk.Texture.new_from_filename(str(cache_path))
        except Exception:
            return None
        self.texture_cache[path] = texture
        return texture

    def request_thumbnail(self, path):
        if path in self.queued_thumbs or path in self.failed_thumbs:
            return
        self.queued_thumbs.add(path)
        self.thumb_queue.put(path)

    def thumb_worker(self):
        """Background decoder: fills a small PNG cache, never touches GTK."""
        while True:
            path = self.thumb_queue.get()
            try:
                cache_path = self.thumb_cache_path(path)
                if cache_path is not None and not cache_path.exists():
                    THUMB_DIR.mkdir(parents=True, exist_ok=True)
                    pixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(
                        path, THUMB_WIDTH, THUMB_HEIGHT, True)
                    tmp = cache_path.with_name(cache_path.name + ".tmp")
                    pixbuf.savev(str(tmp), "png", ["compression"], ["6"])
                    os.replace(tmp, cache_path)
                GLib.idle_add(self.on_thumbnail_ready, path, cache_path)
            except Exception:
                GLib.idle_add(self.on_thumbnail_ready, path, None)

    def on_thumbnail_ready(self, path, cache_path):
        self.queued_thumbs.discard(path)
        texture = None
        if cache_path is not None:
            try:
                texture = Gdk.Texture.new_from_filename(str(cache_path))
            except Exception:
                texture = None
        self.texture_cache[path] = texture if texture else False
        if not texture:
            self.failed_thumbs.add(path)

        for thumbnail, picture in self.thumb_waiters.pop(path, []):
            if texture:
                picture.set_paintable(texture)
                thumbnail.set_visible_child_name("image")
            else:
                thumbnail.get_child_by_name("placeholder").set_from_icon_name(
                    "image-missing-symbolic")
        return False

    def on_add_wallpaper(self, row):
        dialog = Gtk.FileDialog(title="Choose a wallpaper")
        if WALLPAPER_DIR.exists():
            dialog.set_initial_folder(Gio.File.new_for_path(str(WALLPAPER_DIR)))

        images = Gtk.FileFilter()
        images.set_name("Images")
        images.add_pixbuf_formats()
        filters = Gio.ListStore(item_type=Gtk.FileFilter)
        filters.append(images)
        dialog.set_filters(filters)
        dialog.set_default_filter(images)
        dialog.open(self, None, self.on_wallpaper_chosen)

    def on_wallpaper_chosen(self, dialog, result):
        try:
            file = dialog.open_finish(result)
        except Exception:
            return
        if file is None:
            return
        path = file.get_path()
        if path and path not in self.wallpapers:
            self.wallpapers.append(path)
            self.mark_dirty()
            self.rebuild_wallpaper_rows()

    def on_remove_wallpaper(self, button, path):
        if path in self.wallpapers:
            self.wallpapers.remove(path)
            self.mark_dirty()
            self.rebuild_wallpaper_rows()

    # ------------------------------------------------------------- colours
    def on_hex_changed(self, entry, role):
        if self.syncing:
            return
        rgba = parse_hex(entry.get_text())
        if rgba is None:
            return
        self.syncing = True
        self.color_buttons[role].set_rgba(rgba)
        self.syncing = False
        self.preview_area.queue_draw()
        self.mark_dirty()

    def on_color_picked(self, button, _param, role):
        if self.syncing:
            return
        hex_color = rgba_to_hex(button.get_rgba())
        self.syncing = True
        self.color_entries[role].set_text(hex_color)
        self.syncing = False
        self.preview_area.queue_draw()
        self.mark_dirty()

    # ------------------------------------------------------------- preview
    def current_color(self, role, fallback):
        rgba = parse_hex(self.color_entries[role].get_text())
        return rgba or parse_hex(fallback)

    def draw_preview(self, area, cr, width, height):
        background = self.current_color("background", "#1e1e1e")
        surface = self.current_color("surface", "#2a2a2a")

        cr.set_source_rgba(background.red, background.green,
                           background.blue, background.alpha)
        cr.paint()

        rounded_rect(cr, 12, 12, width - 24, height - 24, 10)
        cr.set_source_rgba(surface.red, surface.green, surface.blue, surface.alpha)
        cr.fill()

        chips = [self.current_color("primary", "#3584e4"),
                 self.current_color("secondary", "#9141ac"),
                 self.current_color("tertiary", "#26a269")]
        x = 28
        for chip in chips:
            rounded_rect(cr, x, height / 2 - 9, 54, 18, 9)
            cr.set_source_rgba(chip.red, chip.green, chip.blue, chip.alpha)
            cr.fill()
            x += 66

        # two text bars hinting at copy on the surface colour
        cr.set_source_rgba(background.red, background.green,
                           background.blue, 0.55)
        for offset, bar_width in ((0, 120), (26, 78)):
            rounded_rect(cr, width - 160, 26 + offset, bar_width, 8, 4)
            cr.fill()

    # ------------------------------------------------------------- save
    def on_save_clicked(self, button):
        if self.current is None:
            return

        values = {}
        for role, _label, _hint in ROLES:
            text = self.color_entries[role].get_text().strip()
            rgba = parse_hex(text)
            if rgba is None:
                self.show_error(f"“{text}” is not a valid colour for {role}.")
                return
            values[role] = text

        data = copy.deepcopy(self.current_data or {})
        for role, hex_color in values.items():
            store_color(data, role, hex_color)

        path = THEMES_DIR / f"{self.current}.json"
        try:
            if path.exists():
                shutil.copy2(path, path.with_name(path.name + ".bak"))
            write_atomic(path,
                         json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        except Exception as error:
            self.show_error(f"Could not write the theme file: {error}")
            return

        key = self.wallpaper_key
        if self.wallpapers:
            self.mapping[key] = {"wallpapers": list(self.wallpapers)}
        else:
            self.mapping.pop(key, None)

        try:
            write_map(self.mapping)
        except Exception as error:
            self.show_error(f"Could not write the wallpaper map: {error}")
            return

        self.current_data = data
        base, variant = self.meta.get(self.current, (self.current, ""))[:2]
        self.meta[self.current] = (base, variant,
                                   values["primary"], values["surface"])
        self.update_index_entry(self.current)
        self.dirty = False
        self.update_header_state()
        self.list_view.queue_draw()  # repaint the cached swatch colours
        self.notify_toast(f"Saved “{base}”")

    def update_index_entry(self, stem):
        path = THEMES_DIR / f"{stem}.json"
        try:
            stat = path.stat()
        except OSError:
            return
        base, variant, primary, surface = self.meta[stem]
        self.index[stem] = [stat.st_mtime_ns, stat.st_size,
                            base, variant, primary, surface]
        save_index(self.index)

    def on_revert_clicked(self, button):
        if self.current is None:
            return
        stem = self.current
        data = read_json(THEMES_DIR / f"{stem}.json", None)
        if data is None:
            self.show_error(f"Could not reload “{stem}”.")
            return

        base, variant = self.meta.get(stem, (stem, ""))[:2]
        self.meta[stem] = (base, variant,
                           extract_color(data, "primary", "#ffffff"),
                           extract_color(data, "surface", "#000000"))
        self.load_theme(stem)
        self.update_index_entry(stem)
        self.list_view.queue_draw()
        self.apply_filter(select_stem=stem)
        self.notify_toast("Reloaded from disk")

    # ------------------------------------------------------------- keys
    def on_key_pressed(self, controller, keyval, keycode, state):
        ctrl = state & Gdk.ModifierType.CONTROL_MASK
        if ctrl and keyval == Gdk.KEY_s:
            if self.save_button.get_sensitive():
                self.on_save_clicked(None)
            return True
        if ctrl and keyval == Gdk.KEY_f:
            if not self.split_view.get_show_sidebar():
                self.split_view.set_show_sidebar(True)
            self.search_entry.grab_focus()
            return True
        if keyval == Gdk.KEY_Escape:
            if self.search_entry.get_text():
                self.search_entry.set_text("")
                return True
            # Escape inside a text field only leaves the field, so the window
            # can never close while a colour is being typed; the next Escape
            # (focus now on the list) closes the window instead.
            if isinstance(self.get_focus(), Gtk.Editable):
                self.list_view.grab_focus()
                return True
            self.close()
            return True
        return False

    def on_close_request(self, *_args):
        if not self.dirty:
            return False

        base = self.meta.get(self.current, (self.current,))[0]
        dialog = Adw.AlertDialog(
            heading="Save changes?",
            body=f"“{base}” has unsaved wallpaper and colour changes.")
        dialog.add_response("cancel", "Cancel")
        dialog.add_response("discard", "Close Without Saving")
        dialog.add_response("save", "Save")
        dialog.set_response_appearance("discard",
                                       Adw.ResponseAppearance.DESTRUCTIVE)
        dialog.set_response_appearance("save",
                                       Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("save")
        dialog.set_close_response("cancel")
        dialog.connect("response", self.on_close_response)
        dialog.present(self)
        return True

    def on_close_response(self, dialog, response):
        if response == "cancel":
            return
        if response == "save":
            self.on_save_clicked(None)
            if self.dirty:
                return
        self.destroy()

    # ------------------------------------------------------------- dialogs
    def show_error(self, message):
        dialog = Adw.AlertDialog(heading="Error", body=str(message))
        dialog.add_response("close", "OK")
        dialog.set_default_response("close")
        dialog.present(self)

    def notify_toast(self, message):
        self.toast_overlay.add_toast(Adw.Toast.new(message))


# ---------------------------------------------------------------- drawing
def rounded_rect(cr, x, y, width, height, radius):
    radius = min(radius, width / 2, height / 2)
    cr.new_sub_path()
    cr.arc(x + width - radius, y + radius, radius, -1.5708, 0)
    cr.arc(x + width - radius, y + height - radius, radius, 0, 1.5708)
    cr.arc(x + radius, y + height - radius, radius, 1.5708, 3.1416)
    cr.arc(x + radius, y + radius, radius, 3.1416, 4.7124)
    cr.close_path()


class ConfigEditor(Adw.Application):
    def __init__(self):
        super().__init__(application_id="com.example.WallpaperConfigEditor",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.window = None

    def do_startup(self):
        Gtk.Application.do_startup(self)
        Adw.init()

        css = Gtk.CssProvider()
        css.load_from_data("""
            .color-swatch {
                border-radius: 4px;
                border: 1px solid @borders;
            }

            .wallpaper-thumb {
                border-radius: 6px;
                border: 1px solid @borders;
                margin-right: 6px;
            }

            /* Sidebar row: same metrics and colours as Adwaita's
               .navigation-sidebar rows, which only style GtkListBox rows. */
            .theme-row {
                border-radius: 9px;
                min-height: 36px;
                padding: 6px 8px;
                margin: 0 6px 2px;
            }

            .theme-row:hover {
                background-color: color-mix(in srgb, currentColor 7%,
                                           transparent);
            }

            .theme-row.selected {
                background-color: color-mix(in srgb, currentColor 10%,
                                           transparent);
            }

            .theme-row.selected:hover {
                background-color: color-mix(in srgb, currentColor 13%,
                                           transparent);
            }
        """)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), css,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    def do_activate(self):
        if self.window is None:
            self.window = EditorWindow(application=self)
        self.window.present()


def main():
    app = ConfigEditor()
    app.run(None)


if __name__ == "__main__":
    main()
