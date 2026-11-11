.pragma library
// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): omarchy/Model.js
.import "Window.js" as Window
.import "Pacing.js" as Pacing

// How the panel reads a limit out loud: used or left, the usage color rung,
// the pace arrow, which windows Kian's mood watches, and when he's panting.

// Settings written by hand or with `omarchy bar set` can arrive as text.
function flag(value, fallback) {
  if (value === true || value === false) return value
  var text = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  if (text === "true" || text === "on" || text === "yes" || text === "1") return true
  if (text === "false" || text === "off" || text === "no" || text === "0") return false
  return fallback
}

function normalizeShowAs(value) {
  var text = String(value || "").trim().toLowerCase()
  return text === "left" || text === "remaining" ? "left" : "used"
}

// Which windows drive the mood, as ai-usagebar's barWindow picks the bar's
// number (Kian shows no number, so his face is the reading).
function normalizeMoodWindow(value) {
  var text = String(value || "").trim().toLowerCase()
  if (["session", "5h", "5-hour", "rolling"].indexOf(text) >= 0) return "session"
  if (["weekly", "week", "7d", "7-day"].indexOf(text) >= 0) return "weekly"
  return "auto"
}

// The 0..1 share a meter draws and its percentage reads.
function shownFraction(percent, showAs) {
  var used = Math.max(0, Math.min(1, Number(percent) || 0))
  return showAs === "left" ? 1 - used : used
}

// The color rung of a used share, as pango.rs's severity_for: under 50% low,
// then mid, from 75% high, from 90% critical. Read off the fraction itself,
// so critical starts exactly where the panel's alarm does.
function level(percent) {
  var used = Number(percent) || 0
  if (used >= 0.9) return "critical"
  if (used >= 0.75) return "high"
  if (used >= 0.5) return "mid"
  return "low"
}

// The arrow beside a meter, from the ratio pace and its tolerance band, as
// ai-usagebar's tooltip does. Nothing while the pace can't be told yet. The
// arrow follows the number beside it: read as the share left, a fast pace
// drains it, so ahead points down. "On track" points the way the meter
// moves, so it turns around right-to-left.
function paceGlyph(pace, mirrored, showAs) {
  if (!pace || !pace.known || pace.early) return ""
  var left = showAs === "left"
  if (pace.ratioPace === "ahead") return left ? "↓" : "↑"
  if (pace.ratioPace === "under") return left ? "↑" : "↓"
  return mirrored ? "←" : "→"
}

// "session" | "weekly" | "monthly" | "" for a window title, a model-scoped
// one ("Fable Weekly") counting as the window it runs on.
function kindOf(title) {
  var part = Window.scopedPart(title)
  var kind = part ? part.window : String(title || "")
  if (kind === "Session") return "session"
  if (kind === "Weekly") return "weekly"
  if (kind === "Monthly") return "monthly"
  return ""
}

// The same for a window, whose title may name only a model ("Argon"): then
// its length tells, a week (give or take a day) being weekly.
function windowKind(w) {
  var kind = kindOf(w ? w.title : "")
  if (kind !== "" || !w || !(w.spanMs > 0)) return kind
  if (Math.abs(w.spanMs - Window.WEEK_MS) <= Window.DAY_MS) return "weekly"
  if (w.spanMs >= 28 * Window.DAY_MS) return "monthly"
  return w.spanMs < Window.DAY_MS ? "session" : ""
}

// The windows the mood reads for one provider: every one in auto, else the
// chosen kind. A provider without that kind (a monthly-only plan) keeps all
// of its windows rather than dropping out of the mood.
function moodWindows(windows, moodWindow) {
  var list = windows || []
  if (moodWindow !== "session" && moodWindow !== "weekly") return list
  var picked = list.filter(function(w) { return windowKind(w) === moodWindow })
  return picked.length > 0 ? picked : list
}

// The fullest of them: what stops the next prompt.
function fullest(windows) {
  var best = null
  for (var i = 0; i < (windows || []).length; i++)
    if (!best || windows[i].percent > best.percent) best = windows[i]
  return best
}

// Panting: clearly ahead of an even pace (this many points, with this much
// used, so a few early prompts don't count) and heading for the cap before
// the reset, but not near it yet: from NEAR_CAP on he's worried instead.
var PANT_DELTA = 15
var PANT_MIN_USED = 20
var NEAR_CAP = 0.9

function panting(pace, percent) {
  return !!pace && pace.known && !pace.early && pace.projection === "hits"
    && pace.delta >= PANT_DELTA && pace.usedPct >= PANT_MIN_USED && Number(percent) < NEAR_CAP
}

// The most pressing of [{provider, window}]: of the windows Kian would pant
// over, the one projected to run out first. Null when none is.
function hurried(entries, nowMs) {
  var best = null
  for (var i = 0; i < (entries || []).length; i++) {
    var w = entries[i].window
    var pace = Pacing.forWindow(w, nowMs)
    if (!panting(pace, w ? w.percent : 1)) continue
    if (!best || pace.hitsInMs < best.pace.hitsInMs)
      best = { provider: entries[i].provider, window: w, pace: pace }
  }
  return best
}
