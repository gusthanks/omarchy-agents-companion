.pragma library
// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): src/pacing.rs
.import "Window.js" as Window

// How a window's use compares with the time gone by, and where the average
// pace so far lands it at the reset. Two notions of pace, as in pacing.rs:
// - the point delta, used% - elapsed%, signed, with no tolerance;
// - the ratio, used% / elapsed%, with a tolerance band, capped at 999%.

var DEFAULT_TOLERANCE = 5
// In the first minutes of a window a couple of prompts read as a runaway
// pace: below this much of the window gone by, the ratio and the projection
// stay neutral (the point delta is still exact).
var MIN_ELAPSED = 0.08

function neutral(usedPct) {
  return {
    known: false,
    early: false,
    elapsedPct: 0,
    usedPct: usedPct || 0,
    delta: 0,
    pointPace: "on_track",
    ratioPace: "on_track",
    ratioPct: 0,
    // "none" | "hits" (the limit before the reset) | "left" (some left at the
    // reset) | "maxed" (already at the limit)
    projection: "none",
    hitsInMs: -1,
    leftPct: -1
  }
}

// percent is the 0..1 fraction the records carry; resetAt an ISO string or
// epoch ms. A window without a reset, a length, or whose reset has passed (a
// new window nothing has been read from yet) has no pace.
function calc(percent, resetAt, windowMs, nowMs, tolerance, minElapsed) {
  var used = Math.max(0, Number(percent) || 0)
  var usedPct = Math.round(used * 100)
  var reset = Window.timeMs(resetAt)
  if (!isFinite(reset) || !(windowMs > 0) || reset <= nowMs) return neutral(usedPct)
  var tol = tolerance === undefined ? DEFAULT_TOLERANCE : Number(tolerance)
  var floor = minElapsed === undefined ? MIN_ELAPSED : Number(minElapsed)

  var remaining = reset - nowMs
  var elapsed = Math.max(0, Math.min(windowMs, windowMs - remaining))
  var elapsedPct = Math.max(0, Math.min(100, Math.floor(elapsed * 100 / windowMs)))
  var out = neutral(usedPct)
  out.known = true
  out.elapsedPct = elapsedPct
  out.delta = usedPct - elapsedPct
  out.pointPace = out.delta > 0 ? "ahead" : (out.delta < 0 ? "under" : "on_track")
  out.early = elapsed / windowMs < floor || elapsedPct === 0
  if (out.early) return out

  var x100 = Math.floor(usedPct * 100 / elapsedPct)
  if (x100 > 100 + tol) { out.ratioPace = "ahead"; out.ratioPct = Math.min(999, x100 - 100) }
  else if (x100 < 100 - tol) { out.ratioPace = "under"; out.ratioPct = Math.min(999, 100 - x100) }

  // The average pace so far, carried to the reset.
  if (used >= 1) {
    out.projection = "maxed"
    return out
  }
  var rate = used / elapsed
  var atReset = used + rate * remaining
  if (atReset >= 1) {
    out.projection = "hits"
    out.hitsInMs = Math.round((1 - used) / rate)
  } else {
    out.projection = "left"
    out.leftPct = Math.round((1 - atReset) * 100)
  }
  return out
}

// The same for a window from Window.limitWindow.
function forWindow(w, nowMs, tolerance, minElapsed) {
  if (!w) return neutral(0)
  return calc(w.percent, w.resetAt, w.spanMs, nowMs, tolerance, minElapsed)
}

// Severity of a point delta, as pacing.rs's pace_severity: <= -10 low,
// -10..0 mid, 1..9 high, >= 10 critical.
function severity(delta) {
  if (delta >= 10) return "critical"
  if (delta > 0) return "high"
  if (delta >= -10) return "mid"
  return "low"
}
