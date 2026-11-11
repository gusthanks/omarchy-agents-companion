import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PetColors.js" as PetColors

// Pet settings ("Pet Studio"): a header (stage, dice, name, status line),
// five tabs (Shape, Face, Extras, Color, Saved) over a page of
// fixed height, and a footer (Undo, Reset, Done).
//
// Edits apply at once through signals; the panel persists them. Hovering an
// option (or landing on it with the keyboard) tries it on the stage pet only;
// a click or Enter commits it. Keyboard and mouse share the panel's single
// cursor: the editor publishes `keyRows`, the panel owns `keyTarget`.
Item {
  id: root

  property var look: ({})
  property string petName: ""
  // s | m | l, each on its own: the pet in the bar and the one in the panel.
  property string barSize: "m"
  property string panelSize: "m"
  // lively | calm | still (see BlobAvatar.reactions)
  property string petReactions: "lively"
  property var saved: []
  // The last custom colors picked, newest first (#rrggbb, at most 8). Kept
  // apart from the look, so undo and reset leave them alone.
  property var recentColors: []
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Commons.Color.accent
  property color urgent: Commons.Color.urgent
  property string fontFamily: Style.font.family

  // The panel's cursor target ({kind, index} or null) and the active tab.
  property var keyTarget: null
  property int tab: 0

  // Where backups and PNGs go. Empty: the XDG Documents folder (or ~) and
  // the XDG Pictures folder.
  // The dev harness points these at a temp folder.
  property string backupPath: ""
  property string pngDir: ""

  signal lookEdited(var look)
  signal nameEdited(string name)
  // key: barSize | panelSize
  signal sizeEdited(string key, string size)
  signal reactionsEdited(string reactions)
  signal recentEdited(var colors)
  signal saveCurrent()
  signal wear(int index)
  signal forget(int index)
  signal imported(string name, var look)
  signal done()
  // Panel wiring: move the shared cursor, keep an item in view, and put back
  // a snapshot ({name, look, saved, barSize, panelSize, reactions}; any subset).
  signal pointRequested(string kind, int index)
  signal revealRequested(Item item)
  signal restore(var snapshot)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  function tr(key, fallback) { return strings.t(key, fallback) }

  implicitHeight: col.implicitHeight
  height: implicitHeight

  readonly property string home: Quickshell.env("HOME") || ""

  readonly property var defaults: ({ body: "blob", eyes: "capsule", mouth: "none", extra: "none", accessory: "none", cheeks: true, style: "solid", color: "theme", eyeSize: 1, mouthSize: 1 })

  readonly property var traits: [
    { key: "body", options: ["blob", "orb", "squircle", "drop", "ghost", "cloud", "egg", "mochi", "bean"] },
    { key: "eyes", options: ["capsule", "dot", "googly", "pixel", "sleepy", "star", "sparkle", "cyclops", "heart"] },
    { key: "mouth", options: ["none", "smile", "o", "cat", "flat", "fang", "tongue", "grin", "smirk"] },
    { key: "extra", options: ["none", "antenna", "leaf", "ears", "horns", "halo", "tuft", "bunnyEars", "unicorn"] },
    { key: "accessory", options: ["none", "glasses", "hat", "beanie", "bow", "flower", "headphones", "crown", "scarf", "bowtie"] },
    { key: "style", options: ["solid", "outline"] },
    { key: "cheeks", options: [true, false] }
  ]
  function optionsOf(key) {
    for (var i = 0; i < root.traits.length; i++) if (root.traits[i].key === key) return root.traits[i].options
    return []
  }

  readonly property var optionLabels: ({
    body: { blob: "Blob", orb: "Orb", squircle: "Squircle", drop: "Drop", ghost: "Ghost", cloud: "Cloud", egg: "Egg", mochi: "Mochi", bean: "Bean" },
    eyes: { capsule: "Capsule", dot: "Dots", googly: "Googly", pixel: "Pixel", sleepy: "Sleepy", star: "Star", sparkle: "Sparkly", cyclops: "Cyclops", heart: "Heart" },
    mouth: { none: "None", smile: "Smile", o: "Surprised", cat: "Cat", flat: "Flat", fang: "Fang", tongue: "Tongue", grin: "Grin", smirk: "Smirk" },
    extra: { none: "None", antenna: "Antenna", leaf: "Leaf", ears: "Cat ears", horns: "Horns", halo: "Halo", tuft: "Tuft", bunnyEars: "Bunny ears", unicorn: "Unicorn horn" },
    accessory: { none: "None", glasses: "Glasses", hat: "Top hat", beanie: "Beanie", bow: "Bow", flower: "Flower",
                 headphones: "Headphones", crown: "Crown", scarf: "Scarf", bowtie: "Bow tie" },
    style: { solid: "Solid", outline: "Outline" }
  })
  // Eye and mouth size: numbers in the look, picked from five steps.
  readonly property var lookScales: ["eyeSize", "mouthSize"]
  readonly property var scaleSteps: [0.7, 0.85, 1, 1.2, 1.4]
  // The nearest step; 1 when missing or not a number.
  function scaleStep(v) {
    var n = Number(v)
    if (v === undefined || v === null || v === "" || !isFinite(n)) return 1
    var best = 1
    for (var i = 0; i < root.scaleSteps.length; i++)
      if (Math.abs(root.scaleSteps[i] - n) < Math.abs(best - n)) best = root.scaleSteps[i]
    return best
  }
  readonly property var scaleOptions: [
    { value: "0.7", label: "XS", tooltip: strings.t("pet.size.xs", "Extra small") },
    { value: "0.85", label: "S", tooltip: strings.t("pet.size.s", "Small") },
    { value: "1", label: "M", tooltip: strings.t("pet.size.m", "Medium") },
    { value: "1.2", label: "L", tooltip: strings.t("pet.size.l", "Large") },
    { value: "1.4", label: "XL", tooltip: strings.t("pet.size.xl", "Extra large") }
  ]
  readonly property var sizeOptions: [
    { value: "s", label: "S", tooltip: strings.t("pet.size.s", "Small") },
    { value: "m", label: "M", tooltip: strings.t("pet.size.m", "Medium") },
    { value: "l", label: "L", tooltip: strings.t("pet.size.l", "Large") }
  ]

  function optionName(key, val) {
    var labels = root.optionLabels[key]
    return strings.t("pet.opt." + key + "." + val, labels && labels[val] ? labels[val] : String(val))
  }

  // Shared ThemePalette (from the panel). Suggested colors are the current
  // theme's own, stored as "theme:<name>" so the pet follows theme switches.
  property var themePalette: null
  readonly property var swatches: {
    var out = ["theme"]
    if (!root.themePalette) return out
    var cols = root.themePalette.colors
    var names = root.themePalette.names
    for (var i = 0; i < names.length; i++) if (cols[names[i]]) out.push("theme:" + names[i])
    return out
  }
  function swatchColor(choice) {
    return root.themePalette ? root.themePalette.resolve(choice, root.accent) : (choice === "theme" ? root.accent : choice)
  }
  readonly property color currentColor: root.swatchColor(root.value("color"))
  function colorName(choice) {
    var c = String(choice)
    if (c === "theme") return strings.t("pet.color.accent", "Theme accent")
    if (c.indexOf("theme:") === 0) {
      var n = c.slice(6).replace(/_/g, " ")
      return n.charAt(0).toUpperCase() + n.slice(1)
    }
    return c
  }

  function value(key) {
    var v = root.look ? root.look[key] : undefined
    return v === undefined || v === null || v === "" ? root.defaults[key] : v
  }

  function withTrait(key, val) {
    var next = {}
    for (var k in root.defaults) next[k] = root.value(k)
    next[key] = val
    return next
  }

  // Keep only known traits and values, so a pasted code can never inject junk.
  function sanitize(raw) {
    var out = {}
    raw = raw && typeof raw === "object" ? raw : {}
    for (var i = 0; i < root.traits.length; i++) {
      var t = root.traits[i]
      out[t.key] = t.options.indexOf(raw[t.key]) >= 0 ? raw[t.key] : root.defaults[t.key]
    }
    var c = String(raw.color || "")
    out.color = c === "theme" || /^theme:[a-z_]+$/.test(c) || /^#[0-9a-fA-F]{6}$/.test(c) ? c : "theme"
    for (var j = 0; j < root.lookScales.length; j++) out[root.lookScales[j]] = root.scaleStep(raw[root.lookScales[j]])
    return out
  }

  function shareCode() {
    return JSON.stringify({ agentsPet: 1, name: root.petName, look: root.withTrait("color", root.value("color")) })
  }

  // ------------------------------------------------------------ chip looks
  function hexOf(c) {
    function h2(v) { var s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h2(c.r) + h2(c.g) + h2(c.b)
  }
  function luma(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }
  // Hats, bows and flowers are drawn in the foreground color; on a pet of
  // nearly the same brightness the chip uses a neutral body instead.
  readonly property string neutralColor: {
    var b = Commons.Color.background, f = root.foreground
    return root.hexOf(Qt.rgba(b.r + (f.r - b.r) * 0.45, b.g + (f.g - b.g) * 0.45, b.b + (f.b - b.b) * 0.45, 1))
  }

  // A chip only depends on its trait, the style and the color. The same
  // object comes back while those stay put, so editing another trait doesn't
  // repaint every chip (a new object would). Plain JS cache: no notifications.
  property var chipCache: ({})
  function chipLook(key, val) {
    if (key === "style") return root.withTrait("style", val)
    var color = root.value("color")
    if (key === "accessory" && val !== "none" && val !== "glasses"
        && Math.abs(root.luma(root.currentColor) - root.luma(root.foreground)) < 0.25)
      color = root.neutralColor
    var id = key + "|" + val + "|" + root.value("style") + "|" + color
    var cache = root.chipCache
    if (cache[id]) return cache[id]
    var l = { body: "orb", eyes: "dot", mouth: "none", extra: "none", accessory: "none", cheeks: false,
              style: root.value("style"), color: color }
    l[key] = val
    if (Object.keys(cache).length > 300) for (var k in cache) delete cache[k]
    cache[id] = l
    return l
  }

  function chipFrame(key, val) {
    if (key === "body") return "silhouette"
    if (key === "eyes") return "eyes"
    if (key === "mouth") return "mouth"
    // Bow and flower sit on the sides of the head: the "top" frame keeps
    // them whole, so the accessory row reads as one family. Glasses and
    // headphones need the whole head, neckwear the whole body down to the
    // scarf ends.
    if (key === "accessory") {
      if (val === "glasses" || val === "headphones") return "eyes"
      return val === "scarf" || val === "bowtie" ? "neck" : "top"
    }
    return "top"
  }

  // ------------------------------------------------------------ state
  property var visited: [true, false, false, false, false]
  property var tryOn: null           // { key, val } shown on the stage only
  property string draftColor: ""     // picker drag in progress
  property bool pickerOpen: false
  property var lastSnapshot: null
  property string status: ""
  property string statusKind: "ok"   // ok | error
  property string stageMood: "normal"
  readonly property bool savedFull: root.saved.length >= 24
  readonly property bool fieldFocused: nameField.activeFocus || (root.hexFieldItem !== null && root.hexFieldItem.activeFocus)
  property Item hexFieldItem: null

  readonly property var previewLook: root.draftColor !== "" ? root.withTrait("color", root.draftColor)
    : (root.tryOn ? root.withTrait(root.tryOn.key, root.tryOn.val) : root.look)

  Component.onCompleted: {
    root.pickerOpen = String(root.value("color")).charAt(0) === "#"
    root.markVisited(root.tab)
  }
  onTabChanged: root.markVisited(root.tab)
  onVisibleChanged: if (!visible) { root.tryOn = null; root.draftColor = "" }

  function markVisited(i) {
    if (i < 0 || i > 4 || root.visited[i]) return
    var v = root.visited.slice()
    v[i] = true
    root.visited = v
  }

  function isKey(kind, index) {
    return !!root.keyTarget && root.keyTarget.kind === kind && root.keyTarget.index === (index || 0)
  }

  function say(text, kind, long) {
    root.status = text
    root.statusKind = kind || "ok"
    statusTimer.interval = long ? 3500 : 2200
    statusTimer.restart()
    if (root.statusKind === "error") { root.stageMood = "worried"; moodTimer.restart() }
  }
  Timer { id: statusTimer; interval: 2200; onTriggered: root.status = "" }
  Timer { id: moodTimer; interval: 1200; onTriggered: root.stageMood = "normal" }

  function tildePath(p) {
    return root.home !== "" && p.indexOf(root.home + "/") === 0 ? "~" + p.slice(root.home.length) : p
  }
  // The status line is narrow: file messages name the folder or the file,
  // not the whole path.
  function folderOf(p) {
    var t = root.tildePath(p), i = t.lastIndexOf("/")
    return i > 0 ? t.slice(0, i) : t
  }
  function fileOf(p) { return String(p).slice(String(p).lastIndexOf("/") + 1) }

  // ------------------------------------------------------------ edits
  function commit(key, val) {
    if (key === "color" && String(val).charAt(0) === "#")
      root.recentEdited(PetColors.cleanRecent([val].concat(root.recentColors)))
    root.touch("look")
    root.tryOn = null
    root.lookEdited(root.withTrait(key, val))
    preview.triggerHappy()
  }

  // Undo covers one action: the snapshot keeps only the keys it changes, and
  // a later edit of any of those keys drops it (so undo can't revert that
  // edit, or a pet saved since, along with it).
  function snapshot(keys) {
    var all = {
      name: root.petName,
      look: root.withTrait("color", root.value("color")),
      saved: root.saved.slice(),
      barSize: root.barSize,
      panelSize: root.panelSize,
      reactions: root.petReactions
    }
    var s = {}
    keys = keys || ["name", "look", "saved", "barSize", "panelSize", "reactions"]
    for (var i = 0; i < keys.length; i++) s[keys[i]] = all[keys[i]]
    root.lastSnapshot = s
  }
  function touch(key) {
    if (root.lastSnapshot && root.lastSnapshot[key] !== undefined) root.lastSnapshot = null
  }
  function editName(n) {
    if (n !== root.petName) root.touch("name")
    root.nameEdited(n)
  }
  function editSize(key, v) {
    if (v === root[key]) return
    root.touch(key)
    root.sizeEdited(key, v)
  }
  function validSize(v, fallback) { return ["s", "m", "l"].indexOf(v) >= 0 ? v : fallback }

  function undo() {
    if (!root.lastSnapshot) return
    var s = root.lastSnapshot
    root.lastSnapshot = null
    root.restore(s)
    preview.triggerHappy()
    root.say(strings.t("pet.undone", "Undone"))
  }

  function randomize() {
    root.snapshot(["look"])
    var next = {}
    for (var i = 0; i < root.traits.length; i++) {
      var t = root.traits[i]
      next[t.key] = t.options[Math.floor(Math.random() * t.options.length)]
    }
    next.color = root.swatches[Math.floor(Math.random() * root.swatches.length)]
    // Sizes stay near the middle: the extremes are a deliberate choice.
    var tasteful = [0.85, 1, 1, 1.2]
    for (var j = 0; j < root.lookScales.length; j++) next[root.lookScales[j]] = tasteful[Math.floor(Math.random() * tasteful.length)]
    root.tryOn = null
    root.lookEdited(next)
    preview.triggerHappy()
    root.say(strings.t("pet.randomized", "Rolled a new look · u to undo"), "ok", true)
  }

  function resetLook() {
    root.snapshot(["look"])
    root.tryOn = null
    root.lookEdited(root.defaults)
    preview.triggerHappy()
    root.say(strings.t("pet.resetDone", "Back to default · u to undo"), "ok", true)
  }

  function savePet() {
    if (root.savedFull) { root.say(strings.t("pet.full", "Up to 24 pets"), "error"); return }
    root.editName(nameField.text.trim())
    root.touch("saved")
    root.saveCurrent()
    badgeBump.restart()
    root.say(strings.t("pet.saved", "Saved"))
  }

  function savedName(i) {
    var p = root.saved[i]
    return p && p.name ? String(p.name) : "?"
  }

  function wearCard(i) {
    if (!root.saved[i]) return
    root.snapshot(["name", "look"])
    root.wear(i)
    preview.triggerHappy()
    root.say(strings.t("pet.worn", "Wearing %1 · u to undo").replace("%1", root.savedName(i)), "ok", true)
  }

  function forgetCard(i) {
    if (!root.saved[i]) return
    var name = root.savedName(i)
    root.snapshot(["saved"])
    root.forget(i)
    root.say(strings.t("pet.forgotten", "Removed %1 · u to undo").replace("%1", name), "ok", true)
  }

  function isWorn(i) {
    var p = root.saved[i]
    if (!p) return false
    return String(p.name || "") === root.petName
      && JSON.stringify(root.sanitize(p.look)) === JSON.stringify(root.sanitize(root.look))
  }

  function setReactions(v) {
    if (["lively", "calm", "still"].indexOf(v) < 0 || v === root.petReactions) return
    root.touch("reactions")
    root.reactionsEdited(v)
    preview.triggerHappy()
  }

  readonly property var previewReactions: ["wink", "startle", "dizzy", "yawn", "celebrate"]
  readonly property var reactionLabels: ({ wink: "Wink", startle: "Startle", dizzy: "Dizzy", yawn: "Yawn", celebrate: "Party" })
  function previewReaction(name) {
    preview.stop("")
    preview.play(name, { force: true })
  }

  // ------------------------------------------------------------ clipboard code
  function copyCode() {
    Quickshell.execDetached(["wl-copy", "--", root.shareCode()])
    root.say(strings.t("pet.copied", "Code copied"))
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      onStreamFinished: root.importCode(text)
    }
  }

  function importCode(text) {
    try {
      var data = JSON.parse(String(text || "").trim())
      if (!data || data.agentsPet !== 1 || typeof data.look !== "object") throw "bad"
      root.snapshot(["name", "look"])
      root.imported(String(data.name || "").slice(0, 24), root.sanitize(data.look))
      preview.triggerHappy()
      root.say(strings.t("pet.importedUndo", "Pet imported · u to undo"), "ok", true)
    } catch (e) {
      root.say(strings.t("pet.importFailed", "No pet code in the clipboard"), "error")
    }
  }

  // ------------------------------------------------------------ full backup
  // Everything about the pet in one JSON file: the current pet, the saved
  // pets, both sizes and the personality.
  function backupData() {
    var list = []
    for (var i = 0; i < root.saved.length && i < 24; i++) {
      var p = root.saved[i] || {}
      list.push({ name: String(p.name || "").slice(0, 24), look: root.sanitize(p.look) })
    }
    return { agentsPetBackup: 1, name: root.petName, look: root.sanitize(root.look),
             barSize: root.barSize, panelSize: root.panelSize, reactions: root.petReactions, saved: list,
             recentColors: root.recentColors }
  }

  // A backup (or a single pet code) read back, with every field checked the
  // same way as a pasted code. Returns null when it isn't one.
  function sanitizeBackup(data) {
    if (!data || typeof data !== "object") return null
    if (data.agentsPet === 1 && typeof data.look === "object")
      return { name: String(data.name || "").slice(0, 24), look: root.sanitize(data.look) }
    if (data.agentsPetBackup !== 1) return null
    var out = { name: String(data.name || "").slice(0, 24), look: root.sanitize(data.look) }
    // Backups from before the two sizes carry one "size" for both.
    var legacy = root.validSize(data.size, "")
    out.barSize = root.validSize(data.barSize, legacy || root.barSize)
    out.panelSize = root.validSize(data.panelSize, legacy || root.panelSize)
    out.reactions = ["lively", "calm", "still"].indexOf(data.reactions) >= 0 ? data.reactions : root.petReactions
    var list = []
    if (Array.isArray(data.saved)) {
      for (var i = 0; i < data.saved.length && list.length < 24; i++) {
        var p = data.saved[i]
        if (!p || typeof p !== "object") continue
        list.push({ name: String(p.name || "").slice(0, 24), look: root.sanitize(p.look) })
      }
    }
    out.saved = list
    out.recentColors = Array.isArray(data.recentColors) ? PetColors.cleanRecent(data.recentColors) : root.recentColors
    return out
  }

  // The user's Documents folder (XDG, so localized names work), or ~.
  readonly property string docsDirSh: 'd=$(xdg-user-dir DOCUMENTS 2>/dev/null); [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Documents"; [ -d "$d" ] || d="$HOME"; '

  property string fileMode: ""  // export | import
  Process {
    id: fileProc
    stdout: StdioCollector {
      onStreamFinished: root.fileDone(text)
    }
  }

  function exportBackup() {
    if (fileProc.running) return
    root.editName(nameField.text.trim())
    root.fileMode = "export"
    fileProc.command = ["sh", "-c",
      'f="$2"; if [ -z "$f" ]; then ' + root.docsDirSh + 'f="$d/agents-pet-backup.json"; fi; '
      + 'mkdir -p "$(dirname "$f")" && printf "%s" "$1" > "$f" && printf "OK\\t%s" "$f" || printf "FAIL\\t%s" "$f"',
      "sh", JSON.stringify(root.backupData(), null, 2) + "\n", root.backupPath]
    fileProc.running = true
  }

  function importBackup() {
    if (fileProc.running) return
    root.fileMode = "import"
    fileProc.command = ["sh", "-c",
      'f="$1"; if [ -z "$f" ]; then ' + root.docsDirSh + 'f="$d/agents-pet-backup.json"; [ -f "$f" ] || [ ! -f "$HOME/agents-pet-backup.json" ] || f="$HOME/agents-pet-backup.json"; fi; '
      + 'if [ -f "$f" ]; then printf "OK\\t%s\\n" "$f"; head -c 262144 "$f"; else printf "MISSING\\t%s\\n" "$f"; fi',
      "sh", root.backupPath]
    fileProc.running = true
  }

  function fileDone(text) {
    var out = String(text || "")
    var nl = out.indexOf("\n")
    var head = (nl >= 0 ? out.slice(0, nl) : out).split("\t")
    var full = head[1] || ""
    var folder = root.folderOf(full)
    if (root.fileMode === "export") {
      if (head[0] === "OK") root.say(strings.t("pet.backupSaved", "Backup saved in %1").replace("%1", folder), "ok", true)
      else root.say(strings.t("pet.backupFailed", "Couldn't write to %1").replace("%1", folder), "error")
      console.log("BACKUP export " + head[0] + " " + (head[1] || ""))
      return
    }
    if (head[0] !== "OK") {
      root.say(strings.t("pet.backupMissing", "No backup in %1").replace("%1", folder), "error")
      console.log("BACKUP import missing " + (head[1] || ""))
      return
    }
    var clean = null
    try { clean = root.sanitizeBackup(JSON.parse(out.slice(nl + 1))) } catch (e) { clean = null }
    if (!clean) {
      root.say(strings.t("pet.backupInvalid", "Not a pet backup: %1").replace("%1", root.fileOf(full)), "error")
      console.log("BACKUP import invalid " + (head[1] || ""))
      return
    }
    root.snapshot()
    root.tryOn = null
    root.restore(clean)
    preview.triggerHappy()
    root.say(strings.t("pet.backupRestored", "Backup restored · u to undo"), "ok", true)
    console.log("BACKUP import ok " + JSON.stringify(clean))
  }

  // ------------------------------------------------------------ PNG export
  // A large, still pet is loaded off to the side only while exporting, then
  // grabbed with a transparent background.
  property string pngPath: ""
  function slug(s) {
    return String(s || "").toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32)
  }
  function exportPng() {
    if (mkdirProc.running || pngShot.active) return
    root.pngName = "agents-pet-" + (root.slug(nameField.text.trim() || root.petName) || "pet") + ".png"
    root.pngPath = root.pngName
    // The user's Pictures folder (XDG, so localized names work), created if needed.
    mkdirProc.command = ["sh", "-c",
      'd="$1"; if [ -z "$d" ]; then d=$(xdg-user-dir PICTURES 2>/dev/null); [ -n "$d" ] && [ "$d" != "$HOME" ] || d="$HOME/Pictures"; fi; '
      + 'mkdir -p "$d" && printf "%s" "$d"', "sh", root.pngDir]
    mkdirProc.running = true
  }
  property string pngName: ""
  Process {
    id: mkdirProc
    // Prints the folder only when it exists (or was just made).
    stdout: StdioCollector {
      onStreamFinished: {
        if (text !== "") {
          root.pngPath = text + "/" + root.pngName
          pngShot.active = true
        } else root.say(strings.t("pet.pngFailed", "Couldn't save %1").replace("%1", root.pngName), "error")
      }
    }
  }
  function pngGrabbed(ok) {
    pngShot.active = false
    console.log("PNG " + (ok ? "ok " : "fail ") + root.pngPath)
    if (ok) root.say(strings.t("pet.pngSaved", "PNG saved in %1").replace("%1", root.folderOf(root.pngPath)), "ok", true)
    else root.say(strings.t("pet.pngFailed", "Couldn't save %1").replace("%1", root.pngName), "error")
  }

  Item {
    width: 1
    height: 1
    clip: true
    Loader {
      id: pngShot
      active: false
      sourceComponent: Item {
        id: shot
        width: 512
        height: 512
        BlobAvatar {
          anchors.centerIn: parent
          size: 512
          look: root.look
          themePalette: root.themePalette
          foreground: root.foreground
          interactive: false
          animated: false
          lively: false
          seasonal: false
          showMarks: false
          particles: false
          reactionLevel: "static"
        }
        Timer {
          running: true
          interval: 350
          // False (and no callback) when the editor was hidden meanwhile.
          onTriggered: if (!shot.grabToImage(function(r) { root.pngGrabbed(r.saveToFile(root.pngPath)) }, Qt.size(1024, 1024)))
            root.pngGrabbed(false)
        }
      }
    }
  }

  // ------------------------------------------------------------ keyboard
  function setTab(i, byKey) {
    i = (i + 5) % 5
    root.tryOn = null
    root.tab = i
    if (byKey) Qt.callLater(function() { root.pointRequested("pet.tab", i) })
  }

  function cells(kind, count, from) {
    var out = []
    for (var i = from || 0; i < count; i++) out.push({ kind: kind, index: i })
    return out
  }
  function chunks(kind, count, size) {
    var rows = []
    for (var i = 0; i < count; i += size) {
      var row = []
      for (var j = i; j < Math.min(count, i + size); j++) row.push({ kind: kind, index: j })
      rows.push(row)
    }
    return rows
  }

  readonly property var keyRows: {
    var rows = []
    rows.push([{ kind: "pet.name", index: 0 }, { kind: "pet.random", index: 0 }])
    rows.push(root.cells("pet.tab", 5))
    if (root.tab === 0) {
      rows = rows.concat(root.chunks("pet.body", root.optionsOf("body").length, 5))
      rows.push(root.cells("pet.style", 2))
      rows.push(root.cells("pet.barSize", 3))
      rows.push(root.cells("pet.panelSize", 3))
    } else if (root.tab === 1) {
      rows = rows.concat(root.chunks("pet.eyes", root.optionsOf("eyes").length, 5))
      rows.push(root.cells("pet.eyeSize", 5))
      rows = rows.concat(root.chunks("pet.mouth", root.optionsOf("mouth").length, 5))
      rows.push(root.cells("pet.mouthSize", 5))
      rows.push([{ kind: "pet.cheeks", index: 0 }])
      rows.push(root.cells("pet.personality", 3))
      rows.push(root.cells("pet.react", root.previewReactions.length))
    } else if (root.tab === 2) {
      rows = rows.concat(root.chunks("pet.extra", root.optionsOf("extra").length, 5))
      rows = rows.concat(root.chunks("pet.accessory", root.optionsOf("accessory").length, 5))
    } else if (root.tab === 3) {
      rows = rows.concat(root.chunks("pet.swatch", root.swatches.length + 1, 8))
      rows = rows.concat(root.chunks("pet.recent", root.recentColors.length, 8))
      if (root.pickerOpen) rows.push([{ kind: "pet.hex", index: 0 }])
    } else {
      rows.push(root.cells("pet.action", 3))
      rows.push(root.cells("pet.file", 3))
      rows = rows.concat(root.chunks("pet.card", root.saved.length, 5))
    }
    rows.push(root.cells("pet.foot", 3))
    return rows
  }

  readonly property var chipKeys: ["body", "eyes", "mouth", "extra", "accessory"]

  // The cursor landed somewhere (keyboard): try on what's under it.
  function syncTryOn(target) {
    root.tryOn = null
    if (!target || String(target.kind).indexOf("pet.") !== 0) return
    var k = target.kind.slice(4)
    if (root.chipKeys.indexOf(k) >= 0) {
      var opts = root.optionsOf(k)
      if (target.index < opts.length) root.tryOn = { key: k, val: opts[target.index] }
    } else if (root.lookScales.indexOf(k) >= 0 && target.index < root.scaleSteps.length) {
      root.tryOn = { key: k, val: root.scaleSteps[target.index] }
    } else if (k === "swatch" && target.index < root.swatches.length) {
      root.tryOn = { key: "color", val: root.swatches[target.index] }
    } else if (k === "recent" && target.index < root.recentColors.length) {
      root.tryOn = { key: "color", val: root.recentColors[target.index] }
    }
  }

  function hoverOption(kind, index, key, val) {
    leaveTimer.stop()
    root.pointRequested(kind, index)
    root.tryOn = { key: key, val: val }
  }
  function leaveOption() { leaveTimer.restart() }
  Timer { id: leaveTimer; interval: 80; onTriggered: root.tryOn = null }

  function focusName() { nameField.forceActiveFocus(); nameField.selectAll() }

  function activate(target) {
    if (!target) return
    var k = String(target.kind).slice(4), i = target.index
    if (k === "name") root.focusName()
    else if (k === "random") root.randomize()
    else if (k === "barSize" || k === "panelSize") root.editSize(k, ["s", "m", "l"][i])
    else if (root.lookScales.indexOf(k) >= 0) root.commit(k, root.scaleSteps[i])
    else if (k === "tab") root.setTab(i, true)
    else if (root.chipKeys.indexOf(k) >= 0) root.commit(k, root.optionsOf(k)[i])
    else if (k === "style") root.commit("style", ["solid", "outline"][i])
    else if (k === "cheeks") root.commit("cheeks", root.value("cheeks") !== true)
    else if (k === "personality") root.setReactions(["lively", "calm", "still"][i])
    else if (k === "react") root.previewReaction(root.previewReactions[i])
    else if (k === "swatch") {
      if (i < root.swatches.length) root.commit("color", root.swatches[i])
      else root.pickerOpen = !root.pickerOpen
    }
    else if (k === "recent") root.commit("color", root.recentColors[i])
    else if (k === "hex") { if (root.hexFieldItem) { root.hexFieldItem.forceActiveFocus(); root.hexFieldItem.selectAll() } }
    else if (k === "action") [root.savePet, root.copyCode, function() { pasteProc.running = true }][i]()
    else if (k === "file") [root.exportBackup, root.importBackup, root.exportPng][i]()
    else if (k === "card") root.wearCard(i)
    else if (k === "foot") [root.undo, root.resetLook, root.finish][i]()
  }

  function finish() {
    root.editName(nameField.text.trim())
    root.tryOn = null
    root.done()
  }

  // Esc: close the color picker first. Returns whether it did something.
  function back() {
    if (root.tab === 3 && root.pickerOpen) {
      root.pickerOpen = false
      root.draftColor = ""
      return true
    }
    return false
  }

  // Shortcuts while no text field has focus. Returns whether it was used.
  function textKey(t, modifiers) {
    var ctrl = modifiers & Qt.ControlModifier
    if (t === "\u001a" || (ctrl && (t === "z" || t === "Z"))) { root.undo(); return true }
    if (ctrl) return false
    if (t >= "1" && t <= "5") { root.setTab(Number(t) - 1, true); return true }
    if (t === "[") { root.setTab(root.tab - 1, true); return true }
    if (t === "]") { root.setTab(root.tab + 1, true); return true }
    if (t === "r") { root.randomize(); return true }
    if (t === "u") { root.undo(); return true }
    if (t === "s") { root.savePet(); return true }
    if (t === "c") { root.copyCode(); return true }
    if (t === "v") { pasteProc.running = true; return true }
    if (t === "e") { root.focusName(); return true }
    if (t === "\b") { root.deleteKey(); return true }
    return true // swallow the panel's own letter shortcuts while editing
  }

  function deleteKey() {
    if (root.keyTarget && root.keyTarget.kind === "pet.card") root.forgetCard(root.keyTarget.index)
  }

  // ------------------------------------------------------------ layout sizes
  readonly property real gap: Style.space(8)
  readonly property real chip5: Math.floor((root.width - 4 * root.gap) / 5)
  readonly property real sectionGap: Style.space(10)
  readonly property real headGap: Style.space(6)
  readonly property real headH: headProbe.implicitHeight
  readonly property real buttonH: buttonProbe.implicitHeight
  readonly property real rowH: Math.max(Style.spacing.controlHeight, toggleProbe.implicitHeight)
  readonly property real swatchSize: Style.space(28)
  readonly property real swatchGap: Math.max(Style.space(4), Math.floor((root.width - 8 * root.swatchSize) / 7))
  readonly property int swatchRows: Math.ceil((root.swatches.length + 1) / 8)
  // Trait chips wrap five to a row; the height of one trait's chips.
  function chipsHeight(key) {
    var rows = Math.ceil(root.optionsOf(key).length / 5)
    return rows * root.chip5 + (rows - 1) * root.gap
  }

  // Shape, Extras and Color (picker closed) fit this height, so switching
  // between them never moves the footer. Face (eyes and mouth with nine
  // options and a size each, then the personality) and Saved run taller
  // rather than leave the other pages mostly empty.
  readonly property real fixedPageHeight: {
    var shape = root.headH + root.headGap + root.chipsHeight("body") + root.sectionGap + root.headH + root.headGap + root.buttonH
      + root.sectionGap + 2 * root.buttonH + root.headGap
    var extras = root.headH + root.headGap + root.chipsHeight("extra") + root.sectionGap + root.headH + root.headGap + root.chipsHeight("accessory")
    var color = root.headH + root.headGap + root.swatchRows * root.swatchSize + (root.swatchRows - 1) * Style.space(8)
    // The Recent row (when there are colors) sits under the swatches.
    if (root.recentColors.length > 0) color += Style.space(8) + root.headH + Style.space(8) + root.swatchSize
    return Math.ceil(Math.max(shape, extras, color))
  }
  readonly property real pageHeight: {
    var item = pageLoaders.itemAt(root.tab)
    var h = item && item.item ? item.item.implicitHeight : 0
    return Math.max(root.fixedPageHeight, Math.ceil(h))
  }

  // Invisible probes for the sizes above.
  SectionHead { id: headProbe; visible: false; title: "X" }
  Button { id: buttonProbe; visible: false; text: "X"; fontSize: Style.font.bodySmall; bordered: true }
  ToggleSwitch { id: toggleProbe; visible: false; interactive: false }

  // ------------------------------------------------------------ view
  Column {
    id: col
    width: parent.width
    spacing: Style.space(10)

    // ---------- Header: stage · name · status ----------
    Item {
      width: parent.width
      height: Math.max(stage.height, headerCol.implicitHeight)

      Rectangle {
        id: stage
        width: Style.space(88)
        height: Style.space(88)
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

        BlobAvatar {
          id: preview
          anchors.centerIn: parent
          anchors.verticalCenterOffset: -Style.space(2)
          size: Style.space(70)
          look: root.previewLook
          mood: root.stageMood
          themePalette: root.themePalette
          foreground: root.foreground
          trackGlobalCursor: root.visible
          reactions: root.petReactions
        }

        PanelActionButton {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: Style.space(2)
          iconText: "󰒝"
          tooltipText: strings.t("pet.randomShortcut", "Random (r)")
          foreground: root.foreground
          fontFamily: root.fontFamily
          hasCursor: root.isKey("pet.random")
          onHovered: function(h) { if (h) root.pointRequested("pet.random", 0) }
          onClicked: root.randomize()
        }
      }

      Column {
        id: headerCol
        anchors.left: stage.right
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.verticalCenter: stage.verticalCenter
        spacing: Style.space(6)

        TextField {
          id: nameField
          width: parent.width
          text: root.petName
          placeholderText: strings.t("pet.name.placeholder", "Name your pet")
          maximumLength: 24
          foreground: root.foreground
          hasCursor: root.isKey("pet.name")
          onHoveredChanged: if (hovered) root.pointRequested("pet.name", 0)
          onEditingFinished: root.editName(text.trim())
        }

        Text {
          width: parent.width
          height: Style.font.caption + Style.space(4)
          textFormat: Text.PlainText
          elide: Text.ElideMiddle
          text: root.status !== "" ? (root.statusKind === "ok" ? "✓ " + root.status : root.status)
            : (root.keyTarget ? strings.t("pet.hint", "1-5 tabs · r random · u undo · Esc done") : "")
          color: root.status === "" ? root.dim : (root.statusKind === "ok" ? root.accent : root.urgent)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    PanelSeparator { foreground: root.foreground }

    // ---------- Tabs ----------
    Row {
      id: tabRow
      width: parent.width
      spacing: Style.space(4)
      readonly property var labels: [
        strings.t("pet.tab.shape", "Shape"), strings.t("pet.tab.face", "Face"), strings.t("pet.tab.extras", "Extras"),
        strings.t("pet.tab.color", "Color"), strings.t("pet.tab.saved", "Saved")
      ]

      Repeater {
        model: 5
        CursorSurface {
          id: seg
          required property int index
          readonly property bool active: root.tab === index
          width: (tabRow.width - 4 * tabRow.spacing) / 5
          height: Style.space(30)
          foreground: root.foreground
          hasCursor: root.isKey("pet.tab", index)
          current: false
          onHasCursorChanged: if (hasCursor) root.revealRequested(seg)

          Row {
            anchors.centerIn: parent
            spacing: Style.space(4)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: tabRow.labels[seg.index]
              color: seg.active ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: seg.active
            }
            Text {
              id: badge
              visible: seg.index === 4 && root.saved.length > 0
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: String(root.saved.length)
              color: seg.active ? root.accent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              scale: seg.index === 4 ? root.badgeScale : 1
            }
          }

          Rectangle {
            visible: seg.active
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - Style.space(12)
            height: 2
            radius: 1
            color: root.accent
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.pointRequested("pet.tab", seg.index)
            onClicked: root.setTab(seg.index, false)
          }
        }
      }

      WheelHandler {
        acceptedDevices: PointerDevice.Mouse
        onWheel: function(event) { root.setTab(root.tab + (event.angleDelta.y < 0 ? 1 : -1), false) }
      }
    }

    // ---------- Page ----------
    Item {
      width: parent.width
      height: root.pageHeight

      Repeater {
        id: pageLoaders
        model: [shapePage, facePage, extrasPage, colorPage, savedPage]
        Loader {
          required property var modelData
          required property int index
          width: parent.width
          active: root.visited[index]
          visible: root.tab === index
          sourceComponent: modelData
        }
      }
    }

    PanelSeparator { foreground: root.foreground }

    // ---------- Footer ----------
    Item {
      width: parent.width
      height: doneButton.implicitHeight

      Row {
        spacing: Style.space(6)
        Button {
          id: undoButton
          text: strings.t("pet.undo", "Undo")
          iconText: "󰕌"
          fontSize: Style.font.bodySmall
          fontFamily: root.fontFamily
          foreground: root.foreground
          opacity: root.lastSnapshot ? 1 : 0.4
          tooltipText: "u"
          hasCursor: root.isKey("pet.foot", 0)
          onHasCursorChanged: if (hasCursor) root.revealRequested(undoButton)
          onHovered: function(h) { if (h) root.pointRequested("pet.foot", 0) }
          onClicked: root.undo()
        }
        Button {
          text: strings.t("pet.reset", "Reset")
          fontSize: Style.font.bodySmall
          fontFamily: root.fontFamily
          foreground: root.foreground
          hasCursor: root.isKey("pet.foot", 1)
          onHovered: function(h) { if (h) root.pointRequested("pet.foot", 1) }
          onClicked: root.resetLook()
        }
      }

      Button {
        id: doneButton
        anchors.right: parent.right
        text: strings.t("pet.done", "Done")
        selected: true
        bordered: true
        fontSize: Style.font.bodySmall
        fontFamily: root.fontFamily
        foreground: root.foreground
        hasCursor: root.isKey("pet.foot", 2)
        onHasCursorChanged: if (hasCursor) root.revealRequested(doneButton)
        onHovered: function(h) { if (h) root.pointRequested("pet.foot", 2) }
        onClicked: root.finish()
      }
    }
  }

  property real badgeScale: 1
  SequentialAnimation {
    id: badgeBump
    NumberAnimation { target: root; property: "badgeScale"; to: 1.15; duration: 75 }
    NumberAnimation { target: root; property: "badgeScale"; to: 1; duration: 75 }
  }

  // ------------------------------------------------------------ pages
  Component {
    id: shapePage
    Column {
      spacing: root.sectionGap
      TraitSection { key: "body" }
      Column {
        width: parent.width
        spacing: root.headGap
        SectionHead { title: strings.t("pet.trait.style", "STYLE"); value: root.optionName("style", root.value("style")) }
        ButtonGroup {
          spacing: Style.space(6)
          focusable: false
          fontSize: Style.font.bodySmall
          fontFamily: root.fontFamily
          foreground: root.foreground
          value: root.value("style")
          options: [
            { value: "solid", label: root.optionName("style", "solid") },
            { value: "outline", label: root.optionName("style", "outline") }
          ]
          cursorIndex: root.keyTarget && root.keyTarget.kind === "pet.style" ? root.keyTarget.index : -1
          onChanged: function(v) { root.commit("style", v) }
          onHovered: function(i, h) { if (h) root.pointRequested("pet.style", i) }
        }
      }
      Column {
        width: parent.width
        spacing: root.headGap
        SizeRow { key: "barSize"; label: strings.t("pet.size.bar", "Size in the bar") }
        SizeRow { key: "panelSize"; label: strings.t("pet.size.panel", "Size in the panel") }
      }
    }
  }

  Component {
    id: facePage
    Column {
      spacing: root.sectionGap
      Column {
        width: parent.width
        spacing: root.headGap
        TraitSection { key: "eyes" }
        SizeRow { key: "eyeSize"; label: strings.t("pet.size.eyes", "Eye size") }
      }
      Column {
        width: parent.width
        spacing: root.headGap
        TraitSection { key: "mouth" }
        SizeRow { key: "mouthSize"; label: strings.t("pet.size.mouth", "Mouth size") }
      }

      CursorSurface {
        id: cheeksRow
        width: parent.width
        height: root.rowH
        foreground: root.foreground
        hasCursor: root.isKey("pet.cheeks")
        onHasCursorChanged: if (hasCursor) root.revealRequested(cheeksRow)
        // Flush left like the size rows above it and the section heads.
        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: strings.t("pet.cheeksToggle", "Blush cheeks")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        ToggleSwitch {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          interactive: false
          checked: root.value("cheeks") === true
          foreground: root.foreground
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.pointRequested("pet.cheeks", 0)
          onClicked: root.commit("cheeks", root.value("cheeks") !== true)
        }
      }

      Column {
        width: parent.width
        spacing: root.headGap
        SectionHead {
          title: strings.t("pet.personality", "PERSONALITY")
          value: strings.t("pet.personality." + root.petReactions, ({ lively: "Lively", calm: "Calm", still: "Still" })[root.petReactions])
        }
        // Three cards instead of a button group: the chosen one is filled with
        // the accent, outlined and checked, so the selection reads at a glance.
        Row {
          id: personalityRow
          width: parent.width
          spacing: Style.space(6)
          // Every card gets room for the label plus two lines of hint, so the
          // three always line up whatever the language.
          readonly property real cardHeight: labelMetrics.height + 2 * hintMetrics.height + Style.space(2) + Style.space(16)
          FontMetrics { id: labelMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          FontMetrics { id: hintMetrics; font.family: root.fontFamily; font.pixelSize: Style.font.caption - 1 }
          Repeater {
            model: [
              { value: "lively", glyph: "󱐋", label: strings.t("pet.personality.lively", "Lively"), hint: strings.t("pet.personality.livelyShort", "Reacts to everything"), tooltip: strings.t("pet.personality.livelyTip", "Reacts to everything, with little fidgets") },
              { value: "calm", glyph: "󰖔", label: strings.t("pet.personality.calm", "Calm"), hint: strings.t("pet.personality.calmShort", "No idle fidgets"), tooltip: strings.t("pet.personality.calmTip", "Reacts to you, no idle fidgets") },
              { value: "still", glyph: "󰏤", label: strings.t("pet.personality.still", "Still"), hint: strings.t("pet.personality.stillShort", "Poses only"), tooltip: strings.t("pet.personality.stillTip", "Poses only, no animated reactions") }
            ]
            Rectangle {
              id: card
              required property var modelData
              required property int index
              readonly property bool chosen: root.petReactions === modelData.value
              readonly property bool cursor: root.isKey("pet.personality", index)
              width: (personalityRow.width - 2 * personalityRow.spacing) / 3
              height: personalityRow.cardHeight
              radius: Style.cornerRadius
              color: chosen
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.2)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, (cardMouse.containsMouse || cursor) ? 0.08 : 0.03)
              border.width: chosen ? 2 : 1
              border.color: chosen ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, cursor ? 0.45 : 0.15)
              Behavior on color { ColorAnimation { duration: Style.duration(120) } }

              Text {
                visible: card.chosen
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Style.space(5)
                textFormat: Text.PlainText
                text: "󰄬"
                color: root.accent
                font.pixelSize: Style.font.caption
              }

              Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(2)
                Text {
                  textFormat: Text.PlainText
                  text: card.modelData.glyph + "  " + card.modelData.label
                  color: card.chosen ? root.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: card.chosen
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: card.modelData.hint
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.pointRequested("pet.personality", card.index)
                onClicked: root.setReactions(card.modelData.value)
              }

              PanelToolTip {
                visible: cardMouse.containsMouse
                text: card.modelData.tooltip
              }
            }
          }
        }
        Row {
          id: reactRow
          width: parent.width
          spacing: Style.space(4)
          Text {
            id: tryLabel
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth + Style.space(4)
            textFormat: Text.PlainText
            text: strings.t("pet.try", "Try")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Repeater {
            model: root.previewReactions
            Button {
              id: reactButton
              required property string modelData
              required property int index
              width: (reactRow.width - tryLabel.width - root.previewReactions.length * reactRow.spacing) / root.previewReactions.length
              horizontalPadding: Style.space(4)
              bordered: true
              text: strings.t("pet.react." + modelData, root.reactionLabels[modelData])
              fontSize: Style.font.caption
              fontFamily: root.fontFamily
              foreground: root.foreground
              hasCursor: root.isKey("pet.react", index)
              onHasCursorChanged: if (hasCursor) root.revealRequested(reactButton)
              onHovered: function(h) { if (h) root.pointRequested("pet.react", reactButton.index) }
              onClicked: root.previewReaction(modelData)
            }
          }
        }
      }
    }
  }

  Component {
    id: extrasPage
    Column {
      spacing: root.sectionGap
      TraitSection { key: "extra" }
      TraitSection { key: "accessory" }
    }
  }

  Component {
    id: colorPage
    Column {
      spacing: Style.space(8)
      SectionHead {
        title: strings.t("pet.themeColors", "THEME COLORS")
        trying: root.draftColor !== "" || (!!root.tryOn && root.tryOn.key === "color")
        value: root.draftColor !== "" ? "→ " + root.draftColor
          : (root.tryOn && root.tryOn.key === "color" ? "→ " + root.colorName(root.tryOn.val) : root.colorName(root.value("color")))
      }
      Grid {
        columns: 8
        columnSpacing: root.swatchGap
        rowSpacing: Style.space(8)
        Repeater {
          model: root.swatches.length + 1
          Swatch {
            required property int index
            slot: index
          }
        }
      }
      SectionHead {
        visible: root.recentColors.length > 0
        height: visible ? implicitHeight : 0
        title: strings.t("pet.recentColors", "RECENT")
      }
      Grid {
        visible: root.recentColors.length > 0
        height: visible ? implicitHeight : 0
        columns: 8
        columnSpacing: root.swatchGap
        Repeater {
          model: root.recentColors.length
          Swatch {
            required property int index
            slot: index
            recent: true
          }
        }
      }
      Loader {
        active: root.pickerOpen
        visible: active
        width: parent.width
        sourceComponent: Column {
          width: parent ? parent.width : 0
          spacing: Style.space(8)
          ColorPicker {
            width: parent.width
            height: Style.space(104)
            color: root.currentColor
            onPicking: function(hex) { root.draftColor = hex }
            onPicked: function(hex) { root.draftColor = ""; root.commit("color", hex) }
          }
          Row {
            spacing: Style.space(8)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(28)
              height: Style.space(28)
              radius: Style.cornerRadius
              color: root.draftColor !== "" ? root.draftColor : root.currentColor
              border.width: 1
              border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.2)
            }
            TextField {
              id: hexField
              property bool invalid: false
              width: Style.space(120)
              placeholderText: "#rrggbb"
              maximumLength: 7
              foreground: root.foreground
              hasCursor: root.isKey("pet.hex")
              text: root.draftColor !== "" ? root.draftColor : root.hexOf(root.currentColor)
              Component.onCompleted: root.hexFieldItem = hexField
              Component.onDestruction: if (root.hexFieldItem === hexField) root.hexFieldItem = null
              onHasCursorChanged: if (hasCursor) root.revealRequested(hexField)
              onHoveredChanged: if (hovered) root.pointRequested("pet.hex", 0)
              onTextEdited: invalid = false
              onEditingFinished: {
                var v = text.trim()
                if (v !== "" && v[0] !== "#") v = "#" + v
                if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                  invalid = false
                  if (v.toLowerCase() !== root.hexOf(root.currentColor)) root.commit("color", v.toLowerCase())
                } else invalid = true
              }
              Rectangle {
                anchors.fill: parent
                visible: hexField.invalid
                color: "transparent"
                radius: Style.cornerRadius
                border.width: 1.5
                border.color: root.urgent
              }
            }
            Text {
              visible: hexField.invalid
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: strings.t("pet.color.invalid", "Use #rrggbb")
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  Component {
    id: savedPage
    Column {
      id: savedCol
      spacing: Style.space(8)
      readonly property real buttonW: (width - 2 * Style.space(6)) / 3

      Row {
        spacing: Style.space(6)
        Repeater {
          model: [
            { icon: "󰐕", label: strings.t("pet.saveCurrent", "Save this pet"), tip: root.savedFull ? strings.t("pet.full", "Up to 24 pets") : strings.t("pet.saveShortcut", "Save this pet (s)") },
            { icon: "󰆏", label: strings.t("pet.copyCode", "Copy code"), tip: strings.t("pet.copyShortcut", "Copy code (c)") },
            { icon: "󰆒", label: strings.t("pet.pasteCode", "Paste code"), tip: strings.t("pet.pasteShortcut", "Paste code (v)") }
          ]
          ActionButton { kind: "pet.action" }
        }
      }
      Row {
        spacing: Style.space(6)
        Repeater {
          model: [
            { icon: "󰁯", label: strings.t("pet.exportAll", "Back up all"), tip: strings.t("pet.exportAllTip", "Save this pet, your saved pets, size and personality to agents-pet-backup.json") },
            { icon: "󰦛", label: strings.t("pet.importAll", "Restore"), tip: strings.t("pet.importAllTip", "Load agents-pet-backup.json from Documents or your home folder") },
            { icon: "󰋩", label: strings.t("pet.exportPng", "Save PNG"), tip: strings.t("pet.exportPngTip", "Save this pet as a transparent image in Pictures") }
          ]
          ActionButton { kind: "pet.file" }
        }
      }

      Text {
        visible: root.saved.length === 0
        width: parent.width
        topPadding: Style.space(6)
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: strings.t("pet.savedEmpty", "Saved pets show up here. Click one to wear it.")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Grid {
        visible: root.saved.length > 0
        columns: 5
        columnSpacing: root.gap
        rowSpacing: root.gap
        Repeater {
          model: root.saved
          SavedCard {}
        }
      }
    }
  }

  // ------------------------------------------------------------ parts
  component SectionHead: Item {
    id: head
    property string title: ""
    property string value: ""
    property bool trying: false
    width: parent ? parent.width : 100
    implicitHeight: headTitle.implicitHeight
    height: implicitHeight

    PanelSectionHeader {
      id: headTitle
      text: head.title
      foreground: root.foreground
      fontFamily: root.fontFamily
    }
    Text {
      anchors.right: parent.right
      anchors.baseline: headTitle.baseline
      width: Math.min(implicitWidth, head.width - headTitle.implicitWidth - Style.space(8))
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: head.value
      color: head.trying ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: head.trying
    }
  }

  // A label and a row of sizes: S / M / L for the pet in the bar or the panel
  // (key: barSize | panelSize), or XS to XL for the eyes and the mouth (key:
  // eyeSize | mouthSize, part of the look, so hovering one tries it on).
  component SizeRow: Item {
    id: sizeRow
    property string key: ""
    property string label: ""
    readonly property bool scale: root.lookScales.indexOf(key) >= 0
    readonly property bool trying: !!root.tryOn && root.tryOn.key === sizeRow.key
    width: parent ? parent.width : 100
    height: root.buttonH

    Text {
      anchors.left: parent.left
      anchors.right: sizeGroup.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: sizeRow.label
      color: sizeRow.trying ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    ButtonGroup {
      id: sizeGroup
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      focusable: false
      fontSize: Style.font.bodySmall
      fontFamily: root.fontFamily
      foreground: root.foreground
      value: sizeRow.scale ? String(root.scaleStep(root.value(sizeRow.key))) : root[sizeRow.key]
      options: sizeRow.scale ? root.scaleOptions : root.sizeOptions
      cursorIndex: root.keyTarget && root.keyTarget.kind === "pet." + sizeRow.key ? root.keyTarget.index : -1
      onChanged: function(v) {
        if (sizeRow.scale) root.commit(sizeRow.key, Number(v))
        else root.editSize(sizeRow.key, v)
      }
      onHovered: function(i, h) {
        if (!sizeRow.scale) { if (h) root.pointRequested("pet." + sizeRow.key, i) }
        else if (h) root.hoverOption("pet." + sizeRow.key, i, sizeRow.key, root.scaleSteps[i])
        else root.leaveOption()
      }
    }
  }

  // A trait's header and its row of chips.
  component TraitSection: Column {
    id: section
    property string key: ""
    readonly property bool trying: !!root.tryOn && root.tryOn.key === section.key
    width: parent ? parent.width : 100
    spacing: root.headGap

    SectionHead {
      title: strings.t("pet.trait." + section.key, section.key.toUpperCase())
      trying: section.trying
      value: section.trying ? "→ " + root.optionName(section.key, root.tryOn.val) : root.optionName(section.key, root.value(section.key))
    }
    // Wraps when a trait has more options than fit in a row (body: 5 + 4).
    Flow {
      width: parent.width
      spacing: root.gap
      Repeater {
        model: root.optionsOf(section.key)
        PetChip {
          id: chip
          required property var modelData
          required property int index
          size: root.chip5
          look: root.chipLook(section.key, modelData)
          framing: root.chipFrame(section.key, modelData)
          isNone: modelData === "none"
          selected: root.value(section.key) === modelData
          hasCursor: root.isKey("pet." + section.key, index)
          tip: root.optionName(section.key, modelData)
          themePalette: root.themePalette
          foreground: root.foreground
          fontFamily: root.fontFamily
          onHasCursorChanged: if (hasCursor) root.revealRequested(chip)
          onEntered: root.hoverOption("pet." + section.key, index, section.key, modelData)
          onExited: root.leaveOption()
          onClicked: root.commit(section.key, modelData)
        }
      }
    }
  }

  component Swatch: Item {
    id: sw
    property int slot: 0
    // A color from the Recent row instead of the theme's own.
    property bool recent: false
    readonly property string kind: recent ? "pet.recent" : "pet.swatch"
    readonly property bool custom: !recent && slot >= root.swatches.length
    readonly property string choice: custom ? "" : (recent ? root.recentColors[slot] : root.swatches[slot])
    readonly property bool selected: custom ? String(root.value("color")).charAt(0) === "#"
      : (recent ? String(root.value("color")).toLowerCase() === choice : root.value("color") === choice)
    readonly property bool lit: root.isKey(kind, slot)
    width: root.swatchSize
    height: root.swatchSize
    onLitChanged: if (lit) root.revealRequested(sw)

    Rectangle {
      anchors.fill: parent
      anchors.margins: Style.space(3)
      radius: width / 2
      color: sw.custom ? "white" : root.swatchColor(sw.choice)
      gradient: sw.custom ? hueGradient : null
      border.width: 1
      border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
    }
    Gradient {
      id: hueGradient
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "#f38ba8" }
      GradientStop { position: 0.33; color: "#f9e2af" }
      GradientStop { position: 0.66; color: "#a6e3a1" }
      GradientStop { position: 1.0; color: "#89b4fa" }
    }
    Text {
      visible: sw.custom || sw.choice === "theme"
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: sw.custom ? "+" : "T"
      color: Commons.Color.background
      font.family: root.fontFamily
      font.pixelSize: sw.custom ? Style.font.body : Style.font.caption
      font.bold: true
    }
    // Ring: accent when chosen, the cursor's when lit.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: "transparent"
      visible: sw.selected || sw.lit
      border.width: sw.selected ? 2 : 1.5
      border.color: sw.selected ? root.accent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.7)
    }
    MouseArea {
      id: swMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: {
        if (sw.custom) { leaveTimer.stop(); root.pointRequested(sw.kind, sw.slot); root.tryOn = null }
        else root.hoverOption(sw.kind, sw.slot, "color", sw.choice)
      }
      onExited: root.leaveOption()
      onClicked: root.activate({ kind: sw.kind, index: sw.slot })
    }
    PanelToolTip {
      visible: swMouse.containsMouse
      text: sw.custom ? strings.t("pet.color.custom", "Custom…") : (sw.recent ? sw.choice : root.colorName(sw.choice))
      fontFamily: root.fontFamily
    }
  }

  component ActionButton: Button {
    id: act
    required property var modelData
    required property int index
    property string kind: ""
    width: (root.width - 2 * Style.space(6)) / 3
    horizontalPadding: Style.space(6)
    iconText: modelData.icon
    text: modelData.label
    tooltipText: modelData.tip
    bordered: true
    fontSize: Style.font.caption
    iconSize: Style.font.bodySmall
    fontFamily: root.fontFamily
    foreground: root.foreground
    opacity: kind === "pet.action" && index === 0 && root.savedFull ? 0.4 : 1
    hasCursor: root.isKey(kind, index)
    onHasCursorChanged: if (hasCursor) root.revealRequested(act)
    onHovered: function(h) { if (h) root.pointRequested(act.kind, act.index) }
    onClicked: root.activate({ kind: act.kind, index: act.index })
  }

  component SavedCard: CursorSurface {
    id: card
    required property var modelData
    required property int index
    readonly property bool worn: root.isWorn(index)
    width: root.chip5
    height: root.chip5 + Style.space(16)
    foreground: root.foreground
    hasCursor: root.isKey("pet.card", index)
    current: worn
    onHasCursorChanged: if (hasCursor) root.revealRequested(card)

    BlobAvatar {
      anchors.horizontalCenter: parent.horizontalCenter
      y: Style.space(2)
      size: root.chip5 * 0.86
      look: card.modelData.look || ({})
      themePalette: root.themePalette
      foreground: root.foreground
      interactive: false
      animated: false
      lively: false
      seasonal: false
      showMarks: false
      particles: false
      reactionLevel: "static"
    }
    Text {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(3)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(6)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: card.modelData.name || "·"
      color: card.worn ? root.accent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: card.worn
    }
    MouseArea {
      id: cardMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.pointRequested("pet.card", card.index)
      onClicked: root.wearCard(card.index)
    }
    PanelToolTip {
      visible: cardMouse.containsMouse
      text: (card.modelData.name || "") + (card.worn ? " · " + strings.t("pet.wearing", "Wearing") : "")
      fontFamily: root.fontFamily
    }
    // Remove (undoable), on hover or under the keyboard cursor.
    Rectangle {
      visible: card.hasCursor
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(2)
      width: Style.space(16)
      height: Style.space(16)
      radius: width / 2
      color: root.urgent
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: "×"
        color: Commons.Color.background
        font.pixelSize: Style.font.caption
        font.bold: true
      }
      MouseArea {
        id: removeMouse
        anchors.fill: parent
        anchors.margins: -Style.space(2)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.forgetCard(card.index)
      }
      PanelToolTip {
        visible: removeMouse.containsMouse
        text: strings.t("pet.delete", "Remove") + " (x)"
        fontFamily: root.fontFamily
      }
    }
  }
}
