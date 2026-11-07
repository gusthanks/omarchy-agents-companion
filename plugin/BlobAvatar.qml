import QtQuick
import qs.Commons
import qs.Commons as Commons

// Sleek, organic vector blob companion avatar inspired by bible-strong-avatar-lab
// Adapted natively for Omarchy: fluid breathing, expressive eyes, gaze tracking,
// natural blinking, and dynamic theme-accented states.
Item {
  id: root

  property real size: Style.space(42)
  property color foreground: Commons.Color.foreground
  property color accentColor: Commons.Color.accent
  property color warningColor: Commons.Color.urgent
  property bool alarming: false
  property string avatarState: "idle" // "idle", "hover", "thinking", "speaking", "happy", "warning"

  signal clicked()

  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  // Effective accent color based on alert / warning state
  readonly property color effectiveAccent: (root.alarming || root.avatarState === "warning")
    ? root.warningColor
    : root.accentColor

  readonly property color eyeColor: root.foreground

  // Gaze coordinates relative to eye center (-4 to +4 px)
  property real gazeX: 0.0
  property real gazeY: 0.0

  // Blink scale (1.0 = wide open, 0.08 = closed slit)
  property real eyeBlinkScale: 1.0

  // Organic squash & stretch properties
  property real bodyScaleX: 1.0
  property real bodyScaleY: 1.0
  property real bodyOffsetY: 0.0
  property real bodyRotation: 0.0

  // Smooth easing for gaze transitions
  Behavior on gazeX {
    NumberAnimation {
      duration: Style.duration(130)
      easing.type: Easing.OutQuad
    }
  }

  Behavior on gazeY {
    NumberAnimation {
      duration: Style.duration(130)
      easing.type: Easing.OutQuad
    }
  }

  Behavior on eyeBlinkScale {
    NumberAnimation {
      duration: Style.duration(75)
      easing.type: Easing.InOutQuad
    }
  }

  // ------------------------------------------------------------- Motion & Animations

  // 1. Organic Idle Breathing (gentle counter-cycling scaleX and scaleY)
  SequentialAnimation {
    id: breathingAnim
    running: root.avatarState === "idle" && !root.alarming && !mouseArea.containsMouse
    loops: Animation.Infinite

    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "bodyScaleX"
        to: 1.035
        duration: Style.duration(1800)
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: root
        property: "bodyScaleY"
        to: 0.965
        duration: Style.duration(1800)
        easing.type: Easing.InOutSine
      }
    }

    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "bodyScaleX"
        to: 0.985
        duration: Style.duration(1800)
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: root
        property: "bodyScaleY"
        to: 1.025
        duration: Style.duration(1800)
        easing.type: Easing.InOutSine
      }
    }
  }

  // 2. Thinking Float Animation
  SequentialAnimation {
    id: thinkingAnim
    running: root.avatarState === "thinking"
    loops: Animation.Infinite

    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "bodyOffsetY"
        to: -3.5
        duration: Style.duration(900)
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: root
        property: "bodyRotation"
        to: 1.8
        duration: Style.duration(900)
        easing.type: Easing.InOutSine
      }
    }

    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "bodyOffsetY"
        to: 1.0
        duration: Style.duration(900)
        easing.type: Easing.InOutSine
      }
      NumberAnimation {
        target: root
        property: "bodyRotation"
        to: -1.8
        duration: Style.duration(900)
        easing.type: Easing.InOutSine
      }
    }
  }

  // 3. Speaking Mouth & Bob Animation
  SequentialAnimation {
    id: speakingBobAnim
    running: root.avatarState === "speaking"
    loops: Animation.Infinite

    ParallelAnimation {
      NumberAnimation { target: root; property: "bodyScaleX"; to: 1.04; duration: Style.duration(180); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyScaleY"; to: 0.96; duration: Style.duration(180); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyOffsetY"; to: -1.5; duration: Style.duration(180); easing.type: Easing.OutQuad }
      NumberAnimation { target: mouth; property: "height"; to: Math.max(3.2, root.size * 0.11); duration: Style.duration(180) }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "bodyScaleX"; to: 0.98; duration: Style.duration(180); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyScaleY"; to: 1.02; duration: Style.duration(180); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyOffsetY"; to: 0.5; duration: Style.duration(180); easing.type: Easing.OutQuad }
      NumberAnimation { target: mouth; property: "height"; to: 1.5; duration: Style.duration(180) }
    }
  }

  // 4. Happy Jump & Squash Animation
  SequentialAnimation {
    id: happyAnim
    running: false

    ParallelAnimation {
      NumberAnimation { target: root; property: "bodyScaleX"; to: 1.18; duration: Style.duration(80); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyScaleY"; to: 0.82; duration: Style.duration(80); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyOffsetY"; to: 2.0; duration: Style.duration(80); easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "bodyScaleX"; to: 0.86; duration: Style.duration(160); easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "bodyScaleY"; to: 1.20; duration: Style.duration(160); easing.type: Easing.OutBack }
      NumberAnimation { target: root; property: "bodyOffsetY"; to: -6.0; duration: Style.duration(160); easing.type: Easing.OutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "bodyScaleX"; to: 1.05; duration: Style.duration(120); easing.type: Easing.InOutQuad }
      NumberAnimation { target: root; property: "bodyScaleY"; to: 0.96; duration: Style.duration(120); easing.type: Easing.InOutQuad }
      NumberAnimation { target: root; property: "bodyOffsetY"; to: 1.0; duration: Style.duration(120); easing.type: Easing.InOutQuad }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "bodyScaleX"; to: 1.0; duration: Style.duration(100); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyScaleY"; to: 1.0; duration: Style.duration(100); easing.type: Easing.OutQuad }
      NumberAnimation { target: root; property: "bodyOffsetY"; to: 0.0; duration: Style.duration(100); easing.type: Easing.OutQuad }
    }
  }

  // ------------------------------------------------------------- Timers

  // Natural Random Blinking
  Timer {
    id: blinkTimer
    interval: 3200 + Math.random() * 2000
    running: root.avatarState !== "happy"
    repeat: true
    onTriggered: {
      root.eyeBlinkScale = 0.08
      blinkEndTimer.restart()
    }
  }

  Timer {
    id: blinkEndTimer
    interval: 110
    repeat: false
    onTriggered: {
      root.eyeBlinkScale = 1.0
      blinkTimer.interval = 3000 + Math.random() * 2500
    }
  }

  // Idle Gaze Shifts (micro-saccades)
  Timer {
    id: idleGazeTimer
    interval: 4200
    running: root.avatarState === "idle" && !mouseArea.containsMouse
    repeat: true
    onTriggered: {
      var r = Math.random()
      if (r < 0.28) {
        root.gazeX = -2.8
        root.gazeY = 0.0
      } else if (r < 0.56) {
        root.gazeX = 2.8
        root.gazeY = 0.0
      } else if (r < 0.72) {
        root.gazeX = 0.0
        root.gazeY = -2.0
      } else {
        root.gazeX = 0.0
        root.gazeY = 0.0
      }
    }
  }

  // Happy Reset Timer
  Timer {
    id: happyResetTimer
    interval: 950
    repeat: false
    onTriggered: {
      root.avatarState = root.alarming ? "warning" : "idle"
      root.bodyOffsetY = 0
      root.bodyScaleX = 1.0
      root.bodyScaleY = 1.0
      root.bodyRotation = 0.0
    }
  }

  function triggerHappy() {
    root.avatarState = "happy"
    happyAnim.restart()
    happyResetTimer.restart()
    happyCanvas.requestPaint()
  }

  onAvatarStateChanged: {
    if (avatarState === "thinking") {
      gazeX = 2.4
      gazeY = -2.2
    } else if (avatarState === "happy") {
      gazeX = 0.0
      gazeY = -0.5
      happyCanvas.requestPaint()
    } else if (avatarState === "idle" && !mouseArea.containsMouse) {
      gazeX = 0.0
      gazeY = 0.0
    }
  }

  // ------------------------------------------------------------- Visual Structure

  Item {
    id: blobTransformWrapper
    anchors.centerIn: parent
    width: root.size
    height: root.size

    transform: [
      Scale {
        origin.x: root.size / 2
        origin.y: root.size / 2
        xScale: root.bodyScaleX * (mouseArea.containsMouse ? 1.05 : 1.0)
        yScale: root.bodyScaleY * (mouseArea.containsMouse ? 1.05 : 1.0)
      },
      Translate {
        y: root.bodyOffsetY
      },
      Rotation {
        origin.x: root.size / 2
        origin.y: root.size / 2
        angle: root.bodyRotation
      }
    ]

    // Soft ground ambient shadow
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(1)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width * 0.72
      height: Style.space(3)
      radius: height / 2
      color: Qt.rgba(0, 0, 0, 0.32)
      opacity: 1.0 - Math.min(1.0, Math.abs(root.bodyOffsetY) / 8.0)
    }

    // Organic Blob Body (soft pebble squircle with volumetric gradient)
    Rectangle {
      id: blobBody
      anchors.centerIn: parent
      width: root.size * 0.92
      height: root.size * 0.88
      radius: root.size * 0.44

      gradient: Gradient {
        GradientStop {
          position: 0.0
          color: Qt.rgba(
            root.effectiveAccent.r,
            root.effectiveAccent.g,
            root.effectiveAccent.b,
            mouseArea.containsMouse ? 0.35 : (root.avatarState === "thinking" ? 0.30 : 0.24)
          )
        }
        GradientStop {
          position: 1.0
          color: Qt.rgba(
            root.effectiveAccent.r,
            root.effectiveAccent.g,
            root.effectiveAccent.b,
            mouseArea.containsMouse ? 0.22 : (root.avatarState === "thinking" ? 0.18 : 0.13)
          )
        }
      }

      border.width: 1.5
      border.color: Qt.rgba(
        root.effectiveAccent.r,
        root.effectiveAccent.g,
        root.effectiveAccent.b,
        mouseArea.containsMouse ? 0.92 : (root.avatarState === "thinking" ? 0.70 : 0.50)
      )

      Behavior on border.color { ColorAnimation { duration: Style.duration(160) } }

      // Top Glass Sheen Highlight
      Rectangle {
        anchors.top: parent.top
        anchors.topMargin: Math.max(2.0, root.size * 0.06)
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.60
        height: parent.height * 0.26
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.14)
      }

      // Facial Features Container (Gaze translated)
      Item {
        id: faceContainer
        anchors.centerIn: parent
        width: parent.width
        height: parent.height

        readonly property real eyeSpacing: root.size * 0.28
        readonly property real eyeWidth: Math.max(4.5, root.size * 0.13)
        readonly property real eyeHeight: Math.max(7.8, root.size * 0.235)
        readonly property real faceCenterY: parent.height / 2 - root.size * 0.03

        // Cute Subtle Rosy Cheeks
        Row {
          id: blushRow
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.horizontalCenterOffset: root.gazeX * 0.4
          anchors.top: parent.top
          anchors.topMargin: faceContainer.faceCenterY + (faceContainer.eyeHeight / 2) - 1 + root.gazeY * 0.4
          spacing: faceContainer.eyeSpacing + faceContainer.eyeWidth
          visible: !root.alarming && root.avatarState !== "warning"

          Rectangle {
            width: Math.max(4.0, root.size * 0.11)
            height: Math.max(2.2, root.size * 0.06)
            radius: height / 2
            color: Qt.rgba(root.effectiveAccent.r, root.effectiveAccent.g, root.effectiveAccent.b, 0.35)
          }

          Rectangle {
            width: Math.max(4.0, root.size * 0.11)
            height: Math.max(2.2, root.size * 0.06)
            radius: height / 2
            color: Qt.rgba(root.effectiveAccent.r, root.effectiveAccent.g, root.effectiveAccent.b, 0.35)
          }
        }

        // Normal Vector Capsule Eyes
        Item {
          id: vectorEyes
          visible: root.avatarState !== "happy"
          anchors.fill: parent

          // Left Eye Capsule
          Rectangle {
            id: leftEye
            x: (parent.width / 2) - (faceContainer.eyeSpacing / 2) - (faceContainer.eyeWidth / 2) + root.gazeX
            y: faceContainer.faceCenterY - (height / 2) + root.gazeY
            width: faceContainer.eyeWidth
            height: Math.max(1.5, faceContainer.eyeHeight * root.eyeBlinkScale)
            radius: width / 2
            color: root.eyeColor

            // Pupil Catchlight Sparkle
            Rectangle {
              visible: root.eyeBlinkScale > 0.4
              anchors.right: parent.right
              anchors.rightMargin: 1
              anchors.top: parent.top
              anchors.topMargin: 1.2
              width: Math.max(1.6, parent.width * 0.38)
              height: width
              radius: width / 2
              color: "#ffffff"
              opacity: 0.95
            }
          }

          // Right Eye Capsule
          Rectangle {
            id: rightEye
            x: (parent.width / 2) + (faceContainer.eyeSpacing / 2) - (faceContainer.eyeWidth / 2) + root.gazeX
            y: faceContainer.faceCenterY - (height / 2) + root.gazeY
            width: faceContainer.eyeWidth
            height: Math.max(1.5, faceContainer.eyeHeight * root.eyeBlinkScale)
            radius: width / 2
            color: root.eyeColor

            // Pupil Catchlight Sparkle
            Rectangle {
              visible: root.eyeBlinkScale > 0.4
              anchors.right: parent.right
              anchors.rightMargin: 1
              anchors.top: parent.top
              anchors.topMargin: 1.2
              width: Math.max(1.6, parent.width * 0.38)
              height: width
              radius: width / 2
              color: "#ffffff"
              opacity: 0.95
            }
          }
        }

        // Happy Smiling Vector Crescents ⌒  ⌒ (Canvas)
        Canvas {
          id: happyCanvas
          visible: root.avatarState === "happy"
          anchors.fill: parent
          renderStrategy: Canvas.Cooperative

          onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = root.effectiveAccent
            ctx.lineWidth = Math.max(1.8, root.size * 0.052)
            ctx.lineCap = "round"

            var cx = width / 2 + root.gazeX
            var cy = faceContainer.faceCenterY + root.gazeY + 1.5
            var sp = faceContainer.eyeSpacing
            var r = Math.max(3.2, root.size * 0.082)

            // Left crescent ⌒
            ctx.beginPath()
            ctx.arc(cx - (sp / 2), cy, r, Math.PI * 1.15, Math.PI * 1.85, false)
            ctx.stroke()

            // Right crescent ⌒
            ctx.beginPath()
            ctx.arc(cx + (sp / 2), cy, r, Math.PI * 1.15, Math.PI * 1.85, false)
            ctx.stroke()
          }
        }

        // Animated Speaking Mouth
        Rectangle {
          id: mouth
          visible: root.avatarState === "speaking"
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.horizontalCenterOffset: root.gazeX * 0.6
          anchors.top: parent.top
          anchors.topMargin: faceContainer.faceCenterY + (faceContainer.eyeHeight / 2) + Style.space(2) + root.gazeY
          width: Math.max(4.5, root.size * 0.12)
          height: 1.5
          radius: width / 2
          color: root.eyeColor
        }
      }
    }
  }

  // Interactive Mouse Tracking & Click Handling
  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onPositionChanged: function(mouse) {
      if (root.avatarState === "happy") return
      var cx = width / 2
      var cy = height / 2
      var dx = (mouse.x - cx) / (width / 2)
      var dy = (mouse.y - cy) / (height / 2)
      root.gazeX = Math.max(-3.5, Math.min(3.5, dx * 3.5))
      root.gazeY = Math.max(-2.5, Math.min(2.5, dy * 2.5))
    }

    onExited: {
      if (root.avatarState === "idle") {
        root.gazeX = 0.0
        root.gazeY = 0.0
      }
    }

    onClicked: {
      root.triggerHappy()
      root.clicked()
    }
  }
}
