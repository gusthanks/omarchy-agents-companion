#!/usr/bin/env bash
# Install the committed state of this repo into the live Omarchy plugin.
# Run this only when the work is finished and tested in the dev harness. It
# restarts the shell once at the end so the new version actually shows.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
live="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/$(jq -r .id "$repo/manifest.json")"

[[ -z $(git -C "$repo" status --porcelain) ]] || { echo "Commit your changes first (deploy installs HEAD)." >&2; exit 1; }
omarchy plugin validate "$repo"
"$repo/dev/run.sh" check >/dev/null || { "$repo/dev/run.sh" check; echo "QML does not compile; not deploying." >&2; exit 1; }

if [[ -d $live/.git ]]; then
  git -C "$live" pull --ff-only -q "$repo" "$(git -C "$repo" branch --show-current)"
else
  echo "No git checkout at $live; install with: omarchy plugin add <repo-url>" >&2
  exit 1
fi
echo "Deployed $(git -C "$repo" log --oneline -1) to $live"
# The shell's hot reload is not reliable for plugins (the old version can stay
# on screen), so finish with one restart. Skip with NO_RESTART=1.
if [[ ${NO_RESTART:-0} != 1 ]]; then
  omarchy restart shell >/dev/null 2>&1 || true
  echo "Shell restarted: the new version is live."
fi
