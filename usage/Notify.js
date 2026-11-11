.pragma library
// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): src/notify.rs
.import "Window.js" as Window
.import "Sources.js" as Sources

// Which notices a refresh raises. A window crossing the threshold raises one
// per crossing, and one more, critical, if it then gets spent (a crossing
// that is already at 100% is critical at once). A banked Codex reset credit
// raises one per expiry, 48 hours before it lapses. Only fresh fetches count:
// a source is looked at when its fetch time moved past the last one seen and
// it isn't a cached fallback, so a stale reading neither fires nor re-arms.
//
// decide() is pure: the state goes in and the next one comes out, for the
// caller to keep. Notifications are data (who, which window, how far); the
// wording is the panel's job.
//
// quietBeforeMs (optional): a source the state has never seen, read before
// that instant, is recorded without firing. It is the plugin's start: a
// reading already on disk when Kian started watching (a first run, a lost
// state file, a new account) is old news the panel shows anyway, while a
// source the state knows keeps firing for a reading taken while the shell
// was down, since that one is new. A provider gaining or losing an account
// changes its source key ("claude" to "claude@work"); the old key's past
// moves to the new one first, so the same window isn't news again.
//
// State: { seen: { sourceKey: fetchedAtMs },
//          keys: { "source::label" | "source::credit::expiresMs":
//                  { notifiedAt, reset, level: "normal" | "critical" } } }

var DEFAULT_THRESHOLD = 97
// A notified window re-arms only once it drops this far below the threshold,
// so one hovering at it (97, 96, 97) doesn't fire on every refresh.
var HYSTERESIS_PCT = 7
// A reported reset has to move later by more than this to be a new window:
// the instant jitters between fetches and a rolling window slides forward
// with each refresh, but a real new window moves it by hours.
var RESET_MOVE_TOLERANCE_MS = 90 * 60 * 1000
var CREDIT_WARNING_MS = 48 * Window.HOUR_MS
// Past the longest window, a crossing record is only clutter.
var KEY_TTL_MS = 35 * Window.DAY_MS
// A fetch stamped further ahead than this is a clock that ran ahead (before
// an NTP sync, say): it neither decides nor holds back the real ones after it.
var SKEW_MS = 2 * 60 * 1000

function normalizeThreshold(value) {
  if (value === null || value === undefined || String(value).trim() === "") return DEFAULT_THRESHOLD
  var n = Number(value)
  return isFinite(n) ? Math.max(1, Math.min(100, Math.round(n))) : DEFAULT_THRESHOLD
}

// A later reset than the one recorded is a new window; a reset appearing where
// none was reported counts too. Going back, or disappearing, does not.
function resetMovedLater(current, recorded) {
  if (!isFinite(current)) return false
  if (recorded === null || recorded === undefined || !isFinite(recorded)) return true
  return current - Number(recorded) > RESET_MOVE_TOLERANCE_MS
}

// Moves a source's past from its old key to its new one: its last fetch and
// every crossing and credit recorded under it.
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

function decide(records, threshold, prevState, nowMs, quietBeforeMs) {
  var limit = normalizeThreshold(threshold)
  var rearmBelow = limit - HYSTERESIS_PCT
  var prev = prevState || {}
  var seen = Object.assign({}, prev.seen || {})
  var keys = {}
  var prevKeys = prev.keys || {}
  for (var old in prevKeys) {
    var rec = prevKeys[old]
    if (!rec || !(nowMs - Number(rec.notifiedAt) <= KEY_TTL_MS)) continue
    // A credit's key is spent once the credit itself has lapsed.
    if (old.indexOf("::credit::") >= 0 && !(Number(rec.reset) > nowMs)) continue
    keys[old] = rec
  }

  var fired = []
  var list = Sources.sources(records)
  for (var c = 0; c < list.length; c++) {
    var from = Sources.previousKey(list[c], seen)
    if (from !== "") carryOver(seen, keys, from, list[c].key)
  }
  for (var i = 0; i < list.length; i++) {
    var src = list[i]
    if (src.stale || src.fetchedAt > nowMs + SKEW_MS) continue
    var last = Number(seen[src.key])
    if (!(last <= nowMs + SKEW_MS)) last = 0
    if (!(src.fetchedAt > last)) continue
    var quiet = seen[src.key] === undefined && src.fetchedAt < Number(quietBeforeMs || 0)
    seen[src.key] = src.fetchedAt
    var who = { source: src.key, provider: src.provider, name: src.name, account: src.account, accountLabel: src.accountLabel }

    var windows = Window.limitWindows(src.limits, nowMs)
    for (var w = 0; w < windows.length; w++) {
      var win = windows[w]
      var key = src.key + "::" + win.label
      var pct = Math.round(win.percent * 100)
      var reset = Window.timeMs(win.resetAt)
      if (pct >= limit) {
        var level = pct >= 100 ? "critical" : "normal"
        var known = keys[key]
        var armed = !known || resetMovedLater(reset, known.reset)
        // The same crossing, now spent: the critical notice, once. A key
        // without a level is taken to have had it.
        var spent = !armed && level === "critical" && known.level === "normal"
        if (!armed && !spent) continue
        keys[key] = { notifiedAt: nowMs, reset: isFinite(reset) ? reset : (known ? known.reset : null), level: level }
        if (!quiet) fired.push(Object.assign({
          kind: "limit", key: key,
          urgency: level,
          window: win.label, title: win.title, percent: pct, resetAt: win.resetAt
        }, who))
      } else if (pct < rearmBelow) {
        delete keys[key]
      }
    }

    var credits = src.resetCredits
    var expires = credits ? Window.timeMs(credits.nextExpiresAt) : NaN
    if (credits && Number(credits.available) > 0 && isFinite(expires)) {
      var left = expires - nowMs
      var creditKey = src.key + "::credit::" + expires
      if (left > 0 && left <= CREDIT_WARNING_MS && !keys[creditKey]) {
        keys[creditKey] = { notifiedAt: nowMs, reset: expires }
        if (!quiet) fired.push(Object.assign({
          kind: "credit", key: creditKey, urgency: "normal",
          count: Number(credits.available), expiresAt: expires
        }, who))
      }
    }
  }
  return { notifications: fired, nextState: { seen: seen, keys: keys } }
}

// ---------------------------------------------------------------- delivery

var APP_NAME = "Agents Pet"
// Omarchy's notifier keeps a critical toast until it is dismissed unless the
// sender asks for a timeout; a spent limit is worth seeing, not pinning.
var CRITICAL_TIMEOUT_MS = 30000

// One line of plain text: provider names and labels come from the usage
// records, so control characters go, and a leading dash can't pass for a
// notify-send switch.
function oneLine(text) {
  var s = String(text === undefined || text === null ? "" : text)
  s = s.replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  return s.replace(/^-+\s*/, "").slice(0, 240)
}

// Notification daemons read the body as markup.
function escapeMarkup(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// notify-send's argv for one notice, run as a process: never a shell string.
// The switches come first; notify-send reads the trailing two as title and
// body. Without an icon path the notice simply goes without one.
function sendArgs(urgency, title, body, iconPath) {
  var critical = urgency === "critical"
  var args = ["notify-send", "-a", APP_NAME, "-u", critical ? "critical" : "normal"]
  if (critical) args.push("-t", String(CRITICAL_TIMEOUT_MS))
  if (iconPath) args.push("-i", String(iconPath))
  args.push(oneLine(title), escapeMarkup(oneLine(body)))
  return args
}

// The persisted state, read back: anything that isn't the expected shape is
// no state at all (nothing notified, every source unseen).
function parseState(text) {
  try {
    var s = JSON.parse(String(text || ""))
    if (s && typeof s === "object" && s.seen && typeof s.seen === "object" && s.keys && typeof s.keys === "object")
      return { seen: s.seen, keys: s.keys }
  } catch (e) {}
  return null
}
