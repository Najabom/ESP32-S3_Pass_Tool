/* ============================================================================
 * TagChip.qml —— mono 直角小标签
 *
 * 工业档案风 chip：等宽字体、大写、宽字距、1px 细边框。
 * 用法：TagChip { text: "Sandbox"; accent: true }
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Rectangle {
    id: root

    property string text: ""
    property bool accent: false

    width: chipText.implicitWidth + Theme.u3 * 2
    height: 20
    color: accent ? Theme.aOrange15 : "transparent"
    border.color: accent ? Theme.aOrange35 : Theme.aWhite08
    border.width: 1

    Text {
        id: chipText
        anchors.centerIn: parent
        text: root.text.toUpperCase()
        font.family: Theme.fontMono
        font.pixelSize: 9
        font.letterSpacing: 1.2
        color: root.accent ? Theme.primaryHi : Theme.textBody
    }

    MouseArea {
        cursorShape: Qt.PointingHandCursor
        anchors.fill: parent
        hoverEnabled: true
    }
}
