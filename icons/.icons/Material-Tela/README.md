# Material-Tela

A monochrome icon theme for Linux desktops. Tela-style folders are paired
with a full icon set recolored to a single `matugen` accent color, produced
from the system wallpaper.

The theme is a re-color + extension of the **Yet Another Monochrome Icon
Set** with **Tela** folder shapes. App icons that aren't part of the base set
are added as single-color glyphs traced from each app's official icon.

## Contents

- `apps/` — application icons (including ~200 hand-extracted Flathub apps)
- `actions/`, `categories/`, `devices/`, `emblems/`, `mimetypes/`,
  `places/`, `preferences/`, `status/` — system icon contexts (mostly
  single-color traces of the Tela and Papirus glyphs below)
- `index.theme` — icon theme declaration (inherits Adwaita, hicolor)
- Font-fallback chain: icons not present here are inherited from the
  themes listed above.

## Sources and acknowledgement

Every icon in this theme is derived from work by the following projects and
authors. Many thanks to them:

- **Yet Another Monochrome Icon Set (YAMIS)** — creator **dirn**
  ([bitbucket.org/dirn-typo/yet-another-monochrome-icon-set](https://bitbucket.org/dirn-typo/yet-another-monochrome-icon-set)),
  loosely based on the **Orion** icon theme by Storm Rosenaa. The base of
  this theme (`Authors`, `changelog`, and the `LICENSE` text).
- **Tela icon theme** — creator **vinceliuice**
  ([github.com/vinceliuice/Tela-icon-theme](https://github.com/vinceliuice/Tela-icon-theme)),
  the folder shapes and the "Tela" family naming this theme follows. The
  system-context icons (`actions/`, `categories/`, `devices/`, `emblems/`,
  `preferences/`, `status/`) are single-color accent traces of Tela's
  `22/` and `symbolic/` glyphs.
- **Papirus icon theme** — the Papirus Development Team
  ([github.com/PapirusDevelopmentTeam/papirus-icon-theme](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)),
  source of several app glyphs and the fallback source for system-context
  icons with no Tela equivalent.
- **GNOME Adwaita / hicolor** — a few system app icons sourced for glyph
  extraction.
- **Bibata** — cursor theme by **ful1e5** ([github.com/ful1e5/Bibata_Cursor](https://github.com/ful1e5/Bibata_Cursor));
  the sibling `Bibata-Matugen-*` cursor themes in this repo follow the same
  matugen-accent workflow.
- **Flathub app icons** — the ~200 application icons in `apps/` are
  single-color traces of each upstream app's official Flathub icon. Each
  such icon remains the property of its respective upstream project, whose
  licenses vary (GPL, LGPL, CC-BY-SA, MIT, proprietary, etc.). If your app's
  icon appears here and you'd like it removed, open an issue.
- **matugen** ([github.com/InioX/matugen](https://github.com/InioX/matugen)) —
  the Scheme/template generator that produces the accent colors used to
  recolor every icon.

The `Authors` file additionally credits the base YAMIS author, as required
by its license.

## License

**GPL-3.0-only** — see `LICENSE`.

This theme is a derivative work of GPL-3.0 projects (YAMIS by dirn, Tela by
vinceliuice, Papirus, Bibata), so it is distributed under the GNU General
Public License v3 to stay license-compatible with its sources. Every
original SVG in this theme is released under the same terms. App icons
traced from Flathub are subject to their respective upstream licenses (see
above).