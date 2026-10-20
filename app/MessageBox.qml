import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// The message box. Enter sends the text to the selected session with `herdr agent prompt <name> <text>`.
// Shift+Enter makes a new line. The call is async; `status` says "Sent" or shows herdr's error.
Rectangle {
  id: root
  property string target: ""
  // The status line belongs to the session of the last send: it shows only while that session is the target.
  property string rawStatus: ""
  property string statusTarget: ""
  readonly property string status: statusTarget === target ? rawStatus : ""
  property bool failed: false
  // One draft per session: the text stays with the session it was typed for.
  property var drafts: ({})
  property string shown: ""
  property alias text: input.text
  readonly property bool busy: proc.running

  implicitHeight: Math.min(160, Math.max(52, input.implicitHeight + 24))
  radius: 10
  color: Theme.surface2

  onTargetChanged: {
    drafts[shown] = input.text
    shown = target
    input.text = drafts[target] || ""
  }

  function send() {
    var text = input.text.trim()
    if (text === "" || root.target === "" || proc.running) return
    root.failed = false
    root.statusTarget = root.target
    root.rawStatus = "Sending…"
    proc.sentTarget = root.target
    proc.sentText = text
    proc.command = [Quickshell.env("HERDR_BIN") || "herdr", "agent", "prompt", root.target, text]
    proc.running = true
  }

  Process {
    id: proc
    property string sentTarget: ""
    property string sentText: ""
    stdout: StdioCollector { id: out }
    stderr: StdioCollector { id: err }
    onExited: function (code) {
      if (code === 0) {
        root.failed = false
        root.rawStatus = "Sent"
        // Remove only the text that was sent. Text typed since then, or a draft of another session, stays.
        if (root.target === proc.sentTarget) { if (input.text.trim() === proc.sentText) input.text = "" }
        else if ((root.drafts[proc.sentTarget] || "").trim() === proc.sentText) root.drafts[proc.sentTarget] = ""
        clearTimer.restart()
      } else {
        var raw = (err.text || out.text).trim()
        var msg = raw
        try { var j = JSON.parse(raw); msg = (j.error && (j.error.message || j.error.code)) || raw } catch (e) {}
        root.failed = true
        root.rawStatus = msg !== "" ? msg : "herdr failed (exit " + code + ")"
      }
    }
  }
  Timer { id: clearTimer; interval: 3000; onTriggered: if (!root.failed) root.rawStatus = "" }

  Flickable {
    anchors { fill: parent; margins: 12; rightMargin: 44 + (targetLabel.visible ? targetLabel.implicitWidth + 8 : 0) }
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
  Text {
    id: targetLabel
    visible: input.text !== "" && root.target !== ""
    anchors { right: parent.right; rightMargin: 44; bottom: parent.bottom; bottomMargin: 14 }
    text: "→ " + root.target
    color: Theme.text3
    font.family: Theme.mono; font.pixelSize: 11
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
