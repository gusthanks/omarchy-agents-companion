.pragma library
// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): src/notify.rs
.import "Window.js" as Window
.import "Sources.js" as Sources

// Which notices a refresh raises. A window crossing the threshold raises one
// per crossing (critical once it is spent), and a banked Codex reset credit
// raises one per expiry, 48 hours before it lapses. Only fresh fetches count:
// a source is looked at when its fetch time moved past the last one seen and
// it isn't a cached fallback, so a stale reading neither fires nor re-arms.
//
// decide() is pure: the state goes in and the next one comes out, for the
// caller to keep. Notifications are data (who, which window, how far); the
// wording is the panel's job.
//
// State: { seen: { sourceKey: fetchedAtMs },
//          keys: { "source::label" | "source::credit::expiresMs":
//                  { notifiedAt, reset } } }

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

function decide(records, threshold, prevState, nowMs) {
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
  for (var i = 0; i < list.length; i++) {
    var src = list[i]
    if (src.stale || !(src.fetchedAt > Number(seen[src.key] || 0))) continue
    seen[src.key] = src.fetchedAt
    var who = { source: src.key, provider: src.provider, name: src.name, account: src.account, accountLabel: src.accountLabel }

    var windows = Window.limitWindows(src.limits, nowMs)
    for (var w = 0; w < windows.length; w++) {
      var win = windows[w]
      var key = src.key + "::" + win.label
      var pct = Math.round(win.percent * 100)
      var reset = Window.timeMs(win.resetAt)
      if (pct >= limit) {
        var armed = !keys[key] || resetMovedLater(reset, keys[key].reset)
        if (!armed) continue
        keys[key] = { notifiedAt: nowMs, reset: isFinite(reset) ? reset : null }
        fired.push(Object.assign({
          kind: "limit", key: key,
          urgency: pct >= 100 ? "critical" : "normal",
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
        fired.push(Object.assign({
          kind: "credit", key: creditKey, urgency: "normal",
          count: Number(credits.available), expiresAt: expires
        }, who))
      }
    }
  }
  return { notifications: fired, nextState: { seen: seen, keys: keys } }
}
