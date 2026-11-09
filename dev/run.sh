#!/usr/bin/env bash
# Run the Agents Pet dev harness in its OWN Quickshell instance.
# It never touches the live Omarchy shell or the installed plugin, so the bar
# is not reloaded or restarted while you test or take screenshots.
#
#   dev/run.sh preview          play with the pet + settings in a window
#   dev/run.sh face|sheet|editor  render docs/pet.png | docs/sheet.png | docs/editor.png
#   dev/run.sh gif              render docs/demo.gif
#   dev/run.sh docs             all of the above
#
# PET_FILE picks the pet to render (default: your own ~/.config/omarchy/agents-pet.json).
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
export PET_FILE="${PET_FILE:-$HOME/.config/omarchy/agents-pet.json}"

# A throwaway Quickshell config: Omarchy's Commons/Ui libraries, this repo as
# "pet", and the harness as shell.qml.
cfg="${XDG_RUNTIME_DIR:-/tmp}/agents-pet-dev"
rm -rf "$cfg"
mkdir -p "$cfg"
ln -s "$omarchy_shell/Commons" "$cfg/Commons"
ln -s "$omarchy_shell/Ui" "$cfg/Ui"
ln -s "$repo" "$cfg/pet"
cp "$repo/dev/Harness.qml" "$cfg/shell.qml"

render() { # mode out
  MODE="$1" OUT="$2" timeout 60 quickshell -n -p "$cfg/shell.qml" >"$cfg/$1.log" 2>&1 || true
  if grep -E 'WARN|ERROR' "$cfg/$1.log" | grep -vE 'qmlscanner|portal|polkit' | grep -q .; then
    grep -E 'WARN|ERROR' "$cfg/$1.log" | grep -vE 'qmlscanner|portal|polkit' >&2
  fi
}

gif() {
  local frames="$cfg/frames"
  rm -rf "$frames"; mkdir -p "$frames"
  render gif "$frames"
  local fps; fps=$(cat "$frames/fps" 2>/dev/null || echo 15)
  ffmpeg -loglevel error -y -framerate "$fps" -i "$frames/%04d.png" \
    -vf "fps=15,scale=420:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
    "$repo/docs/demo.gif"
  echo "docs/demo.gif ($(ls "$frames"/*.png | wc -l) frames at ${fps} fps)"
}

mkdir -p "$repo/docs"
case "${1:-preview}" in
  preview) MODE=preview quickshell -n -p "$cfg/shell.qml" ;;
  face)    render face "$repo/docs/pet.png" && echo docs/pet.png ;;
  sheet)   render sheet "$repo/docs/sheet.png" && echo docs/sheet.png ;;
  editor)  render editor "$repo/docs/editor.png" && echo docs/editor.png ;;
  gif)     gif ;;
  docs)    "$0" face; "$0" sheet; "$0" editor; "$0" gif ;;
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
