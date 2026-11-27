# Material Bibata Cursor Matching

How the wallpaper-accent-to-cursor-theme pipeline works on this machine, why the
login screen used to show Fedora's default Adwaita cursor, and how to verify or
repair it.

Short version: a single wallpaper change updates **three independent cursor
settings** — the GNOME session, legacy X11 fallback files, and the GDM greeter.
They do not synchronize with each other, and the greeter also needs the theme
files to be readable by a different user.

## Components

| Component | Path | Tracked in dotfiles |
|---|---|---|
| Matcher | `Scripts/Scripts/cursor_matugen.sh` | yes |
| Colour metric | `Scripts/Scripts/color_match.py` | yes |
| Theme definitions | `Scripts/Scripts/themes.json` | yes |
| Wallpaper colours | `~/.config/matugen/matugen-colors.css` | yes (via symlink) |
| User icon themes | `~/.local/share/icons/Bibata-Material-*` (symlinks into `icons/.icons/`) | yes |
| XDG default cursor | `~/.local/share/icons/default/index.theme` | no (generated) |
| Legacy default cursor | `~/.icons/default/index.theme` -> `icons/.icons/default/index.theme` | yes |
| GDM system cursor default | `/etc/dconf/db/{local,gdm}.d/99-cursor-theme` | no (system config) |
| GDM system accent default | `/etc/dconf/db/{local,gdm}.d/99-gdm-accent` | no (system config) |
| GDM Xcursor default fallback | `/var/lib/gdm/.icons/default/index.theme` | no (system config) |
| System Xcursor default fallback | `/usr/share/icons/default/index.theme` (backup at `.bak`) | no (system config) |
| Accent picker | `Scripts/Scripts/choose-accent.sh` | yes |
| System-wide themes | `/usr/share/icons/Bibata-Material-*` | no (system copy) |
| AccountsService watcher | `~/.config/scripts/cursor-watch.sh` | no (machine-local) |
| Watcher units | `~/.config/systemd/user/cursor-watch.{path,service,target}` | no (machine-local) |

## Flow on a wallpaper change

1. `matugen.fish` (or `hellwal.fish`, `tinct.fish`, `m3wal.fish`,
   `apply-theme.fish`) generates `matugen-colors.css`.
2. `cursor_matugen.sh` reads `--primary` (override with `MATUGEN_KEY`) from that
   CSS. If the file is JSON, `jq` is used instead.
3. `color_match.py` compares the hex against `themes.json` using CIEDE2000 in
   CIELAB space, weighting `primary` 0.75 and `body` 0.25, and prints one theme
   name such as `Sky-Blue` to stdout. Diagnostics go to stderr.
4. The script verifies the theme exists locally, then applies it:
   - `gsettings set org.gnome.desktop.interface cursor-theme` — your session.
   - `hyprctl setcursor` — Hyprland, when running.
   - Both `default/index.theme` files are rewritten with `Inherits=$THEME_NAME`.
   - The theme is copied into `/usr/share/icons/` if missing there.
   - The Xcursor default-theme files (`/usr/share/icons/default/index.theme`
     and `/var/lib/gdm/.icons/default/index.theme`) are rewritten for apps that
     ignore GSettings.
   - The keyfiles in `/etc/dconf/db/{local,gdm}.d/` are rewritten and both
     compiled dbs are rebuilt atomically, so the GDM greeter picks up the theme
     at the next login regardless of which system db its profile reads.
5. Separately, `cursor-watch.path` notices changes to `~/.config/dconf/user` and
   runs `cursor-watch.sh`, which syncs `XCursorTheme` / `XCursorSize` into
   `/var/lib/AccountsService/users/sakib` for GDM/AccountsService consumers.

Callers launch the matcher with `&>/dev/null &`, so failures are silent in the
theme-switcher output. Run it manually when troubleshooting.

## The three cursor settings

| Setting | Read by | How it is written |
|---|---|---|
| Session `gsettings` key | GNOME Shell, GTK apps | `cursor_matugen.sh` |
| `~/.icons/default/index.theme`, `~/.local/share/icons/default/index.theme` | Legacy X11 apps that ignore GSettings | `cursor_matugen.sh` |
| GDM greeter dconf | Login screen, running as its own user | `/etc/dconf/db/{local,gdm}.d/99-cursor-theme` via atomic db recompile |

The greeter's own user database is at
`/var/lib/gdm/seat0/config/dconf/user`; it contains no `cursor-theme` key, so it
falls back to the system `local` dconf database. Your user database has higher
priority than the system database, so the session keeps its wallpaper-driven
theme while the greeter uses the system default.

## GDM accent colour

The login screen has its own dconf accent too. `choose-accent.sh '#rrggbb'`
maps a hex to the nearest named GNOME accent, sets the session key, then mirrors
that name into `/etc/dconf/db/{local,gdm}.d/99-gdm-accent` and rebuilds both
compiled dbs atomically.
GDM accepts named accents only, not arbitrary hex values, so this is a match to
the nearest named colour rather than an exact copy of the matugen accent.

## Why GDM showed Adwaita

Two independent causes:

1. **dconf isolation.** As GDM's user, `gsettings get
   org.gnome.desktop.interface cursor-theme` returned `'Adwaita'` (the schema
   default). The chosen theme existed only in the user's dconf database, which
   the greeter never reads.
2. **Unreadable files.** `~/.local/share/icons/Bibata-Material-*` are symlink
   farms pointing into `icons/.icons/` with mode `0770`. The GDM user could not
   traverse them, so even a correct dconf key would have fallen back to
   Adwaita. AccountsService metadata does not control the greeter cursor either.

## Repair / setup commands

These are system-level changes and are not part of the dotfiles repo. Re-run
them on a fresh machine.

Install the themes where every user can read them. `-L` is required because the
source themes are symlink farms:

```sh
doas sh -c '
    cp -aL /home/sakib/.local/share/icons/Bibata-Material-* /usr/share/icons/
    chown -R root:root /usr/share/icons/Bibata-Material-*
    chmod -R a+rX /usr/share/icons/Bibata-Material-*
    command -v restorecon >/dev/null 2>&1 && restorecon -R /usr/share/icons/Bibata-Material-* || true
'
```

Rebuild the compiled system dconf databases without `dconf update`. The latter
broadcasts GSettings path-change events to every running client and has been
observed crashing gnome-shell's clock code (`update_clock` in
`libgnome-desktop-4`). Compiling to a temp file and replacing the db atomically
changes what the *next* process reads (the greeter at login) without notifying
the live session. Both `local` and `gdm` are written because the greeter's dconf
profile is not guaranteed to include `system-db:local`:

```sh
rebuild_gdm_dconf() {
    doas sh -c '
        for db in local gdm; do
            dconf compile /etc/dconf/db/$db.new /etc/dconf/db/$db.d \
                && chown root:root /etc/dconf/db/$db.new \
                && chmod 644 /etc/dconf/db/$db.new \
                && { command -v restorecon >/dev/null 2>&1 && restorecon /etc/dconf/db/$db.new || true; } \
                && mv -f /etc/dconf/db/$db.new /etc/dconf/db/$db \
                || exit 1
        done
    '
}
```

Set the greeter's cursor through the system dconf databases:

```sh
for db in local gdm; do
    printf "[org/gnome/desktop/interface]\ncursor-theme='Bibata-Material-Blush'\ncursor-size=24\n" \
        | doas tee "/etc/dconf/db/$db.d/99-cursor-theme" >/dev/null
done
rebuild_gdm_dconf
```

`cursor_matugen.sh` maintains both of these automatically from then on. The
current value is whatever the latest wallpaper matched, not necessarily Blush.

Seed the greeter's accent (normally maintained by `choose-accent.sh`):

```sh
accent=$(gsettings get org.gnome.desktop.interface accent-color | tr -d "'")
for db in local gdm; do
    printf "[org/gnome/desktop/interface]\naccent-color='%s'\n" "$accent" \
        | doas tee "/etc/dconf/db/$db.d/99-gdm-accent" >/dev/null
done
rebuild_gdm_dconf
```

## Verification checklist

```sh
# Session and greeter agree
gsettings get org.gnome.desktop.interface cursor-theme
doas -u gdm env XDG_CONFIG_HOME=/var/lib/gdm/seat0/config \
    gsettings get org.gnome.desktop.interface cursor-theme

# Accent agrees
gsettings get org.gnome.desktop.interface accent-color
doas -u gdm env XDG_CONFIG_HOME=/var/lib/gdm/seat0/config \
    gsettings get org.gnome.desktop.interface accent-color

# Legacy X11 fallbacks agree
grep Inherits ~/.icons/default/index.theme ~/.local/share/icons/default/index.theme

# Greeter can actually read the cursor files (0 means yes)
doas -u gdm test -r /usr/share/icons/Bibata-Material-Blush/cursors/left_ptr; echo $?

# Xcursor default fallbacks agree
grep Inherits /usr/share/icons/default/index.theme
doas cat /var/lib/gdm/.icons/default/index.theme

# System defaults are compiled and visible
dconf dump /org/gnome/desktop/interface/ | grep cursor
doas cat /etc/dconf/db/local.d/99-cursor-theme /etc/dconf/db/gdm.d/99-cursor-theme
doas strings /etc/dconf/db/gdm | grep Bibata

# Watcher is healthy
systemctl --user status cursor-watch.path cursor-watch.service --no-pager
```

The greeter process starts at login and reads dconf then. A change made while
logged in takes effect at the **next login**; log out/in (or reboot) to see it.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| GDM still Adwaita after login | GDM `gsettings` value, Xcursor default `Inherits`, then `test -r` on the system theme file | Re-run the setup commands above; remember to log out/in |
| GDM accent still blue | GDM `gsettings get accent-color`, then `/etc/dconf/db/{local,gdm}.d/99-gdm-accent` | Run `choose-accent.sh` with a matching hex or re-seed and run `rebuild_gdm_dconf`; log out/in |
| Shell crashes right after a theme change | `coredumpctl info gnome-shell` — look for `update_clock` in the stack | Never use `dconf update` from a live session; scripts use atomic `dconf compile` + `mv` instead |
| Session cursor wrong, GDM correct | Session `gsettings`, both `default/index.theme` files | Run `bash ~/Scripts/cursor_matugen.sh` directly |
| `Could not extract a valid 6-digit hex color` | `MATUGEN_KEY` vs. `--primary` in `matugen-colors.css` | Set `MATUGEN_KEY` to the CSS variable that actually exists |
| `matched theme ... was not found` | `themes.json` names vs. installed directories | Install/rebuild the matching `Bibata-Material-*` theme |
| Cursor watcher `failed (start-limit-hit)` | `systemctl --user status cursor-watch.service` | Ensure `StartLimitIntervalSec=0` in its `[Unit]` section and `daemon-reload` |
| Log grows with identical "Updated" lines | Run `cursor-watch.sh` twice and compare `wc -l ~/.cursor-watch.log` | The up-to-date check must run inside `doas`; `/var/lib/AccountsService/users` is `0700 root:root` |

## History

- `158c08c7b` — keep the legacy `~/.icons/default/index.theme` in sync with the
  XDG path.
- `94ee1741f` — sync the GDM greeter cursor: install the theme system-wide and
  set the local dconf default on every match.
- `choose-accent.sh` — mirror the named accent into the GDM dconf default.
- Replace `dconf update` with atomic `dconf compile` + `mv` after a gnome-shell
  crash traced to `update_clock` receiving GSettings path-change events.
- Mirror the cursor and accent keys into both `local` and `gdm` system dbs so the
  greeter sees them regardless of its dconf profile.
- Also update the Xcursor default-theme files for GDM and the system, since the
  greeter may use the Xcursor fallback instead of GSettings.
- The watcher fixes (root-side up-to-date check and start-limit change) are in
  machine-local files under `~/.config/` and are not tracked in this repo.
