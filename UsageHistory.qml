import QtQuick
import Quickshell
import Quickshell.Io
import "usage/Priority.js" as Priority

// The local history of fresh limit readings the priority ranking measures the
// recent pace from, in $XDG_STATE_HOME/omarchy/agents-pet/usage-history.json:
// at most 25 hours of {source, window, at, reset, percent}, nothing else. A
// reading is added when a source's fetch time moves on and it isn't a cached
// fallback (Priority.append), and the file is written, atomically, only then.
Item {
  id: root
  visible: false

  property var records: []
  property string dir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/agents-pet"
  property var samples: []

  // Nothing is added before the file has been read, or the first write would
  // drop what was in it.
  property bool ready: false
  property bool dirMade: false

  onRecordsChanged: update()

  function update() {
    if (!ready) return
    var next = Priority.append(samples, records, Date.now())
    if (next.added === 0) return
    samples = next.samples
    if (dirMade) historyFile.setText(Priority.serialize(samples))
    else if (!mkdirProcess.running) mkdirProcess.running = true
  }

  Process {
    id: mkdirProcess
    running: false
    command: ["mkdir", "-p", root.dir]
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.dirMade = true
      historyFile.setText(Priority.serialize(root.samples))
    }
  }

  FileView {
    id: historyFile
    path: root.dir + "/usage-history.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.ready) return
      root.samples = Priority.parse(text())
      root.dirMade = true
      root.ready = true
      root.update()
    }
    onLoadFailed: {
      if (root.ready) return
      root.ready = true
      root.update()
    }
  }
}
