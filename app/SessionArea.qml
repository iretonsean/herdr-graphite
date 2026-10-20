import QtQuick

// The session area. For now: the selected card's title, state, plan steps and last line, and the message box.
// The full session view is H3b.
Rectangle {
  id: root
  property var session: null
  property alias status: box.status
  radius: 12
  color: Theme.surface1

  property var items: {
    if (!session) return []
    try { return JSON.parse(session.planItems) } catch (e) { return [] }
  }

  function seconds(s) {
    if (s === null || s === undefined) return ""
    return s < 60 ? s + " s" : Math.round(s / 60) + " min"
  }

  Column {
    visible: root.session !== null
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 28; topMargin: 24 }
    spacing: 10
    Row {
      spacing: 8
      Chip { text: root.session ? root.session.kindLabel : "" }
      Dot { state: root.session ? root.session.state : "ready"; anchors.verticalCenter: parent.verticalCenter }
      Text {
        text: root.session ? root.session.stText : ""
        color: root.session ? Theme.stateColor(root.session.state) : Theme.text3
        font.family: Theme.mono; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter
      }
    }
    Text {
      width: parent.width
      text: root.session ? root.session.title : ""
      wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
      color: Theme.text1; font.family: Theme.font; font.pixelSize: 24; font.weight: Font.DemiBold
    }
    Text {
      text: root.session ? root.session.machine + " › " + root.session.project + (root.session.branch !== "" ? " · " + root.session.branch : "") : ""
      color: Theme.text3; font.family: Theme.mono; font.pixelSize: 12
    }
    Item { width: 1; height: 8 }
    Text {
      width: parent.width
      visible: root.session && root.session.last !== ""
      text: root.session ? root.session.last : ""
      wrapMode: Text.Wrap
      color: Theme.textSoft; font.family: Theme.font; font.pixelSize: 14
    }
    Rectangle {
      visible: root.items.length > 0
      width: Math.min(parent.width, 520)
      height: planCol.implicitHeight + 24
      radius: 10; color: Theme.surface2
      Column {
        id: planCol
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        spacing: 4
        Row {
          width: parent.width
          Text { text: "Plan"; width: parent.width - doneText.implicitWidth; color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold }
          Text { id: doneText; text: root.session ? root.session.planDone + " of " + root.session.planTotal : ""; color: Theme.text3; font.family: Theme.mono; font.pixelSize: 11 }
        }
        Repeater {
          model: root.items
          delegate: Row {
            required property var modelData
            width: planCol.width; height: 26; spacing: 10
            Dot { state: modelData.status === "done" ? "done" : (modelData.status === "now" ? "working" : "ready"); anchors.verticalCenter: parent.verticalCenter }
            Text {
              width: parent.width - 18 - secs.implicitWidth - 10
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.status === "now" && modelData.doing ? modelData.doing : modelData.name
              elide: Text.ElideRight
              color: modelData.status === "next" ? Theme.text3 : Theme.text1
              font.family: Theme.font; font.pixelSize: 13
            }
            Text { id: secs; anchors.verticalCenter: parent.verticalCenter; text: root.seconds(modelData.seconds); color: Theme.text3; font.family: Theme.mono; font.pixelSize: 11 }
          }
        }
      }
    }
  }

  Text {
    visible: root.session === null
    anchors.centerIn: parent
    text: "Select a session"
    color: Theme.text3; font.family: Theme.font; font.pixelSize: 14
  }

  Text {
    id: statusText
    anchors { left: box.left; bottom: box.top; bottomMargin: 6 }
    text: box.status
    color: box.failed ? Theme.error : Theme.text3
    font.family: Theme.mono; font.pixelSize: 11
  }
  MessageBox {
    id: box
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 28; bottomMargin: 20 }
    target: root.session ? root.session.target : ""
  }
}
