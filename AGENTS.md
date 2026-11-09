# Notes for AI agents (and humans) working on this plugin

## Never work on the live plugin

The copy installed at `~/.config/omarchy/plugins/gusthx.agents-pet/` is the one the
user's Omarchy shell is running. Saving any file there hot-reloads the plugin in the
user's bar, and `omarchy restart shell` restarts the whole bar. Doing that over and over
while developing is disruptive.

- **Edit only this repository** (the working copy, e.g. `~/Work/omarchy-agents-pet`).
- **Do not** edit, copy into, or `git` anything under `~/.config/omarchy/plugins/`.
- **Do not** run `omarchy restart shell`, `omarchy refresh shell`, `omarchy theme set`,
  or IPC calls (`omarchy-shell gusthx.agents-pet ...`) to test a change.
- **Do not** take screenshots of the user's desktop (`grim`) to check your work.

## Test and capture in isolation

`dev/run.sh` starts a **separate** Quickshell instance with Omarchy's `Commons`/`Ui`
libraries and this repo. It never touches the running shell. Capture modes render
offscreen (Qt's offscreen platform, so they also work with the screen off) and save images
straight to files; `HEADLESS=0` draws on a background layer surface instead.

```bash
dev/run.sh preview   # a window to play with the pet and its settings
dev/run.sh face      # docs/pet.png    (the user's current pet, read-only)
dev/run.sh sheet     # docs/sheet.png  (bodies, eyes, head, accessories, moods, reactions)
dev/run.sh chips     # docs/chips.png  (every editor chip, framed, also in outline / pale)
dev/run.sh editor    # docs/editor-<tab>.png for shape face extras color saved, and
                     # docs/editor.png (the face tab); `dev/run.sh editor color` for one
dev/run.sh png       # Save PNG, backup / restore and editor key checks, in a temp folder
dev/run.sh gif       # docs/demo.gif   (scripted demo)
dev/run.sh docs      # all of the above
```

QML errors from the harness are printed by `dev/run.sh`; fix them before going further.
Also run `omarchy plugin validate .`.

What the harness cannot render (the full bar panel with live usage data) is checked by the
user after deploying, not by you on their live shell.

## Deploy only at the end, and only when asked

When a change is finished, tested in the harness and committed:

```bash
dev/deploy.sh   # fast-forwards the live plugin to this repo's HEAD
```

The shell hot-reloads the plugin once. Only if new IPC methods don't appear does the user
need `omarchy restart shell`. Never use `omarchy refresh shell` (it resets the bar layout).

## Other conventions

- Repo root = plugin root (the layout `omarchy plugin add <url>` expects).
- Strings go through the plugin's own catalog in `i18n/` (`Commons.Translations`), never
  through `Commons.I18n` keys, which Omarchy may rename.
- The pet config lives in `~/.config/omarchy/agents-pet.json`; read it, don't rewrite it
  from tests. The harness feeds the editor mock saved pets and points backups / PNGs at
  its own temp folder (`pngDir`, `backupPath`).
- No code from AGPL projects (e.g. bible-strong-avatar-lab): ideas only.
