# Releasing to itch.io

## 1. Export templates

Godot needs the 4.7.2 export templates once per machine: in the editor, **Editor > Manage Export Templates >
Download and Install**. Headless, the files that matter are `web_nothreads_debug.zip` and
`web_nothreads_release.zip` (web) and `windows_release_x86_64.exe` (Windows) in
`%APPDATA%/Godot/export_templates/4.7.2.stable/` (Windows) or
`~/.local/share/godot/export_templates/4.7.2.stable/` (Linux).

## 2. Export

The project ships a `Web` preset (`export_presets.cfg`):

- **Thread support off.** The build does not need `SharedArrayBuffer`, so it runs on itch.io (and GitHub Pages)
  without cross-origin isolation headers.
- `data/*.json` is included explicitly; `tests/`, `docs/` and `build/` are excluded.
- The canvas takes focus on start, so keys work after the first click.

```bash
godot --headless --path . --export-release "Web" build/web/index.html
```

Or in the editor: **Project > Export > Web > Export Project**, to `build/web/index.html`. The output is about 40 MB
(mostly `index.wasm`). `build/` is git-ignored.

Check it locally before uploading (Godot's web build will not run from `file://`):

```bash
cd build/web && python -m http.server 8000     # then open http://localhost:8000
```

### Windows

The `Windows Desktop` preset builds one self-contained .exe (x86_64, game data embedded, no console window):

```bash
godot --headless --path . --export-release "Windows Desktop" "build/windows/Cluck Shift.exe"
```

It is about 110 MB, almost all of it the engine. Double-click to check it runs. Windows SmartScreen will warn about
an unsigned app ("More info > Run anyway"); the itch.io page should say so.

## 3. Upload

1. Zip the **contents** of `build/web/` (so `index.html` is at the root of the zip).
2. itch.io > your game > Edit > Uploads: upload the zip and tick **This file will be played in the browser**.
3. Kind of project: **HTML**. Viewport: **960 x 540**. Tick **Fullscreen button**. Leave
   **SharedArrayBuffer support** off (not needed).
4. Add the Game Off 2026 tag and the GitHub repo link in the description.
5. Upload `build/windows/Cluck Shift.exe` as a second file and mark it **Windows**. Mention the SmartScreen warning.

## 4. Tag the release

1. Move the **Unreleased** section of `CHANGELOG.md` under a version heading.
2. `git tag v0.1.0 && git push --tags`, then create a GitHub release and attach the web zip and the Windows .exe.
