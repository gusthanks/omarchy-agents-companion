#!/usr/bin/env bash
# Install the committed state of this repo into the live Omarchy plugin.
# Run this only when a change is finished and tested in the dev harness:
# the live shell hot-reloads the plugin as soon as its files change.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
live="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/$(jq -r .id "$repo/manifest.json")"

[[ -z $(git -C "$repo" status --porcelain) ]] || { echo "Commit your changes first (deploy installs HEAD)." >&2; exit 1; }
omarchy plugin validate "$repo"

if [[ -d $live/.git ]]; then
  git -C "$live" pull --ff-only -q "$repo" "$(git -C "$repo" branch --show-current)"
else
  echo "No git checkout at $live; install with: omarchy plugin add <repo-url>" >&2
  exit 1
fi
echo "Deployed $(git -C "$repo" log --oneline -1) to $live"
echo "The shell reloads the plugin by itself. Only if new IPC methods don't show up: omarchy restart shell"
