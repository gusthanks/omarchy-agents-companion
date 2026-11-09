import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Inline pet sculptor: a live preview plus one row of choices per trait.
// Edits apply immediately through lookEdited(); the panel persists them.
Item {
  id: root

  property var look: ({})
  property string petName: ""
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal lookEdited(var look)
  signal nameEdited(string name)
  signal done()

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitHeight: col.implicitHeight
  height: implicitHeight

  readonly property var defaults: ({ body: "blob", eyes: "capsule", mouth: "none", extra: "none", cheeks: true, style: "solid", color: "theme" })

  readonly property var traits: [
    { key: "body", options: ["blob", "orb", "squircle", "drop", "ghost"] },
    { key: "eyes", options: ["capsule", "dot", "googly", "pixel", "sleepy"] },
    { key: "mouth", options: ["none", "smile", "o", "cat", "flat"] },
    { key: "extra", options: ["none", "antenna", "leaf", "ears", "horns"] },
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

        Text {
          textFormat: Text.PlainText
          text: strings.t("pet.name")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 1
          font.bold: true
          font.letterSpacing: 1.1
        }

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

          EditorButton {
            label: "🎲  " + strings.t("pet.random")
            onClicked: root.randomize()
          }
          EditorButton {
            label: strings.t("pet.reset")
            onClicked: { root.lookEdited(root.defaults); preview.triggerHappy() }
          }
          EditorButton {
            label: strings.t("pet.done")
            primary: true
            onClicked: { root.nameEdited(nameField.text.trim()); root.done() }
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

        Text {
          textFormat: Text.PlainText
          text: strings.t("pet.trait." + traitRow.modelData.key)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 1
          font.bold: true
          font.letterSpacing: 1.1
        }

        Flow {
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: traitRow.modelData.options

            Rectangle {
              id: chip
              required property var modelData
              readonly property bool selected: root.value(traitRow.modelData.key) === chip.modelData
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
                look: root.withTrait(traitRow.modelData.key, chip.modelData)
                interactive: false
                animated: chipMouse.containsMouse
              }

              MouseArea {
                id: chipMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setTrait(traitRow.modelData.key, chip.modelData)
              }
            }
          }
        }
      }
    }

    // ---------- Color ----------
    Column {
      width: parent.width
      spacing: Style.space(5)

      Text {
        textFormat: Text.PlainText
        text: strings.t("pet.trait.color")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption - 1
        font.bold: true
        font.letterSpacing: 1.1
      }

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
      }
    }
  }

  component EditorButton: Rectangle {
    id: btn
    property string label: ""
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
  }
}
