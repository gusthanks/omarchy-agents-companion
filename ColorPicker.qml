import QtQuick
import qs.Commons
import qs.Commons as Commons

// Saturation/value square plus a vertical hue strip. Emits picking(hex) while
// dragging (for live preview) and picked(hex) on release (to persist).
Item {
  id: root

  property color color: "#ff0000"
  signal picking(string hex)
  signal picked(string hex)

  property real hue: 0
  property real sat: 1
  property real val: 1
  property bool dragging: false

  function syncFromColor() {
    if (root.dragging) return
    var c = root.color
    // Keep the hue when the color is grey (hsvHue is -1 there).
    if (c.hsvHue >= 0) root.hue = c.hsvHue
    root.sat = c.hsvSaturation
    root.val = c.hsvValue
  }
  onColorChanged: syncFromColor()
  Component.onCompleted: syncFromColor()

  function hex() {
    var c = Qt.hsva(root.hue, root.sat, root.val, 1)
    function h2(v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
    return "#" + h2(c.r) + h2(c.g) + h2(c.b)
  }

  readonly property real stripWidth: Style.space(14)
  readonly property real gap: Style.space(6)

  // ---------- Saturation / value square ----------
  Rectangle {
    id: square
    x: 0
    y: 0
    width: root.width - root.stripWidth - root.gap
    height: root.height
    radius: Style.space(4)
    color: Qt.hsva(root.hue, 1, 1, 1)
    clip: true

    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: "#ffffffff" }
        GradientStop { position: 1; color: "#00ffffff" }
      }
    }
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      gradient: Gradient {
        GradientStop { position: 0; color: "#00000000" }
        GradientStop { position: 1; color: "#ff000000" }
      }
    }

    Rectangle {
      width: Style.space(10)
      height: width
      radius: width / 2
      x: root.sat * square.width - width / 2
      y: (1 - root.val) * square.height - height / 2
      color: "transparent"
      border.width: 2
      border.color: root.val > 0.5 ? "#111111" : "#ffffff"
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.CrossCursor
      preventStealing: true
      function update(mouse) {
        root.sat = Math.max(0, Math.min(1, mouse.x / width))
        root.val = Math.max(0, Math.min(1, 1 - mouse.y / height))
        root.picking(root.hex())
      }
      onPressed: function(mouse) { root.dragging = true; update(mouse) }
      onPositionChanged: function(mouse) { if (pressed) update(mouse) }
      onReleased: { root.dragging = false; root.picked(root.hex()) }
    }
  }

  // ---------- Hue strip ----------
  Rectangle {
    id: strip
    x: square.width + root.gap
    y: 0
    width: root.stripWidth
    height: root.height
    radius: Style.space(4)
    gradient: Gradient {
      GradientStop { position: 0.0; color: "#ff0000" }
      GradientStop { position: 0.17; color: "#ffff00" }
      GradientStop { position: 0.33; color: "#00ff00" }
      GradientStop { position: 0.5; color: "#00ffff" }
      GradientStop { position: 0.67; color: "#0000ff" }
      GradientStop { position: 0.83; color: "#ff00ff" }
      GradientStop { position: 1.0; color: "#ff0000" }
    }

    Rectangle {
      x: -2
      width: parent.width + 4
      height: 4
      radius: 2
      y: root.hue * strip.height - height / 2
      color: "transparent"
      border.width: 2
      border.color: Commons.Color.foreground
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      preventStealing: true
      function update(mouse) {
        root.hue = Math.max(0, Math.min(0.999, mouse.y / height))
        root.picking(root.hex())
      }
      onPressed: function(mouse) { root.dragging = true; update(mouse) }
      onPositionChanged: function(mouse) { if (pressed) update(mouse) }
      onReleased: { root.dragging = false; root.picked(root.hex()) }
    }
  }
}
