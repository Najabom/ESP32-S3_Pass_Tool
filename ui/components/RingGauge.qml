/* ============================================================================
 * RingGauge.qml —— 环形指标卡（扁平工业红橘）
 *
 * 用法：RingGauge { label: "连接"; valueText: "在线"; progress: 1.0;
 *                  accent: Theme.ok }
 * 弧线平滑动画（ease-out），中心主值 + 底部标签。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

GlassPanel {
    id: root

    /* ---- 对外属性 ---- */
    property string label: ""
    property string valueText: "—"
    property real progress: 0          // 0..1（弧线比例）
    property color accent: Theme.primary
    property string unitText: ""

    implicitWidth: 180
    implicitHeight: 180

    /* ---- 环形弧线 ---- */
    Item {
        id: ring
        width: parent.height - Theme.u6 * 2
        height: width
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Theme.u5

        property real shown: 0
        Behavior on shown {
            NumberAnimation { duration: Theme.durSlow; easing.type: Easing.OutCubic }
        }

        Canvas {
            id: arcCanvas
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d")
                var w = width, h = height
                ctx.clearRect(0, 0, w, h)
                var cx = w / 2, cy = h / 2
                var r = Math.min(w, h) / 2 - 8
                var start = Math.PI * 0.75        // 225° 起
                var sweepMax = Math.PI * 1.5      // 270° 量程

                /* 背景轨道（极淡白细环） */
                ctx.lineWidth = 4
                ctx.lineCap = "butt"
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.08)
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + sweepMax)
                ctx.stroke()

                /* 前景弧（主色实线） */
                var p = Math.max(0.001, Math.min(1, ring.shown))
                ctx.lineWidth = 4
                ctx.strokeStyle = root.accent
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + sweepMax * p)
                ctx.stroke()

                /* 端点小方块光标（数据感） */
                if (p > 0.02 && p < 1) {
                    var ang = start + sweepMax * p
                    var px = cx + r * Math.cos(ang)
                    var py = cy + r * Math.sin(ang)
                    ctx.fillStyle = "#FFFFFF"
                    ctx.fillRect(px - 2.5, py - 2.5, 5, 5)
                }
            }
            onWidthChanged: requestPaint()
        }

        onShownChanged: arcCanvas.requestPaint()
        Component.onCompleted: arcCanvas.requestPaint()

        /* 进度绑定（外部 progress 变化 → 平滑 shown → 重绘） */
        Connections {
            target: root
            function onProgressChanged() {
                ring.shown = root.progress
                arcCanvas.requestPaint()
            }
        }

        /* 中心主值 */
        Text {
            anchors.centerIn: parent
            text: root.valueText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fsDisplay
            font.bold: true
            color: Theme.textPrimary
        }
        Text {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 22
            text: root.unitText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fsMicro
            color: Theme.textBody
        }
    }

    /* ---- 底部标签 ---- */
    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.u4
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fsSmall
        color: Theme.textSecondary
    }

    Component.onCompleted: ring.shown = progress
}
