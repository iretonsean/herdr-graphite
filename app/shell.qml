import "join.js" as Join
import QtQuick
import Quickshell
import Quickshell.Io

// Herdr Graphite app. Run: quickshell -p app/shell.qml
// It only reads from herdr (agent list, feed files), and sends two commands: `agent focus` and `agent prompt`.
// It never starts, stops or reconfigures herdr. Closing the window ends only this app.
ShellRoot {
  id: root
  property string selectedKey: ""
  property int needCount: 0
  property int weeklyPct: -1
  property string weeklyResets: ""
  property string lastJson: ""

  ListModel { id: rows }

  readonly property var selected: {
    for (var i = 0; i < rows.count; i++)
      if (rows.get(i).key === selectedKey) return rows.get(i)
    return null
  }

  Connections {
    target: Quickshell
    function onLastWindowClosed() { Qt.quit() }
  }

  readonly property var defaults: ({
    key: "", kind: "", machine: "", project: "", target: "", pane: "", title: "", state: "ready", stText: "",
    kindLabel: "", branch: "", facts: "", context: -1, last: "", activity: "", planDone: 0, planTotal: 0,
    planItems: "[]", hasFeed: false, count: ""
  })

  function full(r) {
    var o = {}
    for (var k in defaults) o[k] = r[k] !== undefined ? r[k] : defaults[k]
    return o
  }

  // Bring the list in line with the new rows without rebuilding it: insert, move and update in place,
  // so cards slide to their new place and keep their hover and selection state.
  function sync(next) {
    for (var i = 0; i < next.length; i++) {
      var r = full(next[i])
      var at = -1
      for (var j = i; j < rows.count; j++) if (rows.get(j).key === r.key) { at = j; break }
      if (at < 0) rows.insert(i, r)
      else {
        if (at !== i) rows.move(at, i, 1)
        for (var k in r) if (rows.get(i)[k] !== r[k]) rows.setProperty(i, k, r[k])
      }
    }
    while (rows.count > next.length) rows.remove(rows.count - 1)
  }

  function apply(text) {
    if (text === lastJson) return
    lastJson = text
    var input
    try { input = JSON.parse(text) } catch (e) { return }
    var m = Join.buildModel(input)
    root.needCount = m.needCount
    root.weeklyPct = m.weekly.pct
    root.weeklyResets = m.weekly.resets
    sync(m.rows)
    if (selectedKey === "") {
      for (var i = 0; i < rows.count; i++) if (rows.get(i).kind === "session") { selectedKey = rows.get(i).key; break }
    }
  }

  // One async read every 2 s. The next poll starts only after the last one ended.
  Process {
    id: poll
    command: ["bash", Quickshell.shellPath("poll.sh")]
    stdout: StdioCollector { onStreamFinished: root.apply(text.trim()) }
  }
  Timer { interval: 2000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!poll.running) poll.running = true }

  Process { id: focusProc }
  function focusPane(target) {
    if (focusProc.running) return
    focusProc.command = [Quickshell.env("HERDR_BIN") || "herdr", "agent", "focus", target]
    focusProc.running = true
  }

  FloatingWindow {
    id: win
    title: "Herdr Graphite"
    implicitWidth: Number(Quickshell.env("HG_WIDTH")) || 1100
    implicitHeight: Number(Quickshell.env("HG_HEIGHT")) || 700
    color: Theme.surface0
    visible: true
    // The window closes (the close button of the window manager, or Ctrl+W): the app ends.
    onVisibleChanged: if (!visible) Qt.quit()

    // Ctrl+W closes the window. Closing the last window ends the app (and only the app).
    Shortcut { sequence: "Ctrl+W"; onActivated: win.visible = false }

    Item {
      anchors { fill: parent; margins: 8 }
      Sidebar {
        id: sidebar
        width: 320
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        model: rows
        needCount: root.needCount
        weeklyPct: root.weeklyPct
        weeklyResets: root.weeklyResets
        selectedKey: root.selectedKey
        onPicked: function (key) { root.selectedKey = key }
        onFocusRequested: function (target) { root.focusPane(target) }
      }
      SessionArea {
        anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom; leftMargin: 8 }
        session: root.selected
      }
    }
  }
}
