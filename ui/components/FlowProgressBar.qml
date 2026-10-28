/* ============================================================================
 * FlowProgressBar.qml —— 扁平进度条（工业红橘）
 *
 * 深色轨道 + 橘红实色填充 + 前沿方块光标。
 * progress < 0 表示不确定进度（轨道保持空置，无动画）。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Item {
    id: root

    property real progress: 0          // 0..1；<0 = 不确定
    property string direction: "up"    // "up" / "down"
    property bool indeterminate: progress < 0

    implicitWidth: 400
    implicitHeight: 18

    /* 填充前沿位置（光标左缘绑定此值；progress=0 时从零开始） */
    readonly property real fillWidth: indeterminate ? 0
        : width * Math.max(0, Math.min(1, progress))

    /* ---- 轨道 ---- */
    Rectangle {
        id: track
        anchors.fill: parent
        color: Theme.aWhite06
        border.color: Theme.aWhite08
        border.width: 1
        clip: true

        /* 填充（橘红实色；右缘停在边框内侧） */
        Rectangle {
            id: fill
            visible: !root.indeterminate
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.min(root.fillWidth, track.width - 2)
            color: Theme.primary
            opacity: 0.85
        }

        /* ---- 前沿光标：竖亮线 + 微光晕（贴填充前沿） ---- */
        Rectangle {
            visible: !root.indeterminate
            width: 2
            height: track.height - 4
            x: Math.max(1, Math.min(root.fillWidth, track.width - 3))
            anchors.verticalCenter: parent.verticalCenter
            color: "#FFFFFF"
            opacity: 0.9
            Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            visible: !root.indeterminate
            width: 6
            height: track.height - 2
            x: Math.max(0, Math.min(root.fillWidth - 3, track.width - 7))
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.aOrange50
            opacity: 0.35
            Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
        }
    }

    /* ---- 方向箭头 ---- */
    Text {
        anchors.right: parent.right
        anchors.rightMargin: Theme.u3
        anchors.verticalCenter: parent.verticalCenter
        text: root.direction === "up" ? "↑" : "↓"
        font.family: Theme.fontFamily
        font.pixelSize: 11
        font.bold: true
        color: Theme.textPrimary
        opacity: 0.8
    }
}
