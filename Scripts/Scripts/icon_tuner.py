#!/usr/bin/env python3
"""Icon tuner: render each duotone icon under review, let the user mark it
dark / washed / good, or add a free-text comment for other problems.

Verdict storage (plain string): "good" | "dark" | "washed"
Comment storage (dict): {"comment": "<note>"}
Keys: Space/Right = good, Left = dark, Down = washed, c = comment,
p = prev, n = next, q = quit.
"""
import json
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, Gtk

REVIEW = os.path.expanduser("~/.cache/materialicious-review.json")
THEME = "/home/sakib/Projects/materialicious/Material-Grad/apps/scalable"
SOURCES = "/home/sakib/Projects/materialicious/sources"
RENDER = "/tmp/iconreview_render"


def render(app: str, size: int) -> str:
    os.makedirs(RENDER, exist_ok=True)
    out = f"{RENDER}/{app}.png"
    svg = f"{THEME}/{app}.svg"
    if not os.path.isfile(svg):
        return out
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), "-o", out, svg],
        capture_output=True,
    )
    return out


def verdict_str(verdict) -> str:
    if isinstance(verdict, dict):
        return verdict.get("comment", "comment")
    return str(verdict)


def needs_attention(verdict) -> bool:
    """Icons marked 'good' are done; everything else stays in the review queue."""
    if verdict is None:
        return True
    if isinstance(verdict, dict):
        return True
    return verdict != "good"


class Review(Gtk.Window):
    def __init__(self, apps: list[str], verdicts: dict):
        super().__init__(title="icon tuner")
        self.apps = apps
        self.verdicts = dict(verdicts)
        self.idx = 0
        self.set_default_size(460, 320)
        self.connect("destroy", Gtk.main_quit)
        self.connect("key-press-event", self.on_key)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.add(vbox)
        self.image = Gtk.Image()
        vbox.pack_start(self.image, True, True, 0)
        self.label = Gtk.Label()
        vbox.pack_start(self.label, False, False, 0)

        hbox = Gtk.Box(spacing=4, homogeneous=True)
        vbox.pack_start(hbox, False, False, 0)
        for text, key in [
            ("dark [<-]", "dark"),
            ("good [space]", "good"),
            ("washed [->]", "washed"),
            ("comment [c]", "comment"),
        ]:
            btn = Gtk.Button(label=text)
            btn.set_can_focus(False)
            if key == "comment":
                btn.connect("clicked", self.comment)
            else:
                btn.connect("clicked", self.mark, key)
            hbox.pack_start(btn, True, True, 0)

        nav = Gtk.Box(spacing=4, homogeneous=True)
        vbox.pack_start(nav, False, False, 0)
        prev = Gtk.Button(label="prev [p]")
        prev.set_can_focus(False)
        prev.connect("clicked", self.prev)
        nav.pack_start(prev, True, True, 0)
        next_ = Gtk.Button(label="next [n]")
        next_.set_can_focus(False)
        next_.connect("clicked", self.next_)
        nav.pack_start(next_, True, True, 0)

        self.show_apps()
        self.show_all()

    def show_apps(self):
        app = self.apps[self.idx]
        png = render(app, 160)
        pb = GdkPixbuf.Pixbuf.new_from_file(png)
        self.image.set_from_pixbuf(pb)
        v = verdict_str(self.verdicts.get(app, "-"))
        self.label.set_markup(
            f"<b>{self.idx + 1}/{len(self.apps)}</b>  {app}  "
            f"<span color=\"#d9bafa\">verdict: {v}</span>"
        )

    def mark(self, _btn=None, verdict: str | None = None):
        verdict = verdict or "good"
        self.verdicts[self.apps[self.idx]] = verdict
        json.dump(self.verdicts, open(REVIEW, "w"), indent=1)
        self.advance()

    def comment(self, _btn=None):
        app = self.apps[self.idx]
        old = self.verdicts.get(app)
        prev = old.get("comment", "") if isinstance(old, dict) else ""

        dialog = Gtk.Dialog(
            title=f"Comment: {app}", transient_for=self, modal=True
        )
        dialog.set_default_size(360, 150)
        dialog.add_button("Cancel", Gtk.ResponseType.CANCEL)
        dialog.add_button("Save", Gtk.ResponseType.OK)
        area = dialog.get_content_area()
        area.set_spacing(6)
        area.pack_start(Gtk.Label(label="Problem note (free text):"), False, False, 0)
        entry = Gtk.Entry()
        entry.set_text(prev)
        entry.set_activates_default(True)
        area.pack_start(entry, False, False, 0)
        comment = self.verdicts.get(app)
        if isinstance(comment, dict) and comment.get("comment"):
            clear = Gtk.Button(label="Remove comment (reset verdict)")
            clear.connect("clicked", lambda *_: (
                self.verdicts.pop(app, None),
                json.dump(self.verdicts, open(REVIEW, "w"), indent=1),
                dialog.response(Gtk.ResponseType.CANCEL),
                self.show_apps(),
            ))
            area.pack_start(clear, False, False, 0)
        dialog.show_all()
        resp = dialog.run()
        if resp == Gtk.ResponseType.OK:
            note = entry.get_text().strip()
            if note:
                self.verdicts[app] = {"comment": note}
            else:
                self.verdicts.pop(app, None)
            json.dump(self.verdicts, open(REVIEW, "w"), indent=1)
            self.show_apps()
        dialog.destroy()

    def prev(self, _btn=None, steps=1):
        self.idx = (self.idx - steps) % len(self.apps)
        self.show_apps()

    def advance(self):
        self.idx = (self.idx + 1) % len(self.apps)
        self.show_apps()

    def next_(self, _btn=None, steps=1):
        self.idx = (self.idx + steps) % len(self.apps)
        self.show_apps()

    def on_key(self, _w, ev):
        k = Gdk.keyval_name(ev.keyval)
        if k == "space" or k == "Right":
            self.mark(verdict="good")
        elif k == "Left":
            self.mark(verdict="dark")
        elif k == "Down":
            self.mark(verdict="washed")
        elif k == "c":
            self.comment()
        elif k == "p":
            self.prev()
        elif k == "n":
            self.next_()
        elif k == "q":
            self.destroy()
        return True


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true",
                    help="review every duotone icon, including ones already marked good")
    args = ap.parse_args()
    verdicts = {}
    if os.path.exists(REVIEW):
        verdicts = json.load(open(REVIEW))
    apps = sorted(os.path.basename(f)[:-4] for f in os.listdir(THEME) if f.endswith(".svg"))
    # keep only the 61 duotone icons (those with a source); review cache may
    # still hold verdicts for icons whose sources were dropped
    src_names = {os.path.basename(s)[:-4] for s in os.listdir(SOURCES) if s.endswith(".svg")}
    apps = [a for a in apps if a in src_names]
    if not args.all:
        # only icons that still need review; marking one "good" drops it from the queue
        explicit = verdicts.get if verdicts else (lambda k: None)
        apps = [a for a in apps if needs_attention(explicit(a))]
        if not apps:
            print("no icons need review - all good (use --all to re-check them)")
            return
    Review(apps, verdicts)
    Gtk.main()


if __name__ == "__main__":
    main()