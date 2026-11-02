# Releasing to itch.io

## 1. Export templates

Godot needs the 4.7.2 web templates once per machine: in the editor, **Editor > Manage Export Templates >
Download and Install**. Headless, the files that matter are `web_nothreads_debug.zip` and
`web_nothreads_release.zip` in `%APPDATA%/Godot/export_templates/4.7.2.stable/` (Windows) or
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

## 3. Upload

1. Zip the **contents** of `build/web/` (so `index.html` is at the root of the zip).
2. itch.io > your game > Edit > Uploads: upload the zip and tick **This file will be played in the browser**.
3. Kind of project: **HTML**. Viewport: **960 x 540**. Tick **Fullscreen button**. Leave
   **SharedArrayBuffer support** off (not needed).
4. Add the Game Off 2026 tag and the GitHub repo link in the description.

## 4. Tag the release

1. Move the **Unreleased** section of `CHANGELOG.md` under a version heading.
2. `git tag v0.1.0 && git push --tags`, then create a GitHub release and attach the web zip.
