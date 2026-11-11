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
// hyphen and the bare "auth" next to the reference's cues. Throttling is told
// by its wording ("rate limited", "rate limiting"), not by "rate limits" the
// noun: Codex's "answered without its rate limits" is no throttle. Nor is a
// gateway holding requests "until the account has credits again", which no
// retry fixes.
var RATE_LIMITED = /\brate[- ]?limit(?:ed|ing)\b|\brate[- ]?limit (?:exceeded|reached|hit)\b|\b429\b|too many requests|\bbackoff\b/i

function categoryOf(text) {
  for (var i = 0; i < PREFIXES.length; i++) if (PREFIXES[i].re.test(text)) return PREFIXES[i].category
  if (/not signed in|\bsign[- ]?in\b|log ?in|unauthori[sz]ed|\b401\b|\b403\b|expired token|re-?auth|\bauth\b/i.test(text)) return "credentials"
  if (/\buntil\b[^.]*\bcredits?\b|out of credits/i.test(text)) return "generic"
  if (RATE_LIMITED.test(text)) return "rate_limit"
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

// Collectors say when a rate-limited check will be tried again ("retry after
// 30s", "next attempt in 4m", "try again in 2 minutes"). 0 when no usable
// wait is named; a zero wait is as good as none.
var RETRY = /\b(?:retry(?:ing)?|try(?:ing)? again|next attempt|backoff)\s*(?:after|in|:)?\s*(\d+(?:\.\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h)\b/i

function retryAfterMs(text) {
  var match = RETRY.exec(String(text || ""))
  if (!match) return 0
  var unit = match[2].toLowerCase().charAt(0) === "h" ? 3600000 : match[2].toLowerCase().indexOf("m") === 0 ? 60000 : 1000
  var ms = Math.round(Number(match[1]) * unit)
  return isFinite(ms) && ms > 0 ? ms : 0
}

// The agent CLIs a notice's command may start, each with the only argument
// lists that sign it in ("" is the CLI on its own, which asks to sign in when
// it needs to). The notice text comes from the collectors, which pass a
// provider's own error messages through, so nothing else is ever run: no
// flag, no prompt, no other subcommand. Anything else (a package manager, a
// shell, an editor) is text to read, not a button to press.
var SIGN_IN = {
  "claude": ["auth login", ""],
  "codex": ["login", ""],
  "gemini": [""],
  "copilot": [""],
  "cursor-agent": ["login", ""],
  "grok": ["login", ""],
  "kimi": ["login", ""],
  "opencode": ["auth login"],
  "agy": [""],
  "devin": ["auth login"],
  "droid": [""],
  "qwen": [""],
  "vibe": [""],
  "muse": ["login", ""]
}

function agentClis() { return Object.keys(SIGN_IN) }

// The notice's command as an argument list, or [] when it is not one of the
// sign-in commands above.
function fixArgv(command) {
  var words = String(command || "").trim().split(/\s+/)
  var shapes = SIGN_IN.hasOwnProperty(words[0]) ? SIGN_IN[words[0]] : null
  if (!shapes || shapes.indexOf(words.slice(1).join(" ")) < 0) return []
  return words
}
