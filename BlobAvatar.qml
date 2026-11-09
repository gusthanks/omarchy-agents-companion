import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "PetFace.js" as PetFace
import "PetClips.js" as PetClips

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
  // Editor chips: a still, zoomed crop of one part of the pet. "" draws the
  // whole live pet; silhouette | eyes | mouth | top | topLeft | topRight.
  property string framing: ""
  readonly property bool still: root.framing !== ""

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
  property real hop: 0     // hop offset, px (added to the face's own hop)
  property real squash: 0  // -1..1 (added to the face's own squash)
  readonly property bool hovered: mouseArea.containsMouse

  Behavior on gazeX { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on gazeY { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
  Behavior on blink { NumberAnimation { duration: 70; easing.type: Easing.InOutQuad } }

  onLookChanged: canvas.requestPaint()
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
  onHoveredChanged: canvas.requestPaint()
  onSeasonHatChanged: canvas.requestPaint()
  onSizeChanged: canvas.requestPaint()
  onFaceChanged: canvas.requestPaint()
  onFramingChanged: canvas.requestPaint()

  NumberAnimation on phase {
    from: 0; to: Math.PI * 2
    duration: 5200
    loops: Animation.Infinite
    running: root.animated && root.visible
  }

  // Breathing slows down when tired or asleep, and pauses during a reaction.
  readonly property int breathMs: root.face.breathRate < 0.8 ? 2800 : 1800
  SequentialAnimation on breathe {
    running: root.animated && root.visible && !root.reacting && root.avatarState !== "happy"
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: root.breathMs; easing.type: Easing.InOutSine }
    NumberAnimation { to: -1; duration: root.breathMs; easing.type: Easing.InOutSine }
  }

  // ------------------------------------------------------------ expressions
  // The face every paint routine reads: the mood / sleep base pose, with the
  // playing reaction blended over it (see FacePlayer, PetFace.js, PetClips.js).

  // How lively reactions are (a user setting): lively = everything, calm = no
  // ambient fidgets (yawns, sneezes, idle winks), still = no animated clips
  // (every clip shows one pose, also on the bar pet).
  property string reactions: "lively"
  // What this avatar can afford: full (ticks clips), cheap (the bar: poses,
  // short "full" clips only), static (swatches: nothing plays).
  property string reactionLevel: root.animated ? "full" : (root.lively ? "cheap" : "static")
  readonly property string effectiveLevel: root.reactions === "still" && root.reactionLevel !== "static" ? "still" : root.reactionLevel
  // Cursor-driven reactions (startle, curious). The GIF harness turns them off.
  property bool cursorReactions: true
  // Harness: function() -> ms used instead of the wall clock for clips.
  property var clock: null
  // Static previews: a fixed face, or the peak frame of a named reaction.
  property var faceOverride: null
  property string posePreview: ""

  readonly property var face: root.faceOverride ? root.faceOverride
    : (root.posePreview !== "" ? PetClips.peakPose(root.posePreview, root.basePoseFor(root.mood, root.asleep, root.avatarState))
    : player.face)
  readonly property bool reacting: player.current !== "" && player.current !== "__release"
  readonly property string reaction: root.reacting ? player.current : ""
  readonly property var reactionNames: PetClips.NAMES
  property real lastReactionMs: 0

  property string avatarState: "idle" // static override: "happy" shows the happy face
  property bool asleep: false

  FacePlayer {
    id: player
    level: root.effectiveLevel
    active: root.visible
    clock: root.clock
    onFx: function(kind) { root.runFx(kind) }
    onSleepRequested: root.asleep = true
  }

  function basePoseFor(mood, asleep, state) {
    return PetFace.resolve(PetFace.EXPR[mood] || null,
                           asleep ? PetFace.EXPR.asleep : (state === "happy" ? PetFace.EXPR.happy : null))
  }
  function basePose() { return basePoseFor(root.mood, root.asleep, root.avatarState) }

  onMoodChanged: player.setBase(basePose())
  onAsleepChanged: player.setBase(basePose())
  onAvatarStateChanged: player.setBase(basePose(), true)
  onEffectiveLevelChanged: if (root.effectiveLevel !== "full") player.stop("", true)
  onVisibleChanged: if (!root.visible) player.stop("", true)
  Component.onCompleted: player.setBase(basePose(), true)

  function now() { return root.clock ? root.clock() : Date.now() }

  // Play a reaction by name (see PetClips.NAMES). Returns whether it started.
  // opts: { mirror: -1|1, next: name|"__sleep", force: true (previews: skip
  // cooldowns and priorities), noCooldown: true, priority: n }
  function play(name, opts) {
    var c = PetClips.CLIPS[name]
    if (!c) return false
    var force = opts && opts.force
    if (root.asleep && !c.wakes && !force) return false
    if (root.effectiveLevel === "static") return false
    var wasAsleep = root.asleep
    if (root.asleep) root.asleep = false
    var ok = player.play(name, opts)
    if (ok) root.lastReactionMs = Date.now()
    else if (wasAsleep && name !== "wake") root.asleep = true
    return ok
  }
  function stop(name) { player.stop(name || "") }
  // A reaction's face `ms` into it, without playing (previews, docs).
  function poseAt(name, ms) { return player.poseAt(name, ms) }

  // Ambient clips: only when the user allows them and the pet has been left
  // alone for a while.
  function ambient(name, opts) {
    if (root.reactions !== "lively" || root.hovered || root.reacting) return false
    if (Date.now() - root.lastReactionMs < 45000) return false
    return root.play(name, opts)
  }

  function runFx(kind) {
    if (kind === "heart") {
      spawnParticle("♥", (Math.random() - 0.5) * root.size * 0.5, -root.size * 0.5, root.baseColor)
    } else if (kind === "confetti") {
      for (var i = 0; i < 8; i++) {
        var a = -Math.PI / 2 + (i - 3.5) * 0.32
        spawnParticle(i % 3 === 0 ? "✦" : "•", Math.cos(a) * root.size * 0.9, Math.sin(a) * root.size * 0.75 - root.size * 0.1,
          i % 2 === 0 ? root.baseColor : root.foreground)
      }
    } else if (kind === "star") {
      spawnParticle("✦", (Math.random() - 0.5) * root.size, -root.size * 0.6, root.foreground)
    } else if (kind === "sneeze") {
      spawnParticle("✱", root.size * 0.7, -root.size * 0.05, root.foreground)
      spawnParticle("•", root.size * 0.55, root.size * 0.12, root.foreground)
    }
  }

  // ------------------------------------------------------------ public API
  function triggerHappy() { root.play("happy") }

  // Celebration: a hop with a small burst of confetti (e.g. a limit came back).
  function celebrate() { root.play("celebrate") }

  // A pat: squish, close the eyes happily, let a heart float up. Four quick
  // pats make the pet hop, eight make it dizzy. A pat wakes it with a stretch.
  property int patStreak: 0
  Timer { id: patStreakReset; interval: 2500; onTriggered: root.patStreak = 0 }

  function pat() {
    idleTimer.restart()
    if (root.asleep) { root.play("wake"); return }
    root.patStreak++
    patStreakReset.restart()
    root.runFx("heart")
    if (player.current === "dizzy") return
    if (root.patStreak >= 8) {
      root.patStreak = 0
      root.play("dizzy")
    } else if (root.patStreak === 4) {
      root.play("hop")
    } else {
      root.play("pat")
    }
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
  // The automatic blink stays outside the clips; a reaction holds it off.
  readonly property bool canBlink: root.face.blinkOk === 1 && root.face.eyeOpen > 0.5
    && (root.face.eyeShape === "" || root.face.eyeShape === "wide")
  property bool doubleBlink: false
  Timer {
    interval: 3200
    running: root.lively && root.visible && root.canBlink && !root.asleep
    repeat: true
    onTriggered: {
      root.blink = 0.08
      root.doubleBlink = Math.random() < 0.15
      blinkEnd.restart()
      interval = 2800 + Math.random() * 2800
    }
  }
  Timer {
    id: blinkEnd
    interval: 110
    onTriggered: {
      root.blink = 1.0
      if (root.doubleBlink) { root.doubleBlink = false; blinkAgain.restart() }
    }
  }
  Timer { id: blinkAgain; interval: 140; onTriggered: { root.blink = 0.08; blinkEnd.restart() } }

  // Idle glances when nobody is driving the gaze (and, now and then, a wink).
  Timer {
    interval: 4200
    repeat: true
    running: root.lively && root.visible && !root.trackGlobalCursor && !root.hovered && !root.asleep
    onTriggered: {
      var r = Math.random()
      root.gazeX = r < 0.3 ? -0.7 : (r < 0.6 ? 0.7 : 0)
      root.gazeY = r > 0.85 ? -0.6 : 0
      if (root.mood === "normal" && Math.random() < 0.1) root.ambient("wink")
    }
  }

  // Ambient fidgets on the full pet: a rare sneeze, a wink, yawns when tired.
  Timer {
    interval: 15000
    repeat: true
    running: root.effectiveLevel === "full" && root.lively && root.visible && !root.asleep && root.reactions === "lively"
    onTriggered: {
      var r = Math.random()
      if (root.mood === "tired") { if (r < 0.25) root.ambient("yawn") }
      else if (root.mood === "normal") {
        if (r < 0.008) root.ambient("sneeze")
        else if (r < 0.05 && root.trackGlobalCursor) root.ambient("wink")
      }
    }
  }

  // Dozing off: no pointer movement for a while (sooner late at night). The
  // pet yawns first and falls asleep when the yawn ends.
  Timer {
    id: idleTimer
    interval: {
      var h = new Date().getHours()
      return h < 5 ? 30000 : 90000
    }
    running: root.trackGlobalCursor && root.lively && root.visible && !root.asleep
    onTriggered: {
      root.gazeX = 0
      root.gazeY = 0.3
      if (root.effectiveLevel !== "full") { root.asleep = true; return }
      if (!root.play("yawn", { next: "__sleep", noCooldown: true })) restart()
    }
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
      onHoveredChanged: {
        root.freshPointer = true
        if (!hovered) { root.gazeX = 0; root.gazeY = 0 }
      }
    }
  }

  property real lastLookX: -1
  property real lastLookY: -1
  // Startle detection: the previous sample, and whether the next one is a
  // jump (the pointer just entered the surface).
  property bool freshPointer: true
  property real lastLookMs: 0
  property real lastLookDist: -1
  property int fastSamples: 0

  // Curious: the cursor came to rest close to the pet.
  Timer {
    id: restTimer
    interval: 1200
    onTriggered: {
      if (root.lastLookDist >= 0 && root.lastLookDist < root.size * 1.6)
        root.play("curious", { mirror: root.gazeX < 0 ? -1 : 1 })
    }
  }

  function lookAt(sceneX, sceneY) {
    // Ignore sub-pixel jitter so a resting mouse still lets the pet doze off.
    if (Math.abs(sceneX - lastLookX) < 2 && Math.abs(sceneY - lastLookY) < 2) return
    var px = lastLookX, py = lastLookY
    lastLookX = sceneX
    lastLookY = sceneY
    idleTimer.restart()
    // Moving the pointer during the doze-off yawn keeps the pet awake (a
    // previewed yawn plays on).
    if (player.current === "yawn" && player._next === "__sleep") root.stop("yawn")
    if (root.asleep) {
      if (!root.play("wake")) {
        root.asleep = false
        root.blink = 0.08
        blinkEnd.restart()
      }
    }
    var p = root.mapToItem(null, root.width / 2, root.height / 2)
    var dx = sceneX - p.x
    var dy = sceneY - p.y
    var d = Math.sqrt(dx * dx + dy * dy)
    // Saturates smoothly: close to the pet it looks around, far away it stares.
    var k = d / (d + root.size * 1.2)
    root.gazeX = d > 0 ? (dx / d) * k : 0
    root.gazeY = d > 0 ? (dy / d) * k : 0

    var t = root.now()
    if (root.cursorReactions && root.effectiveLevel === "full") {
      // Startle: two fast samples in a row rushing toward the pet.
      if (!root.freshPointer && root.lastLookDist >= 0 && px >= 0) {
        var dt = Math.max(1, t - root.lastLookMs)
        var mv = Math.sqrt((sceneX - px) * (sceneX - px) + (sceneY - py) * (sceneY - py))
        var fast = mv / dt > root.size * 0.06 && d < root.lastLookDist
        root.fastSamples = fast ? root.fastSamples + 1 : 0
        if (root.fastSamples >= 2 && d < root.size * 2.5) {
          root.fastSamples = 0
          root.play("startle")
        }
      }
      if (d < root.size * 1.6) restTimer.restart()
      else restTimer.stop()
    }
    root.freshPointer = false
    root.lastLookMs = t
    root.lastLookDist = d
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
        var lift = r * 0.2 * sy * (0.75 + 0.25 * root.face.wobble * Math.sin(t * 2 + k * 1.7))
        ctx.quadraticCurveTo(x0 - w / 2, bottom - lift * 2, x0 - w, bottom)
      }
      ctx.closePath()
    } else { // blob: wobbly organic outline
      var steps = 90
      var wa = root.face.wobble
      for (var j = 0; j <= steps; j++) {
        var b = j / steps * Math.PI * 2
        var wob = wa === 1 ? 1 + 0.045 * Math.sin(3 * b + t) + 0.03 * Math.sin(5 * b - t * 2) + 0.02 * Math.sin(2 * b + t * 3)
          : 1 + wa * (0.045 * Math.sin(3 * b + t) + 0.03 * Math.sin(5 * b - t * 2) + 0.02 * Math.sin(2 * b + t * 3))
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
    var e = root.face.eyeShape
    return e === "" || e === "wide" ? root.eyeStyle : e
  }

  function paintEyes(ctx, cx, cy, r) {
    var f = root.face
    // The cursor's gaze, mixed with the expression's own.
    var gzx = (root.still ? 0 : root.gazeX) * (1 - f.gazeLock) + f.gazeX
    var gzy = (root.still ? 0 : root.gazeY) * (1 - f.gazeLock) + f.gazeY
    var gx = gzx * r * 0.2
    var gy = gzy * r * 0.16
    var sp = r * 0.62
    var ey = cy - r * 0.08 + gy + f.eyeY * r
    var style = currentEyes()
    var col = root.rgba(root.featureColor, 1)
    ctx.fillStyle = col
    ctx.strokeStyle = col
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    var k = f.eyeScale
    for (var s = -1; s <= 1; s += 2) {
      var ex = cx + s * sp / 2 + gx
      var open = f.eyeOpen * (s < 0 ? f.eyeOpenL : f.eyeOpenR)
      var blink = Math.max(0.08, (root.still ? 1 : root.blink) * open)
      var eye = style
      // A nearly shut eye (a wink) reads better as a happy arc.
      if (open < 0.3 && (eye === "capsule" || eye === "dot" || eye === "pixel" || eye === "googly")) eye = "happy"
      if (eye === "capsule") {
        var w = r * 0.26 * k, h = r * 0.5 * blink * k
        roundRect(ctx, ex - w / 2, ey - h / 2, w, h, Math.min(w, h) / 2)
        ctx.fill()
      } else if (eye === "dot") {
        ctx.beginPath()
        ctx.ellipse(ex - r * 0.15 * k, ey - r * 0.15 * blink * k, r * 0.3 * k, r * 0.3 * blink * k)
        ctx.fill()
      } else if (eye === "pixel") {
        var p = r * 0.28 * k
        ctx.fillRect(ex - p / 2, ey - p * blink / 2, p, p * blink)
      } else if (eye === "sleepy") {
        ctx.lineWidth = r * 0.1
        ctx.beginPath()
        ctx.arc(ex, ey - r * 0.06, r * 0.17, Math.PI * 0.15, Math.PI * 0.85, false)
        ctx.stroke()
      } else if (eye === "closed") {
        ctx.lineWidth = r * 0.09
        ctx.beginPath()
        ctx.moveTo(ex - r * 0.14, ey + r * 0.04)
        ctx.quadraticCurveTo(ex, ey + r * 0.14, ex + r * 0.14, ey + r * 0.04)
        ctx.stroke()
      } else if (eye === "googly") {
        var er = r * 0.24 * k
        var ox = ex - gx * 0.5, oy = ey - gy * 0.5
        ctx.fillStyle = root.solid ? root.rgba(root.foreground, 1) : root.rgba(root.background, 0.9)
        ctx.beginPath()
        ctx.ellipse(ox - er, oy - er * blink, er * 2, er * 2 * blink)
        ctx.fill()
        ctx.fillStyle = col
        var pr = er * 0.5
        var px = ox + gzx * er * 0.45
        var py = oy + gzy * er * 0.45
        ctx.beginPath()
        ctx.ellipse(px - pr, py - pr * blink, pr * 2, pr * 2 * blink)
        ctx.fill()
      } else if (eye === "squint") { // > <
        ctx.lineWidth = r * 0.09
        ctx.beginPath()
        ctx.moveTo(ex - s * r * 0.12, ey - r * 0.1)
        ctx.lineTo(ex + s * r * 0.07, ey)
        ctx.lineTo(ex - s * r * 0.12, ey + r * 0.1)
        ctx.stroke()
      } else if (eye === "x") {
        ctx.lineWidth = r * 0.08
        ctx.beginPath()
        ctx.moveTo(ex - r * 0.11, ey - r * 0.11)
        ctx.lineTo(ex + r * 0.11, ey + r * 0.11)
        ctx.moveTo(ex + r * 0.11, ey - r * 0.11)
        ctx.lineTo(ex - r * 0.11, ey + r * 0.11)
        ctx.stroke()
      } else if (eye === "spiral") {
        ctx.lineWidth = r * 0.06
        ctx.beginPath()
        var a0 = root.phase * 4 * s
        for (var i = 0; i <= 36; i++) {
          var ang = a0 + s * i * 0.42
          var rad = r * 0.2 * i / 36
          var qx = ex + Math.cos(ang) * rad, qy = ey + Math.sin(ang) * rad
          if (i === 0) ctx.moveTo(qx, qy); else ctx.lineTo(qx, qy)
        }
        ctx.stroke()
      } else { // happy ^ ^
        ctx.lineWidth = r * 0.11
        ctx.beginPath()
        ctx.arc(ex, ey + r * 0.06, r * 0.17, Math.PI * 1.15, Math.PI * 1.85, false)
        ctx.stroke()
      }
    }

    // Brows: inner ends up when worried (browAngle 1), lifted when startled,
    // one raised when curious or thinking.
    if (f.browAlpha > 0.02) {
      if (f.browAlpha < 1) ctx.globalAlpha = f.browAlpha
      ctx.strokeStyle = col
      ctx.lineWidth = r * 0.08
      for (var b = -1; b <= 1; b += 2) {
        var bx = cx + b * sp / 2 + gx
        var lift = r * 0.1 * f.browLift + r * 0.08 * f.browAsym * b
        ctx.beginPath()
        ctx.moveTo(bx - b * r * 0.04, ey - r * (0.35 + 0.05 * f.browAngle) - lift)
        ctx.lineTo(bx + b * r * 0.16, ey - r * (0.35 - 0.05 * f.browAngle) - lift)
        ctx.stroke()
      }
      ctx.globalAlpha = 1
    }
    return { sp: sp, ey: ey, gx: gx, gy: gy }
  }

  function paintMouth(ctx, cx, r, eyes) {
    var f = root.face
    var m = root.mouthStyle
    if (f.mouthShape === "happy") { if (m === "none") m = "smile" }
    else if (f.mouthShape !== "") m = f.mouthShape
    if (m === "none") return
    var mo = f.mouthOpen
    var mx = cx + eyes.gx * 0.8 + f.mouthX * r
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
      var ow = r * 0.14 * (1 + 0.3 * mo), oh = r * 0.16 * (1 + 0.8 * mo)
      ctx.ellipse(mx - ow / 2, my + r * 0.03 - oh / 2, ow, oh)
      ctx.fill()
    } else if (m === "o-small") {
      ctx.ellipse(mx - r * 0.045, my - r * 0.03, r * 0.09, r * 0.1 + 0.02 * r * root.breathe)
      ctx.fill()
    } else if (m === "yawn") {
      var yw = r * 0.26, yh = r * (0.12 + 0.34 * mo)
      ctx.ellipse(mx - yw / 2, my - r * 0.06, yw, yh)
      ctx.fill()
    } else if (m === "grin") {
      ctx.moveTo(mx - r * 0.15, my - r * 0.05)
      ctx.arc(mx, my - r * 0.05, r * 0.15, Math.PI, 0, true)
      ctx.closePath()
      ctx.fill()
    } else if (m === "frown") {
      ctx.arc(mx, my + r * 0.1, r * 0.14, Math.PI * 1.2, Math.PI * 1.8, false)
      ctx.stroke()
    } else if (m === "cat") {
      ctx.arc(mx - r * 0.08, my - r * 0.04, r * 0.08, 0, Math.PI, false)
      ctx.moveTo(mx + r * 0.16, my - r * 0.04)
      ctx.arc(mx + r * 0.08, my - r * 0.04, r * 0.08, 0, Math.PI, false)
      ctx.stroke()
    } else if (m === "flat") {
      ctx.moveTo(mx - r * 0.1, my)
      if (f.mouthCurve === 0) ctx.lineTo(mx + r * 0.1, my)
      else ctx.quadraticCurveTo(mx, my + r * 0.12 * f.mouthCurve, mx + r * 0.1, my)
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

  // Small floating marks: "!" when worried, "z" when tired or asleep, and
  // the reactions' own ("?", "...", a sweat drop, dizzy stars).
  function paintMarks(ctx, S, cx, cy, r) {
    var f = root.face
    var mk = f.mark
    if (mk === "" || f.markAlpha <= 0.02) return
    var ink = root.rgba(root.foreground, 1)
    var fade = Math.min(1, f.markAlpha)
    ctx.fillStyle = ink
    ctx.textAlign = "center"
    ctx.textBaseline = "middle"
    if (fade < 1) ctx.globalAlpha = fade
    if (mk === "z" || mk === "zz") {
      var drift = (root.phase / (Math.PI * 2))
      var count = mk === "zz" ? 2 : 1
      for (var i = 0; i < count; i++) {
        var t = (drift + i * 0.5) % 1
        ctx.globalAlpha = (t < 0.7 ? 0.9 : (1 - t) * 3) * fade
        ctx.font = "bold " + Math.round(r * (0.32 + 0.12 * t)) + "px sans-serif"
        ctx.fillText("z", cx + r * (0.85 + 0.2 * t), cy - r * (0.65 + 0.45 * t))
      }
    } else if (mk === "!" || mk === "?") {
      ctx.font = "bold " + Math.round(r * 0.5) + "px sans-serif"
      ctx.fillText(mk, cx + r * 0.95, cy - r * 0.8 + Math.sin(root.phase * 3) * r * 0.04)
    } else if (mk === "...") {
      for (var d = 0; d < 3; d++) {
        var lit = (Math.floor(root.phase / (Math.PI * 2) * 12) % 4) > d
        ctx.globalAlpha = (lit || !root.animated ? 0.9 : 0.35) * fade
        ctx.beginPath()
        ctx.ellipse(cx + r * (0.7 + d * 0.2) - r * 0.06, cy - r * 0.95 - r * 0.06, r * 0.12, r * 0.12)
        ctx.fill()
      }
    } else if (mk === "sweat") {
      var sx0 = cx - r * 0.95, sy0 = cy - r * 0.55
      ctx.fillStyle = root.rgba(root.foreground, 0.85)
      ctx.beginPath()
      ctx.moveTo(sx0, sy0 - r * 0.2)
      ctx.quadraticCurveTo(sx0 + r * 0.13, sy0, sx0 + r * 0.1, sy0 + r * 0.06)
      ctx.arc(sx0, sy0 + r * 0.06, r * 0.1, 0, Math.PI, false)
      ctx.quadraticCurveTo(sx0 - r * 0.13, sy0, sx0, sy0 - r * 0.2)
      ctx.fill()
    } else if (mk === "stars") {
      ctx.font = "bold " + Math.round(r * 0.3) + "px sans-serif"
      for (var j = 0; j < 3; j++) {
        var a = root.phase * 3 + j * Math.PI * 2 / 3
        ctx.fillText("✦", cx + Math.cos(a) * r * 0.75, cy - r * 1.02 + Math.sin(a) * r * 0.16)
      }
    }
    ctx.globalAlpha = 1
  }

  // Where a framed chip looks, and how close: {x, y, z} in the same space as
  // cx / cy. Every chip zoom lives here.
  function frameFocus(framing, cx, cy, r) {
    // Face chips show the whole body (no crop); the chip look already drops
    // accessories and head extras so the eyes and mouth read clearly.
    if (framing === "eyes" || framing === "mouth") return { x: cx, y: cy, z: 1.0 }
    if (framing === "top") return { x: cx, y: headTop(cy, r, 1) + 0.12 * r, z: 1.35 }
    if (framing === "topRight") return { x: cx + 0.42 * r, y: cy - 0.62 * r, z: 1.7 }
    if (framing === "topLeft") return { x: cx - 0.42 * r, y: cy - 0.62 * r, z: 1.7 }
    return { x: cx, y: cy, z: 1.0 }
  }

  function paintPet(ctx, S) {
    ctx.reset()
    ctx.translate(0, S * 0.15)
    var cx = S / 2
    var r = S * 0.36
    var still = root.still
    // Leave headroom for anything that grows above the head. Chips always
    // use the tall frame, so every chip in a row has the same size.
    var tall = still || root.extraStyle !== "none" || root.headwear !== "" || root.accessory === "bow" || root.accessory === "flower"
    var f = root.face
    var cy = S / 2 + (tall ? S * 0.07 : 0) + (still ? 0 : root.hop * 2 + f.hop * S)
    if (tall) r = S * 0.34
    var grow = root.hovered && root.interactive && !still ? 1.04 : 1.0
    var br = still ? 0 : root.breathe
    var sq = still ? 0 : root.squash + f.squash
    var sx = (1 + 0.025 * br + 0.14 * sq) * grow
    var sy = (1 - 0.025 * br - 0.14 * sq) * grow
    var zoom = 1
    if (still) {
      var fo = frameFocus(root.framing, cx, cy, r)
      zoom = fo.z
      ctx.reset()
      ctx.translate(S / 2, S * 0.65)
      ctx.scale(fo.z, fo.z)
      ctx.translate(-fo.x, -fo.y)
    }
    var shapeOnly = root.framing === "silhouette"

    // Tilt, sideways shift and scale pivot on the base of the body, so hats
    // and ears follow the head. Marks are drawn after, upright.
    var moved = f.tilt !== 0 || f.shiftX !== 0 || f.scale !== 1
    if (moved) {
      var baseY = cy + r * 0.95 * sy
      ctx.save()
      ctx.translate(cx + f.shiftX * r, baseY)
      ctx.rotate(f.tilt)
      ctx.scale(f.scale, f.scale)
      ctx.translate(-cx, -baseY)
    }

    var fill = root.solid ? root.rgba(root.baseColor, 1) : root.rgba(root.baseColor, 0.16)

    // Ears, antenna and leaf sit behind the body so they read as growing out of it.
    paintExtra(ctx, cx, cy, r, sx, sy, root.solid ? fill : root.rgba(root.baseColor, 0.9))

    bodyPath(ctx, cx, cy, r, sx, sy)
    ctx.fillStyle = fill
    ctx.fill()
    if (!root.solid) {
      ctx.strokeStyle = root.rgba(root.baseColor, 0.95)
      ctx.lineWidth = S * 0.03 / zoom
      ctx.stroke()
    }
    if (shapeOnly) return

    var eyes = paintEyes(ctx, cx, cy, r)

    if (root.cheeks) {
      ctx.fillStyle = root.solid ? root.rgba(root.background, 0.18) : root.rgba(root.baseColor, 0.45)
      for (var s = -1; s <= 1; s += 2) {
        ctx.beginPath()
        ctx.ellipse(cx + s * eyes.sp * 0.78 + eyes.gx * 0.6 - r * 0.13, eyes.ey + r * 0.24, r * 0.26, r * 0.14)
        ctx.fill()
      }
    }
    if (f.blush > 0.02) {
      ctx.fillStyle = "rgba(243,139,168," + Math.min(1, f.blush) * 0.55 + ")"
      for (var c = -1; c <= 1; c += 2) {
        ctx.beginPath()
        ctx.ellipse(cx + c * eyes.sp * 0.78 + eyes.gx * 0.6 - r * 0.11, eyes.ey + r * 0.25, r * 0.22, r * 0.11)
        ctx.fill()
      }
    }

    paintMouth(ctx, cx, r, eyes)
    paintAccessory(ctx, cx, cy, r, sx, sy, eyes)
    paintHeadwear(ctx, cx, cy, r, sx, sy)
    if (moved) ctx.restore()
    if (root.showMarks && !still) paintMarks(ctx, S, cx, cy, r)
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
