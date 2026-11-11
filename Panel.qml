import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "gusthx.agents-pet"
  ipcTarget: "gusthx.agents-pet"
  manageIpc: false

  // Items inside the panel's lazily built content, null until it first
  // opens. Code inside the content reaches its own ids directly.
  readonly property Item panelFlick: panel.loadedContent ? panel.loadedContent.panelFlick : null
  readonly property Item hero: panel.loadedContent ? panel.loadedContent.hero : null
  readonly property Item column: panel.loadedContent ? panel.loadedContent.column : null
  readonly property Item providerSections: panel.loadedContent ? panel.loadedContent.providerSections : null
  readonly property Item petEditor: panel.loadedContent ? panel.loadedContent.petEditor : null

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // Persisted pet: name + look, written by the inline editor.
  readonly property string petConfigPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/agents-pet.json"

  FileView {
    id: petConfigFile
    path: root.petConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  readonly property var petConfig: {
    var raw = petConfigFile.text()
    if (raw && raw.trim() !== "") {
      try { return JSON.parse(raw) } catch (e) {}
    }
    return ({})
  }

  readonly property string companionName: String(petConfig.name || setting("companionName", "Kian")).trim() || "Kian"
  readonly property var petLook: petConfig.look || ({})
  // Bar pet as a share of the bar's height (theme token size-horizontal), so a
  // taller bar gets a bigger pet. The bar itself never grows for the pet.
  readonly property real barPetSize: Math.round(Style.bar.sizeHorizontal * (petBarSize === "s" ? 0.7 : (petBarSize === "l" ? 0.96 : 0.85)))
  readonly property real petHeroSize: Style.space(petPanelSize === "s" ? 44 : (petPanelSize === "l" ? 66 : 54))
  // s | m | l for the bar and the panel. Configs from before the two sizes
  // have one "size" for both; the next write stores them apart.
  function petSizeOf(key) {
    var ok = ["s", "m", "l"]
    if (ok.indexOf(petConfig[key]) >= 0) return petConfig[key]
    return ok.indexOf(petConfig.size) >= 0 ? petConfig.size : "m"
  }
  readonly property string petBarSize: petSizeOf("barSize")
  readonly property string petPanelSize: petSizeOf("panelSize")
  // Replaced only when the list really changes: every config write parses a
  // new array, and a new one would rebuild every saved-pet card in the editor.
  property var petSaved: []
  property string petSavedJson: "[]"
  function syncPetSaved() {
    var list = Array.isArray(petConfig.saved) ? petConfig.saved : []
    var json = JSON.stringify(list)
    if (json === petSavedJson) return
    petSavedJson = json
    petSaved = list
  }
  onPetConfigChanged: syncPetSaved()
  Component.onCompleted: syncPetSaved()
  // How lively the pet's reactions are: lively | calm | still.
  readonly property string petReactions: ["lively", "calm", "still"].indexOf(petConfig.reactions) >= 0 ? petConfig.reactions : "lively"
  Commons.Translations { id: petStrings; directory: Qt.resolvedUrl("i18n") }
  ThemePalette { id: petPalette }
  property bool petEditing: false
  // The pet editor's open tab, kept while the panel stays loaded.
  property int petTab: 0
  onPetEditingChanged: if (petEditing && panelFlick) panelFlick.contentY = 0

  // Merge a change into the pet config file and write it back.
  function writePet(patch) {
    var cfg = { name: petConfig.name || "", look: petLook, barSize: petBarSize, panelSize: petPanelSize, saved: petSaved }
    if (petConfig.reactions !== undefined) cfg.reactions = petConfig.reactions
    for (var k in patch) cfg[k] = patch[k]
    petConfigFile.setText(JSON.stringify(cfg, null, 2) + "\n")
  }

  // Capped at 24: the editor disables Save and says so instead of silently
  // dropping the oldest pet.
  function savePetToInventory() {
    if (petSaved.length >= 24) return
    var list = petSaved.slice()
    list.push({ name: petConfig.name || "", look: petLook })
    writePet({ saved: list })
  }

  // Undo snapshots and restored backups: put back whatever keys they carry.
  function restorePet(s) {
    var patch = {}
    var keys = ["name", "look", "saved", "barSize", "panelSize", "reactions"]
    for (var i = 0; i < keys.length; i++) if (s && s[keys[i]] !== undefined) patch[keys[i]] = s[keys[i]]
    writePet(patch)
  }

  function wearSavedPet(i) {
    var p = petSaved[i]
    if (p) writePet({ name: p.name || "", look: p.look || ({}) })
  }

  function forgetSavedPet(i) {
    var list = petSaved.slice()
    list.splice(i, 1)
    writePet({ saved: list })
  }

  // Mood follows the limits: worried when one is close (the same rule that
  // turns the stock icon urgent), tired when every subscription is maxed out.
  readonly property var maxedProviders: {
    var out = []
    for (var i = 0; i < providers.length; i++) {
      var w = bindingWindow(providers[i])
      if (w && w.percent >= 1) out.push(providers[i].providerId || providers[i].providerName || String(i))
    }
    return out
  }
  readonly property bool allMaxed: {
    var withLimits = 0
    for (var i = 0; i < providers.length; i++) if (bindingWindow(providers[i])) withLimits++
    return withLimits > 0 && maxedProviders.length >= withLimits
  }
  readonly property string petMood: allMaxed ? "tired" : (alarming ? "worried" : "normal")

  // A subscription coming back from its cap is worth a little party; one
  // newly hitting its cap gets an "oof".
  property var lastMaxed: []
  // Providers that had a known limit below the cap last time, so a cap seen
  // for the first time at startup doesn't count as "newly maxed".
  property var lastUnderCap: []
  property double lastCelebrateMs: 0
  onMaxedProvidersChanged: {
    var present = {}
    var under = []
    for (var j = 0; j < providers.length; j++) {
      var id = providers[j].providerId || providers[j].providerName || String(j)
      present[id] = true
      var w = bindingWindow(providers[j])
      if (w && w.percent < 1) under.push(id)
    }
    var back = false
    for (var i = 0; i < lastMaxed.length; i++)
      if (maxedProviders.indexOf(lastMaxed[i]) < 0 && present[lastMaxed[i]]) back = true
    var hit = false
    for (var m = 0; m < maxedProviders.length; m++)
      if (lastUnderCap.indexOf(maxedProviders[m]) >= 0) hit = true
    lastMaxed = maxedProviders
    lastUnderCap = under
    if (back) petCelebrate()
    else if (hit) petReact("oof")
  }

  function petCelebrate() {
    lastCelebrateMs = Date.now()
    barPet.celebrate()
    var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
    if (hero && root.opened) hero.celebrate()
  }

  // Play a reaction on the bar pet and, while the panel is open, the big one.
  function petReact(name, opts) {
    var ok = barPet.play(name, opts)
    var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
    if (hero && root.opened) ok = hero.play(name, opts) || ok
    return ok
  }

  // A sigh of relief when a limit stops being close without a party.
  property string lastPetMood: "normal"
  onPetMoodChanged: {
    var was = lastPetMood
    lastPetMood = petMood
    if (was === "worried" && petMood === "normal") Qt.callLater(function() {
      if (Date.now() - root.lastCelebrateMs > 3000) {
        var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
        if (hero && root.opened) hero.play("sigh")
      }
    })
  }

  // The pet thinks while usage refreshes. Debounced so cached runs that
  // finish at once don't flash; the bar pet only shows the pose.
  property double thinkingSince: 0
  Timer {
    id: thinkingDebounce
    interval: 400
    onTriggered: if (usage.updating) root.petThink(true)
  }
  Connections {
    target: usage
    function onUpdatingChanged() {
      if (usage.updating) thinkingDebounce.restart()
      else { thinkingDebounce.stop(); root.petThink(false) }
    }
  }
  function petThink(on) {
    var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
    if (on) {
      thinkingSince = Date.now()
      barPet.play("thinking")
      if (hero && root.opened) hero.play("thinking")
    } else {
      barPet.stop("thinking")
      if (hero) hero.stop("thinking")
    }
  }
  // Thinking is dropped while a stronger reaction plays; pick it up after.
  function retryThinking(pet) {
    if (usage.updating && root.opened && pet.reaction === "" && Date.now() - thinkingSince < 60000)
      Qt.callLater(function() { if (usage.updating && pet.reaction === "") pet.play("thinking") })
  }

  // Forcing refreshes over and over kicks up dust.
  property var refreshTimes: []
  function countRefresh() {
    var t = Date.now()
    var list = refreshTimes.filter(function(x) { return t - x < 30000 })
    list.push(t)
    refreshTimes = list
    if (list.length === 5) {
      var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
      if (hero && root.opened) hero.play("sneeze", { priority: 2 })
    }
  }

  // A wink the first time the panel opens each hour (and a hop on Mondays).
  property string lastGreetHour: ""
  Timer {
    id: greetTimer
    interval: 350
    onTriggered: {
      var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
      if (!hero || !root.opened) return
      var d = new Date()
      hero.play("wink", { priority: 2, next: d.getDay() === 1 ? "hop" : "" })
    }
  }
  property bool tipBannerHovered: false

  readonly property int totalTokensToday: {
    var rev = usage ? usage.dataRevision : 0
    var total = 0
    var providers = usage ? usage.enabledProviders : []
    for (var i = 0; i < providers.length; i++) {
      total += Number(providers[i].todayTotalTokens || 0)
    }
    return total
  }

  readonly property int totalTokensWeek: {
    var rev = usage ? usage.dataRevision : 0
    var total = 0
    var providers = usage ? usage.enabledProviders : []
    for (var i = 0; i < providers.length; i++) {
      var days = providers[i].recentDays || []
      for (var d = 0; d < days.length; d++) {
        total += Number(days[d].messageCount || 0)
      }
    }
    return total
  }

  // The banner follows an insight by key, not by position: the list is rebuilt
  // as records land and tips come and go, and indexing it would swap the line
  // mid-read. Numbers inside the shown tip still update live.
  property string shownInsightKey: ""
  function insightIndex(key) {
    for (var i = 0; i < deepInsights.length; i++) if (deepInsights[i].key === key) return i
    return -1
  }
  readonly property var currentInsight: {
    if (deepInsights.length === 0) return null
    var i = insightIndex(shownInsightKey)
    return deepInsights[i >= 0 ? i : 0]
  }
  function advanceInsight() {
    if (deepInsights.length === 0) return
    var i = insightIndex(shownInsightKey)
    shownInsightKey = deepInsights[(i + 1) % deepInsights.length].key
  }
  readonly property bool currentInsightIsAlert: !!(currentInsight && currentInsight.alert)
  readonly property string currentInsightBadge: currentInsight ? currentInsight.badge : ""
  readonly property string currentInsightIcon: currentInsight ? currentInsight.icon : ""


  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color surface: Commons.Color.popups.background
  readonly property color track: Style.selectedFillFor(foreground, Commons.Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Every subscription on one page, limits first: the question this panel
  // answers is how much room is left, and where.
  readonly property var providers: usage.subscribedProviders

  property bool cursorActive: false

  // Countdowns and "last updated" ages read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  // Every account of every provider that has more than one, in page order.
  // The keyboard picks one by its position; picking only looks, and Enter on
  // a picked account is what moves new sessions to it.
  readonly property var accountEntries: {
    var out = []
    for (var i = 0; i < providers.length; i++) {
      var list = providerAccounts(providers[i])
      if (list.length < 2) continue
      for (var j = 0; j < list.length; j++) out.push({ provider: providers[i], account: list[j] })
    }
    return out
  }
  readonly property var pickedEntry: keyTarget && ["account", "autoswitch", "signin"].indexOf(keyTarget.kind) >= 0
    ? accountEntries[keyTarget.index] || null
    : null

  // The keyboard walks everything on the page that does something, in
  // reading order, one row at a time: the hero's buttons, then each agent's
  // header, its Sign-in required link or switchable accounts, and the starter
  // tiles, or the agents to add while picking one. Up and down change rows, left and right move along one.
  // Hovering moves the same cursor, so only one thing is lit.
  readonly property var keyRows: {
    var rows = []
    var hero = []
    if (addButtonShown) hero.push({ kind: "add", index: 0 })
    if (addStage === "") hero.push({ kind: "pet", index: 0 })
    if (addStage === "") hero.push({ kind: "launch", index: 0 })
    if (hero.length > 0) rows.push(hero)
    // The editor replaces the agents below the hero, so only its own rows.
    if (petEditing && addStage === "" && petEditor) return rows.concat(petEditor.keyRows)
    if (picking) {
      var choices = []
      for (var k = 0; k < addProviders.length; k++) choices.push({ kind: "choice", index: k })
      rows.push(choices)
    } else if (addStage === "") {
      // Accounts count in the same order as accountEntries. Only what can be
      // done is a stop: one that isn't active offers Autoswitch beside Use, a
      // lapsed sign-in comes first, and the active account with nothing to
      // fix is skipped.
      var entry = 0
      for (var p = 0; p < providers.length; p++) {
        // Every agent's header is a stop, so Ctrl+Up/Down can move it.
        rows.push([{ kind: "provider", index: p }])
        var accounts = providerAccounts(providers[p])
        if (accounts.length < 2) {
          if (needsSignIn(providers[p])) rows.push([{ kind: "providerSignin", index: p }])
          continue
        }
        for (var a = 0; a < accounts.length; a++, entry++) {
          var row = []
          if (needsSignIn(accounts[a])) row.push({ kind: "signin", index: entry })
          if (!accounts[a].active) {
            row.push({ kind: "autoswitch", index: entry })
            row.push({ kind: "account", index: entry })
          }
          if (row.length > 0) rows.push(row)
        }
      }
    }
    return rows
  }
  property int keyRow: 0
  property int keyColumn: 0
  readonly property var keyTarget: {
    if (!cursorActive || keyRow < 0 || keyRow >= keyRows.length) return null
    var row = keyRows[keyRow]
    return row[Math.min(keyColumn, row.length - 1)]
  }

  function hasKey(kind, index) {
    return !!keyTarget && keyTarget.kind === kind && keyTarget.index === (index || 0)
  }

  function pointAt(kind, index) {
    for (var r = 0; r < keyRows.length; r++) {
      for (var c = 0; c < keyRows[r].length; c++) {
        if (keyRows[r][c].kind === kind && keyRows[r][c].index === (index || 0)) {
          keyRow = r
          keyColumn = c
          cursorActive = true
          return
        }
      }
    }
  }

  // The first arrow only shows where the cursor is, as in the other panels.
  function moveKey(dx, dy) {
    if (keyRows.length === 0) return
    if (!cursorActive) {
      keyRow = clamp(keyRow, 0, keyRows.length - 1)
      keyColumn = 0
      cursorActive = true
      return
    }
    if (dy !== 0) {
      keyRow = clamp(keyRow + dy, 0, keyRows.length - 1)
      // Arriving on an account lands on Use; left reaches Autoswitch.
      var row = keyRows[keyRow]
      var use = -1
      for (var c = 0; c < row.length; c++) if (row[c].kind === "account") use = c
      keyColumn = use >= 0 ? use : Math.min(keyColumn, row.length - 1)
    } else if (dx !== 0) {
      keyColumn = clamp(Math.min(keyColumn, keyRows[keyRow].length - 1) + dx, 0, keyRows[keyRow].length - 1)
    }
  }

  // The agent the cursor is in, by its position on the page.
  function providerIndexOfKey() {
    var target = keyTarget
    if (!target) return -1
    if (target.kind === "provider" || target.kind === "providerSignin") return target.index
    if (["account", "autoswitch", "signin"].indexOf(target.kind) < 0) return -1
    var entry = accountEntries[target.index]
    return entry ? providers.indexOf(entry.provider) : -1
  }

  // Ctrl+Up/Down carries the agent the cursor is in up or down the page, and
  // the cursor along with it.
  function reorderProvider(dy) {
    var from = providerIndexOfKey()
    if (from < 0) return
    var to = clamp(from + dy, 0, providers.length - 1)
    if (to === from) return
    usage.moveProvider(providers[from].providerId, to)
    Qt.callLater(function() { pointAt("provider", to) })
  }

  // Dragging an agent by its mark lights the header it would land on, and
  // moves it there on release: the sections are rebuilt when the order
  // changes, which would drop a drag still in progress.
  property string dragProviderId: ""
  property int dragTarget: -1
  // An account name being edited keeps Ctrl+Up/Down: moving its agent would
  // rebuild the section and drop the unfinished name.
  property bool renaming: false

  function dragProviderOver(y) {
    if (!providerSections) return
    for (var i = 0; i < providerSections.count; i++) {
      var item = providerSections.itemAt(i)
      if (item && y >= item.y && y < item.y + item.height) {
        dragTarget = i
        return
      }
    }
  }

  function dropProvider() {
    var id = dragProviderId
    var to = dragTarget
    dragProviderId = ""
    dragTarget = -1
    if (id === "" || to < 0) return
    usage.moveProvider(id, to)
    Qt.callLater(function() { pointAt("provider", to) })
  }

  // Keeps whatever the cursor lands on inside the scrolled view.
  function revealItem(item) {
    if (!item || !column || !panelFlick || !panelFlick.interactive) return
    var top = item.mapToItem(column, 0, 0).y
    var margin = Style.space(12)
    if (top - margin < panelFlick.contentY)
      panelFlick.contentY = Math.max(0, top - margin)
    else if (top + item.height + margin > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(panelFlick.contentHeight - panelFlick.height, top + item.height + margin - panelFlick.height)
  }

  // The bar icon lights up when any account new sessions use is nearly out,
  // or a prepaid balance is down to its last 10%.
  readonly property bool alarming: {
    for (var i = 0; i < providers.length; i++) {
      var window = bindingWindow(providers[i])
      if (window && window.percent >= 0.9) return true
      if (balanceAlarming(providers[i].balance)) return true
    }
    return false
  }

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  // A provider's accounts, when it has any. The list arrives as a sequence
  // rather than a JS array once it has passed through a model, so it's
  // judged by its length.
  function providerAccounts(p) {
    return p && p.accounts && p.accounts.length > 0 ? p.accounts : []
  }

  function refreshNow() {
    countRefresh()
    usage.refreshAll(true)
  }

  // ------------------------------------------------------------ adding
  //
  // Adding a subscription happens right here: pick a provider, name it if
  // it's a second account, then sign in through the browser while the panel
  // follows omarchy-agent-account-add --events. The browser taking focus may
  // close the panel; the login carries on, and its result arrives as a
  // notification too.

  readonly property var addProviders: [
    { providerId: "claude", providerName: "Claude Code" },
    { providerId: "codex", providerName: "Codex" },
    { providerId: "grok", providerName: "Grok" }
  ]
  property string addStage: ""
  property string addProvider: ""
  property var addChecks: ({})
  property string addStatus: ""
  property string addCode: ""
  property string addUrl: ""
  property bool addNeedsPaste: false
  property string addResult: ""
  // Whether the sign-in in progress opened a private window, so reopening its
  // page does too.
  property bool addPrivate: false

  function addProviderName(id) {
    for (var i = 0; i < addProviders.length; i++)
      if (addProviders[i].providerId === id) return addProviders[i].providerName
    return id
  }

  function addAccount() {
    if (addStage === "running") return
    addStage = "pick"
    addChecks = ({})
    if (!checkProcess.running) checkProcess.running = true
  }

  function chooseAddProvider(id) {
    var state = addChecks[id] || ""
    if (state === "") return
    addProvider = id
    if (state === "additional") addStage = "name"
    else startAdd("")
  }

  function startAdd(label) {
    addPrivate = (addChecks[addProvider] || "") === "additional"
    addStatus = petStrings.t("agents.starting")
    addCode = ""
    addUrl = ""
    // Claude's login offers pasting a code back whenever its page shows one,
    // and its prompt for it has no newline to read it by, so the field is
    // there from the start.
    addNeedsPaste = addProvider === "claude"
    addResult = ""
    addStage = "running"
    addProcess.command = ["omarchy-agent-account-add", "--events", addProvider].concat(label !== "" ? [label] : [])
    addProcess.running = true
  }

  function cancelAdd() {
    if (addProcess.running) addProcess.signal(15)
    addStage = ""
    root.focusKeys()
  }

  // A first sign-in keeps saying so until its limits arrive, rather than
  // flashing the choices again while the record is written.
  onBlankSlateChanged: if (!blankSlate && addStage === "done") addStage = ""

  function submitPaste(code) {
    if (!addProcess.running || code.trim() === "") return
    addProcess.write(code.trim() + "\n")
    addStatus = petStrings.t("agents.checkingCode")
  }

  // The add command's own lines are tagged; everything else is the CLI
  // talking, and only two things in it matter here: a code to confirm in the
  // browser (Grok), and an invitation to paste one back (Claude).
  function handleAddLine(line) {
    var text = String(line).replace(/\u001b\[[0-9;]*m/g, "")
    var tagged = text.match(/^@@omarchy (status|done|error) (.*)$/)
    if (tagged) {
      if (tagged[1] === "status") {
        addStatus = tagged[2]
      } else {
        addResult = tagged[2]
        addStage = tagged[1]
        if (tagged[1] === "done") {
          usage.refreshLimits()
          addDoneTimer.restart()
          // Nothing to show yet means the sign-in is what counts as set up.
          if (usage.enabledProviders.length === 0 && !checkProcess.running) {
            addChecks = ({})
            checkProcess.running = true
          }
        }
      }
      return
    }
    var code = text.match(/^\s*([A-Z0-9]{4}-[A-Z0-9]{4})\s*$/)
    if (code) addCode = code[1]
    if (/paste code/i.test(text)) addNeedsPaste = true
    var url = text.match(/(https:\/\/\S+)/)
    if (url && addUrl === "") addUrl = url[1]
  }

  function reopenSignIn() {
    if (addUrl === "") return
    Util.execArgv(addPrivate ? ["omarchy-launch-browser", "--private", addUrl] : ["omarchy-launch-browser", addUrl])
  }

  // A few ways into making Omarchy your own, handed to the default agent.
  readonly property var starterPrompts: [
    { glyph: "󰏘", label: petStrings.t("agents.theme"), prompt: "Make me a new Omarchy theme. Ask me what look or inspiration I have in mind, then build it following the Omarchy skill's theming guide and switch to it." },
    { glyph: "󰐱", label: petStrings.t("agents.plugin"), prompt: "Make me a new Omarchy shell plugin. Ask me what I'd like it to do, then build it following the Omarchy skill's plugin guide and enable it." },
    { glyph: "󰣆", label: petStrings.t("agents.app"), prompt: "Make me a new app for my Omarchy desktop. Ask me what it should do, then build it following the omarchy-app skill and install it so it shows up in the app launcher." }
  ]

  function startPrompt(prompt) {
    root.close()
    Util.execArgv(["omarchy-agent-prompt", prompt])
  }

  function renameAccount(p, account, label) {
    if (!p || !account) return
    Util.execArgv(["omarchy-agent-account-rename", p.providerId, String(account.id), label])
  }

  function useAccount(p, account) {
    if (!p || !account || account.active) return
    Util.execArgv(["omarchy-agent-account-use", p.providerId, String(account.id)])
  }

  function autoSwitchFor(p) {
    return !!p && !!p.accountSwitch && p.accountSwitch.mode === "auto"
  }

  function switchThreshold(p) {
    return p && p.accountSwitch ? Number(p.accountSwitch.threshold || 95) : 95
  }

  function setSwitchMode(p, mode) {
    if (!p || providerAccounts(p).length < 2 || mode === (autoSwitchFor(p) ? "auto" : "manual")) return
    Util.execArgv(["bash", "-c", 'omarchy-agent-account-mode "$1" "$2" >/dev/null && omarchy-agent-usage-update --limits-only "$1"',
                   "omarchy-agent-account-mode", p.providerId, mode])
  }

  // `m` flips autoswitch for the picked account's provider, or the first
  // provider with several accounts when nothing is picked.
  function toggleSwitchMode() {
    var p = pickedEntry ? pickedEntry.provider : (accountEntries.length > 0 ? accountEntries[0].provider : null)
    if (p) setSwitchMode(p, autoSwitchFor(p) ? "manual" : "auto")
  }

  function activateSelection() {
    var target = keyTarget
    if (!target) refreshNow()
    else if (target.kind === "add") addStage !== "" ? cancelAdd() : addAccount()
    else if (target.kind === "choice") chooseAddProvider(addProviders[target.index].providerId)
    else if (target.kind === "launch") launchAgent()
    else if (target.kind === "pet") { if (petEditing && petEditor) petEditor.finish(); else petEditing = true }
    else if (String(target.kind).indexOf("pet.") === 0) { if (petEditor) petEditor.activate(target) }
    else if (target.kind === "providerSignin") signInAgain(providers[target.index], null)
    else if (target.kind === "signin") signInAgain(pickedEntry.provider, pickedEntry.account)
    else if (target.kind === "autoswitch") setSwitchMode(pickedEntry.provider, autoSwitchFor(pickedEntry.provider) ? "manual" : "auto")
    else if (pickedEntry && !pickedEntry.account.active) useAccount(pickedEntry.provider, pickedEntry.account)
  }

  function isPicked(p, account) {
    return !!pickedEntry && !!p && !!account
      && pickedEntry.provider.providerId === p.providerId && pickedEntry.account.id === account.id
  }

  // Hands the keyboard back to the panel after an inline edit.
  function focusKeys() {
    if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
  }

  function accountDetail(account) {
    var parts = []
    if (String(account.plan || "") !== "") parts.push(account.plan)
    if (account.resetCredits && Number(account.resetCredits.available) > 0)
      parts.push(freeResetsText(Number(account.resetCredits.available)))
    return parts.join(" · ")
  }

  // Only the agents `omarchy-agent-account-add` signs in get the link; any
  // other agent's sign-in trouble stays text, with its own help to follow.
  function supportsSignIn(p) {
    for (var i = 0; i < addProviders.length; i++)
      if (p && addProviders[i].providerId === p.providerId) return true
    return false
  }

  // A lapsed or missing sign-in is something you can fix from here; any other
  // trouble is only reported.
  function needsSignIn(item) {
    if (item && item.providerId && !supportsSignIn(item)) return false
    var status = String(item && item.usageStatusText || "")
    return status === "Sign-in expired" || status === "Waiting for auth"
  }

  // Whatever keeps the numbers from being current, said beside the last ones
  // known: they stay on show until a check succeeds again. A failed refresh
  // with numbers kept may leave the status empty and say why only in its help.
  function usageNote(item) {
    if (!item || needsSignIn(item)) return ""
    var status = String(item.usageStatusText || "")
    var stale = item.limitsStale === true || item.stale === true
    if (status === "" && !(stale && String(item.authHelpText || "") !== "")) return ""
    return helpDisplayText(item.authHelpText) || statusDisplayText(status)
  }

  // Sign an account that's already here in again, following along in the
  // add view just like adding one.
  function signInAgain(p, account) {
    if (!supportsSignIn(p) || addStage === "running") return
    addProvider = p.providerId
    addPrivate = !!account && account.primary !== true
    addStatus = petStrings.t("agents.starting")
    addCode = ""
    addUrl = ""
    // Claude's login offers pasting a code back whenever its page shows one,
    // and its prompt for it has no newline to read it by, so the field is
    // there from the start.
    addNeedsPaste = addProvider === "claude"
    addResult = ""
    addStage = "running"
    addProcess.command = ["omarchy-agent-account-add", "--events", "--reauth",
      account && account.primary !== true ? String(account.id) : ":primary", p.providerId]
    addProcess.running = true
  }

  function resetCreditsText(credits) {
    if (!credits || !(Number(credits.available) > 0)) return ""
    var count = Number(credits.available)
    var expires = new Date(String(credits.nextExpiresAt || "")).getTime()
    if (isFinite(expires) && expires > nowMs) {
      return petStrings.tn("agents.freeResetsExpires", count)
        .arg(Commons.I18n.formatNumber(count)).arg(formatDuration(expires - nowMs))
    }
    return freeResetsText(count)
  }

  function freeResetsText(count) {
    return petStrings.tn("agents.freeResets", count).arg(Commons.I18n.formatNumber(count))
  }

  function planLabel(p) {
    var tier = String(p && p.tierLabel || "")
    if (tier === "Prepaid") return petStrings.t("agents.tierPrepaid")
    return tier === "" ? "" : tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  function launchAgent() {
    if (root.bar) root.bar.run("omarchy-agent --pick")
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0
      || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0) return 30 * 24 * 3600 * 1000
    if (windowIsLong(text)) return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours) return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes) return Number(minutes[1]) * 60 * 1000
    return 0
  }

  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0) return "Monthly"
    if (windowIsLong(text)) return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0) return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    var reset = new Date(String(resetAt || "")).getTime()
    var expired = isFinite(reset) && reset <= root.nowMs
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: expired ? 0 : Number(percent),
      resetAt: expired ? "" : String(resetAt || "")
    }
  }

  function limitWindows(p) {
    if (!p) return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0) out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // A model-scoped window ("Fable Weekly") is its own allowance, but it runs
  // on the same clock as the window it's named for, so it's shown attached to
  // that row rather than as a row of its own. One with nothing to attach to
  // still gets its own row.
  function scopedPart(title) {
    var match = String(title || "").match(/^(.+) (Session|Weekly|Monthly)$/)
    return match ? { model: match[1], window: match[2] } : null
  }

  function displayWindows(p) {
    var windows = limitWindows(p)
    var out = []
    var byTitle = {}
    for (var i = 0; i < windows.length; i++) {
      if (scopedPart(windows[i].title)) continue
      windows[i].scoped = []
      out.push(windows[i])
      byTitle[windows[i].title] = windows[i]
    }
    var modelCounts = {}
    for (var k = 0; k < windows.length; k++) {
      var pK = scopedPart(windows[k].title)
      if (pK) modelCounts[pK.model] = (modelCounts[pK.model] || 0) + 1
    }
    for (var j = 0; j < windows.length; j++) {
      var part = scopedPart(windows[j].title)
      if (!part) continue
      var title = (modelCounts[part.model] > 1) ? (part.model + " " + part.window) : part.model
      out.push({
        title: title,
        percent: windows[j].percent,
        resetAt: windows[j].resetAt,
        scoped: []
      })
    }
    return out
  }

  // The window that decides how much room is left — the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent) best = windows[i]
    }
    return best
  }

  function resetMsFor(w) {
    if (!w || w.resetAt === "") return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  function formatDuration(ms) {
    if (!(ms > 0)) return petStrings.t("agents.durationNow")
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0) return petStrings.t("agents.durationDaysHours").arg(Commons.I18n.formatNumber(days)).arg(Commons.I18n.formatNumber(hours % 24))
    if (hours > 0) return petStrings.t("agents.durationHoursMinutes").arg(Commons.I18n.formatNumber(hours)).arg(Commons.I18n.formatNumber(minutes % 60))
    return petStrings.t("agents.durationMinutes").arg(Commons.I18n.formatNumber(Math.max(1, minutes)))
  }

  // Window titles stay English in the records, where scopedPart() and the
  // collectors match on them; only what reaches the screen is translated.
  function windowDisplayTitle(title) {
    var value = String(title || "")
    if (value === "Session") return petStrings.t("agents.windowSession")
    if (value === "Weekly") return petStrings.t("agents.windowWeekly")
    if (value === "Monthly") return petStrings.t("agents.windowMonthly")
    if (value === "Spend limit") return petStrings.t("agents.windowSpendLimit")
    if (value === "Limit") return petStrings.t("agents.windowLimit")
    var part = scopedPart(value)
    if (part && part.window === "Session") return petStrings.t("agents.modelSession").arg(part.model)
    if (part && part.window === "Weekly") return petStrings.t("agents.modelWeekly").arg(part.model)
    if (part && part.window === "Monthly") return petStrings.t("agents.modelMonthly").arg(part.model)
    return value
  }

  function scopedAllowanceText(scoped, windowTitle) {
    var percent = Commons.I18n.formatNumber(Math.round(scoped.percent * 100))
    var value = String(windowTitle || "")
    if (value === "Session") return petStrings.t("agents.scopedSession").arg(scoped.title).arg(percent)
    if (value === "Weekly") return petStrings.t("agents.scopedWeekly").arg(scoped.title).arg(percent)
    if (value === "Monthly") return petStrings.t("agents.scopedMonthly").arg(scoped.title).arg(percent)
    return petStrings.t("agents.scopedOther").arg(scoped.title).arg(percent).arg(windowDisplayTitle(value))
  }

  // The collectors write a fixed English status; the ones that reach the
  // screen are shown in the current language.
  function statusDisplayText(status) {
    var value = String(status || "")
    if (value === "Balance unavailable") return petStrings.t("agents.balanceUnavailable")
    if (value === "Out of credits") return petStrings.t("agents.outOfCredits")
    var limits = value.match(/^(.+) limits unavailable$/)
    if (limits) return petStrings.t("agents.providerLimitsUnavailable").arg(limits[1])
    var provider = value.match(/^(.+) unavailable$/)
    if (provider) return petStrings.t("agents.providerUnavailable").arg(provider[1])
    if (value === "Sign-in expired") return petStrings.t("agents.signInExpired")
    if (value === "Waiting for auth") return petStrings.t("agents.waitingForAuth")
    if (value === "Limits paused") return petStrings.t("agents.limitsPaused")
    return value
  }

  // The usage collectors cache their help lines in English, so the fixed
  // ones are translated here; commands stay verbatim as arguments, and raw
  // error text from a provider passes through as it came.
  function helpDisplayText(text) {
    var value = String(text || "")
    switch (value) {
    case "Run `claude auth login` to restore authoritative usage.":
      return petStrings.t("agents.helpRunToRestoreUsage").arg("`claude auth login`")
    case "Run `codex login` to authenticate.":
      return petStrings.t("agents.helpRunToAuthenticate").arg("`codex login`")
    case "Start Grok, or run `grok login`, to sign in.":
      return petStrings.t("agents.helpStartOrRunToSignIn").arg("Grok").arg("`grok login`")
    case "Start Grok to see its limits; signing in again is not needed.":
      return petStrings.t("agents.helpStartToSeeLimits").arg("Grok")
    case "Grok's saved sign-in expired. Start Grok to refresh it.":
      return petStrings.t("agents.helpSignInExpired").arg("Grok")
    case "Set FIREWORKS_API_KEY, run `firectl set-api-key`, or sign in to Fireworks in pi or opencode.":
      return petStrings.t("agents.helpFireworksSignIn").arg("FIREWORKS_API_KEY").arg("`firectl set-api-key`")
    case "codex not found in PATH":
      return petStrings.t("agents.helpNotInPath").arg("codex")
    case "Fireworks usage scan failed":
      return petStrings.t("agents.helpScanFailed").arg("Fireworks")
    }
    return value
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  function balanceAlarming(b) {
    return !!b && b.funded > 0 && b.remaining / b.funded <= 0.1
  }

  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD") return "$"
    if (code === "EUR") return "€"
    if (code === "GBP") return "£"
    return code + " "
  }

  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount)) amount = 0
    return currencyPrefix(currency) + Commons.I18n.formatNumber(amount, 2)
  }

  function balanceDetailText(b) {
    if (!b || !(b.funded > 0)) return ""
    var spent = formatMoney(b.spent, b.currency)
    var funded = formatMoney(b.funded, b.currency)
    return b.estimated
      ? petStrings.t("agents.balanceSpentEstimated").arg(spent).arg(funded)
      : petStrings.t("agents.balanceSpent").arg(spent).arg(funded)
  }

  // ---------------------------------------------------------------- summary
  //
  // The hero's line rotates through what the token counts add up to across
  // every agent, now that they no longer get charts of their own.

  readonly property var summaryPhrases: {
    var rev = usage.dataRevision
    var week = 0
    var today = 0
    var prompts = 0
    var sessions = 0
    var byDay = {}
    var byModel = {}
    var providers = usage.enabledProviders
    for (var i = 0; i < providers.length; i++) {
      var p = providers[i]
      var days = p.recentDays || []
      for (var d = 0; d < days.length; d++) {
        var tokens = Number(days[d].messageCount || 0)
        week += tokens
        byDay[days[d].date] = (byDay[days[d].date] || 0) + tokens
      }
      today += Number(p.todayTotalTokens || 0)
      if (p.hasPromptStats !== false) {
        prompts += Number(p.todayPrompts || 0)
        sessions += Number(p.todaySessions || 0)
      }
      var models = p.modelUsage || {}
      for (var id in models) {
        var bucket = models[id] || {}
        var total = Number(bucket.inputTokens || 0) + Number(bucket.outputTokens || 0)
          + Number(bucket.cacheReadInputTokens || 0) + Number(bucket.cacheCreationInputTokens || 0)
        var name = usage.friendlyModelName(id)
        byModel[name] = (byModel[name] || 0) + total
      }
    }

    var phrases = []
    if (week > 0) phrases.push(petStrings.tn("agents.tokensThisWeek", week).arg(usage.formatTokenCount(week)))
    if (today > 0) phrases.push(petStrings.tn("agents.tokensToday", today).arg(usage.formatTokenCount(today)))
    var topModel = ""
    for (var model in byModel) if (topModel === "" || byModel[model] > byModel[topModel]) topModel = model
    if (topModel !== "" && byModel[topModel] > 0) phrases.push(petStrings.t("agents.mostlyModel").arg(topModel))
    var busiest = ""
    for (var date in byDay) if (busiest === "" || byDay[date] > byDay[busiest]) busiest = date
    if (busiest !== "" && byDay[busiest] > 0) phrases.push(petStrings.t("agents.busiestDay").arg(dayName(busiest)))
    if (prompts > 0) phrases.push(petStrings.tn("agents.promptsToday", prompts).arg(Commons.I18n.formatNumber(prompts)))
    if (sessions > 0) phrases.push(petStrings.tn("agents.sessionsToday", sessions).arg(Commons.I18n.formatNumber(sessions)))
    return phrases
  }
  // Tips shown in the banner: live insights from usage first, then a
  // rotating pool of general advice. Each entry: badge, icon, phrase, alert.
  readonly property int staticTipCount: 14

  readonly property var deepInsights: {
    var t = petStrings
    var list = []
    var provs = root.providers || []
    var totalTokens = 0
    var totalSessions = 0
    var byModel = {}
    var worst = null
    var calmest = null

    for (var i = 0; i < provs.length; i++) {
      var p = provs[i]
      totalTokens += Number(p.todayTotalTokens || 0)
      totalSessions += Number(p.todaySessions || 0)
      if (p.todayTokensByModel) {
        for (var m in p.todayTokensByModel) {
          var mName = usage.friendlyModelName ? usage.friendlyModelName(m) : m
          byModel[mName] = (byModel[mName] || 0) + Number(p.todayTokensByModel[m] || 0)
        }
      }
      var wins = root.limitWindows(p)
      var peak = -1
      for (var w = 0; w < wins.length; w++) {
        var pct = Number(wins[w].percent)
        if (!(pct >= 0)) continue
        peak = Math.max(peak, pct)
        if (!worst || pct > worst.percent) worst = { provider: p.providerName || p.providerId || "", title: wins[w].title || "", percent: pct, resetMs: root.resetMsFor(wins[w]) }
      }
      if (peak >= 0 && (!calmest || peak < calmest.percent)) calmest = { provider: p.providerName || p.providerId || "", percent: peak }
    }

    function pctText(v) { return Commons.I18n.formatNumber(Math.round(v * 100)) + "%" }

    // Limits
    if (worst && worst.percent >= 1) {
      list.push({ key: "limit", badge: t.t("tip.badge.limit"), icon: "⚠️", alert: true,
        phrase: worst.resetMs > 0
          ? t.t("tip.limitMaxed").arg(worst.provider).arg(worst.title).arg(root.formatDuration(worst.resetMs))
          : t.t("tip.limitMaxedNoReset").arg(worst.provider).arg(worst.title) })
    } else if (worst && worst.percent >= 0.9) {
      list.push({ key: "limit", badge: t.t("tip.badge.limit"), icon: "⚠️", alert: true,
        phrase: t.t("tip.limitNear").arg(worst.provider).arg(worst.title).arg(pctText(worst.percent)) })
    } else if (worst) {
      list.push({ key: "limit", badge: t.t("tip.badge.limits"), icon: "✓",
        phrase: t.t("tip.limitsHealthy").arg(worst.provider).arg(worst.title).arg(pctText(worst.percent)) })
    }
    if (worst && worst.percent >= 0.9 && calmest && calmest.provider !== worst.provider && calmest.percent < 0.5) {
      list.push({ key: "switch", badge: t.t("tip.badge.switch"), icon: "↻",
        phrase: t.t("tip.switchProvider").arg(calmest.provider).arg(pctText(calmest.percent)) })
    }

    // Usage
    if (totalTokens > 0 && usage && usage.formatTokenCount) {
      var top = ""
      for (var name in byModel) if (top === "" || byModel[name] > byModel[top]) top = name
      list.push({ key: "today", badge: t.t("tip.badge.today"), icon: "⚡",
        phrase: top !== "" ? t.t("tip.tokensTodayTop").arg(usage.formatTokenCount(totalTokens)).arg(top)
                           : t.t("tip.tokensToday").arg(usage.formatTokenCount(totalTokens)) })
      if (totalSessions > 0) {
        list.push({ key: "pace", badge: t.t("tip.badge.pace"), icon: "⏱️",
          phrase: t.tn("tip.pace", totalSessions).arg(usage.formatTokenCount(Math.round(totalTokens / totalSessions))).arg(Commons.I18n.formatNumber(totalSessions)) })
      }
    }

    // Late night
    var hour = new Date(root.nowMs).getHours()
    if (hour >= 23 || hour < 5) list.push({ key: "night", badge: t.t("tip.badge.night"), icon: "🌙", phrase: t.t("tip.lateNight") })

    // General advice
    for (var k = 1; k <= root.staticTipCount; k++) {
      list.push({ key: "general." + k, badge: t.t("tip.badge.tip"), icon: "💡", phrase: t.t("tip.general." + k) })
    }
    return list
  }

  function showNextInsight() {
    advanceInsight()
    if (currentInsight) shownPhrase = currentInsight.phrase
  }


  property int phraseIndex: 0
  // Every record that lands rebuilds the phrases, and opening the panel
  // refreshes each agent in turn. Indexing the live list would swap the line
  // on each of those, so the hero holds what it shows until the next fade.
  property string shownPhrase: ""
  readonly property string heroPhrase: addStage !== "" || blankSlate
    ? addHeading
    : (shownPhrase !== "" ? shownPhrase : petStrings.t("agents.subscriptions"))

  function showPhrase() {
    if (deepInsights.length > 0) {
      shownPhrase = currentInsight ? currentInsight.phrase : ""
    } else {
      var n = summaryPhrases.length
      shownPhrase = n > 0 ? summaryPhrases[phraseIndex % n] : ""
    }
  }

  onSummaryPhrasesChanged: if (shownPhrase === "" || summaryPhrases.length <= 1) showPhrase()
  onDeepInsightsChanged: if (shownPhrase === "" && deepInsights.length > 0) showPhrase()

  // The held line was written in the language it was shown in; once a new
  // language's strings arrive and the phrases rebuild, show it again.
  Connections {
    target: Commons.I18n
    function onStringsChanged() { Qt.callLater(root.showPhrase) }
  }

  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime())) return String(date || "")
    return Qt.locale(Commons.I18n.formatLocale).dayName([7, 1, 2, 3, 4, 5, 6][parsed.getDay()])
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "") return usage.syncStatusText
    var providers = usage.enabledProviders
    for (var i = 0; i < providers.length; i++) {
      var count = Number(providers[i].syncDeviceCount || 0)
      if (providers[i].syncEnabled && count > 0)
        return petStrings.tn("agents.merged", count).arg(Commons.I18n.formatNumber(count))
    }
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel)) return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r)
      + 0.7152 * colorChannelLuminance(color.g)
      + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p) return []
    var candidates = []
    if (colorLuminance(surfaceColor || Commons.Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // Always in the bar: on a machine with no agent yet, the panel is where you
  // set one up.
  readonly property bool anySignedIn: {
    for (var id in addChecks)
      if (addChecks[id] !== "first") return true
    return false
  }
  // Local history counts as set up, so a machine with no subscription still
  // gets its summary rather than the picker.
  readonly property bool blankSlate: usage.enabledProviders.length === 0 && !anySignedIn
  // Choosing a provider: asked for with the +, or simply what the panel is
  // while nothing is set up. It's derived rather than switched into, so
  // records that load a moment after the panel opens take its place.
  readonly property bool picking: addStage === "pick" || (blankSlate && addStage === "")
  // The + in the hero turns into the X that leaves adding. A first setup has
  // nothing to go back to until an agent is chosen.
  readonly property bool addButtonShown: !blankSlate || !picking

  // Adding takes over the hero's line, and the cursor starts over.
  readonly property string addHeading: picking || addProvider === ""
    ? petStrings.t("agents.addAccount")
    : petStrings.t("agents.addProviderAccount").arg(addProviderName(addProvider))
  onAddStageChanged: {
    phraseSwap.stop()
    if (hero) hero.metaOpacity = 1.0
    resetKeys()
  }

  // A first setup ends when the records land, which swaps the rows under the
  // cursor without any stage change.
  onPickingChanged: resetKeys()

  // Picking an agent to add starts on the first one, ready for Enter. The
  // rows follow the same stage change, so the cursor waits a tick for them.
  function resetKeys() {
    cursorActive = false
    keyRow = 0
    keyColumn = 0
    Qt.callLater(function() { if (picking) pointAt("choice", 0) })
  }
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    if (addStage !== "running") addStage = ""
    resetKeys()
    if (usage.enabledProviders.length === 0 && !checkProcess.running) checkProcess.running = true
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    usage.refreshLimits()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    var d = new Date()
    var hour = d.toDateString() + " " + d.getHours()
    if (hour !== lastGreetHour) { lastGreetHour = hour; greetTimer.restart() }
  } else {
    root.tipBannerHovered = false
    root.petEditing = false
  }

  Main {
    id: usage
    settings: root.settings
  }

  Process {
    id: checkProcess
    running: false
    command: ["omarchy-agent-account-add", "--check"]
    stdout: SplitParser {
      onRead: function(line) {
        var parts = String(line).trim().split(" ")
        if (parts.length !== 2) return
        var checks = Object.assign({}, root.addChecks)
        checks[parts[0]] = parts[1]
        root.addChecks = checks
      }
    }
  }

  Process {
    id: addProcess
    running: false
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.handleAddLine(line) } }
    onExited: {
      if (root.addStage === "running") {
        root.addResult = petStrings.t("agents.signInUnfinished")
        root.addStage = "error"
      }
    }
  }

  Timer {
    id: addDoneTimer
    interval: 2500
    onTriggered: if (root.addStage === "done" && !root.blankSlate) root.addStage = ""
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  Timer {
    interval: 12000
    running: root.opened && root.deepInsights.length > 1 && root.addStage === "" && !root.blankSlate && !root.tipBannerHovered
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 0.0; duration: Style.duration(150); easing.type: Easing.OutCubic
    }
    ScriptAction {
      script: {
        root.advanceInsight()
        root.showPhrase()
      }
    }
    PropertyAnimation {
      target: hero; property: "metaOpacity"
      to: 1.0; duration: Style.duration(200); easing.type: Easing.OutCubic
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
    function nextInsight(): string { root.showNextInsight(); return root.shownPhrase }
    function editPet(): void { root.open(); root.petEditing = true }
    function pat(): void { if (panel.loadedContent) panel.loadedContent.heroPet.pat() }
    function celebrate(): void { root.petCelebrate() }
    // Play a pet reaction by name (manual testing; see PetClips.NAMES).
    function react(name: string): string {
      if (barPet.reactionNames.indexOf(name) < 0) return "unknown reaction; try: " + barPet.reactionNames.join(", ")
      var hero = panel.loadedContent ? panel.loadedContent.heroPet : null
      var ok = hero && root.opened ? hero.play(name, { force: true }) : barPet.play(name, { force: true })
      return ok ? "ok" : "not shown (the bar pet only plays some reactions; open the panel)"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // An empty square keeps the bar's icon slot; the pet is drawn on top of
    // the button below, outside the bar's icon fitting, so it can fill the
    // bar height instead of being shrunk to a 12px glyph.
    iconComponent: Component {
      Rectangle {
        color: "transparent"
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchAgent()
      else if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  BlobAvatar {
    id: barPet
    anchors.centerIn: button
    size: root.barPetSize
    look: root.petLook
    themePalette: petPalette
    mood: root.petMood
    interactive: false
    animated: false
    // Cheap in the bar: no blink or glance timers; reactions are a single
    // repainted pose, except short "full" ones (celebrate, oof).
    lively: false
    reactionLevel: "cheap"
    reactions: root.petReactions
    showMarks: false
    particles: false
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(960))

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias panelFlick: panelFlick
      property alias hero: hero
      property alias column: column
      property alias providerSections: providerSections
      property alias heroPet: heroAvatar
      property alias petEditor: petEditorItem
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      reorderable: root.addStage === "" && !root.renaming
      onReorderRequested: function(dy) { root.reorderProvider(dy) }

      onMoveRequested: function(dx, dy) {
        // Naming and signing in have their own fields; there the arrows scroll.
        if (root.petEditing && root.petEditor && root.petEditor.fieldFocused) return
        if (root.addStage === "" || root.picking) {
          root.moveKey(dx, dy)
          if (root.petEditing && root.petEditor) root.petEditor.syncTryOn(root.keyTarget)
        }
        else if (dy !== 0)
          panelFlick.contentY = root.clamp(panelFlick.contentY + dy * Style.space(56), 0,
                                           Math.max(0, panelFlick.contentHeight - panelFlick.height))
      }
      onActivateRequested: {
        // Enter in the name or hex field commits it (editingFinished) and
        // hands the keys back to the panel.
        if (root.petEditing && root.petEditor && root.petEditor.fieldFocused) { root.focusKeys(); return }
        root.activateSelection()
      }
      onCloseRequested: {
        if (root.petEditing && root.addStage === "" && root.petEditor) {
          // Esc steps back one level: a field, the color picker, the editor.
          if (root.petEditor.fieldFocused) root.focusKeys()
          else if (!root.petEditor.back()) { root.petEditor.finish(); root.pointAt("pet") }
          return
        }
        if (root.addStage !== "") root.cancelAdd()
        else root.close()
      }
      onDeleteRequested: if (root.petEditing && root.petEditor) root.petEditor.deleteKey()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t, modifiers) {
        if (root.petEditing && root.addStage === "" && root.petEditor) { root.petEditor.textKey(t, modifiers); return }
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "m" || t === "M") root.toggleSwitchMode()
        else if (root.addStage === "" && t >= "1" && t <= "9" && Number(t) <= root.accountEntries.length) root.pointAt("account", Number(t) - 1)
      }

      Flickable {
        id: panelFlick
        // Reaches a little into the panel's padding on the left, with the
        // content shifted back, so the box around a lit agent mark isn't
        // clipped where it overhangs the content's edge.
        readonly property real overhang: Style.space(8)
        anchors.fill: parent
        anchors.leftMargin: -overhang
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
          id: panelScroll
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: column
          // The overhang sits on the start side, which is the right when
          // mirrored; there the scroll bar takes the left instead.
          x: LayoutMirroring.enabled ? (panelFlick.interactive ? panelScroll.width + Style.space(6) : 0) : panelFlick.overhang
          // When the panel scrolls, the bar gets its own strip rather than
          // sitting on top of the right-aligned numbers.
          width: panelFlick.width - panelFlick.overhang - (panelFlick.interactive ? panelScroll.width + Style.space(6) : 0)
          spacing: Style.space(16)

          // ---------- Hero: pet · name · actions ----------
          Item {
            id: hero
            width: parent.width
            readonly property real tipGap: Style.space(8)
            // The pet is centered against the name, the token count and the
            // tip's first line. A longer tip only grows downward, so rotating
            // tips never moves the pet or the name.
            readonly property real headBlock: heroTop.height + (tipLine.visible ? tipGap + tipLine.firstLineHeight : 0)
            readonly property real headZone: Math.max(heroAvatar.visible ? heroAvatar.implicitHeight : 0, headBlock)
            implicitHeight: Math.max(headZone, heroTop.y + heroTop.height + (tipLine.visible ? tipGap + tipLine.height : 0))

            property real metaOpacity: 1.0

            BlobAvatar {
              id: heroAvatar
              // While editing, only the pet being edited is shown.
              visible: !root.petEditing
              anchors.left: parent.left
              y: (hero.headZone - height) / 2
              size: root.petHeroSize
              animated: root.opened
              lively: root.opened
              themePalette: petPalette
              mood: root.petMood
              foreground: root.foreground
              accentColor: Commons.Color.accent
              look: root.petLook
              trackGlobalCursor: root.opened
              reactions: root.petReactions
              onReactionChanged: if (reaction === "") root.retryThinking(heroAvatar)
            }

            Item {
            id: heroTop
            x: heroAvatar.visible ? heroAvatar.width + Style.space(12) : 0
            y: (hero.headZone - hero.headBlock) / 2
            width: parent.width - x
            height: Math.max(heroLabelsCol.implicitHeight, trailingButtons.implicitHeight)

            Column {
              id: heroLabelsCol
              anchors.left: parent.left
              anchors.right: trailingButtons.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                id: companionNameLabel
                textFormat: Text.PlainText
                text: root.companionName
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              // Subtitle / Status indicator
              Text {
                id: heroStatusText
                textFormat: Text.PlainText
                text: {
                  if (root.addStage !== "") return root.addHeading.toUpperCase()
                  if (root.petEditing) return petStrings.t("pet.edit", "Pet settings").toUpperCase()
                  if (!usage || !usage.formatTokenCount) return ""
                  if (root.totalTokensToday > 0) {
                    return petStrings.tn("agents.tokensToday", root.totalTokensToday).arg(usage.formatTokenCount(root.totalTokensToday)).toUpperCase()
                  }
                  if (root.totalTokensWeek > 0) {
                    return petStrings.tn("agents.tokensThisWeek", root.totalTokensWeek).arg(usage.formatTokenCount(root.totalTokensWeek)).toUpperCase()
                  }
                  return petStrings.tn("agents.tokensToday", 0).arg(usage.formatTokenCount(0)).toUpperCase()
                }
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption - 1
                font.bold: true
                font.letterSpacing: 1.1
                elide: Text.ElideRight
                width: parent.width
              }
            }

            Row {
              id: trailingButtons
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              visible: root.addStage === "" || root.addButtonShown

              HeroButton {
                visible: root.addStage === ""
                hasCursor: root.hasKey("pet")
                onHovered: root.pointAt("pet")
                glyph: root.petEditing ? "󰄬" : "󰒓"
                tooltip: root.petEditing ? petStrings.t("pet.done", "Done") : petStrings.t("pet.edit", "Pet settings")
                onClicked: {
                  if (root.petEditing && root.petEditor) root.petEditor.finish()
                  else root.petEditing = true
                }
              }

              HeroButton {
                visible: root.addButtonShown
                hasCursor: root.hasKey("add")
                onHovered: root.pointAt("add")
                readonly property bool adding: root.addStage !== ""
                glyph: adding ? "󰅖" : "󰐕"
                tooltip: adding ? petStrings.t("agents.backToLimits") : petStrings.t("agents.addSubscription")
                onClicked: adding ? root.cancelAdd() : root.addAccount()
              }

              HeroButton {
                visible: root.addStage === ""
                hasCursor: root.hasKey("launch")
                onHovered: root.pointAt("launch")
                glyph: "󰞷"
                tooltip: petStrings.t("agents.startDefaultAgent")
                onClicked: root.launchAgent()
              }
            }
            }

            // ---------- Tip line: the whole tip, wrapped under the name ----------
            Item {
              id: tipLine
              // The first line sits level with the icon and the › button.
              readonly property real lineHeight: tipText.implicitHeight / Math.max(1, tipText.lineCount)
              readonly property real textTop: Math.max(0, (nextTip.height - lineHeight) / 2)
              readonly property real firstLineHeight: Math.max(nextTip.height, textTop + lineHeight)
              visible: root.addStage === "" && !root.blankSlate && !root.petEditing && !!root.currentInsight
              anchors.top: heroTop.bottom
              anchors.topMargin: hero.tipGap
              x: heroTop.x
              width: parent.width - x
              height: Math.max(nextTip.height, textTop + tipText.implicitHeight)
              // Tips differ in length: on a rotation the panel below eases to
              // the new height while the tip fades in, and the clip reveals
              // extra lines as it grows. Only then, so the first layout (and a
              // re-wrap on resize) lands at once.
              Behavior on height {
                enabled: phraseSwap.running
                NumberAnimation { duration: Style.duration(200); easing.type: Easing.OutCubic }
              }
              clip: true
              opacity: hero.metaOpacity

              HoverHandler {
                id: tipLineHover
                onHoveredChanged: root.tipBannerHovered = hovered
              }

              Text {
                id: tipIcon
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: Math.max(0, (nextTip.height - implicitHeight) / 2)
                textFormat: Text.PlainText
                text: root.currentInsightIcon
                font.pixelSize: Style.font.caption
              }

              Text {
                id: tipText
                anchors.left: tipIcon.right
                anchors.leftMargin: Style.space(6)
                anchors.right: nextTip.left
                anchors.rightMargin: Style.space(4)
                anchors.top: parent.top
                anchors.topMargin: tipLine.textTop
                textFormat: Text.PlainText
                text: root.currentInsight ? root.currentInsight.phrase : ""
                color: root.currentInsightIsAlert ? Commons.Color.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.weight: root.currentInsightIsAlert ? Font.DemiBold : Font.Normal
                // Tips run to about three lines; the cap only guards a long
                // translation, which then shows whole in a tooltip.
                wrapMode: Text.WordWrap
                elide: Text.ElideRight
                maximumLineCount: 4
              }

              PanelToolTip {
                visible: tipLineHover.hovered && tipText.truncated && !nextTipMouse.containsMouse
                text: tipText.text
              }

              Rectangle {
                id: nextTip
                anchors.right: parent.right
                anchors.top: parent.top
                visible: root.deepInsights.length > 1
                width: Style.space(20)
                height: Style.space(20)
                radius: Style.cornerRadius
                color: nextTipMouse.containsMouse
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.1)
                  : "transparent"

                Text {
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: "󰅂"
                  color: nextTipMouse.containsMouse ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                MouseArea {
                  id: nextTipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  // The same fade as the timed rotation.
                  onClicked: phraseSwap.restart()
                }

                PanelToolTip {
                  visible: nextTipMouse.containsMouse
                  text: petStrings.t("tip.next")
                }
              }
            }
          }

          // ---------- Pet editor ----------
          PetEditor {
            id: petEditorItem
            visible: root.petEditing && root.addStage === ""
            width: parent.width
            look: root.petLook
            petName: root.petConfig.name || ""
            barSize: root.petBarSize
            panelSize: root.petPanelSize
            petReactions: root.petReactions
            saved: root.petSaved
            keyTarget: root.keyTarget
            tab: root.petTab
            onTabChanged: root.petTab = tab
            onPointRequested: function(kind, index) { root.pointAt(kind, index) }
            onRevealRequested: function(item) { root.revealItem(item) }
            onRestore: function(s) { root.restorePet(s) }
            onReactionsEdited: function(r) { root.writePet({ reactions: r }) }
            themePalette: petPalette
            foreground: root.foreground
            dim: root.dim
            fontFamily: root.fontFamily
            onLookEdited: function(look) { root.writePet({ look: look }) }
            onNameEdited: function(name) { if (name !== (root.petConfig.name || "")) root.writePet({ name: name }) }
            onSizeEdited: function(key, size) { var patch = {}; patch[key] = size; root.writePet(patch) }
            onSaveCurrent: root.savePetToInventory()
            onWear: function(index) { root.wearSavedPet(index) }
            onForget: function(index) { root.forgetSavedPet(index) }
            onImported: function(name, look) { root.writePet({ name: name, look: look }) }
            onDone: root.petEditing = false
          }

          AddView {
            visible: root.addStage !== "" || root.blankSlate
            width: column.width
          }

          Repeater {
            id: providerSections
            model: root.addStage === "" && !root.petEditing ? root.providers : []

            ProviderSection {
              required property var modelData
              required property int index
              width: column.width
              provider: modelData
              providerIndex: index
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // Adding a subscription, in place of the list: pick, name, sign in.
  component AddView: Column {
    id: add
    spacing: Style.space(14)

    PanelSeparator { foreground: root.foreground }

    Text {
      visible: root.blankSlate && root.picking
      width: parent.width
      text: petStrings.t("agents.signInIntro")
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    // Pick: each agent by a large mark over its name, three across.
    Row {
      id: choiceRow
      visible: root.picking
      width: parent.width
      spacing: Style.space(10)

      Repeater {
        model: root.picking ? root.addProviders : []

        Item {
          id: choice
          required property var modelData
          required property int index
          readonly property string state: root.addChecks[modelData.providerId] || ""
          readonly property bool available: state === "first" || state === "additional"
          readonly property bool hasCursor: root.hasKey("choice", index)
          width: (choiceRow.width - choiceRow.spacing * (root.addProviders.length - 1)) / root.addProviders.length
          implicitHeight: choiceBody.implicitHeight + Style.space(16)
          onHasCursorChanged: if (hasCursor) root.revealItem(choice)

          Column {
            id: choiceBody
            anchors.centerIn: parent
            spacing: Style.space(10)

            ProviderIcon {
              anchors.horizontalCenter: parent.horizontalCenter
              provider: choice.modelData
              size: Style.font.display * 1.6
              scale: choice.hasCursor ? 1.08 : 1.0
              Behavior on scale { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutQuad } }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: choice.modelData.providerName
              color: choice.hasCursor ? Commons.Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: choice.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onEntered: root.pointAt("choice", choice.index)
            onClicked: root.chooseAddProvider(choice.modelData.providerId)
          }

        }
      }
    }

    // Name: a second account needs telling apart from the first.
    Column {
      visible: root.addStage === "name"
      width: parent.width
      spacing: Style.space(10)

      Text {
        width: parent.width
        text: petStrings.t("agents.nameAccount")
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      TextField {
        id: addNameField
        width: parent.width
        placeholderText: petStrings.t("agents.placeholderWork")
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
        onAccepted: root.startAdd(text.trim())
        Keys.onEscapePressed: function(event) { root.cancelAdd(); event.accepted = true }
      }
    }

    // Running: what's happening, and whatever the sign-in needs from you.
    Column {
      visible: root.addStage === "running"
      width: parent.width
      spacing: Style.space(12)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.addStatus
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Column {
        visible: root.addCode !== ""
        width: parent.width
        spacing: Style.space(4)

        Text {
          text: petStrings.t("agents.confirmCode")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          textFormat: Text.PlainText
          text: root.addCode
          color: Commons.Color.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.display
          font.bold: true
          font.letterSpacing: 2
        }
      }

      Column {
        visible: root.addNeedsPaste
        width: parent.width
        spacing: Style.space(6)

        Text {
          width: parent.width
          text: petStrings.t("agents.pasteCode")
          textFormat: Text.PlainText
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        TextField {
          id: pasteField
          width: parent.width
          placeholderText: petStrings.t("agents.placeholderCode")
          foreground: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          onAccepted: { root.submitPaste(text); text = "" }
          Keys.onEscapePressed: function(event) { root.cancelAdd(); event.accepted = true }
        }
      }

      TextLink {
        visible: root.addUrl !== ""
        text: petStrings.t("agents.reopenSignIn")
        onClicked: root.reopenSignIn()
      }
    }

    // Done or failed.
    Text {
      visible: root.addStage === "done" || root.addStage === "error"
      width: parent.width
      textFormat: Text.PlainText
      text: root.addResult
      color: root.addStage === "error" ? root.urgent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.WordWrap
    }
  }

  // One provider: its mark, name, and plan, then its limits — or, with
  // several accounts, each account's name, state, and limits in turn. A
  // prepaid provider shows its balance instead.
  component ProviderSection: Column {
    id: section
    property var provider: null
    property int providerIndex: -1
    readonly property var accounts: root.providerAccounts(provider)
    readonly property bool multi: accounts.length > 1
    readonly property var windows: root.displayWindows(provider)
    readonly property var balance: provider ? (provider.balance || null) : null
    spacing: Style.space(16)
    opacity: root.dragProviderId !== "" && provider && root.dragProviderId === provider.providerId ? 0.5 : 1.0

    PanelSeparator { visible: section.providerIndex > 0; foreground: root.foreground }

    Item {
      id: sectionHead
      width: parent.width
      implicitHeight: Math.max(sectionMark.height, sectionName.implicitHeight)
      // Lit for the keyboard, and as the drop spot while an agent is dragged.
      readonly property bool lit: root.dragProviderId !== "" ? root.dragTarget === section.providerIndex : root.hasKey("provider", section.providerIndex)
      onLitChanged: if (lit && root.dragProviderId === "") root.revealItem(sectionHead)

      // Only the mark is lit: it's the handle the agent moves by.
      CursorSurface {
        anchors.fill: sectionMark
        anchors.margins: -Style.space(5)
        z: -1
        hasCursor: sectionHead.lit
        foreground: root.foreground
      }

      ProviderIcon {
        id: sectionMark
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        provider: section.provider

        // The mark is the handle for dragging the agent up or down the page.
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          hoverEnabled: true
          preventStealing: true
          cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
          onPressed: {
            root.dragProviderId = section.provider ? section.provider.providerId : ""
            root.dragTarget = section.providerIndex
          }
          onPositionChanged: function(mouse) {
            if (pressed) root.dragProviderOver(mapToItem(root.column, mouse.x, mouse.y).y)
          }
          onReleased: root.dropProvider()
          onCanceled: { root.dragProviderId = ""; root.dragTarget = -1 }
        }
      }

      Text {
        id: sectionName
        anchors.left: sectionMark.right
        anchors.leftMargin: Style.space(10)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: section.provider ? section.provider.providerName : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }

      UsageNote {
        anchors.left: sectionName.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: sectionName.verticalCenter
        visible: !section.multi && message !== ""
        record: section.provider
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: !section.multi
        textFormat: Text.PlainText
        text: root.planLabel(section.provider)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // A sign-in to redo for a single-account provider; with several, each
    // account says so on its own line.
    TextLink {
      visible: !section.multi && root.needsSignIn(section.provider)
      picked: root.hasKey("providerSignin", section.providerIndex)
      text: petStrings.t("agents.signInRequired")
      idleColor: root.urgent
      tooltip: petStrings.t("agents.signInAgainProvider").arg(section.provider ? section.provider.providerName : "")
      onClicked: root.signInAgain(section.provider, null)
    }


    Column {
      visible: !section.multi && section.windows.length > 0
      width: parent.width
      spacing: Style.space(12)

      Repeater {
        model: section.multi ? [] : section.windows

        CompactLimit {
          required property var modelData
          width: section.width
          window: modelData
          stale: !!section.provider && section.provider.limitsStale === true
          fetchedAt: section.provider ? Number(section.provider.limitsFetchedAt || 0) : 0
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        width: parent.width
        text: root.resetCreditsText(section.provider ? section.provider.resetCredits : null)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    // The meter shows what is left, not what is used: a prepaid account
    // drains toward empty rather than filling toward a cap.
    Column {
      visible: !!section.balance
      width: parent.width
      spacing: Style.space(6)

      Item {
        width: parent.width
        implicitHeight: balanceTitle.implicitHeight

        Text {
          id: balanceTitle
          textFormat: Text.PlainText
          width: parent.width * 0.3
          anchors.verticalCenter: parent.verticalCenter
          text: petStrings.t("agents.balance")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Meter {
          anchors.left: balanceTitle.right
          anchors.right: balanceValue.left
          anchors.rightMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          value: section.balance && section.balance.funded > 0 ? section.balance.remaining / section.balance.funded : -1
          alarming: root.balanceAlarming(section.balance)
        }

        Text {
          id: balanceValue
          textFormat: Text.PlainText
          width: Style.space(96)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: section.balance ? root.formatMoney(section.balance.remaining, section.balance.currency) : ""
          color: root.balanceAlarming(section.balance) ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: text !== ""
        width: parent.width
        text: root.balanceDetailText(section.balance)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    Repeater {
      model: section.multi ? section.accounts : []

      Column {
        id: accountBlock
        required property var modelData
        required property int index
        width: section.width
        topPadding: index > 0 ? Style.space(6) : 0
        spacing: Style.space(14)

        AccountHeader {
          width: parent.width
          account: accountBlock.modelData
          owner: section.provider
          picked: root.isPicked(section.provider, accountBlock.modelData)
        }

        Column {
          width: parent.width
          spacing: Style.space(12)

          Repeater {
            model: root.displayWindows({ limits: accountBlock.modelData.limits || [] })

            CompactLimit {
              required property var modelData
              width: accountBlock.width
              window: modelData
              stale: accountBlock.modelData.stale === true
              fetchedAt: Number(accountBlock.modelData.fetchedAt || 0)
            }
          }
        }
      }
    }
  }

  // A provider's mark, falling back to the bar glyph when it ships none.
  component ProviderIcon: Item {
    id: mark
    property var provider: null
    property var candidates: root.iconCandidatesForProvider(provider, root.surface)
    property string candidatesKey: candidates.join("\n")
    property int candidateIndex: 0
    onCandidatesKeyChanged: candidateIndex = 0
    property real size: Style.font.heading

    width: size
    height: size

    Image {
      id: markImage
      anchors.fill: parent
      source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
      sourceSize.width: mark.size * 2
      sourceSize.height: mark.size * 2
      fillMode: Image.PreserveAspectFit
      // Advancing source from inside its own status change trips the
      // binding-loop detector; defer the step one tick.
      onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
        Qt.callLater(function() { mark.candidateIndex++ })
    }

    Text {
      anchors.centerIn: parent
      visible: markImage.status !== Image.Ready
      textFormat: Text.PlainText
      text: button.text
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: mark.size
    }
  }

  // A starter: its glyph and what it makes, on a soft tile that warms to the
  // accent on hover.
  component StarterTile: Rectangle {
    id: tile
    signal clicked()
    signal hovered()
    property string glyph: ""
    property string title: ""
    property bool hasCursor: false
    implicitHeight: tileBody.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: hasCursor ? root.alpha(Commons.Color.accent, 0.14) : root.alpha(root.foreground, 0.05)
    onHasCursorChanged: if (hasCursor) root.revealItem(tile)

    Row {
      id: tileBody
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: tile.glyph
        color: Commons.Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: tile.title
        color: tile.hasCursor ? Commons.Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: tile.hovered()
      onClicked: tile.clicked()
    }

    PanelToolTip {
      visible: tileMouse.containsMouse
      text: petStrings.t("agents.startOnNew").arg(tile.title.toLowerCase())
    }
  }

  // The tinted square in the hero's corner: start an agent, add a subscription.
  component HeroButton: Rectangle {
    id: heroButton
    signal clicked()
    signal hovered()
    property string glyph: ""
    property string tooltip: ""
    property bool hasCursor: false
    implicitWidth: Style.space(34)
    implicitHeight: implicitWidth
    radius: Style.cornerRadius
    // The cursor needs more than a shade deeper to read on a tinted square.
    color: root.alpha(Commons.Color.accent, hasCursor ? 0.3 : 0.12)
    border.width: hasCursor ? Math.max(1, Style.hoverBorderWidth) : 0
    border.color: Commons.Color.accent
    onHasCursorChanged: if (hasCursor) root.revealItem(heroButton)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: heroButton.glyph
      color: Commons.Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
    }

    MouseArea {
      id: heroMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: heroButton.hovered()
      onClicked: heroButton.clicked()
    }

    PanelToolTip {
      visible: heroMouse.containsMouse
      text: heroButton.tooltip
    }
  }

  // A plain-text control: dim until hovered or picked, accent when it's the
  // current choice. Stands in for bordered buttons, which pile up here.
  component TextLink: Text {
    id: link
    signal clicked()
    property bool current: false
    property bool picked: false
    property string tooltip: ""
    property color idleColor: root.dim
    readonly property bool hot: linkMouse.containsMouse || picked
    onPickedChanged: if (picked) root.revealItem(link)
    textFormat: Text.PlainText
    color: current ? Commons.Color.accent : (hot ? root.foreground : idleColor)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: current
    font.underline: hot && !current

    MouseArea {
      id: linkMouse
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: link.clicked()
    }

    PanelToolTip {
      visible: link.tooltip !== "" && linkMouse.containsMouse
      text: link.tooltip
    }
  }

  // An account's name, email and plan, with ACTIVE or a Use link on the
  // right. Clicking the name edits it in place: Enter renames, Esc or
  // clicking away leaves it as it was.
  component AccountHeader: Item {
    id: head
    property var account: ({})
    property var owner: null
    property bool picked: false
    property bool editing: false
    // The new name shows at once; the record catches up a moment later.
    property string renamedTo: ""
    readonly property bool isActive: account.active === true
    readonly property bool autoOn: root.autoSwitchFor(owner)
    // Which of the row's links the keyboard is on, when it's on this row.
    readonly property string pickedKind: picked && root.keyTarget ? root.keyTarget.kind : ""
    readonly property string label: renamedTo !== "" ? renamedTo : String(account.label || account.id || "")

    onAccountChanged: renamedTo = ""
    onEditingChanged: root.renaming = editing
    onPickedChanged: if (picked) root.revealItem(head)

    // Anywhere on the line counts, so Use can show up when it's hidden.
    HoverHandler { id: useHover }
    implicitHeight: Math.max(headText.implicitHeight, headAction.implicitHeight)

    function startRename() {
      editing = true
      nameField.text = label
      nameField.forceActiveFocus()
      nameField.selectAll()
    }

    function finishRename(save) {
      if (!editing) return
      var value = nameField.text.trim()
      editing = false
      root.focusKeys()
      if (save && value !== "" && value !== label) {
        renamedTo = value
        root.renameAccount(owner, account, value)
      }
    }

    // One line: the name, then its plan and any caveats, quieter. The
    // email is the name's tooltip.
    Item {
      id: headText
      anchors.left: parent.left
      anchors.right: headAction.left
      anchors.rightMargin: Style.spacing.sm
      implicitHeight: head.editing ? nameField.implicitHeight : nameText.implicitHeight

      Text {
        id: nameText
        textFormat: Text.PlainText
        visible: !head.editing
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width * 0.6)
        text: head.label
        color: head.picked ? Commons.Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: head.isActive
        font.underline: nameMouse.containsMouse
        elide: Text.ElideRight

        MouseArea {
          id: nameMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.IBeamCursor
          onClicked: head.startRename()
        }

        PanelToolTip {
          visible: nameMouse.containsMouse && String(head.account.email || "") !== ""
          text: String(head.account.email || "")
        }
      }

      // Bounded by the actions on the right: the plan shortens first, and the
      // Sign-in required link keeps its whole width.
      Row {
        id: detailRow
        visible: !head.editing
        anchors.left: nameText.right
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: nameText.verticalCenter
        width: Math.max(0, parent.width - nameText.width - Style.space(8))
        spacing: Style.space(8)

        Text {
          textFormat: Text.PlainText
          visible: text !== ""
          width: Math.max(0, Math.min(implicitWidth, detailRow.width
            - (accountNote.visible ? accountNote.implicitWidth + detailRow.spacing : 0)
            - (signInDot.visible ? signInDot.implicitWidth + detailRow.spacing : 0)
            - (signInLink.visible ? signInLink.implicitWidth + detailRow.spacing : 0)))
          elide: Text.ElideRight
          text: {
            var detail = root.accountDetail(head.account)
            return detail !== "" ? "· " + detail : ""
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        UsageNote {
          id: accountNote
          record: head.account
        }

        // The dot is punctuation, not part of the link.
        Text {
          id: signInDot
          visible: root.needsSignIn(head.account)
          text: "·"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        TextLink {
          id: signInLink
          visible: root.needsSignIn(head.account)
          picked: head.pickedKind === "signin"
          text: petStrings.t("agents.signInRequired")
          idleColor: root.urgent
          tooltip: petStrings.t("agents.signInAgainAccount")
          onClicked: root.signInAgain(head.owner, head.account)
        }
      }

      TextField {
        id: nameField
        visible: head.editing
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        foreground: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        horizontalPadding: Style.space(4)
        verticalPadding: Style.space(1)
        onAccepted: head.finishRename(true)
        onActiveFocusChanged: if (!activeFocus) head.finishRename(false)
        Keys.onEscapePressed: function(event) {
          head.finishRename(false)
          event.accepted = true
        }
      }
    }

    Item {
      id: headAction
      anchors.right: parent.right
      anchors.top: parent.top
      implicitWidth: head.isActive ? headActive.implicitWidth : useRow.implicitWidth
      implicitHeight: head.isActive ? headActive.implicitHeight : useRow.implicitHeight

      Text {
        id: headActive
        visible: head.isActive
        anchors.right: parent.right
        text: petStrings.t("agents.active")
        textFormat: Text.PlainText
        color: Commons.Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }

      // Switching now is Use. Hovering it also offers Autoswitch: move new
      // sessions over by themselves once the active account reaches the
      // threshold. While that's on it stays in view in place of Use, and
      // clicking it again goes back to only being notified.
      Row {
        id: useRow
        visible: !head.isActive
        anchors.right: parent.right
        spacing: Style.space(12)

        TextLink {
          visible: head.autoOn || useHover.hovered || head.picked
          text: petStrings.t("agents.autoswitch") + (head.pickedKind === "autoswitch" ? " ⏎" : "")
          picked: head.pickedKind === "autoswitch"
          current: head.autoOn
          tooltip: head.autoOn
            ? petStrings.t("agents.stopAutoSwitch")
            : petStrings.t("agents.switchAutoAt").arg(Commons.I18n.formatNumber(root.switchThreshold(head.owner)))
          onClicked: root.setSwitchMode(head.owner, head.autoOn ? "manual" : "auto")
        }

        // With Autoswitch on, Use waits until the line is hovered or picked.
        TextLink {
          visible: !head.autoOn || useHover.hovered || head.picked
          text: petStrings.t("agents.use") + (head.pickedKind === "account" ? " ⏎" : "")
          picked: head.pickedKind === "account"
          onClicked: root.useAccount(head.owner, head.account)
        }
      }
    }
  }

  // A mark beside the name when the numbers aren't current, with why and
  // what to do on hover.
  component UsageNote: Text {
    id: noteMark
    property var record: null
    readonly property string message: root.usageNote(record)
    visible: message !== ""
    text: "󰋽"
    textFormat: Text.PlainText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption

    HoverHandler { id: noteHover }

    PanelToolTip {
      visible: noteHover.hovered && noteMark.visible
      // Capped through implicitWidth, which the tooltip centers itself by.
      implicitWidth: Math.min(implicitContentWidth + leftPadding + rightPadding, Style.space(320))
      text: noteMark.message
    }
  }

  // One line per limit window: title, meter, percentage, and reset. A
  // model-scoped allowance on the same clock ("Fable" on Weekly) is a marker
  // on this row's meter, named in the row's tooltip.
  component CompactLimit: Item {
    id: compact
    property var window: null
    // The age of numbers kept past a failed check is shown only on hover.
    property bool stale: false
    property real fetchedAt: 0
    readonly property var scoped: window && window.scoped ? window.scoped : []
    readonly property bool alarming: window && window.percent >= 0.9
    readonly property real resetMs: root.resetMsFor(window)
    implicitHeight: Math.max(compactTitle.implicitHeight, compactPercent.implicitHeight, compactValue.implicitHeight)

    HoverHandler { id: compactHover }

    PanelToolTip {
      visible: compactHover.hovered && !!compact.window
      text: {
        var lines = []
        if (compact.window) {
          var windowName = root.windowDisplayTitle(compact.window.title)
          var used = Commons.I18n.formatNumber(Math.round(compact.window.percent * 100))
          lines.push(compact.resetMs > 0
            ? petStrings.t("agents.windowUsedResets").arg(windowName).arg(used).arg(root.formatDuration(compact.resetMs))
            : petStrings.t("agents.windowUsed").arg(windowName).arg(used))
        }
        if (compact.stale)
          lines.push(compact.fetchedAt > 0 && root.nowMs - compact.fetchedAt > 60000
            ? petStrings.t("agents.lastUpdatedAgo").arg(root.formatDuration(root.nowMs - compact.fetchedAt))
            : compact.fetchedAt > 0 ? petStrings.t("agents.lastUpdatedJustNow") : petStrings.t("agents.lastUpdatedUnknown"))
        for (var i = 0; i < compact.scoped.length; i++)
          lines.push(root.scopedAllowanceText(compact.scoped[i], compact.window ? compact.window.title : ""))
        return lines.join("\n")
      }
    }

    Text {
      id: compactTitle
      textFormat: Text.PlainText
      width: parent.width * 0.3
      anchors.verticalCenter: parent.verticalCenter
      text: compact.window ? root.windowDisplayTitle(compact.window.title) : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    TextMetrics {
      id: compactPercentMetrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      text: "100%"
    }

    Text {
      id: compactPercent
      anchors.left: compactTitle.right
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.ceil(compactPercentMetrics.advanceWidth)
      horizontalAlignment: Text.AlignRight
      textFormat: Text.PlainText
      text: compact.window && compact.window.percent >= 0
        ? Commons.I18n.formatNumber(Math.round(compact.window.percent * 100)) + "%"
        : ""
      color: compact.alarming ? root.urgent : root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Meter {
      anchors.left: compactPercent.right
      anchors.leftMargin: Style.space(10)
      anchors.right: compactValue.left
      anchors.rightMargin: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      value: compact.window ? compact.window.percent : -1
      alarming: compact.alarming
      markers: compact.scoped
    }

    // Sized to the widest time left ("19h 40m"), so every meter ends in the
    // same place.
    TextMetrics {
      id: compactValueMetrics
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      text: "00h 00m"
    }

    // How long until the window resets. The meter says how full it is; the
    // exact percentage is in the row's tooltip.
    Text {
      id: compactValue
      width: Math.ceil(compactValueMetrics.advanceWidth)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignRight
      text: compact.resetMs > 0 ? root.formatDuration(compact.resetMs) : ""
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  // Rounded track showing the percentage of the allowance used.
  component Meter: Item {
    id: meter
    property real value: -1
    property bool alarming: false
    property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

    // Other allowances on the same clock, drawn as ticks across the track.
    property var markers: []

    implicitHeight: thickness

    Rectangle {
      id: meterTrack
      anchors.fill: parent
      radius: height / 2
      color: root.track
    }

    Rectangle {
      anchors.left: meterTrack.left
      anchors.verticalCenter: meterTrack.verticalCenter
      height: meterTrack.height
      radius: meterTrack.radius
      width: meterTrack.width * root.clamp(meter.value, 0, 1)
      color: meter.alarming ? root.urgent : root.foreground

      Behavior on width {
        NumberAnimation { duration: Style.duration(160); easing.type: Easing.OutCubic }
      }
    }

    Repeater {
      model: meter.markers

      Rectangle {
        required property var modelData
        width: Math.max(2, Math.round(meter.thickness * 0.5))
        height: meter.thickness * 2.5
        radius: width / 2
        anchors.verticalCenter: meterTrack.verticalCenter
        // Explicit x doesn't mirror, so the tick measures from the end the
        // fill grows from.
        readonly property real along: root.clamp(meterTrack.width * root.clamp(Number(modelData.percent), 0, 1) - width / 2, 0, meterTrack.width - width)
        x: LayoutMirroring.enabled ? meterTrack.width - width - along : along
        color: meter.alarming ? root.urgent : root.foreground
      }
    }
  }
}
