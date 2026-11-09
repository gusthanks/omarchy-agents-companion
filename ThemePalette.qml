import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// The current Omarchy theme's named colors (red, green, blue, ...), read from
// its colors.toml. Pets store a color as "theme:<name>" so they follow the
// theme; this resolves the name to today's hex.
Item {
  id: root
  visible: false

  // Order shown in the editor's suggested swatches.
  readonly property var names: ["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "foreground"]
  property var colors: ({})

  function resolve(choice, fallback) {
    if (choice === "theme" || choice === "theme:accent") return Commons.Color.accent
    if (typeof choice === "string" && choice.indexOf("theme:") === 0) {
      var c = root.colors[choice.slice(6)]
      return c ? c : fallback
    }
    return /^#[0-9a-fA-F]{6}$/.test(String(choice)) ? choice : fallback
  }

  function parse(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
      if (m) out[m[1]] = m[2]
    }
    root.colors = out
  }

  FileView {
    id: file
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.parse(text())
    onFileChanged: reload()
  }

  // A theme switch swaps the whole theme directory; re-read when the shell's
  // own colors change so we never keep the previous theme's palette.
  Connections {
    target: Commons.Color
    function onAccentChanged() { file.reload() }
    function onBackgroundChanged() { file.reload() }
  }
}
