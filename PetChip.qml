import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One option in the pet editor: a still, framed crop of the pet wearing it
// (see BlobAvatar.framing). Visuals come only from `hasCursor` / `selected`:
// mouse hover is reported through entered() so the panel moves its single
// cursor here, never painted from containsMouse.
CursorSurface {
  id: chip

  property var look: ({})
  property string framing: ""
  property bool isNone: false
  property bool selected: false
  property real size: Style.space(62)
  property string tip: ""
  property var themePalette: null
  property color dim: Qt.darker(foreground, 1.55)
  property string fontFamily: Style.font.family
  readonly property bool hovered: chipMouse.containsMouse

  signal clicked()
  signal entered()
  signal exited()

  current: selected
  width: size
  height: size
  clip: true

  BlobAvatar {
    anchors.centerIn: parent
    size: chip.size
    look: chip.look
    framing: chip.framing
    themePalette: chip.themePalette
    foreground: chip.foreground
    interactive: false
    animated: false
    lively: false
    seasonal: false
    showMarks: false
    particles: false
    reactionLevel: "static"
  }

  // A zoomed crop can cover the whole chip, so the state ring is drawn on
  // top of the pet: accent when selected, the cursor border when lit.
  Rectangle {
    anchors.fill: parent
    z: 2
    color: "transparent"
    radius: chip.radius
    border.width: chip.selected ? 2 : (chip.hasCursor ? 1.5 : 0)
    border.color: chip.selected ? chip.accent : Qt.rgba(chip.foreground.r, chip.foreground.g, chip.foreground.b, 0.7)
  }

  Text {
    z: 3
    visible: chip.isNone
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(4)
    textFormat: Text.PlainText
    text: "󰜺"
    color: chip.foreground
    opacity: 0.4
    font.family: chip.fontFamily
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: chip.entered()
    onExited: chip.exited()
    onClicked: chip.clicked()
  }

  PanelToolTip {
    visible: chip.tip !== "" && chipMouse.containsMouse
    text: chip.tip
    fontFamily: chip.fontFamily
  }
}
