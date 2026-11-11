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
// look: { body, eyes, mouth, extra, accessory, cheeks, style, color,
//         eyeSize, mouthSize }
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
  // whole live pet; silhouette | eyes | mouth | top | topLeft | topRight | neck.
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
  // Eye and mouth size, 0.7..1.4 (1 when missing or hand-edited into junk).
  function scaleOpt(name) {
    var v = Number(opt(name, 1))
    return isFinite(v) ? Math.max(0.7, Math.min(1.4, v)) : 1
  }
  readonly property real eyeSize: scaleOpt("eyeSize")
  readonly property real mouthSize: scaleOpt("mouthSize")

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
  // The day to dress for; null is today (the dev harness picks a holiday).
  property var day: null
  readonly property string seasonHat: {
    if (!root.seasonal) return ""
    var stamp = root.dayStamp
    var d = root.day || new Date()
    var m = d.getMonth() + 1, day = d.getDate()
    if (m === 12 && (day === 24 || day === 25)) return "santa"
    if ((m === 12 && day === 31) || (m === 1 && day === 1)) return "party"
    return ""
  }
  // What sits on top of the head: the seasonal hat replaces the look's own
  // (top hat, beanie or crown) for the day, and either one hides the extras
  // that grow from the crown of the head (antenna, leaf, tuft, unicorn horn,
  // halo). Ears and horns stay: they come out on each side of a hat.
  readonly property string headwear: root.seasonHat !== "" ? root.seasonHat
    : (["hat", "beanie", "crown"].indexOf(root.accessory) >= 0 ? root.accessory : "")
  // Scarf and bow tie: worn at the bottom of the body, with anything on top.
  readonly property bool neckwear: root.accessory === "scarf" || root.accessory === "bowtie"
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
    } else if (shape === "cloud") {
      cloudPath(ctx, cx, cy, r, sx, sy, t)
    } else if (shape === "egg") {
      // An ellipse whose width grows downward: narrow top, round heavy base.
      for (var e = 0; e <= 72; e++) {
        var ea = e / 72 * Math.PI * 2
        var ec = Math.cos(ea), es = Math.sin(ea)
        var ex = cx + r * 0.84 * sx * ec * (1 + 0.17 * es)
        var ey = cy + r * sy * (-0.04 + 0.98 * es)
        if (e === 0) ctx.moveTo(ex, ey); else ctx.lineTo(ex, ey)
      }
      ctx.closePath()
    } else if (shape === "mochi") {
      // A soft dome slumped on a flat base, spreading a little toward it like
      // a daifuku sitting on a plate. The dome jiggles with the wobble clock.
      var eq = cy + r * 0.22 * sy
      var dome = r * 0.97 * sy * (1 + 0.025 * root.face.wobble * Math.sin(t * 3))
      for (var m = 0; m <= 72; m++) {
        var ma = m / 72 * Math.PI * 2
        var mc = Math.cos(ma), ms = Math.sin(ma)
        var mx, my
        if (ms < 0) {
          mx = cx + r * 1.04 * sx * mc
          my = eq + dome * ms
        } else { // superellipse quadrant: flat bottom, full lower sides
          mx = cx + r * 1.04 * (1 + 0.05 * ms) * sx * Math.sign(mc) * Math.pow(Math.abs(mc), 0.5)
          my = eq + r * 0.66 * sy * Math.pow(ms, 0.5)
        }
        if (m === 0) ctx.moveTo(mx, my); else ctx.lineTo(mx, my)
      }
      ctx.closePath()
    } else if (shape === "bean") {
      // A kidney bean lying down: an oval with a dent under the belly, so
      // it rests on its two rounded ends.
      for (var v = 0; v <= 90; v++) {
        var va = v / 90 * Math.PI * 2
        var vc = Math.cos(va), vs = Math.sin(va)
        var uy = 0.8 * vs
        if (vs > 0) uy -= 0.3 * vs * Math.exp(-(vc * vc) / 0.3)
        var vx = cx + r * sx * 1.06 * vc
        var vy = cy + r * sy * (0.07 + uy)
        if (v === 0) ctx.moveTo(vx, vy); else ctx.lineTo(vx, vy)
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

  // Cloud puffs as [x, y, radius] in units of r, left to right over the top.
  // The outline runs along each puff's outer arc, from where it meets the
  // previous puff to where it meets the next, then closes with a flat base
  // (the end puffs share their lowest point).
  readonly property var cloudPuffs: [[-0.7, 0.42, 0.4], [-0.43, -0.14, 0.42], [0, -0.36, 0.5], [0.43, -0.14, 0.42], [0.7, 0.42, 0.4]]

  function cloudPath(ctx, cx, cy, r, sx, sy, t) {
    var p = root.cloudPuffs
    var n = p.length
    var c = []
    for (var i = 0; i < n; i++) {
      // The top puffs swell in turn; the end puffs keep the base level.
      var swell = i === 0 || i === n - 1 ? 0 : 0.03 * root.face.wobble * Math.sin(t * 2 + i * 1.9)
      c.push({ x: p[i][0], y: p[i][1], r: p[i][2] * (1 + swell) })
    }
    // Where two neighbouring puffs cross, on the outside of the cloud.
    function meet(a, b) {
      var dx = b.x - a.x, dy = b.y - a.y
      var d = Math.sqrt(dx * dx + dy * dy)
      var along = (a.r * a.r - b.r * b.r + d * d) / (2 * d)
      var h = Math.sqrt(Math.max(0, a.r * a.r - along * along))
      var mx = a.x + along * dx / d, my = a.y + along * dy / d
      var p1 = { x: mx - h * dy / d, y: my + h * dx / d }
      var p2 = { x: mx + h * dy / d, y: my - h * dx / d }
      var d1 = p1.x * p1.x + (p1.y - 0.2) * (p1.y - 0.2)
      var d2 = p2.x * p2.x + (p2.y - 0.2) * (p2.y - 0.2)
      return d1 > d2 ? p1 : p2
    }
    var meets = []
    for (var j = 0; j < n - 1; j++) meets.push(meet(c[j], c[j + 1]))
    var first = true
    for (var k = 0; k < n; k++) {
      var q = c[k]
      // The end puffs start / stop at their lowest point (angle pi / 2).
      var from = k === 0 ? Math.PI / 2 : Math.atan2(meets[k - 1].y - q.y, meets[k - 1].x - q.x)
      var to = k === n - 1 ? Math.PI / 2 : Math.atan2(meets[k].y - q.y, meets[k].x - q.x)
      while (to <= from) to += Math.PI * 2
      var steps = Math.max(4, Math.ceil((to - from) / 0.2))
      for (var s = 0; s <= steps; s++) {
        var a = from + (to - from) * s / steps
        var px = cx + r * sx * (q.x + q.r * Math.cos(a))
        var py = cy + r * sy * (q.y + q.r * Math.sin(a))
        if (first) { ctx.moveTo(px, py); first = false } else ctx.lineTo(px, py)
      }
    }
    ctx.closePath()
  }

  // Where things sit on each body's head, in units of r: how high the top
  // is, how far apart side pieces (ears, horns, bow, flower) go, and how big
  // hats are, so a narrow egg top or a puffy cloud still wears them well.
  // chin: the lowest a mouth may reach in the middle (the bean's dent, the
  // ghost's waves), so big mouths and yawns stay on the body. crest: the
  // body's real top, which the headphones band clears; side: its half width
  // at ear height, where the ear cups go; neck: where a scarf or bow tie
  // starts, low on the body but under the mouth (it also raises the chin).
  readonly property var headFit: ({
    drop: { top: 1.05, spread: 1, hat: 1, chin: 0.8, crest: 1.12, side: 0.88, neck: 0.5 },
    ghost: { top: 0.92, spread: 1, hat: 1, chin: 0.62, crest: 1.1, side: 1, neck: 0.44 },
    cloud: { top: 0.84, spread: 1, hat: 0.9, chin: 0.72, crest: 0.86, side: 0.85, neck: 0.42 },
    egg: { top: 1.0, spread: 0.72, hat: 0.82, chin: 0.8, crest: 1.02, side: 0.82, neck: 0.46 },
    mochi: { top: 0.75, spread: 1.04, hat: 1, chin: 0.78, crest: 0.75, side: 0.97, neck: 0.44 },
    bean: { top: 0.74, spread: 1, hat: 1, chin: 0.47, crest: 0.73, side: 1.04, neck: 0.38 }
  })
  readonly property var head: root.headFit[root.bodyShape] || { top: 0.92, spread: 1, hat: 1, chin: 0.8, crest: 1, side: 1, neck: 0.44 }

  function headTop(cy, r, sy) {
    return cy - r * sy * root.head.top
  }

  function paintExtra(ctx, cx, cy, r, sx, sy, fill) {
    var e = root.extraStyle
    if (e === "none") return
    // The ones growing from the crown of the head hide under a hat.
    if (root.headwear !== "" && ["antenna", "leaf", "tuft", "unicorn", "halo"].indexOf(e) >= 0) return
    var topY = headTop(cy, r, sy)
    var trim = root.rgba(root.trimColor, 1)
    ctx.fillStyle = fill
    ctx.strokeStyle = fill
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
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
        var bx = cx + s * r * 0.55 * root.head.spread * sx
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
    } else if (e === "bunnyEars") {
      // Two long ears splaying out a little, the right one's tip leaning
      // out, with a lighter inside (the base hides behind the body).
      var inner = root.solid ? root.rgba(root.background, 0.28) : root.rgba(root.background, 0.4)
      var flop = Math.sin(root.phase * 2) * 0.04
      for (var b = -1; b <= 1; b += 2) {
        ctx.save()
        ctx.translate(cx + b * r * 0.3 * root.head.spread * sx, topY + r * 0.16)
        ctx.rotate(b * (0.2 + flop))
        bunnyEar(ctx, r, b > 0)
        ctx.fillStyle = fill
        ctx.fill()
        ctx.save()
        ctx.translate(0, -r * 0.04)
        ctx.scale(0.5, 0.82)
        bunnyEar(ctx, r, b > 0)
        ctx.restore()
        ctx.fillStyle = inner
        ctx.fill()
        ctx.restore()
      }
    } else if (e === "tuft") {
      // Three strands of hair curling to one side, swaying a little. They
      // grow from the body's real top, so an outline pet shows no roots.
      var crest = cy - r * root.head.crest * sy
      var lean = Math.sin(root.phase * 2) * 0.05
      var strands = [[-0.13, 0.26, -0.5], [0, 0.42, 0.25], [0.13, 0.3, 0.75]]
      for (var t = 0; t < strands.length; t++) {
        var st = strands[t]
        ctx.save()
        ctx.translate(cx + st[0] * r, crest + r * 0.08)
        ctx.rotate(st[2] * 0.5 + lean)
        ctx.beginPath()
        ctx.moveTo(-r * 0.11, 0)
        ctx.quadraticCurveTo(-r * 0.1, -r * (0.16 + st[1] * 0.7), r * 0.14, -r * (0.16 + st[1]))
        ctx.quadraticCurveTo(r * 0.04, -r * (0.1 + st[1] * 0.5), r * 0.11, 0)
        ctx.closePath()
        ctx.fill()
        ctx.restore()
      }
    } else if (e === "unicorn") {
      // A spiral horn, in the trim color so it reads apart from the body.
      ctx.save()
      ctx.translate(cx + r * 0.04, cy - r * (root.head.crest - 0.1) * sy)
      ctx.rotate(0.14)
      var hw = r * 0.16, hl = r * 0.78
      ctx.fillStyle = trim
      ctx.beginPath()
      ctx.moveTo(-hw, 0)
      ctx.quadraticCurveTo(-hw * 0.5, -hl * 0.6, 0, -hl)
      ctx.quadraticCurveTo(hw * 0.5, -hl * 0.6, hw, 0)
      ctx.closePath()
      ctx.fill()
      ctx.clip()
      ctx.strokeStyle = root.rgba(root.baseColor, 0.75)
      ctx.lineWidth = r * 0.045
      ctx.beginPath()
      for (var g = 1; g <= 3; g++) {
        var gy = -hl * (0.04 + 0.2 * g)
        ctx.moveTo(-hw, gy + r * 0.04)
        ctx.lineTo(hw, gy - r * 0.05)
      }
      ctx.stroke()
      ctx.restore()
    } else if (e === "halo") {
      // A ring floating over the head, bobbing gently.
      var hy = topY - r * (0.34 + 0.03 * Math.sin(root.phase * 2))
      ctx.strokeStyle = trim
      ctx.lineWidth = r * 0.08
      ctx.beginPath()
      ctx.ellipse(cx - r * 0.36, hy - r * 0.1, r * 0.72, r * 0.2)
      ctx.stroke()
    }
  }

  // One bunny ear standing on its base at (0, 0); bent leans its tip out.
  function bunnyEar(ctx, r, bent) {
    var w = r * 0.15, h = r * 0.82
    ctx.beginPath()
    ctx.moveTo(-w * 0.7, 0)
    ctx.bezierCurveTo(-w * 1.15, -h * 0.45, -w * 0.9, -h, bent ? w * 0.2 : 0, -h)
    ctx.bezierCurveTo(bent ? w * 1.4 : w * 0.9, -h, w * 1.15, -h * 0.45, w * 0.7, 0)
    ctx.closePath()
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

  // Eyes drawn from the look (they grow when startled), as opposed to the
  // expressions' own arcs, crosses and spirals.
  readonly property var lookEyes: ({ capsule: 1, dot: 1, googly: 1, pixel: 1, star: 1, sparkle: 1, cyclops: 1, heart: 1 })
  // A single eye in the middle: expressions draw one bigger eye and one brow,
  // and a wink (either eye shut) closes it.
  readonly property bool oneEye: root.eyeStyle === "cyclops"
  readonly property string tongueColor: "#f38ba8"

  function disc(ctx, x, y, rad) {
    ctx.beginPath()
    ctx.ellipse(x - rad, y - rad, rad * 2, rad * 2)
    ctx.fill()
  }

  // topY: the top of the head; brows stay below it.
  function paintEyes(ctx, cx, cy, r, topY) {
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
    // Eye whites and glints: light on a solid pet, dark on an outline one.
    var hi = root.solid ? root.rgba(root.foreground, 1) : root.rgba(root.background, 0.9)
    ctx.fillStyle = col
    ctx.strokeStyle = col
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    // The look's eye size times the expression's (startled), capped so the
    // biggest eyes still fit every body. Expression eyes follow the size more
    // gently; a cyclops's single one is drawn bigger.
    var size = root.eyeSize
    var k = Math.min(f.eyeScale * size, 1.6)
    var kx = (1 + 0.6 * (size - 1)) * (root.oneEye ? 1.45 : 1)
    // The cyclops's eyeball turns only halfway toward the gaze (its pupil
    // does the rest) and sits a bit higher, clear of the mouth.
    var oy = root.oneEye ? ey - gy * 0.5 - r * 0.04 : ey
    var sides = root.oneEye ? [0] : [-1, 1]
    for (var i = 0; i < sides.length; i++) {
      var s = sides[i]
      var ex = cx + s * sp / 2 + gx
      var open = f.eyeOpen * (s < 0 ? f.eyeOpenL : (s > 0 ? f.eyeOpenR : Math.min(f.eyeOpenL, f.eyeOpenR)))
      var blink = Math.max(0.08, (root.still ? 1 : root.blink) * open)
      var eye = style
      // A nearly shut eye (a wink) reads better as a happy arc.
      if (open < 0.3 && root.lookEyes[eye]) eye = "happy"
      if (root.lookEyes[eye]) {
        paintLookEye(ctx, eye, ex, ey, r, k, blink, gx, gy, gzx, gzy, col, hi)
      } else {
        var ox = root.oneEye ? cx + gx * 0.5 : ex
        ctx.save()
        ctx.translate(ox, oy)
        ctx.scale(kx, kx)
        ctx.translate(-ox, -oy)
        paintExpressionEye(ctx, eye, ox, oy, r, s)
        ctx.restore()
      }
    }

    // Brows: inner ends up when worried (browAngle 1), lifted when startled,
    // one raised when curious or thinking. They sit higher over bigger eyes.
    if (f.browAlpha > 0.02) {
      if (f.browAlpha < 1) ctx.globalAlpha = f.browAlpha
      ctx.strokeStyle = col
      ctx.lineWidth = r * 0.08
      var raise = r * 0.2 * (size - 1)
      if (root.oneEye) {
        // One brow: worried arches it, cross dips it, curious tilts it.
        var bc = cx + gx * 0.5
        var by = Math.max(oy - r * 0.44 - raise - r * 0.1 * f.browLift, topY + r * 0.12)
        var bw = r * 0.2 * (1 + 0.5 * (size - 1))
        ctx.beginPath()
        ctx.moveTo(bc - bw, by + r * 0.06 * f.browAsym)
        ctx.lineTo(bc, by - r * 0.07 * f.browAngle)
        ctx.lineTo(bc + bw, by - r * 0.06 * f.browAsym)
        ctx.stroke()
      } else {
        for (var b = -1; b <= 1; b += 2) {
          var bx = cx + b * sp / 2 + gx
          var lift = r * 0.1 * f.browLift + r * 0.08 * f.browAsym * b + raise
          var y1 = ey - r * (0.35 + 0.05 * f.browAngle) - lift
          var y2 = ey - r * (0.35 - 0.05 * f.browAngle) - lift
          // Lowered as a whole (keeping its slant) when it would leave the head.
          var drop = Math.max(0, topY + r * 0.16 - Math.min(y1, y2))
          ctx.beginPath()
          ctx.moveTo(bx - b * r * 0.04, y1 + drop)
          ctx.lineTo(bx + b * r * 0.16, y2 + drop)
          ctx.stroke()
        }
      }
      ctx.globalAlpha = 1
    }
    // The face (mouth, cheeks, glasses) follows the cyclops's eyeball.
    return { sp: sp, ey: root.oneEye ? ey - gy * 0.5 : ey, gx: gx, gy: gy }
  }

  // One of the look's eyes at (ex, ey); k is its size, blink how open it is.
  function paintLookEye(ctx, eye, ex, ey, r, k, blink, gx, gy, gzx, gzy, col, hi) {
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
    } else if (eye === "googly") {
      var er = r * 0.24 * k
      var ox = ex - gx * 0.5, oy = ey - gy * 0.5
      ctx.fillStyle = hi
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
    } else if (eye === "star") {
      // Five points, softened by a thin stroke of the same ink.
      var so = r * 0.2 * k, si = so * 0.48
      var sy = ey + r * 0.02 * k
      ctx.lineWidth = r * 0.05
      ctx.beginPath()
      for (var n = 0; n < 10; n++) {
        var a = -Math.PI / 2 + n * Math.PI / 5
        var sr = n % 2 === 0 ? so : si
        if (n === 0) ctx.moveTo(ex + Math.cos(a) * sr, sy + Math.sin(a) * sr * blink)
        else ctx.lineTo(ex + Math.cos(a) * sr, sy + Math.sin(a) * sr * blink)
      }
      ctx.closePath()
      ctx.fill()
      ctx.stroke()
    } else if (eye === "sparkle") {
      // A tall anime eye with two glints (gone while it blinks).
      var sw = r * 0.17 * k, sh = r * 0.23 * k
      ctx.beginPath()
      ctx.ellipse(ex - sw, ey - sh * blink, sw * 2, sh * 2 * blink)
      ctx.fill()
      if (blink > 0.5) {
        ctx.fillStyle = hi
        disc(ctx, ex - sw * 0.34, ey - sh * 0.38 * blink, sw * 0.36)
        disc(ctx, ex + sw * 0.36, ey + sh * 0.4 * blink, sw * 0.17)
        ctx.fillStyle = col
      }
    } else if (eye === "heart") {
      // Beats softly while the pet is animated.
      var beat = root.animated && !root.still ? 1 + 0.08 * Math.pow(Math.max(0, Math.sin(root.phase * 6)), 8) : 1
      var hw = r * 0.19 * k * beat, hh = r * 0.17 * k * beat * blink
      var hy = ey + r * 0.01 * k
      ctx.beginPath()
      ctx.moveTo(ex, hy + hh)
      ctx.bezierCurveTo(ex - 0.3 * hw, hy + 0.75 * hh, ex - hw, hy + 0.3 * hh, ex - hw, hy - 0.3 * hh)
      ctx.bezierCurveTo(ex - hw, hy - 0.9 * hh, ex - 0.3 * hw, hy - 1.1 * hh, ex, hy - 0.55 * hh)
      ctx.bezierCurveTo(ex + 0.3 * hw, hy - 1.1 * hh, ex + hw, hy - 0.9 * hh, ex + hw, hy - 0.3 * hh)
      ctx.bezierCurveTo(ex + hw, hy + 0.3 * hh, ex + 0.3 * hw, hy + 0.75 * hh, ex, hy + hh)
      ctx.fill()
    } else if (eye === "cyclops") {
      // One big eyeball; the pupil looks around inside it.
      var cr = r * 0.29 * k
      var cx0 = ex - gx * 0.5, cy0 = ey - gy * 0.5 - r * 0.04
      ctx.fillStyle = hi
      ctx.beginPath()
      ctx.ellipse(cx0 - cr, cy0 - cr * blink, cr * 2, cr * 2 * blink)
      ctx.fill()
      // An outline pet's eyeball is dark on a dark body: rim it in ink.
      if (!root.solid) {
        ctx.lineWidth = r * 0.05
        ctx.stroke()
      }
      ctx.fillStyle = col
      var ir = cr * 0.52
      var ix = cx0 + gzx * cr * 0.4, iy = cy0 + gzy * cr * 0.4 * blink
      ctx.beginPath()
      ctx.ellipse(ix - ir, iy - ir * blink, ir * 2, ir * 2 * blink)
      ctx.fill()
      if (blink > 0.5) {
        ctx.fillStyle = hi
        disc(ctx, ix - ir * 0.36, iy - ir * 0.4, ir * 0.28)
        ctx.fillStyle = col
      }
    }
  }

  // The expressions' own eyes, drawn at size 1 (paintEyes scales them).
  // s: -1 left, 1 right, 0 the cyclops's single eye.
  function paintExpressionEye(ctx, eye, ex, ey, r, s) {
    if (eye === "sleepy") {
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
    } else if (eye === "squint") { // > <
      ctx.lineWidth = r * 0.09
      ctx.beginPath()
      if (s === 0) { // one eye squeezed shut: ><
        for (var d = -1; d <= 1; d += 2) {
          ctx.moveTo(ex + d * r * 0.19, ey - r * 0.09)
          ctx.lineTo(ex + d * r * 0.06, ey)
          ctx.lineTo(ex + d * r * 0.19, ey + r * 0.09)
        }
      } else {
        ctx.moveTo(ex - s * r * 0.12, ey - r * 0.1)
        ctx.lineTo(ex + s * r * 0.07, ey)
        ctx.lineTo(ex - s * r * 0.12, ey + r * 0.1)
      }
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
      var dir = s || 1
      ctx.lineWidth = r * 0.06
      ctx.beginPath()
      var a0 = root.phase * 4 * dir
      for (var i = 0; i <= 36; i++) {
        var ang = a0 + dir * i * 0.42
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

  // How far each mouth reaches below its anchor, in units of r.
  function mouthDepth(m, mo) {
    if (m === "o") return 0.03 + 0.08 * (1 + 0.8 * mo)
    if (m === "yawn") return 0.06 + 0.34 * mo
    if (m === "fang") return 0.18
    if (m === "tongue") return 0.16
    if (m === "grin") return 0.1
    if (m === "o-small") return 0.08
    return 0.06
  }

  function paintMouth(ctx, cx, r, eyes, chinY) {
    var f = root.face
    var m = root.mouthStyle
    if (f.mouthShape === "happy") { if (m === "none") m = "smile" }
    else if (f.mouthShape !== "") m = f.mouthShape
    if (m === "none") return
    var mo = f.mouthOpen
    var mx = cx + eyes.gx * 0.8 + f.mouthX * r
    // Bigger eyes (and the cyclops's) push the mouth down a little.
    var my = eyes.ey + r * (0.38 + 0.1 * (root.eyeSize - 1) + (root.oneEye ? 0.08 : 0))
    // The look's mouth size scales every mouth, the reactions' too. A mouth
    // that would hang past the chin shrinks a little, then moves up.
    var ms = root.mouthSize
    var depth = root.mouthDepth(m, mo) * r
    if (my + depth * ms > chinY) {
      ms = Math.max(Math.min(0.75, ms), (chinY - my) / depth)
      my = Math.min(my, chinY - depth * ms)
    }
    var col = root.rgba(root.featureColor, 1)
    ctx.save()
    if (ms !== 1) {
      ctx.translate(mx, my)
      ctx.scale(ms, ms)
      ctx.translate(-mx, -my)
    }
    ctx.strokeStyle = col
    ctx.fillStyle = col
    ctx.lineWidth = r * 0.08
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
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
      // A big open smile, with a tongue at the bottom.
      ctx.moveTo(mx - r * 0.15, my - r * 0.05)
      ctx.arc(mx, my - r * 0.05, r * 0.15, Math.PI, 0, true)
      ctx.closePath()
      ctx.fill()
      ctx.clip()
      ctx.fillStyle = root.tongueColor
      root.disc(ctx, mx, my + r * 0.12, r * 0.09)
    } else if (m === "fang") {
      // A small smile with one little fang hanging from it (a light tooth
      // with an ink rim, so it reads as a tooth and not a blot).
      var fr = r * 0.14, fc = my - r * 0.08
      var a1 = Math.PI * 0.2, a2 = Math.PI * 0.42
      var x1 = mx + Math.cos(a1) * fr, y1 = fc + Math.sin(a1) * fr
      var x2 = mx + Math.cos(a2) * fr, y2 = fc + Math.sin(a2) * fr
      ctx.moveTo(x1, y1)
      ctx.lineTo((x1 + x2) / 2 + r * 0.01, Math.max(y1, y2) + r * 0.12)
      ctx.lineTo(x2, y2)
      ctx.closePath()
      ctx.fillStyle = root.solid ? root.rgba(root.foreground, 1) : root.rgba(root.background, 0.9)
      ctx.fill()
      ctx.lineWidth = r * 0.03
      ctx.stroke()
      ctx.beginPath()
      ctx.lineWidth = r * 0.08
      ctx.arc(mx, fc, fr, Math.PI * 0.2, Math.PI * 0.8, false)
      ctx.stroke()
    } else if (m === "tongue") {
      // A smile with the tongue sticking out from under it.
      var tw = r * 0.08, ty = my + r * 0.03
      ctx.moveTo(mx - tw, ty)
      ctx.lineTo(mx - tw, ty + r * 0.05)
      ctx.arc(mx, ty + r * 0.05, tw, Math.PI, 0, true)
      ctx.lineTo(mx + tw, ty)
      ctx.closePath()
      ctx.fillStyle = root.tongueColor
      ctx.fill()
      ctx.lineWidth = r * 0.035
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(mx, ty + r * 0.03)
      ctx.lineTo(mx, ty + r * 0.08)
      ctx.lineWidth = r * 0.025
      ctx.stroke()
      ctx.beginPath()
      ctx.lineWidth = r * 0.08
      ctx.arc(mx, my - r * 0.1, r * 0.16, Math.PI * 0.18, Math.PI * 0.82, false)
      ctx.stroke()
    } else if (m === "smirk") {
      // A sideways half smile: flat on the left, curling up on the right.
      ctx.moveTo(mx - r * 0.1, my + r * 0.02)
      ctx.quadraticCurveTo(mx + r * 0.06, my + r * 0.06, mx + r * 0.14, my - r * 0.05)
      // and a dimple at the curl
      ctx.moveTo(mx + r * 0.11, my - r * 0.09)
      ctx.quadraticCurveTo(mx + r * 0.16, my - r * 0.07, mx + r * 0.17, my - r * 0.02)
      ctx.stroke()
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
    ctx.restore()
  }

  // Glasses, bow, flower, headphones and neckwear; hats and the crown are
  // drawn by paintHeadwear (over the headphones band, so a seasonal hat sits
  // on top of it).
  function paintAccessory(ctx, cx, cy, r, sx, sy, eyes) {
    var a = root.accessory
    var ink = root.rgba(root.featureColor, 1)
    if (a === "headphones") paintHeadphones(ctx, cx, cy, r, sx, sy)
    else if (a === "scarf") paintScarf(ctx, cx, cy, r, sx, sy)
    else if (a === "bowtie") paintBowtie(ctx, cx, cy, r, sx, sy)
    if (a === "glasses" && root.oneEye) {
      // One round lens around the cyclops's eye, with short side arms.
      ctx.strokeStyle = ink
      ctx.lineWidth = r * 0.07
      var lx = cx + eyes.gx * 0.5, ly = eyes.ey - r * 0.04, lr = r * (0.29 * root.eyeSize + 0.07)
      ctx.beginPath()
      ctx.ellipse(lx - lr, ly - lr, lr * 2, lr * 2)
      ctx.moveTo(lx - lr, ly - r * 0.04)
      ctx.lineTo(lx - lr - r * 0.16, ly - r * 0.08)
      ctx.moveTo(lx + lr, ly - r * 0.04)
      ctx.lineTo(lx + lr + r * 0.16, ly - r * 0.08)
      ctx.stroke()
    } else if (a === "glasses") {
      ctx.strokeStyle = ink
      ctx.lineWidth = r * 0.07
      // Grow with the eyes, a little less so the lenses never touch.
      var gr = r * 0.25 * (1 + 0.45 * (root.eyeSize - 1))
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
      var bx = cx + r * 0.58 * root.head.spread * sx, by = headTop(cy, r, sy) + r * 0.22
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
      var fx = cx - r * 0.55 * root.head.spread * sx, fy = headTop(cy, r, sy) + r * 0.25
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

  // A band over the head (clearing its real top) and a cup on each side at
  // ear height, where the body is widest; ears and horns poke out past it.
  function paintHeadphones(ctx, cx, cy, r, sx, sy) {
    var hf = root.head
    var trim = root.rgba(root.trimColor, 1)
    var cupY = cy - r * 0.12 * sy
    var cupW = r * 0.24, cupH = r * 0.44 * sy
    var reach = r * hf.side * sx
    var baseY = cupY - cupH * 0.25
    var rise = baseY - (cy - r * (hf.crest + 0.1) * sy)
    ctx.strokeStyle = trim
    ctx.lineCap = "round"
    ctx.lineWidth = r * 0.09
    ctx.beginPath()
    for (var i = 0; i <= 32; i++) {
      var a = Math.PI + Math.PI * i / 32
      var x = cx + (reach - r * 0.03) * Math.cos(a), y = baseY + rise * Math.sin(a)
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
    }
    ctx.stroke()
    ctx.fillStyle = trim
    for (var s = -1; s <= 1; s += 2) {
      roundRect(ctx, cx + s * reach - cupW / 2, cupY - cupH / 2, cupW, cupH, cupW / 2)
      ctx.fill()
    }
    // The pads' inner edge, in the body color.
    ctx.fillStyle = root.rgba(root.baseColor, 0.85)
    for (var p = -1; p <= 1; p += 2) {
      ctx.beginPath()
      ctx.ellipse(cx + p * (reach + cupW * 0.08) - r * 0.04, cupY - cupH * 0.28, r * 0.08, cupH * 0.56)
      ctx.fill()
    }
  }

  // Neckwear sits low on the body, under the mouth (paintPet raises the chin
  // to keep big mouths off it).
  function neckY(cy, r, sy) { return cy + r * root.head.neck * sy }

  // A band wrapped around the lower body (clipped to it, so it follows every
  // silhouette), knotted on one side with two ends hanging over the edge.
  function paintScarf(ctx, cx, cy, r, sx, sy) {
    var trim = root.rgba(root.trimColor, 1)
    var seam = root.rgba(root.background, 0.22)
    var top = neckY(cy, r, sy)
    var th = r * 0.26 * sy, sag = r * 0.1 * sy, wide = r * 1.3 * sx
    ctx.save()
    bodyPath(ctx, cx, cy, r, sx, sy)
    ctx.clip()
    ctx.beginPath()
    ctx.moveTo(cx - wide, top - sag * 0.4)
    ctx.quadraticCurveTo(cx, top + sag, cx + wide, top - sag * 0.4)
    ctx.lineTo(cx + wide, top + th - sag * 0.4)
    ctx.quadraticCurveTo(cx, top + th + sag, cx - wide, top + th - sag * 0.4)
    ctx.closePath()
    ctx.fillStyle = trim
    ctx.fill()
    ctx.restore()

    // The two ends flare out from a knot on one side, swinging a little
    // with the wobble; a stripe of the body color near each fringe.
    var kx = cx + r * 0.42 * sx, ky = top + th * 0.5 + sag * 0.2
    var swing = Math.sin(root.phase * 2) * 0.05
    var ends = [[-0.38, 0.5], [0.06, 0.6]] // angle, length
    ctx.lineJoin = "round"
    for (var i = 0; i < ends.length; i++) {
      ctx.save()
      ctx.translate(kx, ky)
      ctx.rotate(ends[i][0] + swing)
      var len = r * ends[i][1] * sy
      ctx.beginPath()
      ctx.moveTo(-r * 0.12, 0)
      ctx.lineTo(-r * 0.16, len)
      ctx.lineTo(r * 0.16, len)
      ctx.lineTo(r * 0.12, 0)
      ctx.closePath()
      ctx.fillStyle = trim
      ctx.fill()
      ctx.strokeStyle = seam
      ctx.lineWidth = r * 0.03
      ctx.stroke()
      ctx.fillStyle = root.rgba(root.baseColor, 0.7)
      ctx.fillRect(-r * 0.155, len - r * 0.17, r * 0.31, r * 0.07)
      ctx.beginPath()
      for (var f = -1; f <= 1; f++) {
        ctx.moveTo(f * r * 0.1, len)
        ctx.lineTo(f * r * 0.1, len + r * 0.07)
      }
      ctx.strokeStyle = trim
      ctx.lineWidth = r * 0.04
      ctx.stroke()
      ctx.restore()
    }
    ctx.fillStyle = trim
    ctx.strokeStyle = seam
    ctx.lineWidth = r * 0.03
    ctx.beginPath()
    ctx.ellipse(kx - r * 0.17, ky - r * 0.15, r * 0.34, r * 0.3)
    ctx.fill()
    ctx.stroke()
  }

  // A bow tie in the middle, just under where the scarf would start.
  function paintBowtie(ctx, cx, cy, r, sx, sy) {
    var trim = root.rgba(root.trimColor, 1)
    var bx = cx, by = neckY(cy, r, sy) + r * 0.16 * sy
    var bw = r * 0.38 * sx, bh = r * 0.2 * sy
    ctx.fillStyle = trim
    ctx.strokeStyle = trim
    ctx.lineJoin = "round"
    ctx.lineWidth = r * 0.06
    for (var w = -1; w <= 1; w += 2) {
      ctx.beginPath()
      ctx.moveTo(bx, by)
      ctx.lineTo(bx + w * bw, by - bh)
      ctx.quadraticCurveTo(bx + w * bw * 1.12, by, bx + w * bw, by + bh)
      ctx.closePath()
      ctx.fill()
      ctx.stroke()
    }
    roundRect(ctx, bx - r * 0.1, by - r * 0.11 * sy, r * 0.2, r * 0.22 * sy, r * 0.06)
    ctx.fill()
    ctx.strokeStyle = root.rgba(root.background, 0.35)
    ctx.lineWidth = r * 0.03
    ctx.stroke()
  }

  function paintHeadwear(ctx, cx, cy, r, sx, sy) {
    var h = root.headwear
    if (h === "") return
    var top = headTop(cy, r, sy)
    var ink = root.rgba(root.trimColor, 1)
    // Smaller hats on narrow heads, scaled from the crown so they still sit on it.
    var fit = root.head.hat
    if (fit !== 1) {
      ctx.save()
      ctx.translate(cx, top + r * 0.2)
      ctx.scale(fit, fit)
      ctx.translate(-cx, -top - r * 0.2)
    }
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
    } else if (h === "crown") {
      // Three points with a ball on each, and gems in the body color.
      ctx.fillStyle = ink
      ctx.strokeStyle = ink
      ctx.lineJoin = "round"
      ctx.lineWidth = r * 0.06
      ctx.beginPath()
      ctx.moveTo(cx - r * 0.42, top + r * 0.18)
      ctx.lineTo(cx - r * 0.48, top - r * 0.3)
      ctx.lineTo(cx - r * 0.22, top - r * 0.06)
      ctx.lineTo(cx, top - r * 0.4)
      ctx.lineTo(cx + r * 0.22, top - r * 0.06)
      ctx.lineTo(cx + r * 0.48, top - r * 0.3)
      ctx.lineTo(cx + r * 0.42, top + r * 0.18)
      ctx.closePath()
      ctx.fill()
      ctx.stroke()
      disc(ctx, cx - r * 0.48, top - r * 0.32, r * 0.08)
      disc(ctx, cx, top - r * 0.42, r * 0.08)
      disc(ctx, cx + r * 0.48, top - r * 0.32, r * 0.08)
      ctx.fillStyle = root.rgba(root.baseColor, 0.9)
      disc(ctx, cx - r * 0.24, top + r * 0.07, r * 0.055)
      disc(ctx, cx, top + r * 0.06, r * 0.07)
      disc(ctx, cx + r * 0.24, top + r * 0.07, r * 0.055)
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
    if (fit !== 1) ctx.restore()
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
    if (framing === "neck") return { x: cx, y: cy + 0.3 * r, z: 1.05 }
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
    var tall = still || root.extraStyle !== "none" || root.headwear !== "" || ["bow", "flower", "headphones"].indexOf(root.accessory) >= 0
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

    var eyes = paintEyes(ctx, cx, cy, r, headTop(cy, r, sy))

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

    var chin = root.neckwear ? Math.min(root.head.chin, root.head.neck - 0.03) : root.head.chin
    paintMouth(ctx, cx, r, eyes, cy + r * sy * chin)
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
