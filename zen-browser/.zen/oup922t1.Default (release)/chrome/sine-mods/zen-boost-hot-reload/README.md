# Zen Boost Hot Reload

A mod for Zen Browser that automatically watches your Boost files on disk and applies changes in real time. Edit a file, save it, and the browser updates instantly -- no manual re-importing required.

This mod is built for the [Sine Mod Engine](https://github.com/CosmoCreeper/Sine).

---

## What It Does

Zen Browser lets you apply "Boosts" -- visual overrides (colors, CSS, sliders) for individual websites. Normally, when you edit a Boost file on disk, you have to manually re-import it through the Site Control Panel every time.

This mod removes that step. It watches a directory for changes and automatically applies the updated Boost to any open tab that uses it.

### How Matching Works

When a file changes, the mod reads it and looks for the `boostName` field inside the JSON. It then finds every domain in your browser that has an active Boost with that same name and updates it. This means the file name itself does not matter -- only the `boostName` inside the JSON is used for matching.

---

## Installation

This mod is installed through Sine, the mod manager for Zen Browser.

**Two Sine settings must be enabled for this mod to work:**

1. Open Zen Browser and go to **Settings > Sine Mods**.
2. Open the Sine settings menu (the gear icon).
3. Enable **"Enable installing mods from unofficial sources"** -- this allows you to install mods from GitHub URLs.
4. Enable **"Allow External JS"** -- this allows Sine to load JavaScript from mods not published on the official store. Without this, the hot-reload script will not run.
5. Paste the following URL into the installation field and confirm:
   ```
   https://github.com/UpayanChatterjee/zen-boost-hot-reload
   ```
6. Restart Zen Browser.

After restarting, the mod is active. A watch directory is created automatically at `~/.config/zen-boosts/`.

---

## Configuration

### Default: Watch `~/.config/zen-boosts/`

Out of the box, the mod watches `~/.config/zen-boosts/` for any `.json` files (or files with no extension). This directory is created automatically on first run.

Place your Boost JSON files in this directory. The file name does not matter -- only the `boostName` field inside the JSON is used for matching.

Example directory structure:

```
~/.config/zen-boosts/
  github.json
  youtube.json
  reddit.json
```

Each file should contain a `boostName` that matches the name of the Boost currently applied to the target website in your browser.

### Custom Directory

You can point the mod at a different directory instead of the default one.

1. Go to **Settings > Sine Mods**.
2. Find **Zen Boost Hot Reload** and open its settings.
3. Enter the absolute path to a directory in the text field (for example, `/home/username/my-boosts`).
4. The change takes effect immediately -- no restart needed.

When a custom path is set, the mod watches that directory instead. The default `~/.config/zen-boosts/` directory is ignored. If you clear the field, the mod reverts to the default.

You can provide the path with or without a trailing slash -- both work.

---

## Usage

1. Apply a Boost to a website using Zen Browser's normal process and export the boost.
2. Select a suitable location on disk to export the boost to. If you are using the default setup, export it to `~/.config/zen-boosts/`.
3. Open the file in any text editor.
4. Make changes (adjust `brightness`, `contrast`, `customCSS`, `zapSelectors`, etc.).
5. Save the file.

The mod detects the change within about half a second and applies it. A toast notification appears in the browser confirming the update.

---

## License

This project is licensed under the [MIT License](LICENSE).
