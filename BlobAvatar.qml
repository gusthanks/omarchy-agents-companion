import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons

// Flat, parametric pet. Everything is drawn in one Canvas from a small "look"
// object, so the same component renders the bar pet, the panel pet and every
// preview in the editor.
//
// look: { body, eyes, mouth, extra, accessory, cheeks, style, color }
// mood (set by the host): "normal" | "worried" | "tired"
Item {
  id: root

  property real size: Style.space(42)
  property var look: ({})
  property string mood: "normal"
  property color accentColor: Commons.Color.accent
  property color foreground: Commons.Color.foreground
  property color background: Commons.Color.background
  // Follow the cursor anywhere on the panel screen; also enables dozing off.
  property bool trackGlobalCursor: false
  property bool interactive: true
  // Wobble + breathing (continuous repaints). Off for the bar and swatches.
  property bool animated: true
  // Blinking and idle glances (a repaint every few seconds).
  property bool lively: true
  // Santa hat on Dec 24-25, party hat on Dec 31 / Jan 1.
  property bool seasonal: true
  // Floating "!" / "z" marks (off in the bar, where they would be clipped).
  property bool showMarks: true
  // Hearts and confetti (off in the bar, which is one icon tall).
  property bool particles: true

  property string avatarState: "idle" // idle | happy (transient)
  property bool asleep: false

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
  readonly property string accessory: opt("accessory", "none")
  readonly property bool cheeks: opt("cheeks", true) === true
  readonly property string fillStyle: opt("style", "solid")
  readonly property string colorChoice: opt("color", "theme")

  // Shared ThemePalette from the host; resolves "theme:<name>" colors.
  property var themePalette: null
  readonly property color baseColor: {
    if (root.themePalette) {
      var dep = root.themePalette.colors
      return root.themePalette.resolve(root.colorChoice, root.accentColor)
    }
    return /^#[0-9a-fA-F]{6}$/.test(root.colorChoice) ? root.colorChoice : root.accentColor
  }
  readonly property bool solid: root.fillStyle === "solid"
  readonly property color featureColor: root.solid ? root.background : root.foreground
  // Hats, bows and petals stick out past the body, so they need to read on
  // the panel background too: use the theme's text color.
  readonly property color trimColor: root.foreground

  property int dayStamp: 0 // bumped hourly so the seasonal hat follows the date
  readonly property string seasonHat: {
    if (!root.seasonal) return ""
    var stamp = root.dayStamp
    var d = new Date()
    var m = d.getMonth() + 1, day = d.getDate()
    if (m === 12 && (day === 24 || day === 25)) return "santa"
    if ((m === 12 && day === 31) || (m === 1 && day === 1)) return "party"
    return ""
  }
  readonly property string headwear: root.seasonHat !== "" ? root.seasonHat
    : (root.accessory === "hat" || root.accessory === "beanie" ? root.accessory : "")
  Timer { interval: 3600000; repeat: true; running: root.seasonal; onTriggered: root.dayStamp++ }

  // ------------------------------------------------------------ live state
  property real gazeX: 0   // -1..1
  property real gazeY: 0   // -1..1
  property real blink: 1.0 // 1 open, ~0 closed
  property real phase: 0   // wobble clock
  property real breathe: 0 // -1..1
  property real hop: 0     // hop offset, px
  property real squash: 0  // -1..1
  readonly property bool hovered: mouseArea.containsMouse

  Behavior on gazeX { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on gazeY { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on blink { NumberAnimation { duration: 70; easing.type: Easing.InOutQuad } }

  onLookChanged: canvas.requestPaint()
  onMoodChanged: canvas.requestPaint()
  onBaseColorChanged: canvas.requestPaint()
  onFeatureColorChanged: canvas.requestPaint()
  onForegroundChanged: canvas.requestPaint()
  onGazeXChanged: canvas.requestPaint()
  onGazeYChanged: canvas.requestPaint()
  onBlinkChanged: canvas.requestPaint()
  onPhaseChanged: canvas.requestPaint()
  onBreatheChanged: canvas.requestPaint()
  onSquashChanged: canvas.requestPaint()
  onHopChanged: canvas.requestPaint()
  onAvatarStateChanged: canvas.requestPaint()
  onHoveredChanged: canvas.requestPaint()
  onAsleepChanged: canvas.requestPaint()
  onSeasonHatChanged: canvas.requestPaint()
  onSizeChanged: canvas.requestPaint()

  NumberAnimation on phase {
    from: 0; to: Math.PI * 2
    duration: 5200
    loops: Animation.Infinite
    running: root.animated && root.visible
  }

  // Breathing slows down when tired or asleep.
  SequentialAnimation on breathe {
    running: root.animated && root.visible && root.avatarState !== "happy"
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: root.asleep || root.mood === "tired" ? 2800 : 1800; easing.type: Easing.InOutSine }
    NumberAnimation { to: -1; duration: root.asleep || root.mood === "tired" ? 2800 : 1800; easing.type: Easing.InOutSine }
  }

  SequentialAnimation {
    id: hopAnim
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

  SequentialAnimation {
    id: patAnim
    NumberAnimation { target: root; property: "squash"; to: 0.85; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "squash"; to: -0.25; duration: 170; easing.type: Easing.OutBack }
    NumberAnimation { target: root; property: "squash"; to: 0; duration: 140; easing.type: Easing.InOutQuad }
  }

  Timer {
    id: happyReset
    interval: 900
    onTriggered: root.avatarState = "idle"
  }

  function triggerHappy() {
    root.asleep = false
    root.avatarState = "happy"
    happyReset.interval = 900
    happyReset.restart()
    hopAnim.restart()
  }

  // Celebration: a hop with a small burst of confetti (e.g. a limit came back).
  function celebrate() {
    triggerHappy()
    happyReset.interval = 1600
    happyReset.restart()
    for (var i = 0; i < 8; i++) {
      var a = -Math.PI / 2 + (i - 3.5) * 0.32
      spawnParticle(i % 3 === 0 ? "✦" : "•", Math.cos(a) * root.size * 0.9, Math.sin(a) * root.size * 0.75 - root.size * 0.1,
        i % 2 === 0 ? root.baseColor : root.foreground)
    }
  }

  // A pat: squish, close the eyes happily, let a heart float up. A quick run
  // of pats makes the pet hop. Pats also wake it up.
  property int patStreak: 0
  Timer { id: patStreakReset; interval: 1600; onTriggered: root.patStreak = 0 }

  function pat() {
    root.asleep = false
    idleTimer.restart()
    root.patStreak++
    patStreakReset.restart()
    root.avatarState = "happy"
    happyReset.interval = 1200
    happyReset.restart()
    if (root.patStreak >= 4) {
      root.patStreak = 0
      hopAnim.restart()
    } else {
      patAnim.restart()
    }
    spawnParticle("♥", (Math.random() - 0.5) * root.size * 0.5, -root.size * 0.5, root.baseColor)
  }

  // Particles live on the window's root item so the panel's scroll area does
  // not clip them at its top edge.
  readonly property Item windowRoot: root.Window.contentItem
  // Where hearts and confetti are drawn; defaults to the window root. The dev
  // harness points it at its capture stage so frames include them.
  property Item particleHost: null

  function spawnParticle(glyph, dx, dy, color) {
    if (!root.particles) return
    var host = root.particleHost || root.windowRoot || root
    var origin = root.mapToItem(host, root.width / 2, root.height * 0.3)
    particleComp.createObject(host, { glyph: glyph, ox: origin.x, oy: origin.y, dx: dx, dy: dy, tint: color })
  }

  Component {
    id: particleComp

    Text {
      id: particle
      property string glyph: "♥"
      property real ox: 0
      property real oy: 0
      property real dx: 0
      property real dy: 0
      property color tint: "white"
      property real t: 0
      textFormat: Text.PlainText
      text: glyph
      color: tint
      font.pixelSize: Math.max(9, root.size * 0.28)
      x: ox - width / 2 + dx * t
      y: oy - height / 2 + dy * t
      scale: 0.6 + 0.5 * t
      opacity: t < 0.5 ? 1 : 1 - (t - 0.5) * 2
      z: 100001

      NumberAnimation on t {
        from: 0; to: 1
        duration: 950
        easing.type: Easing.OutQuad
        onFinished: particle.destroy()
      }
    }
  }

  // ------------------------------------------------------------ timers
  Timer {
    interval: 3200
    running: root.lively && root.visible && root.avatarState !== "happy" && !root.asleep
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
    running: root.lively && root.visible && !root.trackGlobalCursor && !root.hovered && !root.asleep
    onTriggered: {
      var r = Math.random()
      root.gazeX = r < 0.3 ? -0.7 : (r < 0.6 ? 0.7 : 0)
      root.gazeY = r > 0.85 ? -0.6 : 0
    }
  }

  // Dozing off: no pointer movement for a while (sooner late at night).
  Timer {
    id: idleTimer
    interval: {
      var h = new Date().getHours()
      return h < 5 ? 30000 : 90000
    }
    running: root.trackGlobalCursor && root.lively && root.visible && !root.asleep
    onTriggered: { root.asleep = true; root.gazeX = 0; root.gazeY = 0.3 }
  }
  onTrackGlobalCursorChanged: {
    if (!trackGlobalCursor) { gazeX = 0; gazeY = 0; asleep = false }
  }

  // ------------------------------------------------------------ cursor tracking
  // The Omarchy panel is a fullscreen surface on its monitor (minus the bar),
  // so a passive HoverHandler spread over the whole window sees the pointer
  // anywhere on screen while the panel is open, at no polling cost.
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

  property real lastLookX: -1
  property real lastLookY: -1

  function lookAt(sceneX, sceneY) {
    // Ignore sub-pixel jitter so a resting mouse still lets the pet doze off.
    if (Math.abs(sceneX - lastLookX) < 2 && Math.abs(sceneY - lastLookY) < 2) return
    lastLookX = sceneX
    lastLookY = sceneY
    idleTimer.restart()
    if (root.asleep) {
      root.asleep = false
      root.blink = 0.08
      blinkEnd.restart()
    }
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
    // Taller than wide: the extra room above keeps hats and antennas inside
    // the canvas when the pet hops.
    width: root.size * 2
    height: root.size * 2.6
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

  function headTop(cy, r, sy) {
    return cy - r * sy * (root.bodyShape === "drop" ? 1.05 : 0.92)
  }

  function paintExtra(ctx, cx, cy, r, sx, sy, fill) {
    var e = root.extraStyle
    if (e === "none") return
    var topY = headTop(cy, r, sy)
    ctx.fillStyle = fill
    ctx.strokeStyle = fill
    ctx.lineCap = "round"
    ctx.lineWidth = r * 0.1
    if (e === "antenna") {
      if (root.headwear !== "") return // hidden under a hat
      var sway = Math.sin(root.phase * 2) * r * 0.12
      ctx.beginPath()
      ctx.moveTo(cx, topY + r * 0.2)
      ctx.quadraticCurveTo(cx + sway * 0.4, topY - r * 0.25, cx + sway, topY - r * 0.42)
      ctx.stroke()
      ctx.beginPath()
      ctx.arc(cx + sway, topY - r * 0.48, r * 0.13, 0, Math.PI * 2)
      ctx.fill()
    } else if (e === "leaf") {
      if (root.headwear !== "") return
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

  // Which eye drawing the current moment calls for.
  function currentEyes() {
    if (root.asleep) return "closed"
    if (root.avatarState === "happy") return "happy"
    if (root.mood === "tired") return "sleepy"
    return root.eyeStyle
  }

  function paintEyes(ctx, cx, cy, r) {
    var still = root.asleep
    var gx = still ? 0 : root.gazeX * r * 0.2
    var gy = still ? 0 : root.gazeY * r * 0.16
    var sp = r * 0.62
    var ey = cy - r * 0.08 + gy
    var style = currentEyes()
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
      } else if (style === "closed") {
        ctx.lineWidth = r * 0.09
        ctx.beginPath()
        ctx.moveTo(ex - r * 0.14, ey + r * 0.04)
        ctx.quadraticCurveTo(ex, ey + r * 0.14, ex + r * 0.14, ey + r * 0.04)
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

    // Worried brows: inner ends raised.
    if (root.mood === "worried" && !root.asleep && root.avatarState !== "happy") {
      ctx.lineWidth = r * 0.08
      for (var b = -1; b <= 1; b += 2) {
        var bx = cx + b * sp / 2 + gx
        ctx.beginPath()
        ctx.moveTo(bx - b * r * 0.04, ey - r * 0.4)
        ctx.lineTo(bx + b * r * 0.16, ey - r * 0.3)
        ctx.stroke()
      }
    }
    return { sp: sp, ey: ey, gx: gx, gy: gy }
  }

  function paintMouth(ctx, cx, r, eyes) {
    var m = root.mouthStyle
    if (root.avatarState === "happy" && m === "none") m = "smile"
    if (root.asleep) m = "o-small"
    else if (root.mood === "worried" && root.avatarState !== "happy") m = "wavy"
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
    } else if (m === "o-small") {
      ctx.ellipse(mx - r * 0.045, my - r * 0.03, r * 0.09, r * 0.1 + 0.02 * r * root.breathe)
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
    } else if (m === "wavy") {
      ctx.moveTo(mx - r * 0.14, my)
      ctx.quadraticCurveTo(mx - r * 0.07, my - r * 0.06, mx, my)
      ctx.quadraticCurveTo(mx + r * 0.07, my + r * 0.06, mx + r * 0.14, my)
      ctx.stroke()
    }
  }

  // Glasses, bow and flower sit on the face; hats are drawn by paintHeadwear.
  function paintAccessory(ctx, cx, cy, r, sx, sy, eyes) {
    var a = root.accessory
    var ink = root.rgba(root.featureColor, 1)
    if (a === "glasses") {
      ctx.strokeStyle = ink
      ctx.lineWidth = r * 0.07
      var gr = r * 0.25
      for (var s = -1; s <= 1; s += 2) {
        ctx.beginPath()
        ctx.ellipse(cx + s * eyes.sp / 2 + eyes.gx * 0.5 - gr, eyes.ey - gr, gr * 2, gr * 2)
        ctx.stroke()
      }
      ctx.beginPath()
      ctx.moveTo(cx - eyes.sp / 2 + gr + eyes.gx * 0.5, eyes.ey - r * 0.04)
      ctx.quadraticCurveTo(cx + eyes.gx * 0.5, eyes.ey - r * 0.12, cx + eyes.sp / 2 - gr + eyes.gx * 0.5, eyes.ey - r * 0.04)
      ctx.stroke()
    } else if (a === "bow") {
      var bx = cx + r * 0.58 * sx, by = headTop(cy, r, sy) + r * 0.22
      ctx.fillStyle = root.rgba(root.trimColor, 1)
      ctx.save()
      ctx.translate(bx, by)
      ctx.rotate(0.35)
      for (var w = -1; w <= 1; w += 2) {
        ctx.beginPath()
        ctx.moveTo(0, 0)
        ctx.lineTo(w * r * 0.34, -r * 0.18)
        ctx.lineTo(w * r * 0.34, r * 0.18)
        ctx.closePath()
        ctx.fill()
      }
      ctx.beginPath()
      ctx.ellipse(-r * 0.08, -r * 0.08, r * 0.16, r * 0.16)
      ctx.fill()
      ctx.restore()
    } else if (a === "flower") {
      var fx = cx - r * 0.55 * sx, fy = headTop(cy, r, sy) + r * 0.25
      ctx.fillStyle = root.rgba(root.foreground, 1)
      for (var i = 0; i < 5; i++) {
        var ang = i / 5 * Math.PI * 2 + root.phase * 0.2
        ctx.beginPath()
        ctx.ellipse(fx + Math.cos(ang) * r * 0.13 - r * 0.1, fy + Math.sin(ang) * r * 0.13 - r * 0.1, r * 0.2, r * 0.2)
        ctx.fill()
      }
      ctx.fillStyle = root.rgba(root.baseColor, 1)
      ctx.beginPath()
      ctx.ellipse(fx - r * 0.07, fy - r * 0.07, r * 0.14, r * 0.14)
      ctx.fill()
    }
  }

  function paintHeadwear(ctx, cx, cy, r, sx, sy) {
    var h = root.headwear
    if (h === "") return
    var top = headTop(cy, r, sy)
    var ink = root.rgba(root.trimColor, 1)
    if (h === "hat") { // top hat
      ctx.fillStyle = ink
      roundRect(ctx, cx - r * 0.62, top + r * 0.02, r * 1.24, r * 0.16, r * 0.08)
      ctx.fill()
      roundRect(ctx, cx - r * 0.38, top - r * 0.5, r * 0.76, r * 0.56, r * 0.06)
      ctx.fill()
      ctx.fillStyle = root.rgba(root.baseColor, 0.8)
      ctx.fillRect(cx - r * 0.38, top - r * 0.08, r * 0.76, r * 0.08)
    } else if (h === "beanie") {
      ctx.fillStyle = ink
      ctx.beginPath()
      ctx.arc(cx, top + r * 0.22, r * 0.62, Math.PI, Math.PI * 2, false)
      ctx.closePath()
      ctx.fill()
      roundRect(ctx, cx - r * 0.66, top + r * 0.12, r * 1.32, r * 0.2, r * 0.1)
      ctx.fill()
      ctx.beginPath()
      ctx.ellipse(cx - r * 0.12, top - r * 0.56, r * 0.24, r * 0.24)
      ctx.fill()
    } else if (h === "santa") {
      ctx.fillStyle = "#d94450"
      ctx.beginPath()
      ctx.moveTo(cx - r * 0.6, top + r * 0.15)
      ctx.quadraticCurveTo(cx - r * 0.1, top - r * 0.75, cx + r * 0.62, top - r * 0.35)
      ctx.lineTo(cx + r * 0.6, top + r * 0.15)
      ctx.closePath()
      ctx.fill()
      ctx.fillStyle = "#f4f1ea"
      roundRect(ctx, cx - r * 0.66, top + r * 0.06, r * 1.32, r * 0.2, r * 0.1)
      ctx.fill()
      ctx.beginPath()
      ctx.ellipse(cx + r * 0.5, top - r * 0.48, r * 0.24, r * 0.24)
      ctx.fill()
    } else if (h === "party") {
      ctx.save()
      ctx.translate(cx + r * 0.12, top + r * 0.1)
      ctx.rotate(0.18)
      ctx.beginPath()
      ctx.moveTo(-r * 0.3, 0)
      ctx.lineTo(0, -r * 0.72)
      ctx.lineTo(r * 0.3, 0)
      ctx.closePath()
      ctx.fillStyle = "#f9e2af"
      ctx.fill()
      ctx.clip()
      ctx.fillStyle = "#f38ba8"
      for (var i = 0; i < 3; i++) ctx.fillRect(-r * 0.4, -r * (0.12 + i * 0.24), r * 0.8, r * 0.1)
      ctx.restore()
      ctx.fillStyle = "#89b4fa"
      ctx.beginPath()
      ctx.ellipse(cx + r * 0.12 + r * 0.13 * 0.18 * 4 - r * 0.1, top - r * 0.7, r * 0.2, r * 0.2)
      ctx.fill()
    }
  }

  // Small floating marks: "!" when worried, "z" when tired or asleep.
  function paintMarks(ctx, S, cx, cy, r) {
    var ink = root.rgba(root.foreground, 1)
    ctx.fillStyle = ink
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    if (root.asleep || (root.mood === "tired" && root.avatarState !== "happy")) {
      var drift = (root.phase / (Math.PI * 2))
      var count = root.asleep ? 2 : 1
      for (var i = 0; i < count; i++) {
        var t = (drift + i * 0.5) % 1
        ctx.globalAlpha = t < 0.7 ? 0.9 : (1 - t) * 3
        ctx.font = "bold " + Math.round(r * (0.32 + 0.12 * t)) + "px sans-serif"
        ctx.fillText("z", cx + r * (0.85 + 0.2 * t), cy - r * (0.65 + 0.45 * t))
      }
      ctx.globalAlpha = 1
    } else if (root.mood === "worried" && root.avatarState !== "happy") {
      ctx.font = "bold " + Math.round(r * 0.5) + "px sans-serif"
      ctx.fillText("!", cx + r * 0.95, cy - r * 0.8 + Math.sin(root.phase * 3) * r * 0.04)
    }
  }

  function paintPet(ctx, S) {
    ctx.reset()
    ctx.translate(0, S * 0.15)
    var cx = S / 2
    var r = S * 0.36
    // Leave headroom for anything that grows above the head.
    var tall = root.extraStyle !== "none" || root.headwear !== "" || root.accessory === "bow" || root.accessory === "flower"
    var cy = S / 2 + (tall ? S * 0.07 : 0) + root.hop * 2
    if (tall) r = S * 0.34
    var grow = root.hovered && root.interactive ? 1.04 : 1.0
    var sx = (1 + 0.025 * root.breathe + 0.14 * root.squash) * grow
    var sy = (1 - 0.025 * root.breathe - 0.14 * root.squash) * grow

    var fill = root.solid ? root.rgba(root.baseColor, 1) : root.rgba(root.baseColor, 0.16)

    // Ears, antenna and leaf sit behind the body so they read as growing out of it.
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
    paintAccessory(ctx, cx, cy, r, sx, sy, eyes)
    paintHeadwear(ctx, cx, cy, r, sx, sy)
    if (root.showMarks) paintMarks(ctx, S, cx, cy, r)
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
