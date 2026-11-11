import QtQuick
import Quickshell
import Quickshell.Io
import "usage/Mood.js" as Mood

// What Kian worries about, as usage/Mood.js decides it: a subscription you
// are spending crossing 90% worries him for ten minutes, once per crossing;
// every subscription being close worries him for as long as it lasts; every
// one maxed makes him tired.
//
// Which crossings he already worried about lives in
// $XDG_STATE_HOME/omarchy/agents-pet/mood-state.json, written atomically, so
// a restart doesn't worry him again. A missing or unreadable file starts over
// quietly (whatever is already close counts as worried about).
//
// The ten minutes run on their own timer, so he calms down with the panel
// closed too, when nothing else moves the clock.
Item {
  id: root
  visible: false

  property var records: []
  property var samples: []
  property string moodWindow: "auto"

  readonly property bool worried: result ? result.worried : false
  readonly property bool tired: result ? result.tired : false
  readonly property bool cornered: result ? result.cornered : false
  property var result: null

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/agents-pet"

  property var moodState: null
  property string stateJson: ""
  property bool loaded: false
  property bool dirMade: false
  property string pendingJson: ""

  onRecordsChanged: settle.restart()
  onSamplesChanged: settle.restart()
  onMoodWindowChanged: settle.restart()

  // Records land one file at a time after a refresh; decide once they have.
  Timer {
    id: settle
    interval: 1500
    onTriggered: root.evaluate()
  }

  // The end of the current worry, whatever the panel is doing.
  Timer {
    id: expiry
    repeat: false
    onTriggered: root.evaluate()
  }

  function evaluate() {
    if (!loaded || !records || records.length === 0) return
    var now = Date.now()
    var r = Mood.decide(records, samples, moodState, now, { moodWindow: moodWindow })
    moodState = r.state
    result = r
    expiry.stop()
    if (r.until > now) {
      expiry.interval = Math.max(1000, r.until - now + 1000)
      expiry.start()
    }
    var json = Mood.serialize(r.state)
    if (json === stateJson) return
    // Kept in memory either way; on disk so a restart doesn't worry him again.
    pendingJson = json
    if (dirMade) save()
    else if (!mkdirProcess.running) mkdirProcess.running = true
  }

  function save() {
    stateJson = pendingJson
    stateFile.setText(pendingJson)
  }

  Process {
    id: mkdirProcess
    running: false
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.dirMade = true
      root.save()
    }
  }

  FileView {
    id: stateFile
    path: root.stateDir + "/mood-state.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.loaded) return
      root.moodState = Mood.parseState(text())
      root.stateJson = root.moodState ? Mood.serialize(root.moodState) : ""
      root.dirMade = true
      root.loaded = true
      settle.restart()
    }
    onLoadFailed: {
      if (root.loaded) return
      root.loaded = true
      settle.restart()
    }
    onSaveFailed: root.stateJson = ""
  }
}
