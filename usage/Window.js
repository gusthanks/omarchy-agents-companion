.pragma library

// The limit-window model the panel and the usage math share: what a limit's
// window is called, how long it lasts and how far into it we are. The clock is
// always passed in, so these stay pure and the Node tests can pin it.

var MINUTE_MS = 60 * 1000
var HOUR_MS = 60 * MINUTE_MS
var DAY_MS = 24 * HOUR_MS
var WEEK_MS = 7 * DAY_MS
var MONTH_MS = 30 * DAY_MS
// Both Claude and Codex run five-hour sessions; a session window that doesn't
// spell out its length is taken to be one of those.
var SESSION_MS = 5 * HOUR_MS

var HOURS_RE = /(\d+)\s*-?\s*h(?:our)?\b/
var MINUTES_RE = /(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/

// An ISO string or epoch milliseconds, as the records carry them; NaN when
// neither.
function timeMs(value) {
  if (typeof value === "number") return isFinite(value) ? value : NaN
  var text = String(value || "")
  return text === "" ? NaN : new Date(text).getTime()
}

// Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
// them ("5h window", "30m window"). Both have to land on the same record.
function isLong(text) {
  return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
    || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
}

function spanMs(label) {
  var text = String(label || "").toLowerCase()
  if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return MONTH_MS
  if (isLong(text)) return WEEK_MS
  var hours = text.match(HOURS_RE)
  if (hours) return Number(hours[1]) * HOUR_MS
  var minutes = text.match(MINUTES_RE)
  if (minutes) return Number(minutes[1]) * MINUTE_MS
  return 0
}

function title(label) {
  var text = String(label || "").toLowerCase()
  if (text.indexOf("month") >= 0) return "Monthly"
  if (isLong(text)) return "Weekly"
  if (text.indexOf("session") >= 0 || spanMs(label) > 0) return "Session"
  var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
  return plain === "" ? "Limit" : plain
}

// A model-scoped window ("Fable Weekly") is its own allowance on the clock of
// the window it's named for.
function scopedPart(title) {
  var match = String(title || "").match(/^(.+) (Session|Weekly|Monthly)$/)
  return match ? { model: match[1], window: match[2] } : null
}

// How long a window lasts, or 0 when that can't be known. As in limitWindow,
// the collector's title beats the label, and for a titled session only an hour
// count is trusted: a model's name can read like a span ("Opus 5 (1M context)").
function durationMs(label, windowTitle) {
  var given = String(windowTitle || "")
  var text = String(label || "").toLowerCase()
  if (given !== "") {
    var part = scopedPart(given)
    var kind = part ? part.window : given
    if (kind === "Weekly") return WEEK_MS
    if (kind === "Monthly") return MONTH_MS
    if (kind !== "Session") return 0
    var hours = text.match(HOURS_RE)
    return hours ? Number(hours[1]) * HOUR_MS : SESSION_MS
  }
  var span = spanMs(text)
  if (span > 0) return span
  if (/\bdaily\b/.test(text)) return DAY_MS
  var days = text.match(/(\d+)\s*-?\s*d(?:ays?)?\b/)
  if (days) return Number(days[1]) * DAY_MS
  return text.indexOf("session") >= 0 ? SESSION_MS : 0
}

// A collector that already knows which window a limit belongs to says so,
// and that beats reading it back out of the label: a model-scoped limit is
// titled after its model, and a name like "Opus 5 (1M context)" would parse
// as a one-minute window. A window whose reset has passed has started over,
// so whatever it last said no longer counts.
function limitWindow(label, percent, resetAt, windowTitle, nowMs) {
  var reset = timeMs(resetAt)
  var expired = isFinite(reset) && reset <= nowMs
  return {
    label: String(label || ""),
    title: String(windowTitle || "") !== "" ? String(windowTitle) : title(label),
    percent: expired ? 0 : Number(percent),
    resetAt: expired ? "" : String(resetAt || ""),
    spanMs: durationMs(label, windowTitle)
  }
}

function limitWindows(limits, nowMs) {
  var out = []
  var list = limits || []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i] || {}
    var percent = Number(entry.percent)
    if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title, nowMs))
  }
  return out
}

// Milliseconds until the window resets, or -1 when it names no reset.
function resetInMs(w, nowMs) {
  if (!w || String(w.resetAt || "") === "") return -1
  var ms = timeMs(w.resetAt)
  return isFinite(ms) ? ms - nowMs : -1
}

// How much of the window has gone by, 0..1, or -1 when its reset or length is
// unknown. A reset further away than the window is long (a clock running
// behind, or a window that hasn't started) counts as nothing gone by yet.
function elapsedFraction(resetMs, windowMs, nowMs) {
  if (!isFinite(resetMs) || !(windowMs > 0)) return -1
  var fraction = 1 - (resetMs - nowMs) / windowMs
  return Math.max(0, Math.min(1, fraction))
}
