import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// Flat, parametric pet avatar. Everything is drawn in one Canvas from a small
// "look" object (body, eyes, mouth, extra, cheeks, color, style), so the same
// component renders the hero pet and every preview in the editor.
Item {
  id: root

  property real size: Style.space(42)
  property var look: ({})
  property color accentColor: Commons.Color.accent
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  property string avatarState: "idle" // idle | happy
  // Follow the cursor anywhere on the panel screen.
  property bool trackGlobalCursor: false
  property bool interactive: true
  // Keep the wobble/breathing running (off for static editor swatches).
  property bool animated: true

  signal clicked()

  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  // ------------------------------------------------------------ resolved look
  function opt(name, fallback) {
    var v = root.look ? root.look[name] : undefined
    return v === undefined || v === null || v === "" ? fallback : v
  }

  readonly property string bodyShape: opt("body", "blob")
  readonly property string eyeStyle: opt("eyes", "capsule")
  readonly property string mouthStyle: opt("mouth", "none")
  readonly property string extraStyle: opt("extra", "none")
  readonly property bool cheeks: opt("cheeks", true) === true
  readonly property string fillStyle: opt("style", "solid")
  readonly property string colorChoice: opt("color", "theme")

  readonly property color baseColor: {
    if (root.colorChoice === "theme") return root.accentColor
    return root.colorChoice
  }
  readonly property bool solid: root.fillStyle === "solid"
  readonly property color featureColor: root.solid ? root.background : root.foreground

  // ------------------------------------------------------------ live state
  property real gazeX: 0   // -1..1
  property real gazeY: 0   // -1..1
  property real blink: 1.0 // 1 open, ~0 closed
  property real phase: 0   // wobble clock
  property real breathe: 0 // -1..1
  property real hop: 0     // happy hop offset, px
  property real squash: 0  // happy squash, -1..1
  readonly property bool hovered: mouseArea.containsMouse

  Behavior on gazeX { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on gazeY { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on blink { NumberAnimation { duration: 70; easing.type: Easing.InOutQuad } }

  onLookChanged: canvas.requestPaint()
  onBaseColorChanged: canvas.requestPaint()
  onFeatureColorChanged: canvas.requestPaint()
  onGazeXChanged: canvas.requestPaint()
  onGazeYChanged: canvas.requestPaint()
  onBlinkChanged: canvas.requestPaint()
  onPhaseChanged: canvas.requestPaint()
  onBreatheChanged: canvas.requestPaint()
  onSquashChanged: canvas.requestPaint()
  onHopChanged: canvas.requestPaint()
  onAvatarStateChanged: canvas.requestPaint()
  onHoveredChanged: canvas.requestPaint()

  NumberAnimation on phase {
    from: 0; to: Math.PI * 2
    duration: 5200
    loops: Animation.Infinite
    running: root.animated && root.visible
  }

  SequentialAnimation on breathe {
    running: root.animated && root.visible && root.avatarState !== "happy"
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 1800; easing.type: Easing.InOutSine }
    NumberAnimation { to: -1; duration: 1800; easing.type: Easing.InOutSine }
  }

  SequentialAnimation {
    id: happyAnim
    NumberAnimation { target: root; property: "squash"; to: 1; duration: 80; easing.type: Easing.OutQuad }
    ParallelAnimation {
      NumberAnimation { target: root; property: "squash"; to: -1; duration: 160; easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "hop"; to: -root.size * 0.14; duration: 160; easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "squash"; to: 0.3; duration: 120 }
      NumberAnimation { target: root; property: "hop"; to: 0; duration: 140; easing.type: Easing.InQuad }
    }
    NumberAnimation { target: root; property: "squash"; to: 0; duration: 120 }
  }

  Timer {
    id: happyReset
    interval: 900
    onTriggered: root.avatarState = "idle"
  }

  // A pat: squish down, close the eyes happily and let a heart float up.
  // A quick run of pats makes the pet hop.
  property int patStreak: 0

  SequentialAnimation {
    id: patAnim
    NumberAnimation { target: root; property: "squash"; to: 0.85; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "squash"; to: -0.25; duration: 170; easing.type: Easing.OutBack }
    NumberAnimation { target: root; property: "squash"; to: 0; duration: 140; easing.type: Easing.InOutQuad }
  }

  Timer { id: patStreakReset; interval: 1600; onTriggered: root.patStreak = 0 }

  function pat() {
    root.patStreak++
    patStreakReset.restart()
    root.avatarState = "happy"
    happyReset.interval = 1200
    happyReset.restart()
    if (root.patStreak >= 4) {
      root.patStreak = 0
      happyAnim.restart()
    } else {
      patAnim.restart()
    }
    heartComp.createObject(root, { dx: (Math.random() - 0.5) * root.size * 0.5 })
  }

  Component {
    id: heartComp

    Text {
      id: heart
      property real dx: 0
      textFormat: Text.PlainText
      text: "♥"
      color: root.baseColor
      font.pixelSize: Math.max(8, root.size * 0.26)
      x: root.width / 2 - width / 2 + dx
      y: root.height * 0.05
      z: 10

      ParallelAnimation {
        running: true
        NumberAnimation { target: heart; property: "y"; to: -root.size * 0.45; duration: 950; easing.type: Easing.OutQuad }
        NumberAnimation { target: heart; property: "dx"; to: heart.dx * 1.6; duration: 950 }
        NumberAnimation { target: heart; property: "scale"; from: 0.6; to: 1.1; duration: 950 }
        SequentialAnimation {
          PauseAnimation { duration: 450 }
          NumberAnimation { target: heart; property: "opacity"; to: 0; duration: 500; easing.type: Easing.InQuad }
        }
        onFinished: heart.destroy()
      }
    }
  }

  function triggerHappy() {
    happyReset.interval = 900
    root.avatarState = "happy"
    happyAnim.restart()
    happyReset.restart()
  }

  // Blinking
  Timer {
    interval: 3200
    running: root.animated && root.visible && root.avatarState !== "happy"
    repeat: true
    onTriggered: {
      root.blink = 0.08
      blinkEnd.restart()
      interval = 2800 + Math.random() * 2800
    }
  }
  Timer { id: blinkEnd; interval: 110; onTriggered: root.blink = 1.0 }

  // Idle glances when nobody is driving the gaze
  Timer {
    interval: 4200
    repeat: true
    running: root.animated && root.visible && !root.trackGlobalCursor && !root.hovered
    onTriggered: {
      var r = Math.random()
      root.gazeX = r < 0.3 ? -0.7 : (r < 0.6 ? 0.7 : 0)
      root.gazeY = r > 0.85 ? -0.6 : 0
    }
  }

  // ------------------------------------------------------------ cursor tracking
  // The Omarchy panel is a fullscreen surface on its monitor (minus the bar),
  // so a passive HoverHandler spread over the whole window sees the pointer
  // anywhere on screen while the panel is open, at no polling cost.
  readonly property Item windowRoot: root.Window.contentItem

  Item {
    id: cursorCatcher
    parent: root.trackGlobalCursor && root.windowRoot ? root.windowRoot : root
    anchors.fill: parent
    z: 100000

    HoverHandler {
      enabled: root.trackGlobalCursor
      onPointChanged: if (hovered) root.lookAt(point.scenePosition.x, point.scenePosition.y)
      onHoveredChanged: if (!hovered) { root.gazeX = 0; root.gazeY = 0 }
    }
  }

  onTrackGlobalCursorChanged: if (!trackGlobalCursor) { gazeX = 0; gazeY = 0 }

  function lookAt(sceneX, sceneY) {
    var p = root.mapToItem(null, root.width / 2, root.height / 2)
    var dx = sceneX - p.x
    var dy = sceneY - p.y
    var d = Math.sqrt(dx * dx + dy * dy)
    // Saturates smoothly: close to the pet it looks around, far away it stares.
    var k = d / (d + root.size * 1.2)
    root.gazeX = d > 0 ? (dx / d) * k : 0
    root.gazeY = d > 0 ? (dy / d) * k : 0
  }

  // ------------------------------------------------------------ drawing
  Canvas {
    id: canvas
    // Draw at 2x and scale down so the pet stays crisp on fractional scaling.
    width: root.size * 2
    height: root.size * 2
    scale: 0.5
    anchors.centerIn: parent
    renderStrategy: Canvas.Cooperative
    antialiasing: true

    onPaint: root.paintPet(getContext("2d"), width)
  }

  function rgba(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
  }

  function bodyPath(ctx, cx, cy, r, sx, sy) {
    var shape = root.bodyShape
    var t = root.phase
    ctx.beginPath()
    if (shape === "orb") {
      ctx.ellipse(cx - r * sx, cy - r * sy, 2 * r * sx, 2 * r * sy)
    } else if (shape === "squircle") {
      var n = 4.2
      for (var i = 0; i <= 72; i++) {
        var a = i / 72 * Math.PI * 2
        var ca = Math.cos(a), sa = Math.sin(a)
        var x = cx + r * 1.02 * sx * Math.sign(ca) * Math.pow(Math.abs(ca), 2 / n)
        var y = cy + r * 0.94 * sy * Math.sign(sa) * Math.pow(Math.abs(sa), 2 / n)
        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
      }
      ctx.closePath()
    } else if (shape === "drop") {
      var top = cy - r * 1.12 * sy
      var mid = cy + r * 0.18 * sy
      var rr = r * 0.94
      ctx.moveTo(cx, top)
      ctx.quadraticCurveTo(cx + rr * 0.98 * sx, cy - r * 0.45 * sy, cx + rr * sx, mid)
      ctx.arc(cx, mid, rr * sx, 0, Math.PI, false)
      ctx.quadraticCurveTo(cx - rr * 0.98 * sx, cy - r * 0.45 * sy, cx, top)
      ctx.closePath()
    } else if (shape === "ghost") {
      var shoulder = cy - r * 0.1 * sy
      var bottom = cy + r * 0.92 * sy
      ctx.moveTo(cx - r * sx, shoulder)
      ctx.arc(cx, shoulder, r * sx, Math.PI, Math.PI * 2, false)
      ctx.lineTo(cx + r * sx, bottom)
      var waves = 3
      var w = (2 * r * sx) / waves
      for (var k = 0; k < waves; k++) {
        var x0 = cx + r * sx - k * w
        var lift = r * 0.2 * sy * (0.75 + 0.25 * Math.sin(t * 2 + k * 1.7))
        ctx.quadraticCurveTo(x0 - w / 2, bottom - lift * 2, x0 - w, bottom)
      }
      ctx.closePath()
    } else { // blob: wobbly organic outline
      var steps = 90
      for (var j = 0; j <= steps; j++) {
        var b = j / steps * Math.PI * 2
        var wob = 1 + 0.045 * Math.sin(3 * b + t) + 0.03 * Math.sin(5 * b - t * 2) + 0.02 * Math.sin(2 * b + t * 3)
        var bx = cx + Math.cos(b) * r * sx * wob
        var by = cy + Math.sin(b) * r * 0.95 * sy * wob
        if (j === 0) ctx.moveTo(bx, by); else ctx.lineTo(bx, by)
      }
      ctx.closePath()
    }
  }

  function paintExtra(ctx, cx, cy, r, sx, sy, fill) {
    var e = root.extraStyle
    if (e === "none") return
    var topY = cy - r * sy * (root.bodyShape === "drop" ? 1.05 : 0.92)
    ctx.fillStyle = fill
    ctx.strokeStyle = fill
    ctx.lineCap = "round"
    ctx.lineWidth = r * 0.1
    if (e === "antenna") {
      var sway = Math.sin(root.phase * 2) * r * 0.12
      ctx.beginPath()
      ctx.moveTo(cx, topY + r * 0.2)
      ctx.quadraticCurveTo(cx + sway * 0.4, topY - r * 0.25, cx + sway, topY - r * 0.42)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(cx + sway, topY - r * 0.48, r * 0.13, 0, Math.PI * 2)
      ctx.fill()
    } else if (e === "leaf") {
      ctx.beginPath()
      ctx.moveTo(cx, topY + r * 0.15)
      ctx.lineTo(cx, topY - r * 0.22)
      ctx.stroke()
      var tilt = Math.sin(root.phase) * 0.15
      ctx.save()
      ctx.translate(cx, topY - r * 0.22)
      ctx.rotate(-0.6 + tilt)
      ctx.beginPath()
      ctx.ellipse(0, -r * 0.13, r * 0.42, r * 0.26)
      ctx.fill()
      ctx.restore()
    } else if (e === "ears" || e === "horns") {
      var tall = e === "ears" ? 0.5 : 0.42
      for (var s = -1; s <= 1; s += 2) {
        var bx = cx + s * r * 0.55 * sx
        ctx.beginPath()
        if (e === "ears") {
          ctx.moveTo(bx - s * r * 0.32, topY + r * 0.35)
          ctx.lineTo(bx + s * r * 0.12, topY - r * tall)
          ctx.lineTo(bx + s * r * 0.36, topY + r * 0.25)
        } else {
          ctx.moveTo(bx - s * r * 0.12, topY + r * 0.25)
          ctx.quadraticCurveTo(bx + s * r * 0.05, topY - r * 0.1, bx + s * r * 0.3, topY - r * tall)
          ctx.quadraticCurveTo(bx + s * r * 0.24, topY + r * 0.05, bx + s * r * 0.2, topY + r * 0.3)
        }
        ctx.closePath()
        ctx.fill()
      }
    }
  }

  function roundRect(ctx, x, y, w, h, rad) {
    ctx.beginPath()
    ctx.moveTo(x + rad, y)
    ctx.arcTo(x + w, y, x + w, y + h, rad)
    ctx.arcTo(x + w, y + h, x, y + h, rad)
    ctx.arcTo(x, y + h, x, y, rad)
    ctx.arcTo(x, y, x + w, y, rad)
    ctx.closePath()
  }

  function paintEyes(ctx, cx, cy, r) {
    var gx = root.gazeX * r * 0.2
    var gy = root.gazeY * r * 0.16
    var sp = r * 0.62
    var ey = cy - r * 0.08 + gy
    var style = root.avatarState === "happy" ? "happy" : root.eyeStyle
    var col = root.rgba(root.featureColor, 1)
    ctx.fillStyle = col
    ctx.strokeStyle = col
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    var blink = Math.max(0.08, root.blink)
    for (var s = -1; s <= 1; s += 2) {
      var ex = cx + s * sp / 2 + gx
      if (style === "capsule") {
        var w = r * 0.26, h = r * 0.5 * blink
        roundRect(ctx, ex - w / 2, ey - h / 2, w, h, Math.min(w, h) / 2)
        ctx.fill()
      } else if (style === "dot") {
        ctx.beginPath()
        ctx.ellipse(ex - r * 0.15, ey - r * 0.15 * blink, r * 0.3, r * 0.3 * blink)
        ctx.fill()
      } else if (style === "pixel") {
        var p = r * 0.28
        ctx.fillRect(ex - p / 2, ey - p * blink / 2, p, p * blink)
      } else if (style === "sleepy") {
        ctx.lineWidth = r * 0.1
        ctx.beginPath()
        ctx.arc(ex, ey - r * 0.06, r * 0.17, Math.PI * 0.15, Math.PI * 0.85, false)
        ctx.stroke()
      } else if (style === "googly") {
        var er = r * 0.24
        var ox = ex - gx * 0.5, oy = ey - gy * 0.5
        ctx.fillStyle = root.solid ? root.rgba(root.foreground, 1) : root.rgba(root.background, 0.9)
        ctx.beginPath()
        ctx.ellipse(ox - er, oy - er * blink, er * 2, er * 2 * blink)
        ctx.fill()
        ctx.fillStyle = col
        var pr = er * 0.5
        var px = ox + root.gazeX * er * 0.45
        var py = oy + root.gazeY * er * 0.45
        ctx.beginPath()
        ctx.ellipse(px - pr, py - pr * blink, pr * 2, pr * 2 * blink)
        ctx.fill()
      } else { // happy ^ ^
        ctx.lineWidth = r * 0.11
        ctx.beginPath()
        ctx.arc(ex, ey + r * 0.06, r * 0.17, Math.PI * 1.15, Math.PI * 1.85, false)
        ctx.stroke()
      }
    }
    return { sp: sp, ey: ey, gx: gx, gy: gy }
  }

  function paintMouth(ctx, cx, r, eyes) {
    var m = root.avatarState === "happy" && root.mouthStyle === "none" ? "smile" : root.mouthStyle
    if (m === "none") return
    var mx = cx + eyes.gx * 0.8
    var my = eyes.ey + r * 0.38
    var col = root.rgba(root.featureColor, 1)
    ctx.strokeStyle = col
    ctx.fillStyle = col
    ctx.lineWidth = r * 0.08
    ctx.lineCap = "round"
    ctx.beginPath()
    if (m === "smile") {
      ctx.arc(mx, my - r * 0.08, r * 0.14, Math.PI * 0.2, Math.PI * 0.8, false)
      ctx.stroke()
    } else if (m === "o") {
      ctx.ellipse(mx - r * 0.07, my - r * 0.05, r * 0.14, r * 0.16)
      ctx.fill()
    } else if (m === "cat") {
      ctx.arc(mx - r * 0.08, my - r * 0.04, r * 0.08, 0, Math.PI, false)
      ctx.moveTo(mx + r * 0.16, my - r * 0.04)
      ctx.arc(mx + r * 0.08, my - r * 0.04, r * 0.08, 0, Math.PI, false)
      ctx.stroke()
    } else if (m === "flat") {
      ctx.moveTo(mx - r * 0.1, my)
      ctx.lineTo(mx + r * 0.1, my)
      ctx.stroke()
    }
  }

  function paintPet(ctx, S) {
    ctx.reset()
    var cx = S / 2
    var r = S * 0.36
    // Leave headroom for extras (antenna, ears) above the body.
    var cy = S / 2 + (root.extraStyle === "none" ? 0 : S * 0.06) + root.hop * 2
    var grow = root.hovered && root.interactive ? 1.04 : 1.0
    var sx = (1 + 0.025 * root.breathe + 0.14 * root.squash) * grow
    var sy = (1 - 0.025 * root.breathe - 0.14 * root.squash) * grow

    var fill = root.solid ? root.rgba(root.baseColor, 1) : root.rgba(root.baseColor, 0.16)

    // Extras sit behind the body so they read as growing out of it.
    paintExtra(ctx, cx, cy, r, sx, sy, root.solid ? fill : root.rgba(root.baseColor, 0.9))

    bodyPath(ctx, cx, cy, r, sx, sy)
    ctx.fillStyle = fill
    ctx.fill()
    if (!root.solid) {
      ctx.strokeStyle = root.rgba(root.baseColor, 0.95)
      ctx.lineWidth = S * 0.03
      ctx.stroke()
    }

    var eyes = paintEyes(ctx, cx, cy, r)

    if (root.cheeks) {
      ctx.fillStyle = root.solid ? root.rgba(root.background, 0.18) : root.rgba(root.baseColor, 0.45)
      for (var s = -1; s <= 1; s += 2) {
        ctx.beginPath()
        ctx.ellipse(cx + s * eyes.sp * 0.78 + eyes.gx * 0.6 - r * 0.13, eyes.ey + r * 0.24, r * 0.26, r * 0.14)
        ctx.fill()
      }
    }

    paintMouth(ctx, cx, r, eyes)
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onPositionChanged: function(mouse) {
      if (root.trackGlobalCursor) return
      root.gazeX = Math.max(-1, Math.min(1, (mouse.x - width / 2) / (width / 2)))
      root.gazeY = Math.max(-1, Math.min(1, (mouse.y - height / 2) / (height / 2)))
    }
    onExited: if (!root.trackGlobalCursor) { root.gazeX = 0; root.gazeY = 0 }
    onClicked: {
      root.pat()
      root.clicked()
    }
  }
}
