.pragma library
.import "PetFace.js" as PetFace

// Reactions as data. Each clip is a list of steps; a step's `to` is a sparse
// delta added to the clip's running pose, so later steps inherit earlier
// ones. A null value hands that channel back to the base pose (mood, sleep).
//
//   ms     transition time        hold   time spent at the target
//   ease   see PetFace.EASE       snap   when discrete channels switch: start | mid | end
//   fx     effect fired when the step starts (heart, confetti, star, sneeze, sweat)
//   jitter { channel: amplitude } random offset picked once per play
//
// Clip fields:
//   priority  0 ambient, 1 reaction, 2 interaction, 3 event
//   interrupt what a repeat request does: restart | ignore | extend
//   mode      once | loop | pingpong, with `loops` (0 = until stopped) and `maxMs`
//   release   ms to blend back to the base after the last step
//   wakes     may play while asleep (wakes the pet first)
//   cooldown  ms before the same clip may start again
//   bar       on the cheap bar pet: full (ticks) | pose (one repaint) | off
//   ambient   only started by the pet's own idle timers (Calm turns these off)
//   peak      ms into the clip that best shows it (docs sheet)

var E = PetFace.EXPR
var ext = PetFace.ext

function hopSteps(first, hold, fx) {
  return [
    { to: ext(first, { squash: 1 }), ms: 80, ease: "outQuad", snap: "start" },
    { to: { squash: -1, hop: -0.14 }, ms: 160, ease: "outBack", fx: fx || "" },
    { to: { squash: 0.3, hop: 0 }, ms: 140, ease: "inQuad" },
    { to: { squash: 0 }, ms: 120, ease: "inOutQuad", hold: hold }
  ]
}

var CLIPS = {
  // ---- existing behaviour, as data
  happy: {
    priority: 2, interrupt: "restart", mode: "once", release: 200, wakes: true, bar: "full", peak: 240,
    steps: hopSteps(E.happy, 400)
  },
  hop: {
    priority: 2, interrupt: "restart", mode: "once", release: 200, wakes: true, bar: "full", peak: 240,
    steps: hopSteps(E.happy, 700)
  },
  celebrate: {
    priority: 3, interrupt: "restart", mode: "once", release: 200, wakes: true, bar: "full", peak: 240,
    steps: hopSteps(E.happy, 1100, "confetti")
  },
  pat: {
    priority: 2, interrupt: "restart", mode: "once", release: 220, wakes: true, bar: "full", peak: 90,
    steps: [
      { to: ext(E.happy, { squash: 0.85 }), ms: 90, ease: "outQuad", snap: "start" },
      { to: { squash: -0.25 }, ms: 170, ease: "outBack" },
      { to: { squash: 0 }, ms: 140, ease: "inOutQuad", hold: 800 }
    ]
  },

  // ---- new reactions
  yawn: {
    priority: 0, interrupt: "ignore", mode: "once", release: 300, bar: "off", cooldown: 60000, ambient: true, peak: 900,
    steps: [
      { to: { eyeShape: "squint", mouthShape: "o", mouthOpen: 0.3, squash: -0.15, gazeLock: 1, gazeX: 0, gazeY: -0.3, blinkOk: 0, mark: "" }, ms: 300, ease: "inOutSine" },
      { to: { mouthShape: "yawn", mouthOpen: 1, squash: -0.4, tilt: -0.06 }, ms: 450, ease: "outQuad", hold: 600 },
      { to: { mouthOpen: 0.2, squash: 0.15, tilt: 0, eyeShape: "closed" }, ms: 350, ease: "inOutQuad" },
      { to: { mouthShape: "o-small", squash: 0 }, ms: 250, ease: "outQuad", hold: 300 }
    ]
  },
  wake: {
    priority: 2, interrupt: "ignore", mode: "once", release: 200, wakes: true, bar: "pose", peak: 500,
    steps: [
      { to: { eyeShape: "closed", mouthShape: "o-small", squash: -0.6, hop: -0.02, blinkOk: 0, mark: "" }, ms: 380, ease: "outQuad", hold: 250 },
      { to: { eyeShape: "squint", squash: 0.25, hop: 0 }, ms: 180, ease: "inQuad" },
      { to: { eyeShape: null, mouthShape: null, squash: 0, tilt: 0.08 }, ms: 140, ease: "outBack" },
      { to: { tilt: -0.08 }, ms: 120, ease: "inOutSine" },
      { to: { tilt: 0, blinkOk: null, mark: null }, ms: 120, ease: "outQuad" }
    ]
  },
  startle: {
    priority: 2, interrupt: "ignore", mode: "once", release: 250, wakes: true, bar: "off", cooldown: 8000, peak: 120,
    steps: [
      { to: ext(E.startled, { squash: -0.5, hop: -0.05, blinkOk: 0 }), ms: 70, ease: "outQuad", snap: "start" },
      { to: { squash: 0.2, hop: 0 }, ms: 160, ease: "inQuad", hold: 350 },
      { to: { eyeShape: null, eyeScale: 1, mouthShape: null, mouthOpen: null, mark: null, browLift: null,
              browAlpha: null, browAngle: null, squash: 0 }, ms: 300, ease: "inOutSine" }
    ]
  },
  curious: {
    priority: 1, interrupt: "extend", mode: "once", release: 300, bar: "off", cooldown: 20000, peak: 600,
    steps: [
      { to: ext(E.curious, { tilt: 0.22 }), ms: 260, ease: "outBack", hold: 1400 },
      { to: { tilt: 0.12, eyeOpenR: 0.8 }, ms: 220, ease: "inOutSine", hold: 600 }
    ]
  },
  dizzy: {
    priority: 2, interrupt: "ignore", mode: "pingpong", loops: 4, release: 400, bar: "off", cooldown: 10000, peak: 260,
    steps: [
      { to: ext(E.dizzy, { tilt: -0.15, shiftX: -0.06 }), ms: 260, ease: "inOutSine", fx: "star" },
      { to: { tilt: 0.15, shiftX: 0.06 }, ms: 260, ease: "inOutSine" }
    ]
  },
  wink: {
    priority: 0, interrupt: "ignore", mode: "once", release: 160, bar: "pose", cooldown: 300000, peak: 200,
    steps: [
      { to: { eyeOpenR: 0.05, mouthShape: "happy", blush: 0.5, tilt: 0.05, blinkOk: 0 }, ms: 90, ease: "outQuad", hold: 380 },
      { to: { eyeOpenR: 1, tilt: 0, blush: 0 }, ms: 160, ease: "outBack" }
    ]
  },
  sneeze: {
    priority: 0, interrupt: "ignore", mode: "once", release: 200, bar: "off", cooldown: 1200000, ambient: true, peak: 850,
    steps: [
      { to: { eyeShape: "squint", mouthShape: "o", mouthOpen: 0.2, tilt: -0.08, squash: -0.2, blinkOk: 0 }, ms: 250, ease: "inQuad" },
      { to: { mouthOpen: 0.45, tilt: -0.14, squash: -0.35 }, ms: 350, ease: "inQuad", hold: 180 },
      { to: { eyeShape: "closed", mouthShape: "grin", tilt: 0.12, squash: 0.5, shiftX: 0.08 }, ms: 70, ease: "outQuad", fx: "sneeze", snap: "start" },
      { to: { tilt: 0, squash: 0, shiftX: 0, eyeShape: "squint" }, ms: 260, ease: "outElastic", hold: 200 },
      { to: { eyeShape: null, mouthShape: null, mouthOpen: null }, ms: 150 }
    ]
  },
  thinking: {
    priority: 1, interrupt: "ignore", mode: "loop", loops: 0, maxMs: 60000, release: 300, bar: "pose", peak: 1200,
    steps: [
      { to: E.thinking, ms: 300, ease: "inOutSine", hold: 900 },
      { to: { gazeX: -0.3, mouthX: 0.18 }, ms: 400, ease: "inOutSine", hold: 700 },
      { to: { gazeX: -0.6, mouthX: 0.12 }, ms: 400, ease: "inOutSine" }
    ]
  },
  oof: {
    priority: 3, interrupt: "restart", mode: "once", release: 400, wakes: true, bar: "full", peak: 300,
    steps: [
      { to: E.oof, ms: 120, ease: "outQuad", hold: 700 }
    ]
  },
  // A desktop notice just went out: eyes wide with a "!", a little jump, and
  // the pose held long enough to catch on the bar (a capped limit gets "oof").
  alert: {
    priority: 3, interrupt: "ignore", mode: "once", release: 300, wakes: true, bar: "pose", cooldown: 5000, peak: 300,
    steps: [
      { to: ext(E.startled, { squash: -0.45, hop: -0.06, blinkOk: 0 }), ms: 80, ease: "outQuad", snap: "start" },
      { to: { squash: 0.15, hop: 0 }, ms: 160, ease: "inQuad" },
      { to: { squash: 0, eyeScale: 1.15, mouthOpen: 0.45 }, ms: 200, ease: "inOutSine", hold: 1400 }
    ]
  },
  sigh: {
    priority: 1, interrupt: "ignore", mode: "once", release: 500, bar: "pose", cooldown: 30000, peak: 500,
    steps: [
      { to: { squash: 0.3, eyeShape: "closed", mouthShape: "o-small", blinkOk: 0, mark: "" }, ms: 400, ease: "inOutSine", hold: 300 }
    ]
  }
}

// The reactions worth listing (settings previews, docs, IPC help).
var NAMES = ["pat", "hop", "celebrate", "yawn", "wake", "startle", "curious", "dizzy",
             "wink", "sneeze", "thinking", "oof", "alert", "sigh"]

var MIRRORED = { tilt: 1, gazeX: 1, shiftX: 1, browAsym: 1, mouthX: 1 }

// Absolute keyframes for a clip over `base`: one resolved face per step.
// opts.mirror (-1 / 1) flips sideways channels and swaps the eyes.
function keyframes(clip, base, opts) {
  var side = opts && opts.mirror ? (opts.mirror < 0 ? -1 : 1) : 1
  var acc = {}
  var keys = []
  for (var i = 0; i < clip.steps.length; i++) {
    var st = clip.steps[i]
    var to = st.to || {}
    for (var k in to) {
      var v = to[k]
      if (v === null) { delete acc[k]; continue }
      if (side < 0 && MIRRORED[k]) v = -v
      var key = k
      if (side < 0 && k === "eyeOpenL") key = "eyeOpenR"
      else if (side < 0 && k === "eyeOpenR") key = "eyeOpenL"
      acc[key] = v
    }
    var pose = PetFace.resolve(base, acc)
    if (st.jitter) for (var j in st.jitter) pose[j] += (Math.random() * 2 - 1) * st.jitter[j]
    keys.push(PetFace.clamp(pose))
  }
  return keys
}

// The face `ms` into a clip, without playing it (first pass, no loops):
// for docs and previews.
function poseAt(name, base, ms, opts) {
  var clip = CLIPS[name]
  var b = base || PetFace.resolve()
  if (!clip) return b
  var keys = keyframes(clip, b, opts)
  var from = b
  var t = ms
  for (var i = 0; i < clip.steps.length; i++) {
    var st = clip.steps[i]
    var dur = st.ms || 0
    if (t < dur) {
      var k = dur > 0 ? t / dur : 1
      return PetFace.mix(from, keys[i], PetFace.ease(st.ease, k), k, st.snap)
    }
    t -= dur
    if (t < (st.hold || 0)) return keys[i]
    t -= st.hold || 0
    from = keys[i]
  }
  return from
}

function peakPose(name, base, opts) {
  var clip = CLIPS[name]
  return poseAt(name, base, clip ? clip.peak || 0 : 0, opts)
}
