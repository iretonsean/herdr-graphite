import QtQuick

// A session card: title, state, type label, branch, time, context bar, last line.
// Click selects. Double click focuses the herdr pane.
Item {
  id: root
  property var row
  property bool selected: false
  signal picked()
  signal focusRequested()

  height: body.implicitHeight + 16

  Rectangle {
    anchors.fill: parent
    radius: 8
    color: root.selected ? Theme.surface3 : (hover.hovered ? Theme.surface2 : "transparent")
    border.width: root.selected ? 1 : 0
    border.color: Theme.highlight
    Behavior on color { ColorAnimation { duration: Theme.fast } }
  }

  Column {
    id: body
    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 8; leftMargin: 12; rightMargin: 8 }
    spacing: 5

    Row {
      width: parent.width
      spacing: 8
      Dot { state: root.row.state; anchors.verticalCenter: parent.verticalCenter }
      Text {
        width: parent.width - 24 - stateText.implicitWidth
        text: root.row.title
        elide: Text.ElideRight
        color: Theme.text1
        font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
      }
      Text {
        id: stateText
        text: root.row.stText
        color: Theme.stateColor(root.row.state)
        font.family: Theme.mono; font.pixelSize: 11
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    Row {
      x: 16
      width: parent.width - 16
      spacing: 7
      Chip { id: chip; text: root.row.kindLabel; fill: root.selected ? Theme.lift : Theme.surface3 }
      Text {
        width: parent.width - chip.width - 7
        anchors.verticalCenter: parent.verticalCenter
        text: root.row.facts
        elide: Text.ElideRight
        color: Theme.text3
        font.family: Theme.mono; font.pixelSize: 11
      }
    }
    Rectangle {
      x: 16
      width: parent.width - 16
      height: 3; radius: 2
      color: Theme.surface3
      visible: root.row.context >= 0
      Rectangle {
        width: parent.width * Math.min(100, Math.max(0, root.row.context)) / 100
        height: parent.height; radius: 2
        color: root.row.context >= 85 ? Theme.warn : Theme.accent
        Behavior on width { NumberAnimation { duration: Theme.slow; easing.type: Easing.OutCubic } }
      }
    }
    Text {
      x: 16
      width: parent.width - 16
      visible: root.row.last !== ""
      text: root.row.last
      elide: Text.ElideRight
      color: Theme.textSoft
      font.family: Theme.font; font.pixelSize: 12
    }
  }

  HoverHandler { id: hover }
  TapHandler { onTapped: root.picked(); onDoubleTapped: root.focusRequested() }
}
