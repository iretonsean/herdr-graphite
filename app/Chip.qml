import QtQuick

// The small type label ("Agent · Opus").
Rectangle {
  property alias text: label.text
  property color fill: Theme.surface3
  implicitHeight: 18
  implicitWidth: label.implicitWidth + 14
  height: implicitHeight
  width: implicitWidth
  radius: 5
  color: fill
  Text {
    id: label
    anchors.centerIn: parent
    color: Theme.textSoft
    font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
  }
}
