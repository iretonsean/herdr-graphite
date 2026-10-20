import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// The message box. Enter sends the text to the selected session with `herdr agent prompt <name> <text>`.
// Shift+Enter makes a new line. The call is async; `status` says "Sent" or shows herdr's error.
Rectangle {
  id: root
  property string target: ""
  property string status: ""
  property bool failed: false
  property alias text: input.text
  readonly property bool busy: proc.running

  implicitHeight: Math.min(160, Math.max(52, input.implicitHeight + 24))
  radius: 10
  color: Theme.surface2

  function send() {
    var text = input.text.trim()
    if (text === "" || root.target === "" || proc.running) return
    root.failed = false
    root.status = "Sending…"
    proc.command = [Quickshell.env("HERDR_BIN") || "herdr", "agent", "prompt", root.target, text]
    proc.running = true
  }

  Process {
    id: proc
    stdout: StdioCollector { id: out }
    stderr: StdioCollector { id: err }
    onExited: function (code) {
      if (code === 0) {
        root.failed = false
        root.status = "Sent"
        input.text = ""
        clearTimer.restart()
      } else {
        var raw = (err.text || out.text).trim()
        var msg = raw
        try { var j = JSON.parse(raw); msg = (j.error && (j.error.message || j.error.code)) || raw } catch (e) {}
        root.failed = true
        root.status = msg !== "" ? msg : "herdr failed (exit " + code + ")"
      }
    }
  }
  Timer { id: clearTimer; interval: 3000; onTriggered: if (!root.failed) root.status = "" }

  Flickable {
    anchors { fill: parent; margins: 12; rightMargin: 44 }
    contentHeight: input.implicitHeight
    clip: true
    TextArea.flickable: TextArea {
      id: input
      placeholderText: root.target === "" ? "Select a session" : "Message " + root.target
      placeholderTextColor: Theme.text4
      enabled: root.target !== ""
      color: Theme.text1
      selectionColor: Theme.accent
      font.family: Theme.font; font.pixelSize: 14
      wrapMode: TextEdit.Wrap
      background: null
      padding: 0
      Keys.onPressed: function (e) {
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !(e.modifiers & Qt.ShiftModifier)) {
          root.send(); e.accepted = true
        }
      }
    }
  }
  Rectangle {
    anchors { right: parent.right; bottom: parent.bottom; margins: 10 }
    width: 28; height: 28; radius: 7
    color: sendHover.hovered && input.text.trim() !== "" ? Theme.lift : "transparent"
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Text {
      anchors.centerIn: parent
      text: "↑"
      color: input.text.trim() !== "" && root.target !== "" ? Theme.text1 : Theme.text4
      font.pixelSize: 15
    }
    HoverHandler { id: sendHover }
    TapHandler { onTapped: root.send() }
  }
}
