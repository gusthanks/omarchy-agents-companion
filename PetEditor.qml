import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Pet settings: live preview, name, size, one row of choices per trait, color,
// and an inventory of saved pets that can be copied/pasted as a short code.
// Edits apply immediately through signals; the panel persists them.
Item {
  id: root

  property var look: ({})
  property string petName: ""
  property string petSize: "m"
  property var saved: []
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal lookEdited(var look)
  signal nameEdited(string name)
  signal sizeEdited(string size)
  signal saveCurrent()
  signal wear(int index)
  signal forget(int index)
  signal imported(string name, var look)
  signal done()

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitHeight: col.implicitHeight
  height: implicitHeight

  readonly property var defaults: ({ body: "blob", eyes: "capsule", mouth: "none", extra: "none", accessory: "none", cheeks: true, style: "solid", color: "theme" })

  readonly property var traits: [
    { key: "body", options: ["blob", "orb", "squircle", "drop", "ghost"] },
    { key: "eyes", options: ["capsule", "dot", "googly", "pixel", "sleepy"] },
    { key: "mouth", options: ["none", "smile", "o", "cat", "flat"] },
    { key: "extra", options: ["none", "antenna", "leaf", "ears", "horns"] },
    { key: "accessory", options: ["none", "glasses", "hat", "beanie", "bow", "flower"] },
    { key: "style", options: ["solid", "outline"] },
    { key: "cheeks", options: [true, false] }
  ]

  readonly property var swatches: ["theme", "#f38ba8", "#fab387", "#f9e2af", "#a6e3a1", "#94e2d5", "#89b4fa", "#cba6f7", "#e8e8e8"]

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

  function setTrait(key, val) {
    root.lookEdited(root.withTrait(key, val))
    preview.triggerHappy()
  }

  function randomize() {
    var next = {}
    for (var i = 0; i < root.traits.length; i++) {
      var t = root.traits[i]
      next[t.key] = t.options[Math.floor(Math.random() * t.options.length)]
    }
    next.color = root.swatches[Math.floor(Math.random() * root.swatches.length)]
    root.lookEdited(next)
    preview.triggerHappy()
  }

  // Keep only known traits and values, so a pasted code can never inject junk.
  function sanitize(raw) {
    var out = {}
    for (var i = 0; i < root.traits.length; i++) {
      var t = root.traits[i]
      out[t.key] = t.options.indexOf(raw[t.key]) >= 0 ? raw[t.key] : root.defaults[t.key]
    }
    var c = String(raw.color || "")
    out.color = c === "theme" || /^#[0-9a-fA-F]{6}$/.test(c) ? c : "theme"
    return out
  }

  function shareCode() {
    return JSON.stringify({ agentsPet: 1, name: root.petName, look: root.withTrait("color", root.value("color")) })
  }

  property string toast: ""
  Timer { id: toastTimer; interval: 2200; onTriggered: root.toast = "" }
  function say(text) { root.toast = text; toastTimer.restart() }

  function copyCode() {
    Quickshell.execDetached(["wl-copy", "--", root.shareCode()])
    root.say(strings.t("pet.copied"))
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
      root.imported(String(data.name || "").slice(0, 24), root.sanitize(data.look))
      preview.triggerHappy()
      root.say(strings.t("pet.imported"))
    } catch (e) {
      root.say(strings.t("pet.importFailed"))
    }
  }

  Column {
    id: col
    width: parent.width
    spacing: Style.space(10)

    // ---------- Preview + name ----------
    Item {
      width: parent.width
      height: stage.height

      Rectangle {
        id: stage
        width: Style.space(104)
        height: Style.space(104)
        radius: Style.cornerRadius
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

        BlobAvatar {
          id: preview
          anchors.centerIn: parent
          size: Style.space(92)
          look: root.look
          trackGlobalCursor: true
        }
      }

      Column {
        anchors.left: stage.right
        anchors.leftMargin: Style.space(12)
        anchors.right: parent.right
        anchors.verticalCenter: stage.verticalCenter
        spacing: Style.space(8)

        SectionLabel { text: strings.t("pet.name") }

        TextField {
          id: nameField
          width: parent.width
          text: root.petName
          placeholderText: "Kian"
          maximumLength: 24
          onEditingFinished: root.nameEdited(text.trim())
        }

        Row {
          spacing: Style.space(6)
          EditorButton { label: "🎲"; onClicked: root.randomize(); tip: strings.t("pet.random") }
          EditorButton { label: strings.t("pet.reset"); onClicked: { root.lookEdited(root.defaults); preview.triggerHappy() } }
          EditorButton {
            label: strings.t("pet.done")
            primary: true
            onClicked: { root.nameEdited(nameField.text.trim()); root.done() }
          }
        }
      }
    }

    // ---------- Size ----------
    Column {
      width: parent.width
      spacing: Style.space(5)
      SectionLabel { text: strings.t("pet.size") }
      Row {
        spacing: Style.space(6)
        Repeater {
          model: ["s", "m", "l"]
          EditorButton {
            required property string modelData
            label: strings.t("pet.size." + modelData)
            primary: root.petSize === modelData
            onClicked: root.sizeEdited(modelData)
          }
        }
      }
    }

    // ---------- Trait rows ----------
    Repeater {
      model: root.traits

      Column {
        id: traitRow
        required property var modelData
        width: col.width
        spacing: Style.space(5)

        SectionLabel { text: strings.t("pet.trait." + traitRow.modelData.key) }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: traitRow.modelData.options

            PetChip {
              required property var modelData
              selected: root.value(traitRow.modelData.key) === modelData
              look: root.withTrait(traitRow.modelData.key, modelData)
              onClicked: root.setTrait(traitRow.modelData.key, modelData)
            }
          }
        }
      }
    }

    // ---------- Color ----------
    Column {
      width: parent.width
      spacing: Style.space(5)

      SectionLabel { text: strings.t("pet.trait.color") }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.swatches

          Rectangle {
            id: swatch
            required property string modelData
            readonly property bool selected: root.value("color") === modelData
            width: Style.space(26)
            height: Style.space(26)
            radius: width / 2
            color: modelData === "theme" ? root.accent : modelData
            border.width: selected ? 2 : 0
            border.color: root.foreground

            Text {
              visible: swatch.modelData === "theme"
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: "T"
              color: Commons.Color.background
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setTrait("color", swatch.modelData)
            }
          }
        }

        TextField {
          id: hexField
          width: Style.space(96)
          placeholderText: "#rrggbb"
          maximumLength: 7
          text: /^#/.test(root.value("color")) && root.swatches.indexOf(root.value("color")) < 0 ? root.value("color") : ""
          onEditingFinished: {
            var v = text.trim()
            if (v !== "" && v[0] !== "#") v = "#" + v
            if (/^#[0-9a-fA-F]{6}$/.test(v)) root.setTrait("color", v.toLowerCase())
          }
        }
      }
    }

    // ---------- Inventory ----------
    Column {
      width: parent.width
      spacing: Style.space(5)

      SectionLabel { text: strings.t("pet.inventory") }

      Flow {
        width: parent.width
        spacing: Style.space(6)

        Repeater {
          model: root.saved

          PetChip {
            id: savedChip
            required property var modelData
            required property int index
            look: modelData.look || ({})
            tip: modelData.name || ""
            onClicked: { root.wear(index); preview.triggerHappy() }

            Rectangle {
              visible: savedChip.hot
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: -Style.space(4)
              width: Style.space(16)
              height: Style.space(16)
              radius: width / 2
              color: Commons.Color.urgent

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "×"
                color: Commons.Color.background
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.forget(savedChip.index)
              }
            }
          }
        }

        Rectangle {
          width: Style.space(48)
          height: Style.space(48)
          radius: Style.cornerRadius
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, saveMouse.containsMouse ? 0.08 : 0.03)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "+"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          MouseArea {
            id: saveMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.nameEdited(nameField.text.trim()); root.saveCurrent(); root.say(strings.t("pet.saved")) }
          }

          PanelToolTip {
            visible: saveMouse.containsMouse
            text: strings.t("pet.saveCurrent")
          }
        }
      }

      Row {
        spacing: Style.space(6)
        EditorButton { label: strings.t("pet.copyCode"); onClicked: root.copyCode() }
        EditorButton { label: strings.t("pet.pasteCode"); onClicked: pasteProc.running = true }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: root.toast
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  component SectionLabel: Text {
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption - 1
    font.bold: true
    font.letterSpacing: 1.1
  }

  component PetChip: Rectangle {
    id: chip
    property var look: ({})
    property bool selected: false
    property string tip: ""
    readonly property bool hot: chipMouse.containsMouse
    signal clicked()
    width: Style.space(48)
    height: Style.space(48)
    radius: Style.cornerRadius
    color: selected
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, chipMouse.containsMouse ? 0.08 : 0.03)
    border.width: selected ? 1.5 : 0
    border.color: root.accent

    BlobAvatar {
      anchors.centerIn: parent
      size: Style.space(44)
      look: chip.look
      interactive: false
      animated: chipMouse.containsMouse
      lively: false
      seasonal: false
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }

    PanelToolTip {
      visible: chip.tip !== "" && chipMouse.containsMouse
      text: chip.tip
    }
  }

  component EditorButton: Rectangle {
    id: btn
    property string label: ""
    property string tip: ""
    property bool primary: false
    signal clicked()
    width: btnText.implicitWidth + Style.space(16)
    height: btnText.implicitHeight + Style.space(10)
    radius: Style.cornerRadius
    color: primary
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, btnMouse.containsMouse ? 0.3 : 0.2)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, btnMouse.containsMouse ? 0.1 : 0.05)

    Text {
      id: btnText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: btn.label
      color: btn.primary ? root.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: btn.primary
    }

    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }

    PanelToolTip {
      visible: btn.tip !== "" && btnMouse.containsMouse
      text: btn.tip
    }
  }
}
