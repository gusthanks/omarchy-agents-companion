.pragma library
// Ported from ai-usagebar (MIT, (c) 2026 AkitaOnRails): omarchy/Notice.js

// Turns a collector's status or error text into a notice: what kind of
// trouble it is, a readable body and a command to copy. The text is data from
// outside; nothing parsed here is ever run, only shown or copied.

var PREFIXES = [
  { re: /^credentials? error:\s*/i, category: "credentials" },
  { re: /^auth(?:entication)? error:\s*/i, category: "credentials" },
  { re: /^http error:\s*/i, category: "network" },
  { re: /^network error:\s*/i, category: "network" }
]

var MAX_BODY = 400

// The collectors here say "Sign-in expired" and "Waiting for auth", hence the
// hyphen and the bare "auth" next to the reference's cues.
function categoryOf(text) {
  for (var i = 0; i < PREFIXES.length; i++) if (PREFIXES[i].re.test(text)) return PREFIXES[i].category
  if (/not signed in|\bsign[- ]?in\b|log ?in|unauthori[sz]ed|\b401\b|\b403\b|expired token|re-?auth|\bauth\b/i.test(text)) return "credentials"
  if (/rate.?limit|\b429\b|too many requests|backoff/i.test(text)) return "rate_limit"
  if (/timed? ?out|timeout|connect|dns|network|unreachable|\b5\d\d\b/i.test(text)) return "network"
  return "generic"
}

// A command is a `backticked` run that a cue word introduces ("Run `codex
// login`", "sign in with `droid`"), or the text after a trailing "with:" or
// "run:". It must also be shaped like one: an executable-like first word and
// no shell control characters. Backticked prose ("see `the docs page`") has no
// cue and is not offered.
var CUED = /\b(?:run|with|use|try|execute)\s*:?\s*`([^`\n]{2,120})`/i
var TRAILING = /\b(?:with|run):\s*([a-z][\w.\/-]*(?: [\w@.\/=-]+){0,6})\s*\.?$/i

function commandOf(text) {
  var value = String(text || "")
  var match = CUED.exec(value) || TRAILING.exec(value)
  if (!match) return ""
  var command = match[1].trim()
  return /^[A-Za-z0-9_.\/-]+(?: [^`$;&|<>(){}\\]+)?$/.test(command) ? command : ""
}

// One line, no control characters, a sane length: it ends up in a toast.
function clean(text) {
  var value = String(text || "").replace(/[\u0000-\u001f\u007f]+/g, " ").replace(/\s+/g, " ").trim()
  return value.length > MAX_BODY ? value.slice(0, MAX_BODY - 1) + "…" : value
}

function cleanBody(text) {
  var body = clean(text)
  for (var i = 0; i < PREFIXES.length; i++) body = body.replace(PREFIXES[i].re, "")
  body = body.replace(/`([^`\n]+)`/g, "\"$1\"")
  return body.charAt(0).toUpperCase() + body.slice(1)
}

// kind: "error" | "info". The category says whether a retry can help.
function build(message, kind, forcedCategory) {
  var text = clean(message)
  if (text === "") return null
  var category = forcedCategory || categoryOf(text)
  return {
    kind: kind === "info" ? "info" : "error",
    category: category,
    body: cleanBody(text),
    command: commandOf(text),
    retry: kind !== "info" && (category === "network" || category === "rate_limit")
  }
}

// A record's status ("Sign-in expired") with its help line ("Run `claude auth
// login` to ..."): the status names the trouble, the help carries the fix.
function fromStatus(status, help) {
  var s = clean(status)
  var h = clean(help)
  if (s === "") return build(h, "error")
  var joined = h === "" ? s : s + (/[.!?]$/.test(s) ? " " : ". ") + h
  var notice = build(joined, "error")
  notice.category = categoryOf(s) !== "generic" ? categoryOf(s) : categoryOf(h)
  notice.retry = notice.category === "network" || notice.category === "rate_limit"
  return notice
}
