.pragma library
.import "Window.js" as Window
.import "Display.js" as Display
.import "Sources.js" as Sources

// Kian only worries about what affects you, and only for a while.
//
// A subscription getting close to its cap is a moment, not a state: when one
// you are using crosses 90% in the windows his mood watches (or a prepaid
// balance you are spending drops to its last 10%), he worries for ten
// minutes and then calms down. The same window doesn't worry him again until
// it drops back below 83% or starts over. The red meters, the tips and the
// desktop notices stay as the lasting signal.
//
// "In use" means one of the source's windows rose in the last two hours,
// read from the local history of fresh readings (usage/Priority.js) plus the
// current one. A nearly full subscription nobody is spending doesn't affect
// you, so it doesn't worry him.
//
// Two lasting moods remain: worried while EVERY subscription with limits is
// at 90% or more (nowhere to escape to), and tired while every one is maxed,
// which wins.
//
// decide() is pure: the state goes in and the next one comes out, for the
// caller to keep. A missing or corrupt state starts over quietly: whatever is
// already close is taken as already worried about, since worrying again
// about old news is worse than missing one moment.
//
// State: { since: ms the state was started,
//          seen: { sourceKey: fetchedAtMs },
//          keys: { "source::label" | "provider::balance":
//                  { noted: ms, worriedAt: ms (0 = recorded quietly), reset: ms | null } },
//          balances: { provider: { remaining, droppedAt } } }

var MINUTE_MS = Window.MINUTE_MS
var HOUR_MS = Window.HOUR_MS
var DAY_MS = Window.DAY_MS

// Where the meters turn red (Display.level's "critical").
var NEAR_PCT = 90
// A window worried about re-arms only once it drops this far, as in
// Notify.js, so one hovering at 90 (90, 89, 90) isn't news every refresh.
var REARM_BELOW_PCT = 83
// How long one crossing keeps him worried.
var WORRY_MS = 10 * MINUTE_MS
// The span a source counts as in use after a window of it last rose. Readings
// come every 15 minutes (3 near a limit) and the weekly share moves in whole
// points, so a shorter span would miss steady light use; two hours also
// carries over a lunch break, and is still well inside the 25 hours the
// history keeps.
var IN_USE_MS = 2 * HOUR_MS
// Points a window has to climb between two readings to count as spending:
// collectors report whole points, or fractions that can wobble.
var MIN_RISE_PCT = 0.5
// The last 10% of a prepaid balance lights the same alarm (Panel's
// balanceAlarming); a top-up past 15% re-arms it.
var LOW_BALANCE = 0.1
var BALANCE_REARM_ABOVE = 0.15
// A reported reset moving later by more than this is a new window (Notify's
// tolerance: jitter and a rolling window slide less between readings).
var RESET_MOVE_TOLERANCE_MS = 90 * MINUTE_MS
// A key for a window that is no longer reported is kept this long.
var KEY_TTL_MS = 35 * DAY_MS
var SKEW_MS = 2 * MINUTE_MS

function pct(fraction) {
  return Math.round(Number(fraction) * 10000) / 100
}

// The persisted state, read back: anything that isn't the expected shape is
// no state at all.
function parseState(text) {
  try {
    var s = JSON.parse(String(text || ""))
    if (s && typeof s === "object" && isFinite(s.since)
        && s.seen && typeof s.seen === "object" && !Array.isArray(s.seen)
        && s.keys && typeof s.keys === "object" && !Array.isArray(s.keys))
      return {
        since: Number(s.since), seen: s.seen, keys: s.keys,
        balances: s.balances && typeof s.balances === "object" && !Array.isArray(s.balances) ? s.balances : {}
      }
  } catch (e) {}
  return null
}

function serialize(state) {
  return JSON.stringify(state) + "\n"
}

// Whether any window of the source rose by MIN_RISE_PCT between two readings,
// the later one within IN_USE_MS of now. samples are the history's
// {source, window, at, percent}, oldest first; current, the source's own
// fresh reading as [{window, percent}] at currentAt (0 when not fresh).
function inUse(samples, sourceKey, nowMs, current, currentAt) {
  var from = nowMs - IN_USE_MS
  var last = {}
  var lastAt = {}
  var list = samples || []
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (!s || s.source !== sourceKey || !isFinite(s.at) || !isFinite(s.percent)) continue
    if (s.at > nowMs + SKEW_MS) continue
    var before = last[s.window]
    if (before !== undefined && s.at >= from && s.percent - before >= MIN_RISE_PCT) return true
    last[s.window] = s.percent
    lastAt[s.window] = s.at
  }
  if (!(currentAt >= from) || currentAt > nowMs + SKEW_MS) return false
  for (var j = 0; j < (current || []).length; j++) {
    var c = current[j]
    var prev = last[c.window]
    if (prev !== undefined && !(lastAt[c.window] >= currentAt) && c.percent - prev >= MIN_RISE_PCT) return true
  }
  return false
}

// Moves a source's past from its old key to its new one (a provider gaining
// or losing an account), as Notify.js does.
function carryOver(seen, keys, from, to) {
  seen[to] = seen[from]
  delete seen[from]
  var names = Object.keys(keys)
  for (var i = 0; i < names.length; i++) {
    if (names[i].indexOf(from + "::") !== 0) continue
    keys[to + names[i].slice(from.length)] = keys[names[i]]
    delete keys[names[i]]
  }
}

function resetMovedLater(current, recorded) {
  if (!isFinite(current)) return false
  if (recorded === null || recorded === undefined || !isFinite(recorded)) return true
  return current - Number(recorded) > RESET_MOVE_TOLERANCE_MS
}

// records: the panel's providers (or the raw usage records); samples: the
// usage history; opts: { moodWindow }. Returns
// { worried, tired, cornered, until, worriedAbout: [key], state }:
// worried covers both the ten-minute moments and being cornered; until is
// when the last moment ends (0 when none is running), for the caller's timer.
function decide(records, samples, prevState, nowMs, opts) {
  var moodWindow = Display.normalizeMoodWindow(opts && opts.moodWindow)
  var fresh = !prevState
  var prev = prevState || {}
  var since = fresh ? nowMs : Number(prev.since)
  var seen = Object.assign({}, prev.seen || {})
  var oldKeys = Object.assign({}, prev.keys || {})
  var oldBalances = prev.balances || {}
  var keys = {}
  var balances = {}

  var list = Sources.sources(records)
  for (var c = 0; c < list.length; c++) {
    var from = Sources.previousKey(list[c], seen)
    if (from !== "") carryOver(seen, oldKeys, from, list[c].key)
  }

  var withLimits = 0
  var tight = 0
  var maxed = 0
  var present = {}

  for (var i = 0; i < list.length; i++) {
    var src = list[i]
    var windows = Window.limitWindows(src.limits, nowMs)
    if (windows.length === 0) continue
    withLimits++
    var all = Display.fullest(windows)
    if (all && all.percent >= 1) maxed++
    var watched = Display.moodWindows(windows, moodWindow)
    var top = Display.fullest(watched)
    if (top && pct(top.percent) >= NEAR_PCT) tight++

    var future = src.fetchedAt > nowMs + SKEW_MS
    if (src.fetchedAt > 0 && !future && !(Number(seen[src.key]) >= src.fetchedAt)) seen[src.key] = src.fetchedAt
    // A reading taken before the state existed is old news.
    var quiet = fresh || !(src.fetchedAt >= since)
    var fresher = !src.stale && !future && src.fetchedAt > 0
    var current = []
    for (var w = 0; w < windows.length; w++)
      current.push({ window: windows[w].label, percent: pct(windows[w].percent) })
    var using = fresher && inUse(samples, src.key, nowMs, current, src.fetchedAt)

    for (var k = 0; k < watched.length; k++) {
      var win = watched[k]
      var key = src.key + "::" + win.label
      var p = pct(win.percent)
      var reset = Window.timeMs(win.resetAt)
      var known = oldKeys[key]
      present[key] = true
      if (p < REARM_BELOW_PCT) continue
      if (known && !resetMovedLater(reset, known.reset)) {
        // Still the same window: keep it, following a rolling reset forward.
        var kept = Object.assign({}, known)
        if (isFinite(reset) && !(Number(known.reset) >= reset)) kept.reset = reset
        keys[key] = kept
        continue
      }
      if (p < NEAR_PCT) continue
      if (quiet) keys[key] = { noted: nowMs, worriedAt: 0, reset: isFinite(reset) ? reset : null }
      else if (using) keys[key] = { noted: nowMs, worriedAt: nowMs, reset: isFinite(reset) ? reset : null }
      // Close but untouched: stays armed until it is spent from.
    }
  }

  // Prepaid balances, per provider record.
  var recs = records || []
  for (var r = 0; r < recs.length; r++) {
    var rec = recs[r]
    if (!rec || !rec.balance) continue
    var id = String(rec.providerId || rec.id || "")
    if (id === "") continue
    var remaining = Number(rec.balance.remaining)
    var funded = Number(rec.balance.funded)
    if (!isFinite(remaining) || remaining < 0) continue
    var bkey = id + "::balance"
    present[bkey] = true
    var before = oldBalances[id]
    var droppedAt = before && isFinite(before.droppedAt) ? Number(before.droppedAt) : 0
    if (before && isFinite(before.remaining) && remaining < Number(before.remaining)) droppedAt = nowMs
    balances[id] = { remaining: remaining, droppedAt: droppedAt }
    if (!(funded > 0)) continue
    var share = remaining / funded
    var bknown = oldKeys[bkey]
    if (share > BALANCE_REARM_ABOVE) continue
    if (bknown) { keys[bkey] = bknown; continue }
    if (share > LOW_BALANCE) continue
    var spending = droppedAt > 0 && nowMs - droppedAt <= IN_USE_MS
    if (fresh) keys[bkey] = { noted: nowMs, worriedAt: 0, reset: null }
    else if (spending) keys[bkey] = { noted: nowMs, worriedAt: nowMs, reset: null }
  }

  // Windows no longer reported keep their key for a while: a source that
  // comes back hasn't started over.
  for (var old in oldKeys) {
    if (present[old] || keys[old]) continue
    var o = oldKeys[old]
    if (o && nowMs - Number(o.noted) <= KEY_TTL_MS) keys[old] = o
  }

  var until = 0
  var about = []
  for (var name in keys) {
    var at = Number(keys[name].worriedAt)
    if (!(at > 0) || at > nowMs + SKEW_MS) continue
    var end = at + WORRY_MS
    if (end > nowMs) {
      about.push(name)
      until = Math.max(until, end)
    }
  }
  about.sort()

  var tired = withLimits > 0 && maxed >= withLimits
  var cornered = withLimits > 0 && tight >= withLimits
  return {
    worried: about.length > 0 || cornered,
    tired: tired,
    cornered: cornered,
    until: until,
    worriedAbout: about,
    state: { since: since, seen: seen, keys: keys, balances: balances }
  }
}

// The face, strongest first: tired, worried, out of breath, hungry.
function mood(flags) {
  var f = flags || {}
  if (f.tired) return "tired"
  if (f.worried) return "worried"
  if (f.panting) return "panting"
  if (f.hungry) return "hungry"
  return "normal"
}
