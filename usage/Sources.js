.pragma library

// One "source" per set of limits: the provider itself, or each of its
// accounts once it has more than one (the panel's own rule for showing them).
// Accepts the panel's provider objects (providerId, limitsStale,
// limitsFetchedAt) as well as the raw usage records (id).
//
// key is "provider" or "provider@account", stable across refreshes, and is
// what the history and notification state are keyed by.
function sources(records) {
  var out = []
  var list = records || []
  for (var i = 0; i < list.length; i++) {
    var r = list[i]
    if (!r) continue
    var id = String(r.providerId || r.id || "")
    if (id === "") continue
    var name = String(r.providerName || r.name || id)
    var accounts = Array.isArray(r.accounts) ? r.accounts : []
    if (accounts.length > 1) {
      for (var a = 0; a < accounts.length; a++) {
        var acc = accounts[a]
        if (!acc || acc.id === undefined || acc.id === null) continue
        out.push({
          key: id + "@" + String(acc.id),
          provider: id,
          account: String(acc.id),
          name: name,
          accountLabel: String(acc.label || acc.id),
          ready: true,
          limits: Array.isArray(acc.limits) ? acc.limits : [],
          stale: acc.stale === true,
          fetchedAt: Number(acc.fetchedAt) || 0,
          resetCredits: acc.resetCredits || null
        })
      }
      continue
    }
    out.push({
      key: id,
      provider: id,
      account: "",
      name: name,
      accountLabel: "",
      ready: r.ready !== false,
      limits: Array.isArray(r.limits) ? r.limits : [],
      stale: r.limitsStale === true,
      fetchedAt: Number(r.limitsFetchedAt) || 0,
      resetCredits: r.resetCredits || null
    })
  }
  return out
}
