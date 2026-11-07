import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Streamlined, modern desktop companion card attached directly under Kian's hero
Item {
  id: root

  property string companionName: "Kian"
  property string companionModel: "gemini-3.8-flash-medium"
  property string companionModelDisplayName: "Gemini 3.8 Flash (Medium)"
  property string companionEffort: companionModel.endsWith("-high") ? "high" : (companionModel.endsWith("-low") ? "low" : "medium")
  property color foreground: Commons.Color.foreground
  property color dim: Qt.darker(foreground, 1.55)
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family
  property var providers: []
  property bool alarming: false

  signal openBrainSelectorRequested()

  // Selected insight (from hero click / cycle)
  property var currentInsight: null

  // State exported to parent & avatar
  property string avatarState: "idle"
  property bool isThinking: false
  property bool hasActiveConversation: false
  property string conversationId: ""
  property string lastResponseText: ""
  property string currentInsightBadge: "INSIGHT"
  property string copyFeedback: ""

  implicitHeight: contentCol.implicitHeight
  height: implicitHeight

  // Read battery stats from sysfs
  FileView {
    id: batCapFile
    path: "/sys/class/power_supply/BAT1/capacity"
    watchChanges: true
    printErrors: false
  }

  FileView {
    id: batStatFile
    path: "/sys/class/power_supply/BAT1/status"
    watchChanges: true
    printErrors: false
  }

  // Headless agy background execution
  Process {
    id: agyProcess
    running: false
    command: []

    stdout: StdioCollector {
      id: agyStdout
      waitForEnd: true
      onStreamFinished: function(text) {
        root.handleAgyResponse(text)
      }
    }

    stderr: StdioCollector {
      id: agyStderr
      waitForEnd: true
      onStreamFinished: function(text) {
        if (text && text.trim() !== "") {
          console.warn("Companion agy stderr:", text)
        }
      }
    }

    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && root.isThinking) {
        root.isThinking = false
        root.avatarState = root.alarming ? "warning" : "idle"
        var errDetail = agyStderr && agyStderr.text ? agyStderr.text.trim() : ""
        root.lastResponseText = "Failed to communicate with " + root.companionName + " (CLI exit code " + exitCode + (errDetail ? ": " + errDetail : "") + ")."
        root.currentInsightBadge = "ERROR"
      }
    }
  }

  Timer {
    id: speakingTimer
    interval: 1600
    repeat: false
    onTriggered: {
      root.avatarState = root.alarming ? "warning" : "idle"
    }
  }

  Timer {
    id: copyFeedbackTimer
    interval: 2000
    repeat: false
    onTriggered: root.copyFeedback = ""
  }

  function buildAmbientContext() {
    var cap = (batCapFile.text() || "100").trim()
    var stat = (batStatFile.text() || "Discharging").trim()

    var totalTokens = 0
    var totalPrompts = 0
    var totalSessions = 0
    var limitAlerts = []

    if (root.providers && root.providers.length > 0) {
      for (var i = 0; i < root.providers.length; i++) {
        var p = root.providers[i]
        totalTokens += Number(p.todayTotalTokens || 0)
        totalPrompts += Number(p.todayPrompts || 0)
        totalSessions += Number(p.todaySessions || 0)

        var lims = p.limits || []
        for (var l = 0; l < lims.length; l++) {
          var lim = lims[l]
          var pct = Number(lim.percent || 0)
          if (pct >= 0.8) {
            var provName = p.providerName || p.providerId || p.name || p.id || "Agent"
            limitAlerts.push(provName + " " + (lim.label || lim.title || "Limit") + " at " + Math.round(pct * 100) + "%")
          }
        }
      }
    }

    var mTokens = (totalTokens / 1000000).toFixed(1)
    var ctx = "OS: Omarchy Linux (Arch Linux) on Hyprland.\n"
    ctx += "Battery: " + cap + "% (" + stat + ").\n"
    ctx += "Token Totals Today: " + mTokens + "M tokens across " + totalSessions + " sessions, " + totalPrompts + " prompts.\n"
    if (limitAlerts.length > 0) {
      ctx += "Active Quota Alerts: " + limitAlerts.join("; ") + ".\n"
    } else {
      ctx += "Active Quota Alerts: None (all limits healthy).\n"
    }
    return ctx
  }

  function askQuestion(userPrompt) {
    if (isThinking || !userPrompt || userPrompt.trim() === "") return
    var query = userPrompt.trim()

    isThinking = true
    avatarState = "thinking"
    currentInsightBadge = "THINKING..."

    var ambient = buildAmbientContext()
    var fullPrompt = ""

    if (!hasActiveConversation && conversationId === "") {
      fullPrompt = "You are " + companionName + ", an intelligent, witty, hacker-chic desktop AI companion for Omarchy Linux.\n"
      fullPrompt += "Ambient Context:\n" + ambient + "\n"
      fullPrompt += "Instructions: Answer directly, concisely, and helpfully. Keep answers to 1-3 short paragraphs or clean bullet points. Avoid markdown headers like # or tables. Use clean plain text.\n\n"
      fullPrompt += "User: " + query
    } else {
      fullPrompt = "[Ambient Update: " + ambient.replace(/\n/g, " | ") + "]\n"
      fullPrompt += "User: " + query
    }

    var cmd = ["agy"]
    if (conversationId !== "") {
      cmd.push("--conversation", conversationId)
    } else if (hasActiveConversation) {
      cmd.push("--continue")
    }
    cmd.push(
      "-p", fullPrompt,
      "--model", companionModel,
      "--effort", companionEffort,
      "--dangerously-skip-permissions",
      "--output-format", "text"
    )

    agyProcess.command = cmd
    agyProcess.running = true
  }

  function handleAgyResponse(rawOutput) {
    root.isThinking = false
    var clean = String(rawOutput || "").trim()
    var reply = clean

    if (reply.startsWith("{") && reply.endsWith("}")) {
      try {
        var data = JSON.parse(reply)
        if (data.conversation_id) root.conversationId = data.conversation_id
        if (data.response !== undefined) reply = data.response
      } catch (e) {
      }
    }

    if (reply === "") {
      reply = "No response received."
    } else {
      root.hasActiveConversation = true
    }

    root.lastResponseText = reply.trim()
    root.currentInsightBadge = root.companionName.toUpperCase() + " AI"

    root.avatarState = "speaking"
    speakingTimer.restart()
  }

  function clearChat() {
    hasActiveConversation = false
    conversationId = ""
    lastResponseText = ""
    currentInsightBadge = "INSIGHT"
    avatarState = alarming ? "warning" : "idle"
  }

  function copyTextToClipboard(text) {
    if (!text || text === "") return
    Quickshell.execDetached(["wl-copy", "--", text])
    copyFeedback = "Copied!"
    copyFeedbackTimer.restart()
  }

  readonly property string displayBodyText: {
    if (lastResponseText !== "") return lastResponseText
    if (currentInsight && currentInsight.details) return currentInsight.details
    return "Click " + companionName + " above or ask any question about your laptop, tokens, or system state below."
  }

  readonly property string activeBadgeText: {
    if (copyFeedback !== "") return copyFeedback
    if (isThinking) return "THINKING..."
    if (lastResponseText !== "") return companionName.toUpperCase() + " AI"
    if (currentInsight && currentInsight.badge) return currentInsight.badge
    return "INSIGHT"
  }

  // ------------------------------------------------------------- UI Layout

  Column {
    id: contentCol
    width: parent.width
    spacing: Style.space(8)

    // Sleek Speech Bubble / Insight Card
    Rectangle {
      id: speechCard
      width: parent.width
      radius: Style.cornerRadius
      color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
      border.width: 1
      border.color: root.isThinking
        ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.40)
        : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

      implicitHeight: speechCardCol.implicitHeight + Style.space(16)
      height: implicitHeight

      Column {
        id: speechCardCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(10)
        spacing: Style.space(6)

        // Card Header Bar: Badge + Model + Actions
        Row {
          width: parent.width
          spacing: Style.space(6)

          // Badge pill
          Rectangle {
            implicitWidth: badgeText.implicitWidth + Style.space(8)
            implicitHeight: Style.space(18)
            radius: Style.cornerRadius
            color: root.isThinking
              ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)
              : Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.12)

            Text {
              id: badgeText
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: root.activeBadgeText
              color: Commons.Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption - 1
              font.bold: true
            }
          }

          // Spacer
          Item {
            width: Math.max(0, parent.width - parent.children[0].width - cardActions.width - Style.space(6))
            height: 1
          }

          // Trailing Actions (Copy, Clear, Model)
          Row {
            id: cardActions
            spacing: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter

            // Copy button
            Rectangle {
              visible: root.lastResponseText !== ""
              width: Style.space(20)
              height: Style.space(20)
              radius: Style.cornerRadius
              color: copyMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰆏"
                color: root.dim
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: copyMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.copyTextToClipboard(root.lastResponseText)
              }
            }

            // Clear button
            Rectangle {
              visible: root.lastResponseText !== "" || root.conversationId !== ""
              width: Style.space(20)
              height: Style.space(20)
              radius: Style.cornerRadius
              color: clearMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "󰃢"
                color: root.dim
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.clearChat()
              }
            }

            // Interactive Model Pill (Full Name)
            Rectangle {
              implicitWidth: modelRow.implicitWidth + Style.space(12)
              implicitHeight: Style.space(20)
              radius: Style.cornerRadius
              color: modelPillMouse.containsMouse
                ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.16)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
              border.width: 1
              border.color: modelPillMouse.containsMouse
                ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.35)
                : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

              Behavior on color { ColorAnimation { duration: Style.duration(100) } }

              Row {
                id: modelRow
                anchors.centerIn: parent
                spacing: Style.space(4)

                Text {
                  id: modelLabel
                  textFormat: Text.PlainText
                  text: root.companionModelDisplayName
                  color: modelPillMouse.containsMouse ? Commons.Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - 1
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                  textFormat: Text.PlainText
                  text: "▾"
                  color: modelPillMouse.containsMouse ? Commons.Color.accent : root.dim
                  font.pixelSize: Style.font.caption - 2
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                id: modelPillMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openBrainSelectorRequested()
              }
            }
          }
        }

        // Main text content
        Text {
          id: bodyText
          textFormat: Text.PlainText
          width: parent.width
          text: root.displayBodyText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          lineHeight: 1.25
        }
      }
    }

    // Interactive Input Row
    Row {
      width: parent.width
      spacing: Style.space(6)

      TextField {
        id: queryField
        width: parent.width - sendBtn.width - Style.space(6)
        placeholderText: "Ask " + root.companionName + " anything..."
        foreground: root.foreground
        accent: Commons.Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        enabled: !root.isThinking
        onAccepted: {
          if (text.trim() !== "") {
            root.askQuestion(text.trim())
            text = ""
          }
        }
      }

      Button {
        id: sendBtn
        iconText: "󰒭"
        tooltipText: "Send to " + root.companionName
        bordered: true
        foreground: root.foreground
        accent: Commons.Color.accent
        enabled: queryField.text.trim() !== "" && !root.isThinking
        onClicked: {
          if (queryField.text.trim() !== "") {
            root.askQuestion(queryField.text.trim())
            queryField.text = ""
          }
        }
      }
    }
  }
}
