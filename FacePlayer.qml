import QtQuick
import "PetFace.js" as PetFace
import "PetClips.js" as PetClips

// Plays one reaction clip at a time over a base pose (mood, sleep) and keeps
// `face` up to date for the avatar's canvas. Nothing ticks while nothing
// plays, so an idle pet costs no frames.
//
// level: full   clips tick every frame
//        cheap  (the bar pet) "pose" clips jump to their last pose with one
//               repaint, "full" clips tick, "off" clips are refused, and
//               base changes snap
//        still  (the Still personality) every clip shows one pose: "pose"
//               clips their last, the others their peak; "off" clips only
//               with force (previews); base changes snap
//        static nothing plays; base changes snap
QtObject {
  id: p

  property var basePose: PetFace.resolve()
  property var face: PetFace.resolve()
  property string level: "full"
  // False while the owner is hidden: no ticking then.
  property bool active: true
  property bool running: false
  property string current: ""
  property int currentPriority: -1
  // Harness override: function() -> ms, so captures step clips evenly.
  property var clock: null

  signal changed()
  signal fx(string kind)
  signal finished(string name)
  signal sleepRequested()

  property var _clip: null
  property var _keys: []
  property int _i: 0
  property real _t0: 0
  property real _start: 0
  property var _from: null
  property int _dir: 1
  property int _loop: 0
  property string _next: ""
  property var _lastPlayed: ({})

  function now() { return p.clock ? p.clock() : Date.now() }

  function _setFace(f) {
    if (PetFace.equal(f, p.face)) return
    p.face = f
    p.changed()
  }

  // Start a clip. opts: { mirror: -1|1, next: "clip" | "__sleep", force: bool }
  function play(name, opts) {
    var c = PetClips.CLIPS[name]
    if (!c || p.level === "static") return false
    var t = now()
    var force = !!(opts && opts.force)
    var prio = opts && opts.priority !== undefined ? opts.priority : c.priority
    var posesOnly = p.level === "still" || p.level === "cheap" && c.bar === "pose"
    if ((c.bar || "off") === "off" && (p.level === "cheap" || p.level === "still" && !force)) return false
    if (!force && !(opts && opts.noCooldown) && c.cooldown && p._lastPlayed[name] !== undefined
        && t - p._lastPlayed[name] < c.cooldown) return false
    if (!force) {
      if (p.current === name) {
        if (c.interrupt === "ignore") return false
        if (c.interrupt === "extend") { p._t0 = t; return true }
      } else if (p.current !== "" && p.current !== "__release" && prio < p.currentPriority) {
        return false
      }
    }
    p._lastPlayed[name] = t
    // A pose clip's revert timer must not cut off whatever replaces it.
    poseTimer.stop()
    p._clip = c
    p.current = name
    p.currentPriority = prio
    p._next = opts && opts.next !== undefined ? opts.next : (c.next || "")
    p._keys = PetClips.keyframes(c, p.basePose, opts)
    if (posesOnly) {
      p.running = false
      p._setFace(c.bar === "pose" ? p._keys[p._keys.length - 1] : PetClips.peakPose(name, p.basePose, opts))
      // A loop holds its pose until stopped; a one-shot reverts on its own.
      poseTimer.interval = c.mode === "once" || c.loops > 0 ? 1200 : (c.maxMs || 60000)
      poseTimer.restart()
      return true
    }
    p._from = p.face
    p._i = 0
    p._dir = 1
    p._loop = 0
    p._t0 = t
    p._start = t
    p.running = true
    p.fx(c.steps[0].fx || "")
    return true
  }

  // Blend back to the base pose. With a name, only if that clip is playing.
  function stop(name, snap) {
    if (name && name !== p.current) return
    poseTimer.stop()
    if (!p._clip) return
    p._next = ""
    if (snap || p.level !== "full" && !p.running) {
      p._clip = null
      p.current = ""
      p.currentPriority = -1
      p.running = false
      p._setFace(p.basePose)
      return
    }
    var rel = p.current === "__release" ? 0 : (p._clip.release || 200)
    p._release(rel || 200)
  }

  function _release(ms) {
    p._clip = { steps: [{ ms: ms, ease: "inOutQuad" }], mode: "once" }
    p._keys = [p.basePose]
    p._from = p.face
    p._i = 0
    p._dir = 1
    p._t0 = now()
    p.current = "__release"
    p.currentPriority = -1
    p.running = true
  }

  // The mood or sleep changed. A playing clip keeps going over it and
  // releases into the new base when it ends.
  function setBase(pose, snap) {
    p.basePose = pose
    if (p.current !== "" && p.current !== "__release") return
    if (snap || p.level !== "full" || !p.active) {
      p._clip = null
      p.current = ""
      p.running = false
      p._setFace(pose)
      return
    }
    p._release(350)
  }

  function poseAt(name, ms, opts) { return PetClips.poseAt(name, p.basePose, ms, opts) }

  function tick() {
    if (!p._clip) { p.running = false; return }
    var s = p._clip.steps[p._i]
    var dur = s.ms || 0
    var hold = s.hold || 0
    var e = now() - p._t0
    var k = dur > 0 ? Math.min(1, e / dur) : 1
    p._setFace(PetFace.mix(p._from, p._keys[p._i], PetFace.ease(s.ease, k), k, s.snap))
    if (e < dur + hold) return
    // next step
    p._from = p._keys[p._i]
    p._t0 = now()
    var n = p._i + p._dir
    if (n >= 0 && n < p._keys.length) {
      p._i = n
      p.fx(p._clip.steps[n].fx || "")
      return
    }
    var mode = p._clip.mode || "once"
    var loops = p._clip.loops || 0
    if (mode !== "once" && (loops === 0 || ++p._loop < loops)
        && !(p._clip.maxMs && now() - p._start > p._clip.maxMs)) {
      if (mode === "pingpong") { p._dir = -p._dir; p._i += p._dir }
      else { p._i = 0; p.fx(p._clip.steps[0].fx || "") }
      return
    }
    var done = p.current
    if (done === "__release") {
      p._clip = null
      p.current = ""
      p.currentPriority = -1
      p.running = false
      return
    }
    var chain = p._next
    p._next = ""
    if (chain === "__sleep") {
      // Fall asleep from where the clip ended; the owner sets the new base.
      p._clip = null
      p.current = ""
      p.currentPriority = -1
      p.running = false
      p.finished(done)
      p.sleepRequested()
      return
    }
    p._release(p._clip.release || 200)
    p.finished(done)
    if (chain !== "") Qt.callLater(function() { p.play(chain) })
  }

  property Timer poseTimer: Timer {
    onTriggered: p.stop("", true)
  }

  property FrameAnimation driver: FrameAnimation {
    running: p.running && p.active
    onTriggered: p.tick()
  }
}
