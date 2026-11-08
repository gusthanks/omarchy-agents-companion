import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Interactive Brain Selector for Kian: displays the full model name
// and lets the user switch companion model on-demand via a sleek dropdown popup.
Item {
  id: root

  property string modelId: "gemini-3.8-flash-medium"
  property var availableModels: [
    { id: "gemini-3.8-flash-medium", label: "Gemini 3.8 Flash (Medium)" },
    { id: "gemini-3.8-flash-high", label: "Gemini 3.8 Flash (High)" },
    { id: "gemini-4-argon-medium", label: "Gemini 4 Argon (Medium)" },
    { id: "gemini-4-argon-high", label: "Gemini 4 Argon (High)" },
    { id: "claude-sonnet-5-5-medium", label: "Claude Sonnet 5.5 (Medium)" },
    { id: "claude-sonnet-5-5-high", label: "Claude Sonnet 5.5 (High)" },
    { id: "claude-opus-5-5-medium", label: "Claude Opus 5.5 (Medium)" },
    { id: "gpt-oss-120b-medium", label: "GPT-OSS 120B (Medium)" }
  ]

  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real maxWidth: -1

  readonly property real maxTextWidth: root.maxWidth > 0
    ? Math.max(0, root.maxWidth - arrowText.implicitWidth - Style.space(16) - pillRow.spacing)
    : -1

  signal modelSelected(string id, string label)

  function modelLabel(id) {
    if (availableModels && availableModels.length > 0) {
      for (var i = 0; i < availableModels.length; i++) {
        if (availableModels[i].id === id) return availableModels[i].label
      }
    }
    if (!id) return "Gemini 3.8 Flash (Medium)"
    return id.replace(/-/g, " ").replace(/\b\w/g, function(l){ return l.toUpperCase() })
  }

  readonly property string currentLabel: modelLabel(root.modelId)

  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  implicitWidth: root.maxWidth > 0
    ? Math.min(pillRect.implicitWidth, root.maxWidth)
    : pillRect.implicitWidth
  implicitHeight: pillRect.implicitHeight
  width: implicitWidth
  height: implicitHeight
  visible: root.maxWidth < 0 || root.maxWidth >= Style.space(36)

  Rectangle {
    id: pillRect
    implicitWidth: pillRow.implicitWidth + Style.space(12)
    implicitHeight: Style.space(22)
    width: root.width
    height: implicitHeight
    radius: Style.cornerRadius
    clip: true
    color: (pillMouse.containsMouse || popup.opened)
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
    border.width: 1
    border.color: (pillMouse.containsMouse || popup.opened)
      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.40)
      : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

    Behavior on color { ColorAnimation { duration: Style.duration(100) } }
    Behavior on border.color { ColorAnimation { duration: Style.duration(100) } }

    Row {
      id: pillRow
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        id: pillText
        textFormat: Text.PlainText
        text: root.currentLabel
        color: (pillMouse.containsMouse || popup.opened) ? root.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption - 1
        font.bold: true
        elide: Text.ElideRight
        width: root.maxWidth > 0 ? Math.min(implicitWidth, Math.max(0, root.maxTextWidth)) : implicitWidth
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: arrowText
        textFormat: Text.PlainText
        text: popup.opened ? "▴" : "▾"
        color: (pillMouse.containsMouse || popup.opened) ? root.accent : root.dim
        font.pixelSize: Style.font.caption - 2
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggle()
    }
  }

  Popup {
    id: popup
    y: pillRect.height + Style.space(4)
    x: {
      var _ = popup.opened
      var globalX = pillRect.mapToItem(null, 0, 0).x
      var winWidth = (root.Window && root.Window.window) ? root.Window.window.width : 380
      if (globalX + width > winWidth - 12) {
        return Math.max(-globalX + 12, (winWidth - 12) - (globalX + width))
      }
      return 0
    }
    width: Style.space(260)
    implicitHeight: Math.min(Style.space(340), popupCol.implicitHeight + Style.space(16))
    closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
    padding: Style.space(8)

    background: Rectangle {
      color: Commons.Color.popups.background
      border.width: 1
      border.color: Commons.Color.popups.border
      radius: Style.cornerRadius
    }

    contentItem: Column {
      id: popupCol
      spacing: Style.space(6)
      width: parent.width

      // Popup Header
      Item {
        width: parent.width
        implicitHeight: Math.max(headerTitle.implicitHeight, brainCount.implicitHeight)
        height: implicitHeight

        Text {
          id: headerTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "SWITCH BRAIN"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 2
          font.bold: true
          font.letterSpacing: 1.1
        }

        Text {
          id: brainCount
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: (root.availableModels ? root.availableModels.length : 0) + " available"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - 2
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
      }

      // Models list
      ListView {
        id: modelsListView
        width: parent.width
        implicitHeight: Math.min(Style.space(260), contentHeight)
        clip: true
        model: root.availableModels
        spacing: Style.space(3)
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
          required property var modelData
          required property int index

          readonly property bool isSelected: modelData.id === root.modelId
          width: modelsListView.width
          implicitHeight: Style.space(30)
          height: implicitHeight
          radius: Style.cornerRadius - 2
          color: modelItemMouse.containsMouse
            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            : (isSelected ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06) : "transparent")

          Behavior on color { ColorAnimation { duration: Style.duration(80) } }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: isSelected ? "●" : "○"
              color: isSelected ? root.accent : root.dim
              font.pixelSize: Style.font.caption
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(24)
              text: modelData.label
              color: isSelected ? root.accent : (modelItemMouse.containsMouse ? root.foreground : Qt.darker(root.foreground, 1.15))
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: isSelected
              elide: Text.ElideRight
            }
          }

          MouseArea {
            id: modelItemMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.modelId = modelData.id
              root.modelSelected(modelData.id, modelData.label)
              popup.close()
            }
          }
        }
      }
    }
  }
}
