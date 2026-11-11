.pragma library
// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): src/recommendation.rs
.import "Window.js" as Window
.import "Sources.js" as Sources

// Use it or lose it: which subscription to reach for first. A weekly quota
// that would reset with room unused is wasted, so the one projected to waste
// the most per hour left ranks first. The projection blends the whole cycle's
// average with the pace of the last few hours, measured from a bounded local
// history of fresh readings ({source, window, at, reset, percent}, percent
// 0..100, times in epoch ms). Nothing else is recorded.

var HOUR_MS = Window.HOUR_MS
var DAY_MS = Window.DAY_MS
var WEEK_MS = Window.WEEK_MS

var DEFAULT_RECENT_HOURS = 3
var MAX_RECENT_HOURS = 24
var DEFAULT_ALERT_UNUSED_PERCENT = 50
var DEFAULT_ALERT_HOURS = 24
var MAX_ALERT_HOURS = 168
var HISTORY_MS = (MAX_RECENT_HOURS + 1) * HOUR_MS
var MAX_SAMPLES = 4096
var MIN_UNUSED_PERCENT = 5
// A cached reading (kept through a failed check) still describes a weekly
// quota for a few hours; older than this it is unavailable.
var MAX_STALE_MS = 6 * HOUR_MS
// The refresh interval goes up to an hour here (pacing.rs's tool refreshes
// every 30 minutes at most), so a reading counts as current, and two readings
// as one unbroken run, within an hour and a quarter.
var FRESH_MS = 75 * 60 * 1000
// Less than this between the first and the last reading is not a pace yet.
var MIN_RUN_MS = 30 * 60 * 1000
// Collectors report the same reset with sub-second jitter between fetches.
var RESET_JITTER_MS = 120 * 1000
// The record's clock and this one can disagree a little (a reading stamped
// just after the panel last looked at the time).
var SKEW_MS = 2 * 60 * 1000

function clampInt(value, min, max, fallback) {
  if (value === null || value === undefined || String(value).trim() === "") return fallback
  var n = Number(value)
  return isFinite(n) ? Math.max(min, Math.min(max, Math.round(n))) : fallback
}

function normalizeHours(value) { return clampInt(value, 1, MAX_RECENT_HOURS, DEFAULT_RECENT_HOURS) }
function normalizeAlertPercent(value) { return clampInt(value, 1, 100, DEFAULT_ALERT_UNUSED_PERCENT) }
function normalizeAlertHours(value) { return clampInt(value, 1, MAX_ALERT_HOURS, DEFAULT_ALERT_HOURS) }

// A record's 0..1 fraction as the 0..100 points the history keeps, rounded the
// same way everywhere so a reading compares equal to its own sample.
function points(fraction) {
  return Math.round(Number(fraction) * 10000) / 100
}

function validSample(s) {
  return !!s && typeof s.source === "string" && typeof s.window === "string"
    && isFinite(s.at) && isFinite(s.reset) && isFinite(s.percent)
    && s.percent >= 0 && s.percent <= 100
}

// The stored history, whatever state the file is in: a corrupt or foreign
// file is no history rather than an error.
function parse(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return [] }
  if (!data || !Array.isArray(data.samples)) return []
  return data.samples.filter(validSample)
}

function serialize(samples) {
  return JSON.stringify({ version: 1, samples: samples || [] }) + "\n"
}

// Adds the fresh readings in records to the history: a reading counts once,
// when a source's fetch time moves past the newest one already kept for that
// window, and only while it is current and not a cached fallback. Readings
// older than the longest recent span (or from the future) are dropped.
// Returns { samples, added }; the input is never changed.
function append(samples, records, nowMs) {
  var kept = (samples || []).filter(function(s) {
    return validSample(s) && s.at >= nowMs - HISTORY_MS && s.at <= nowMs + SKEW_MS
  })
  var newest = {}
  for (var i = 0; i < kept.length; i++) {
    var id = kept[i].source + "\n" + kept[i].window
    if (!(newest[id] >= kept[i].at)) newest[id] = kept[i].at
  }
  var added = 0
  var list = Sources.sources(records)
  for (var j = 0; j < list.length; j++) {
    var src = list[j]
    var at = src.fetchedAt
    if (src.stale || !(at > 0) || at > nowMs + SKEW_MS || nowMs - at > FRESH_MS) continue
    for (var k = 0; k < src.limits.length; k++) {
      var limit = src.limits[k] || {}
      var label = String(limit.label || "")
      var percent = points(limit.percent)
      var reset = Window.timeMs(limit.resetsAt)
      if (label === "" || !isFinite(reset) || !(percent >= 0 && percent <= 100)) continue
      var key = src.key + "\n" + label
      if (newest[key] >= at) continue
      newest[key] = at
      kept.push({ source: src.key, window: label, at: at, reset: reset, percent: percent })
      added++
    }
  }
  kept.sort(function(a, b) { return a.at - b.at })
  if (kept.length > MAX_SAMPLES) kept = kept.slice(kept.length - MAX_SAMPLES)
  return { samples: kept, added: added }
}

// The consumption rate (points per hour) over the last recentHours before the
// reading at `at`, from one unbroken run of readings of the same window. A
// drop means a reset or a correction and starts the run over, as does a gap.
// null until the run spans half an hour. Returns { rate, hours }.
function recentRate(samples, source, window, resetMs, at, used, recentHours) {
  var hours = normalizeHours(recentHours)
  var run = []
  var list = samples || []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (s.source !== source || s.window !== window) continue
    if (Math.abs(s.reset - resetMs) > RESET_JITTER_MS) continue
    if (s.at < at - hours * HOUR_MS || s.at > at) continue
    var last = run.length > 0 ? run[run.length - 1] : null
    if (last && (s.percent < last.percent || s.at - last.at > FRESH_MS)) run = []
    run.push(s)
  }
  if (run.length === 0) return null
  var first = run[0]
  var end = run[run.length - 1]
  if (at - end.at > FRESH_MS || used < end.percent || at - first.at < MIN_RUN_MS) return null
  var span = (at - first.at) / HOUR_MS
  return { rate: (used - first.percent) / span, hours: span }
}

var TIER = { urgent: 0, priority: 1, on_track: 2, unknown: 3, blocked: 4, unavailable: 5 }

function tierOf(row) {
  return row.status === "priority" && row.urgent ? TIER.urgent : TIER[row.status]
}

// Ranks every source with limits. status: "priority" (projected to reset with
// at least 5% unused; urgent when that is at least alertUnusedPercent and the
// reset is within alertHours), "on_track" (the pace uses it up), "blocked"
// (the weekly quota is spent), "unknown" (no window of a day or longer with a
// known length and reset) or "unavailable" (no current data).
// opts: { recentHours, alertUnusedPercent, alertHours }, each optional.
function rank(records, samples, nowMs, opts) {
  var o = opts || {}
  var recentHours = normalizeHours(o.recentHours)
  var alertUnused = normalizeAlertPercent(o.alertUnusedPercent)
  var alertHours = normalizeAlertHours(o.alertHours)
  var horizon = alertHours * HOUR_MS
  var rows = []
  var list = Sources.sources(records)
  for (var i = 0; i < list.length; i++) {
    var src = list[i]
    if (src.limits.length === 0) continue
    var row = {
      key: src.key, provider: src.provider, account: src.account,
      name: src.name, accountLabel: src.accountLabel,
      status: "unknown", urgent: false, score: -1,
      stale: src.stale, fetchedAt: src.fetchedAt
    }
    var tooOld = !(src.fetchedAt > 0) || nowMs - src.fetchedAt > MAX_STALE_MS
    if (!src.ready || (src.stale && tooOld)) {
      row.status = "unavailable"
      rows.push(row)
      continue
    }

    // Model-scoped windows ("Fable Weekly") are a single model's allowance;
    // the shared windows are what every prompt spends.
    var shared = []
    for (var k = 0; k < src.limits.length; k++) {
      var limit = src.limits[k] || {}
      var percent = Number(limit.percent)
      if (!(percent >= 0)) continue
      var windowTitle = String(limit.title || "") !== "" ? String(limit.title) : Window.title(limit.label)
      if (Window.scopedPart(windowTitle)) continue
      shared.push({
        label: String(limit.label || ""),
        span: Window.durationMs(limit.label, limit.title),
        reset: Window.timeMs(limit.resetsAt),
        used: points(percent)
      })
    }

    // A short window refills within hours and doesn't lose anything at its
    // reset, but a spent one is worth saying alongside the weekly forecast.
    row.sessionExhausted = shared.some(function(w) {
      return w.span > 0 && w.span < WEEK_MS - DAY_MS && !(w.reset <= nowMs) && w.used >= 100
    })

    // Quota is lost at the weekly reset, so the weekly window is the measure;
    // with several the most used binds.
    // Without a weekly window, the longest one of at least a day stands in.
    // An expired window can't bind the current quota.
    var windowed = shared.filter(function(w) { return w.span >= DAY_MS && w.reset > nowMs })
    var weekly = function(w) { return Math.abs(w.span - WEEK_MS) <= DAY_MS }
    var pool
    if (windowed.some(weekly)) pool = windowed.filter(weekly)
    else {
      var longest = 0
      for (var n = 0; n < windowed.length; n++) longest = Math.max(longest, windowed[n].span)
      pool = windowed.filter(function(c) { return c.span === longest })
    }
    var bind = null
    for (var p = 0; p < pool.length; p++) {
      var c = pool[p]
      if (!bind || c.used > bind.used || (c.used === bind.used && c.reset < bind.reset)) bind = c
    }
    if (!bind) {
      rows.push(row)
      continue
    }
    row.window = bind.label
    row.resetMs = bind.reset
    if (bind.used >= 100) {
      row.status = "blocked"
      rows.push(row)
      continue
    }

    var remaining = bind.reset - nowMs
    var remainingH = remaining / HOUR_MS
    // Usage follows a daily rhythm: the first hours of a cycle are averaged
    // over a whole day instead of being extrapolated around the clock.
    var elapsed = Math.max(0, bind.span - remaining)
    var cycle = bind.used / (Math.max(elapsed, DAY_MS) / HOUR_MS)
    var current = nowMs - src.fetchedAt <= FRESH_MS && src.fetchedAt <= nowMs + SKEW_MS
    var recent = current ? recentRate(samples, src.key, bind.label, bind.reset, src.fetchedAt, bind.used, recentHours) : null
    var weight = recent ? Math.min(0.75, recent.hours / recentHours * 0.75) : 0
    var blended = recent ? recent.rate * weight + cycle * (1 - weight) : cycle
    // The recent pace speaks for the next day; the cycle average for the rest.
    var near = Math.min(remainingH, 24)
    var consumed = blended * near + cycle * (remainingH - near)
    var left = 100 - bind.used
    var unused = Math.max(0, Math.min(left, left - consumed))
    var priority = unused >= MIN_UNUSED_PERCENT

    row.status = priority ? "priority" : "on_track"
    row.urgent = remaining <= horizon && unused >= Math.max(alertUnused, MIN_UNUSED_PERCENT)
    row.score = unused / remainingH
    row.unusedPercent = Math.round(unused)
    row.remainingPercent = Math.round(left)
    row.requiredPerHour = left / remainingH
    row.pacePerHour = consumed / remainingH
    row.cyclePerHour = cycle
    row.recentPerHour = recent ? recent.rate : null
    row.recentHours = recent ? recent.hours : null
    row.alertUnusedPercent = alertUnused
    row.alertHours = alertHours
    rows.push(row)
  }

  rows.sort(function(a, b) {
    return (tierOf(a) - tierOf(b)) || (b.score - a.score) || (a.key < b.key ? -1 : (a.key > b.key ? 1 : 0))
  })
  // The score only orders the rows.
  for (var r = 0; r < rows.length; r++) delete rows[r].score
  return rows
}

// The subscription to use first, or null when none would waste anything.
function recommendation(rows) {
  for (var i = 0; i < (rows || []).length; i++)
    if (rows[i].status === "priority") return rows[i]
  return null
}

// The rows the panel's "Use first" list shows: a source with no window of a
// day or longer ("unknown") has no forecast to rank it by.
function listed(rows) {
  return (rows || []).filter(function(r) { return r.status !== "unknown" })
}

// "urgent" | "priority" | "on_track" | "blocked" | "unavailable" | "unknown":
// what a row's line says, urgency being a kind of priority.
function state(row) {
  if (!row) return "unknown"
  return row.status === "priority" && row.urgent ? "urgent" : row.status
}

// The quota Kian gets hungry over: the first urgent row, which the ranking
// already puts first (the most to lose per hour left). Null when none is.
function hungry(rows) {
  for (var i = 0; i < (rows || []).length; i++)
    if (state(rows[i]) === "urgent") return rows[i]
  return null
}
