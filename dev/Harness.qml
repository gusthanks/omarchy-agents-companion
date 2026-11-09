import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons as Commons
import "pet" as Pet

// Isolated dev harness. Runs in its own Quickshell instance (see dev/run.sh),
// never inside the live Omarchy shell, so testing and screenshots do not
// reload or restart the user's bar.
//
// MODE (env):
//   preview  interactive floating window to play with the pet and its settings
//   face     the user's current pet, large      -> $OUT (png)
//   sheet    grid of bodies, eyes, accessories, moods, reactions -> $OUT (png)
//   editor   the pet settings panel             -> $OUT (png)
//   gif      scripted demo, one png per frame   -> $OUT/0000.png ... + $OUT/fps
ShellRoot {
  id: shell

  readonly property string mode: Quickshell.env("MODE") || "preview"
  readonly property string out: Quickshell.env("OUT") || ""
  readonly property bool capturing: mode !== "preview"

  Pet.ThemePalette { id: themeColors }

  // The pet to show: $PET_FILE (an agents-pet.json), falling back to a default.
  FileView {
    id: petFile
    path: Quickshell.env("PET_FILE") || ""
    blockLoading: true
    printErrors: false
  }
  readonly property var petConfig: {
    try { var c = JSON.parse(petFile.text()); return c && typeof c === "object" ? c : ({}) } catch (e) { return ({}) }
  }
  readonly property var petLook: petConfig.look || ({ body: "blob", eyes: "capsule" })
  readonly property string petName: petConfig.name || "Kian"

  readonly property color bg: Commons.Color.background
  readonly property color fg: Commons.Color.foreground
  readonly property color dim: Qt.darker(fg, 1.55)

  function save(item, path, scale, done) {
    item.grabToImage(function(r) {
      r.saveToFile(path)
      if (done) done()
    }, Qt.size(item.width * scale, item.height * scale))
  }

  // ------------------------------------------------------------ capture window
  // A background-layer surface: below every window, never tiled, no focus.
  PanelWindow {
    visible: shell.capturing
    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "agents-pet-dev"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; bottom: true }
    implicitWidth: stage.width
    implicitHeight: stage.height
    color: "transparent"

    Rectangle {
      id: stage
      color: shell.bg
      width: loader.item ? loader.item.width : 10
      height: loader.item ? loader.item.height : 10

      Loader {
        id: loader
        sourceComponent: shell.mode === "face" ? faceScene
          : shell.mode === "sheet" ? sheetScene
          : shell.mode === "editor" ? editorScene
          : shell.mode === "gif" ? gifScene : null
      }
    }
  }

  // One-shot captures: let animations settle, grab at 2x, quit.
  Timer {
    running: shell.capturing && shell.mode !== "gif"
    interval: 1600
    onTriggered: shell.save(stage, shell.out, 2, function() { Qt.quit() })
  }

  // ------------------------------------------------------------ scenes
  Component {
    id: faceScene
    Item {
      width: 360
      height: 300
      Pet.BlobAvatar {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -16
        size: 210
        look: shell.petLook
        themePalette: themeColors
        interactive: false
        seasonal: false
        Component.onCompleted: { gazeX = 0.35; gazeY = -0.15 }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        text: shell.petName
        color: shell.fg
        font.family: Commons.Style.font.family
        font.pixelSize: 22
        font.bold: true
      }
    }
  }

  Component {
    id: sheetScene
    Column {
      id: sheet
      padding: 18
      spacing: 10
      readonly property var rows: [
        { label: "body", key: "body", options: ["blob", "orb", "squircle", "drop", "ghost"] },
        { label: "eyes", key: "eyes", options: ["capsule", "dot", "googly", "pixel", "sleepy"] },
        { label: "head", key: "extra", options: ["none", "antenna", "leaf", "ears", "horns"] },
        { label: "accessory", key: "accessory", options: ["glasses", "hat", "beanie", "bow", "flower"] }
      ]
      Repeater {
        model: sheet.rows
        Row {
          id: sheetRow
          required property var modelData
          spacing: 8
          Text { width: 84; anchors.verticalCenter: parent.verticalCenter; text: sheetRow.modelData.label; color: shell.dim; font.family: Commons.Style.font.family; font.pixelSize: 13 }
          Repeater {
            model: sheetRow.modelData.options
            Pet.BlobAvatar {
              required property string modelData
              size: 64
              look: { var l = {}; for (var k in shell.petLook) l[k] = shell.petLook[k]; l[sheetRow.modelData.key] = modelData; return l }
              themePalette: themeColors
              interactive: false; animated: false; lively: false; seasonal: false
            }
          }
        }
      }
      Row {
        spacing: 8
        Text { width: 84; anchors.verticalCenter: parent.verticalCenter; text: "mood"; color: shell.dim; font.family: Commons.Style.font.family; font.pixelSize: 13 }
        Repeater {
          model: ["normal", "worried", "tired", "asleep", "happy"]
          Pet.BlobAvatar {
            required property string modelData
            size: 64
            look: shell.petLook
            themePalette: themeColors
            mood: modelData === "worried" || modelData === "tired" ? modelData : "normal"
            asleep: modelData === "asleep"
            avatarState: modelData === "happy" ? "happy" : "idle"
            interactive: false; animated: false; lively: false; seasonal: false
          }
        }
      }
      // Reactions, frozen at their peak frame (PetClips poseAt), captioned.
      Repeater {
        model: [
          { label: "reactions", names: ["yawn", "wake", "startle", "curious", "dizzy"] },
          { label: "", names: ["wink", "sneeze", "thinking", "oof", "sigh"] }
        ]
        Row {
          id: reactRow
          required property var modelData
          spacing: 8
          Text { width: 84; y: 22; text: reactRow.modelData.label; color: shell.dim; font.family: Commons.Style.font.family; font.pixelSize: 13 }
          Repeater {
            model: reactRow.modelData.names
            Column {
              required property string modelData
              spacing: 0
              Pet.BlobAvatar {
                size: 64
                look: shell.petLook
                themePalette: themeColors
                posePreview: parent.modelData
                interactive: false; animated: false; lively: false; seasonal: false
              }
              Text {
                width: 64
                horizontalAlignment: Text.AlignHCenter
                text: parent.modelData
                color: shell.dim
                font.family: Commons.Style.font.family
                font.pixelSize: 10
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: editorScene
    Rectangle {
      width: 380
      height: editor.implicitHeight + 36
      color: shell.bg
      Pet.PetEditor {
        id: editor
        x: 18; y: 18
        width: 344
        look: shell.petLook
        petName: shell.petName
        petSize: shell.petConfig.size || "m"
        saved: [{ name: shell.petName, look: shell.petLook }, { name: "Mochi", look: { body: "ghost", eyes: "googly", color: "theme:magenta", accessory: "bow" } }, { name: "Byte", look: { body: "squircle", eyes: "pixel", color: "theme:blue", extra: "antenna" } }]
        themePalette: themeColors
      }
    }
  }

  // Scripted demo: a fake cursor wanders, the pet follows it, gets pats,
  // worries about a limit, celebrates when it comes back, and tries on a few
  // looks. Each frame is grabbed after the previous one is written.
  Component {
    id: gifScene
    Rectangle {
      id: scene
      width: 420
      height: 260
      color: shell.bg

      property var look: shell.petLook

      Pet.BlobAvatar {
        id: gifPet
        anchors.centerIn: parent
        size: 150
        look: scene.look
        themePalette: themeColors
        interactive: false
        seasonal: false
        particleHost: scene
        // Clips advance one fixed step per captured frame, however long a
        // frame takes to save; no random fidgets or cursor reactions.
        clock: function() { return scene.frame * scene.frameMs }
        reactions: "calm"
        cursorReactions: false
      }

      Text {
        id: cursor
        text: "➤"
        color: shell.fg
        font.pixelSize: 18
        rotation: -120
        x: 30; y: 30
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 10
        text: scene.caption
        color: shell.dim
        font.family: Commons.Style.font.family
        font.pixelSize: 13
      }
      property string caption: ""

      property int frame: 0
      // Close to the real capture rate (~8-10 fps), so wall-clock animations
      // (wobble, particles) keep about their speed in the GIF.
      readonly property int frameMs: 100
      readonly property int total: 280
      property real startMs: 0

      function moveCursor(t) {
        // a loop around the pet
        cursor.x = scene.width / 2 + Math.cos(t * Math.PI * 2) * 170 - 9
        cursor.y = scene.height / 2 - 12 + Math.sin(t * Math.PI * 2) * 80 - 9
        var p = cursor.mapToItem(null, 9, 9)
        gifPet.lookAt(p.x, p.y)
      }

      // The cursor rushes in from the corner toward the pet.
      function rushCursor(t) {
        cursor.x = 10 + (scene.width / 2 - 95 - 10) * t
        cursor.y = 10 + (scene.height / 2 - 60 - 10) * t
      }

      function step(f) {
        if (f < 40) { scene.caption = "follows your cursor"; cursor.visible = true; moveCursor(f / 40) }
        else if (f === 40) { cursor.visible = false; scene.caption = "pat it"; gifPet.pat() }
        else if (f === 48 || f === 56) gifPet.pat()
        else if (f === 68) { scene.caption = "worried when a limit is close"; gifPet.mood = "worried" }
        else if (f === 84) { scene.caption = "...and a party when it comes back"; gifPet.mood = "normal"; gifPet.celebrate() }
        else if (f === 104) { scene.caption = "thinks while your usage refreshes"; gifPet.play("thinking") }
        else if (f === 126) gifPet.stop("thinking")
        else if (f >= 130 && f <= 133) { scene.caption = "startled by a sudden cursor"; cursor.visible = true; rushCursor((f - 130) / 3)
          if (f === 133) gifPet.play("startle") }
        else if (f === 146) { cursor.visible = false; scene.caption = "too many pats make it dizzy" }
        else if (f >= 148 && f <= 155) gifPet.pat()
        else if (f === 182) { scene.caption = "a wink now and then"; gifPet.play("wink") }
        else if (f === 194) { scene.caption = "yawns and dozes off"; gifPet.play("yawn", { next: "__sleep" }) }
        else if (f === 228) { scene.caption = "a pat wakes it with a stretch"; gifPet.pat() }
        else if (f === 246) { scene.caption = "make it yours"; scene.look = withLook({ accessory: "hat" }) }
        else if (f === 253) scene.look = withLook({ body: "ghost", accessory: "bow", color: "theme:magenta" })
        else if (f === 260) scene.look = withLook({ body: "squircle", eyes: "pixel", extra: "ears", accessory: "none", color: "theme:blue" })
        else if (f === 267) scene.look = withLook({ body: "drop", eyes: "googly", extra: "leaf", color: "theme:yellow" })
        else if (f === 274) { scene.look = shell.petLook; scene.caption = "" }
      }

      function withLook(patch) {
        var l = {}
        for (var k in shell.petLook) l[k] = shell.petLook[k]
        for (var p in patch) l[p] = patch[p]
        return l
      }

      function pad(n) { var s = String(n); while (s.length < 4) s = "0" + s; return s }

      function next() {
        if (scene.frame >= scene.total) {
          // Clips run on the frame clock, so play back at its rate; the
          // capture's own rate is logged to judge wall-clock animations.
          var real = scene.total / ((Date.now() - scene.startMs) / 1000)
          console.log("captured at " + (Math.round(real * 10) / 10) + " fps")
          fpsFile.setText(String(Math.round(10000 / scene.frameMs) / 10) + "\n")
          Qt.callLater(Qt.quit)
          return
        }
        scene.step(scene.frame)
        var f = scene.frame
        scene.frame++
        shell.save(scene, shell.out + "/" + pad(f) + ".png", 1.5, function() { gap.restart() })
      }

      Timer { id: gap; interval: 45; onTriggered: scene.next() }
      Timer { running: true; interval: 1200; onTriggered: { scene.startMs = Date.now(); scene.next() } }

      FileView { id: fpsFile; path: shell.out + "/fps"; printErrors: false }
    }
  }

  // ------------------------------------------------------------ preview
  FloatingWindow {
    visible: !shell.capturing
    title: "Agents Pet (dev)"
    implicitWidth: 420
    implicitHeight: 760
    color: shell.bg

    Flickable {
      anchors.fill: parent
      contentHeight: previewCol.implicitHeight + 36
      clip: true

      Column {
        id: previewCol
        x: 18; y: 18
        width: parent.width - 36
        spacing: 16

        Pet.BlobAvatar {
          anchors.horizontalCenter: parent.horizontalCenter
          size: 140
          look: previewEditor.look
          themePalette: themeColors
          trackGlobalCursor: true
        }

        Pet.PetEditor {
          id: previewEditor
          width: parent.width
          look: shell.petLook
          petName: shell.petName
          themePalette: themeColors
          onLookEdited: function(l) { look = l }
          onNameEdited: function(n) { petName = n }
          onSizeEdited: function(s) { petSize = s }
        }
      }
    }
  }
}
