.pragma library

// The pet's expression parameters ("face"). Every paint routine in
// BlobAvatar reads one of these objects. Numeric channels interpolate,
// discrete channels snap. NEUTRAL reproduces the plain idle drawing exactly.

var NEUTRAL = {
  // eyes
  eyeShape: "",      // "" (the look's own) | happy | sleepy | closed | wide | squint | x | spiral
  eyeOpen: 1.0,      // multiplied with the automatic blink
  eyeOpenL: 1.0,     // per-eye multipliers (a wink closes one)
  eyeOpenR: 1.0,
  eyeScale: 1.0,     // bigger eyes when startled (times the look's eyeSize)
  eyeY: 0.0,         // extra vertical offset, units of r
  // brows (hidden at neutral)
  browAlpha: 0.0,
  browAngle: 0.0,    // +1 worried (inner ends up), -1 cross
  browLift: 0.0,     // both brows up, units of r * 0.1
  browAsym: 0.0,     // one brow up (thinking, curious)
  // mouth
  mouthShape: "",    // "" (the look's own) | happy (look's, or a smile when it has none)
                     // | smile | o | o-small | flat | wavy | cat | yawn | grin | frown | pant | lick | none
  mouthOpen: 0.0,    // size of o and yawn
  mouthCurve: 0.0,   // bends the flat mouth: -1 frown .. 1 smile
  mouthX: 0.0,       // sideways shift, units of r
  // body, added to the avatar's own squash / hop
  squash: 0.0,       // -1 tall .. 1 flat
  hop: 0.0,          // fraction of size, negative is up
  tilt: 0.0,         // radians, around the base of the body
  shiftX: 0.0,       // units of r
  scale: 1.0,
  // gaze, mixed with cursor tracking
  gazeX: 0.0,
  gazeY: 0.0,
  gazeLock: 0.0,     // 0 follow the cursor .. 1 only use gazeX / gazeY
  // skin
  blush: 0.0,
  // floating marks (only when showMarks)
  mark: "",          // "" | z | zz | ! | ? | ... | sweat | pant | stars | cutlery
  markAlpha: 1.0,
  // procedural modifiers
  breathRate: 1.0,   // below 0.8 breathes slowly (tired, asleep)
  wobble: 1.0,       // blob and ghost outline amplitude
  blinkOk: 1         // 0 holds off the automatic blink
}

var DISCRETE = { eyeShape: 1, mouthShape: 1, mark: 1, blinkOk: 1 }

// Copy of `a` with `b` laid over it (sparse deltas, no spread syntax needed).
function ext(a, b) {
  var out = {}
  var k
  if (a) for (k in a) out[k] = a[k]
  if (b) for (k in b) out[k] = b[k]
  return out
}

// Named expressions: sparse deltas over NEUTRAL.
var EXPR = {
  happy:    { eyeShape: "happy", mouthShape: "happy", blinkOk: 0, browAlpha: 0, mark: "" },
  worried:  { browAlpha: 1, browAngle: 1, mouthShape: "wavy", mark: "!" },
  // Out of breath from burning a limit too fast: heavy lids, a strained
  // brow, flushed cheeks, an open mouth and quick breaths.
  panting:  { eyeOpen: 0.72, browAlpha: 0.8, browAngle: 0.45, mouthShape: "pant", mouthOpen: 1,
              blush: 0.45, mark: "pant", breathRate: 1.6 },
  // A quota about to go to waste: eager eyes on a fork and knife, brows up,
  // licking his lips with a drop of drool.
  hungry:   { eyeScale: 1.1, browAlpha: 0.85, browAngle: 0, browLift: 0.6, mouthShape: "lick", mark: "cutlery",
              gazeLock: 0.35, gazeX: 0.4, gazeY: -0.4 },
  tired:    { eyeShape: "sleepy", mark: "z", breathRate: 0.65 },
  asleep:   { eyeShape: "closed", mouthShape: "o-small", mark: "zz", breathRate: 0.65,
              gazeLock: 1, gazeX: 0, gazeY: 0, blinkOk: 0, browAlpha: 0 },
  startled: { eyeShape: "wide", eyeScale: 1.3, mouthShape: "o", mouthOpen: 0.7,
              browAlpha: 1, browAngle: 0, browLift: 1, mark: "!" },
  curious:  { eyeScale: 1.1, browAlpha: 1, browAngle: 0, browAsym: 1, mark: "?" },
  thinking: { gazeLock: 0.85, gazeX: -0.6, gazeY: -0.7, browAlpha: 1, browAngle: 0, browAsym: -0.8,
              mouthShape: "flat", mouthX: 0.12, mouthCurve: -0.2, mark: "..." },
  dizzy:    { eyeShape: "spiral", mouthShape: "wavy", mark: "stars", gazeLock: 1, gazeX: 0, gazeY: 0, blinkOk: 0 },
  yawn:     { eyeShape: "squint", mouthShape: "yawn", mouthOpen: 1, squash: -0.35, blinkOk: 0 },
  oof:      { eyeShape: "closed", mouthShape: "frown", mark: "sweat", squash: 0.45, blinkOk: 0, browAlpha: 0 }
}

// NEUTRAL <- layer1 <- layer2 ... (unknown keys are dropped)
function resolve() {
  var out = {}
  var k
  for (k in NEUTRAL) out[k] = NEUTRAL[k]
  for (var i = 0; i < arguments.length; i++) {
    var l = arguments[i]
    if (!l) continue
    for (k in l) if (k in NEUTRAL) out[k] = l[k]
  }
  return out
}

var EASE = {
  linear: function (t) { return t },
  inQuad: function (t) { return t * t },
  outQuad: function (t) { return t * (2 - t) },
  inOutQuad: function (t) { return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t },
  inOutSine: function (t) { return -(Math.cos(Math.PI * t) - 1) / 2 },
  outBack: function (t) { var c = 1.70158; return 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2) },
  outElastic: function (t) { return t === 0 || t === 1 ? t : Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * 2.094) + 1 },
  step: function (t) { return t < 1 ? 0 : 1 }
}

function ease(name, t) {
  var f = EASE[name || "inOutQuad"] || EASE.inOutQuad
  return f(t)
}

// Blend two faces. `k` is the linear progress (0..1) used for the discrete
// snap point, `e` the eased value used for numbers (may overshoot).
function mix(a, b, e, k, snap) {
  var at = snap === "start" ? 0 : (snap === "end" ? 1 : 0.5)
  var out = {}
  for (var key in NEUTRAL) {
    var x = a[key], y = b[key]
    if (DISCRETE[key]) out[key] = (snap === "start" ? k > 0 : k >= at) ? y : x
    else out[key] = x + (y - x) * e
  }
  return clamp(out)
}

// Keep tilts and hops inside the canvas.
function clamp(f) {
  if (f.tilt > 0.25) f.tilt = 0.25
  else if (f.tilt < -0.25) f.tilt = -0.25
  if (f.hop < -0.16) f.hop = -0.16
  return f
}

function equal(a, b) {
  for (var k in NEUTRAL) if (a[k] !== b[k]) return false
  return true
}
