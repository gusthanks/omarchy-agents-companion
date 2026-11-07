#!/usr/bin/env bash
# Install the companion plugin into the Omarchy shell plugin directory.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dest="${OMARCHY_PLUGIN_DIR:-$HOME/.config/omarchy/plugins}/gusthx.agents"

command -v rsync >/dev/null || { echo "rsync is required" >&2; exit 1; }
command -v agy >/dev/null || echo "warning: 'agy' not found - chat will not work until it is installed" >&2

if [ -e "$dest" ]; then
  backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
  echo "Backing up existing plugin to $backup"
  cp -a "$dest" "$backup"
fi

mkdir -p "$dest"
rsync -a --delete "$repo/plugin/" "$dest/"
echo "Installed to $dest"
echo "Now run: omarchy restart shell   (not 'omarchy refresh shell', which resets your bar)"
