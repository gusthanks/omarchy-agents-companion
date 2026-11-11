.pragma library

// Recent custom colors. The panel cleans what it reads from the config (even
// while the editor isn't loaded) and the editor cleans what it adds, so both
// share this one rule.

// Only valid #rrggbb, distinct ignoring case, newest first, at most 8.
function cleanRecent(list) {
  var out = []
  if (!Array.isArray(list)) return out
  for (var i = 0; i < list.length && out.length < 8; i++) {
    var c = String(list[i]).toLowerCase()
    if (/^#[0-9a-f]{6}$/.test(c) && out.indexOf(c) < 0) out.push(c)
  }
  return out
}
