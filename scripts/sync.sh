#!/usr/bin/env bash
# Developer helper: mirror the live plugin into plugin/, commit, and push.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/gusthx.agents"

rsync -a --delete --exclude '*.bak' --exclude 'DotMatrixAvatar.qml' "$src/" "$repo/plugin/"

cd "$repo"
git add -A
if git diff --cached --quiet; then
  exit 0
fi
git commit -q -m "${1:-Sync plugin ($(date '+%Y-%m-%d %H:%M'))}"
git push -q origin HEAD
echo "Synced and pushed."
