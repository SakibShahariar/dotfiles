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
| GDM system cursor default | `/etc/dconf/db/local.d/99-cursor-theme` | no (system config) |
| GDM system accent default | `/etc/dconf/db/local.d/99-gdm-accent` | no (system config) |
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
   - `/etc/dconf/db/local.d/99-cursor-theme` is rewritten and `dconf update`
     runs, so the GDM greeter picks it up at the next login.
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
| GDM greeter dconf | Login screen, running as its own user | `/etc/dconf/db/local.d/99-cursor-theme` via `dconf update` |

The greeter's own user database is at
`/var/lib/gdm/seat0/config/dconf/user`; it contains no `cursor-theme` key, so it
falls back to the system `local` dconf database. Your user database has higher
priority than the system database, so the session keeps its wallpaper-driven
theme while the greeter uses the system default.

## GDM accent colour

The login screen has its own dconf accent too. `choose-accent.sh '#rrggbb'`
maps a hex to the nearest named GNOME accent, sets the session key, then mirrors
that name into `/etc/dconf/db/local.d/99-gdm-accent` and runs `dconf update`.
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

Set the greeter's cursor through the system dconf database:

```sh
printf "[org/gnome/desktop/interface]\ncursor-theme='Bibata-Material-Blush'\ncursor-size=24\n" \
    | doas tee /etc/dconf/db/local.d/99-cursor-theme >/dev/null
doas dconf update
```

`cursor_matugen.sh` maintains both of these automatically from then on. The
current value is whatever the latest wallpaper matched, not necessarily Blush.

Seed the greeter's accent (normally maintained by `choose-accent.sh`):

```sh
accent=$(gsettings get org.gnome.desktop.interface accent-color | tr -d "'")
printf "[org/gnome/desktop/interface]\naccent-color='%s'\n" "$accent" \
    | doas tee /etc/dconf/db/local.d/99-gdm-accent >/dev/null
doas dconf update
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

# System default is compiled and visible
dconf dump /org/gnome/desktop/interface/ | grep cursor
doas cat /etc/dconf/db/local.d/99-cursor-theme

# Watcher is healthy
systemctl --user status cursor-watch.path cursor-watch.service --no-pager
```

The greeter process starts at login and reads dconf then. A change made while
logged in takes effect at the **next login**; log out/in (or reboot) to see it.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| GDM still Adwaita after login | GDM `gsettings` value, then `test -r` on the system theme file | Re-run the setup commands above; remember to log out/in |
| GDM accent still blue | GDM `gsettings get accent-color`, then `/etc/dconf/db/local.d/99-gdm-accent` | Run `choose-accent.sh` with a matching hex or re-seed and run `dconf update`; log out/in |
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
- The watcher fixes (root-side up-to-date check and start-limit change) are in
  machine-local files under `~/.config/` and are not tracked in this repo.
