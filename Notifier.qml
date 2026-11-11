// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): src/notify.rs
import QtQuick
import Quickshell
import Quickshell.Io
import "usage/Notify.js" as Notify

// Desktop notices: a limit crossing the threshold (and once more, critical,
// when it is spent)
// and a Codex reset credit about to lapse, as usage/Notify.js decides them.
// Only fresh fetches count (decide() looks at each source's fetch time), so
// re-reading the same records is harmless.
//
// The dedupe state lives in $XDG_STATE_HOME/omarchy/agents-pet/notify-state.json
// and is written, atomically, before anything is shown: a failure anywhere
// (folder, write, notify-send) skips the notice silently, since a missed
// notification beats a repeated one. A restart re-reads the state, so it
// never repeats one either. Readings already on disk when the plugin starts,
// from a source the state has never seen (the first run, a lost state file),
// are recorded without a word: the panel shows them anyway, and an install
// shouldn't open with a burst of toasts.
//
// fired() hands the notices to the panel, which words them and calls send().
// The icon is the pet itself, rendered to
// $XDG_CACHE_HOME/omarchy/agents-pet/kian-icon.png whenever its look changes;
// until that worked, notices go without an icon.
Item {
  id: root
  // A 1px clipped spot in the bar: grabbing the icon needs a live window, and
  // nothing of it shows here.
  width: 1
  height: 1
  clip: true

  property var records: []
  property bool enabled: true
  property int threshold: Notify.DEFAULT_THRESHOLD
  property var look: ({})
  property var themePalette: null
  property color foreground: "white"

  signal fired(var notifications)

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents-pet"
  readonly property string iconDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omarchy/agents-pet"
  readonly property string iconPath: iconDir + "/kian-icon.png"
  property double startedAt: 0
  Component.onCompleted: {
    startedAt = Date.now()
    if (enabled) iconDebounce.restart()
  }

  // ---------------------------------------------------------------- decide

  // The dedupe state (not Item.state, the states machinery).
  property var notifyState: null
  property string stateJson: ""
  property bool loaded: false
  property bool dirMade: false
  property bool saving: false
  property bool again: false
  property var prevState: null
  property var pending: []
  property string writingJson: ""

  onRecordsChanged: if (enabled) settle.restart()
  onEnabledChanged: if (enabled) { settle.restart(); iconDebounce.restart() }

  // Records land one file at a time after a refresh; decide once they have.
  Timer {
    id: settle
    interval: 1500
    onTriggered: root.evaluate()
  }

  function evaluate() {
    if (!enabled || !loaded || !records || records.length === 0) return
    if (saving) { again = true; return }
    var r = Notify.decide(records, threshold, notifyState, Date.now(), startedAt)
    var json = JSON.stringify(r.nextState)
    if (json === stateJson) return
    prevState = notifyState
    notifyState = r.nextState
    pending = r.notifications
    writingJson = json
    saving = true
    if (dirMade) stateFile.setText(json + "\n")
    else mkdirProcess.running = true
  }

  function finishSave(ok) {
    saving = false
    var list = pending
    pending = []
    if (ok) {
      stateJson = writingJson
      if (list.length > 0) root.fired(list)
    } else {
      // Not on disk, so not shown: the next fresh fetch decides again.
      notifyState = prevState
    }
    if (again) { again = false; settle.restart() }
  }

  Process {
    id: mkdirProcess
    running: false
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.finishSave(false); return }
      root.dirMade = true
      stateFile.setText(root.writingJson + "\n")
    }
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/notify-state.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.loaded) return
      root.notifyState = Notify.parseState(text())
      root.stateJson = root.notifyState ? JSON.stringify(root.notifyState) : ""
      root.dirMade = true
      root.loaded = true
      settle.restart()
    }
    onLoadFailed: {
      if (root.loaded) return
      root.loaded = true
      settle.restart()
    }
    onSaved: if (root.saving) root.finishSave(true)
    onSaveFailed: if (root.saving) root.finishSave(false)
  }

  // --------------------------------------------------------------- deliver

  property var outbox: []

  function send(urgency, title, body) {
    if (!enabled) return
    outbox = outbox.concat([Notify.sendArgs(urgency, title, body, iconReady ? iconPath : "")])
    sendNext()
  }

  function sendNext() {
    if (sendProcess.running || outbox.length === 0) return
    sendProcess.command = outbox[0]
    outbox = outbox.slice(1)
    sendProcess.running = true
  }

  // argv only, never a shell; one at a time, and a hung notifier is dropped.
  Process {
    id: sendProcess
    running: false
    onRunningChanged: if (running) sendKill.restart(); else sendKill.stop()
    onExited: root.sendNext()
  }

  Timer {
    id: sendKill
    interval: 5000
    onTriggered: sendProcess.running = false
  }

  // ------------------------------------------------------------------ icon

  property bool iconReady: false
  property bool iconDirMade: false
  property string iconKey: ""
  readonly property string lookKey: JSON.stringify(look || {}) + "|" + foreground
    + "|" + JSON.stringify(themePalette ? themePalette.colors : {})
  readonly property string iconTmpPath: iconDir + "/kian-icon.tmp.png"

  onLookKeyChanged: if (enabled) iconDebounce.restart()

  // Editing the pet changes the look many times a second; render once it rests.
  Timer {
    id: iconDebounce
    interval: 3000
    onTriggered: root.renderIcon()
  }

  function renderIcon() {
    if (!enabled || iconShot.active || iconMkdir.running || iconMove.running) return
    if (lookKey === iconKey && iconReady) return
    iconKey = lookKey
    if (iconDirMade) iconShot.active = true
    else iconMkdir.running = true
  }

  function iconGrabbed(ok) {
    iconShot.active = false
    if (ok) iconMove.running = true
    else if (lookKey !== iconKey) iconDebounce.restart()
  }

  Process {
    id: iconMkdir
    running: false
    command: ["mkdir", "-p", root.iconDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.iconDirMade = true
      iconShot.active = true
    }
  }

  // Written beside and moved over, so notify-send never reads half a PNG.
  Process {
    id: iconMove
    running: false
    command: ["mv", "-f", root.iconTmpPath, root.iconPath]
    onExited: function(exitCode) {
      if (exitCode === 0) root.iconReady = true
      if (root.lookKey !== root.iconKey) iconDebounce.restart()
    }
  }

  // The editor's Save PNG, smaller: a still pet loaded only while grabbed.
  Loader {
    id: iconShot
    active: false
    sourceComponent: Item {
      id: shot
      width: 256
      height: 256
      BlobAvatar {
        anchors.centerIn: parent
        size: 256
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
        onTriggered: if (!shot.grabToImage(function(r) { root.iconGrabbed(r.saveToFile(root.iconTmpPath)) }, Qt.size(256, 256)))
          root.iconGrabbed(false)
      }
    }
  }
}
