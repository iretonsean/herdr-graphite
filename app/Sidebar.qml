import QtQuick

// The left column of the v2 prototype: the "N need you" row, search placeholder, machines -> projects -> session
// cards, the weekly limit card, and the New session and Closed rows (inert for now).
Rectangle {
  id: root
  property var model
  property int needCount: 0
  property int weeklyPct: -1
  property string weeklyResets: ""
  property string selectedKey: ""
  signal picked(string key)
  signal focusRequested(string target)

  radius: 12
  color: Theme.surface1

  component NavRow: Rectangle {
    property alias text: lbl.text
    property alias badge: badgeText.text
    property bool dim: false
    height: 40; radius: 8
    color: navHover.hovered ? Theme.surface3 : Theme.surface2
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Text {
      id: lbl
      x: 12; anchors.verticalCenter: parent.verticalCenter
      color: parent.dim ? Theme.text3 : Theme.text2
      font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
    }
    Rectangle {
      visible: badgeText.text !== ""
      anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
      height: 20; width: badgeText.implicitWidth + 16; radius: 10
      color: Qt.rgba(1, 0.8, 0.4, 0.14)
      Text { id: badgeText; anchors.centerIn: parent; color: Theme.warn; font.family: Theme.mono; font.pixelSize: 11 }
    }
    HoverHandler { id: navHover }
  }

  Column {
    id: top
    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; topMargin: 14 }
    spacing: 10
    NavRow { width: parent.width; text: "Command center"; badge: root.needCount > 0 ? root.needCount + " need you" : "" }
    NavRow { width: parent.width; text: "Search or run"; dim: true }
    Text {
      leftPadding: 6
      text: "Sessions"
      color: Theme.labelTint
      font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
    }
  }

  ListView {
    id: list
    anchors { left: parent.left; right: parent.right; top: top.bottom; bottom: weekly.top; margins: 10; topMargin: 6; bottomMargin: 6 }
    clip: true
    spacing: 2
    model: root.model
    boundsBehavior: Flickable.StopAtBounds

    // Cards slide to their new place when the order changes.
    move: Transition { NumberAnimation { properties: "y"; duration: Theme.slow; easing.type: Easing.OutCubic } }
    displaced: Transition { NumberAnimation { properties: "y"; duration: Theme.slow; easing.type: Easing.OutCubic } }
    add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.slow } }
    remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Theme.fast } }

    delegate: Item {
      id: del
      required property var model
      width: list.width
      height: model.kind === "session" ? card.height : (model.kind === "machine" ? 36 : 26)

      Rectangle {
        visible: del.model.kind === "machine" && del.y > 0
        width: parent.width; height: 1; color: Theme.hairline
      }
      Row {
        visible: del.model.kind === "machine"
        x: 8; spacing: 8; height: parent.height
        Dot { state: "done"; anchors.verticalCenter: parent.verticalCenter }
        Text {
          text: del.model.title; anchors.verticalCenter: parent.verticalCenter
          color: Theme.text1; font.family: Theme.mono; font.pixelSize: 13; font.weight: Font.Medium
        }
        Text {
          text: del.model.stText; anchors.verticalCenter: parent.verticalCenter
          color: Theme.text3; font.family: Theme.font; font.pixelSize: 12
        }
      }
      Text {
        visible: del.model.kind === "machine"
        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        text: del.model.count; color: Theme.text3; font.family: Theme.mono; font.pixelSize: 11
      }
      Item {
        visible: del.model.kind === "project"
        anchors.fill: parent
        Text {
          x: 28; anchors.verticalCenter: parent.verticalCenter
          text: del.model.title; color: Theme.labelTint
          font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        }
        Text {
          anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
          text: del.model.count; color: Theme.text3; font.family: Theme.mono; font.pixelSize: 11
        }
      }
      SessionCard {
        id: card
        visible: del.model.kind === "session"
        x: 16; width: parent.width - 16
        row: del.model
        selected: root.selectedKey === del.model.key
        onPicked: root.picked(del.model.key)
        onFocusRequested: { root.picked(del.model.key); root.focusRequested(del.model.target) }
      }
    }
  }

  // The weekly limit card (from the feed's weekly fields). Hidden when no feed has them.
  Rectangle {
    id: weekly
    anchors { left: parent.left; right: parent.right; bottom: actions.top; margins: 10; bottomMargin: 8 }
    height: root.weeklyPct >= 0 ? 44 : 0
    visible: root.weeklyPct >= 0
    radius: 8; color: Theme.surface2
    Text {
      x: 12; y: 8; text: "Weekly limit"
      color: Theme.text2; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
    }
    Text {
      anchors.right: parent.right; anchors.rightMargin: 12; y: 9
      text: root.weeklyPct + " %" + (root.weeklyResets !== "" ? " · " + root.weeklyResets : "")
      color: Theme.text3; font.family: Theme.mono; font.pixelSize: 11
    }
    Rectangle {
      x: 12; y: 31; width: parent.width - 24; height: 3; radius: 2; color: Theme.surface3
      Rectangle {
        width: parent.width * Math.min(100, root.weeklyPct) / 100; height: parent.height; radius: 2
        color: root.weeklyPct >= 90 ? Theme.warn : Theme.accent
        Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
      }
    }
  }

  Row {
    id: actions
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
    spacing: 8
    NavRow { width: (parent.width - 8) * 0.55; text: "+  New session" }
    NavRow { width: (parent.width - 8) * 0.45; text: "Closed" }
  }
}
