import QtQuick

// The state dot. Working and needs-you pulse softly.
Item {
  id: root
  property string state: "ready"
  implicitWidth: 8
  implicitHeight: 8
  Rectangle {
    id: halo
    anchors.centerIn: parent
    width: 8; height: 8; radius: 4
    color: "transparent"
    border.width: 2
    border.color: Theme.stateColor(root.state)
    opacity: 0
    visible: root.state === "working" || root.state === "needs"
    NumberAnimation on opacity { running: halo.visible; loops: Animation.Infinite; from: 0.5; to: 0; duration: 1600; easing.type: Easing.OutQuad }
    NumberAnimation on scale { running: halo.visible; loops: Animation.Infinite; from: 1; to: 1.9; duration: 1600; easing.type: Easing.OutQuad }
  }
  Rectangle {
    anchors.fill: parent; radius: 4
    color: Theme.stateColor(root.state)
    Behavior on color { ColorAnimation { duration: Theme.fast } }
  }
}
