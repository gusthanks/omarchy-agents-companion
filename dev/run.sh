#!/usr/bin/env bash
# Run the Agents Pet dev harness in its OWN Quickshell instance.
# It never touches the live Omarchy shell or the installed plugin, so the bar
# is not reloaded or restarted while you test or take screenshots.
#
#   dev/run.sh preview          play with the pet + settings in a window
#   dev/run.sh face|sheet|chips render docs/pet.png | docs/sheet.png | docs/chips.png
#   dev/run.sh fit              docs/fit.png: every head extra and accessory on
#                               every body, both styles, panel and bar size
#                               (a local check image, git-ignored)
#   dev/run.sh editor [TAB]     render docs/editor-<tab>.png for each settings tab
#                               (shape face extras color saved), or just TAB;
#                               docs/editor.png is the face tab
#   dev/run.sh png              test the "Save as PNG" and backup export/import
#                               paths into a temp folder (never your config)
#   dev/run.sh gif              render docs/demo.gif
#   dev/run.sh docs             all of the above
#   dev/run.sh check            compile every plugin type, Panel.qml included
#                               (declared, never instantiated), and every usage/
#                               library; run before deploy
#   dev/run.sh test             Node tests of the usage/ math (dev/tests)
#
# PET_FILE picks the pet to render (default: your own ~/.config/omarchy/agents-pet.json,
# read only). Captures render offscreen (HEADLESS=1, the default), so nothing
# shows on the desktop and they work with the screen off; HEADLESS=0 uses a
# background layer surface instead.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
omarchy_shell="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
export PET_FILE="${PET_FILE:-$HOME/.config/omarchy/agents-pet.json}"
export HEADLESS="${HEADLESS:-1}"

# A throwaway Quickshell config: Omarchy's Commons/Ui libraries, this repo as
# "pet", and the harness as shell.qml.
cfg="${XDG_RUNTIME_DIR:-/tmp}/agents-pet-dev"
rm -rf "$cfg"
mkdir -p "$cfg"
ln -s "$omarchy_shell/Commons" "$cfg/Commons"
ln -s "$omarchy_shell/Ui" "$cfg/Ui"
ln -s "$repo" "$cfg/pet"
cp "$repo/dev/Harness.qml" "$cfg/shell.qml"
cp "$repo/dev/LayerStage.qml" "$cfg/LayerStage.qml"

render() { # mode out [log-name]
  local log="$cfg/${3:-$1}.log"
  local platform=()
  # Offscreen has no monitor scale: DEV_SCALE stands in for it (1.6 matches
  # the images made on the laptop screen).
  [ "$HEADLESS" = 1 ] && platform=(env QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR="${DEV_SCALE:-1.6}")
  MODE="$1" OUT="$2" timeout 60 "${platform[@]}" quickshell -n -p "$cfg/shell.qml" >"$log" 2>&1 || true
  local noise='qmlscanner|portal|polkit|QT_QPA_PLATFORM|actually running wayland|window masks|--- WARNING ---|No PanelWindow backend|toplevel-mapping'
  if grep -E 'WARN|ERROR' "$log" | grep -vE "$noise" | grep -q .; then
    grep -E 'WARN|ERROR' "$log" | grep -vE "$noise" >&2
  fi
  grep -E '^.*qml.*: (PNG|BACKUP|CHECK)' "$log" | sed 's/^.*qml[^:]*: //' || true
}

editor() { # [tab]
  local tabs="${1:-shape face extras color saved}"
  for t in $tabs; do
    rm -f "$repo/docs/editor-$t.png"; TAB="$t" render editor "$repo/docs/editor-$t.png" "editor-$t"; [ -f "$repo/docs/editor-$t.png" ] && echo "docs/editor-$t.png"
  done
  [ -f "$repo/docs/editor-face.png" ] && cp "$repo/docs/editor-face.png" "$repo/docs/editor.png" && echo docs/editor.png
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
  chips)   render chips "$repo/docs/chips.png" && echo docs/chips.png ;;
  fit)     render fit "$repo/docs/fit.png" && echo docs/fit.png ;;
  editor)  editor "${2:-${TAB:-}}" ;;
  png)     out="$cfg/out"; mkdir -p "$out"; render png "$out"; ls -la "$out"; echo "(files in $out)" ;;
  gif)     gif ;;
  check)
    # Compile-only: types are declared inside Components that never get created,
    # so no window opens. Needs the Wayland backend (Panel uses PanelWindow).
    files=$(cd "$repo" && ls *.qml | sed 's/\.qml$//')
    # The usage/ libraries are imported too, so a broken one fails the load
    # even before a type uses it.
    libs=$(cd "$repo" && ls usage/*.js 2>/dev/null || true)
    { echo 'import QtQuick'; echo 'import Quickshell'; echo 'import "pet" as Pet'
      i=0; for f in $libs; do echo "import \"pet/$f\" as Lib$i"; i=$((i+1)); done
      echo 'ShellRoot {'
      i=0; for f in $files; do echo "  Component { id: c$i; Pet.$f {} }"; i=$((i+1)); done
      echo '  Component.onCompleted: {'
      i=0; for f in $files; do echo "    console.warn(\"CHECK $f\", c$i.status === Component.Ready ? \"OK\" : c$i.errorString())"; i=$((i+1)); done
      echo '  }'; echo '}'; } > "$cfg/shell.qml"
    timeout 20 quickshell -n -p "$cfg/shell.qml" >"$cfg/check.log" 2>&1 || true
    if grep -q 'Failed to load configuration' "$cfg/check.log"; then grep -E 'ERROR' "$cfg/check.log" >&2; exit 1; fi
    grep -a 'CHECK ' "$cfg/check.log" | sed 's/^.*CHECK /CHECK /'
    ! grep -a 'CHECK ' "$cfg/check.log" | grep -vq ' OK$' ;;
  test)    nice -n 19 node --test "$repo"/dev/tests/*.test.mjs ;;
  docs)    "$0" face; "$0" sheet; "$0" chips; "$0" fit; "$0" editor; "$0" gif ;;
  *) sed -n '2,25p' "$0"; exit 1 ;;
esac
