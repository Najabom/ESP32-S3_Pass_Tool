/* ============================================================================
 * TickerBar.qml —— 顶部状态滚动条
 *
 * 参考站 ticker 语言：左侧实心 primary 标签块 + 无缝循环滚动文本（◆ 分隔）。
 * items: ["文字1", "文字2", ...] 双份内容平移 -50% 实现无缝循环。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Rectangle {
    id: root

    property var items: []

    height: 26
    color: Theme.aWhite03

    /* 左侧实心标签块 */
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: label.implicitWidth + Theme.u4
        color: Theme.primary
        z: 2

        Text {
            id: label
            anchors.centerIn: parent
            text: "LIVE"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMono
            font.bold: true
            font.letterSpacing: 2
            color: "#0A0A0A"
        }
    }

    /* 滚动窗口 */
    Item {
        id: window
        anchors.fill: parent
        clip: true

        Row {
            id: track
            objectName: "tickerTrack"
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            x: 0

            Repeater {
                /* 4 份拼接：总宽须 ≥ 窗口宽 + 一个回绕单位，否则后半程露空白 */
                model: root.items.concat(root.items, root.items, root.items)

                Row {
                    spacing: Theme.u6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        font.letterSpacing: 0.8
                        color: Theme.textBody
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "◆"
                        font.pixelSize: 7
                        color: Theme.primary
                        opacity: 0.85
                    }
                    Rectangle { width: Theme.u6; height: 1; color: "transparent" }
                }
            }
        }

        /* 帧驱动平移：实时按轨道四分之一宽（=一份内容）回绕，打开即滚、无缝循环 */
        Timer {
            interval: 16
            repeat: true
            running: root.visible && track.width > 0 && root.items.length > 0
            onTriggered: {
                var unit = track.width / 4
                if (unit < 10)
                    return   /* 内容尚未布局完成，等待下一帧 */
                track.x -= 0.66
                if (track.x <= -unit)
                    track.x += unit
            }
        }
    }
}
