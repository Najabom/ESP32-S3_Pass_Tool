/* ============================================================================
 * FlowChart.qml —— 传输速率历史曲线（橘红折线 + 半透明填充 + 极淡网格）
 *
 * 用法：FlowChart { }
 * 数据：push(value) 追加一个点（KB/s），内部保留最近 90 点，Canvas 重绘。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

GlassPanel {
    id: root

    property int capacity: 90
    property real maxValue: 1            // 自适应纵轴
    property var points: []              // [KB/s, ...]
    property string title: "传输速率"

    /* ---- 标题 + 当前值 ---- */
    Row {
        anchors.top: parent.top
        anchors.topMargin: Theme.u4
        anchors.left: parent.left
        anchors.leftMargin: Theme.u5
        spacing: Theme.u3
        Rectangle { width: 3; height: 12; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: root.title + " · RATE"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fsSmall
            color: Theme.textSecondary
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    Text {
        id: curValue
        anchors.top: parent.top
        anchors.topMargin: Theme.u4
        anchors.right: parent.right
        anchors.rightMargin: Theme.u5
        text: root.points.length ? root.points[root.points.length - 1].toFixed(1) + " KB/s" : "— KB/s"
        font.family: Theme.fontMono
        font.pixelSize: Theme.fsSmall
        font.bold: true
        color: Theme.primary
    }

    /* ---- 曲线画布 ---- */
    Canvas {
        id: chartCanvas
        anchors.fill: parent
        anchors.topMargin: Theme.u6 + Theme.u1
        anchors.bottomMargin: Theme.u4
        anchors.leftMargin: Theme.u5
        anchors.rightMargin: Theme.u5

        onPaint: {
            var ctx = getContext("2d")
            var w = width, h = height
            ctx.clearRect(0, 0, w, h)

            /* 水平参考线（极淡白） */
            ctx.strokeStyle = "rgba(255, 255, 255, 0.05)"
            ctx.lineWidth = 1
            ctx.beginPath()
            for (var i = 1; i <= 3; i++) {
                var gy = h * i / 4
                ctx.moveTo(0, gy)
                ctx.lineTo(w, gy)
            }
            ctx.stroke()

            var pts = root.points
            if (pts.length < 2)
                return

            var mx = Math.max(root.maxValue, 1)
            var stepX = w / (root.capacity - 1)
            var x0 = w - (pts.length - 1) * stepX   // 右对齐（新点在右侧）

            /* 折线路径 */
            ctx.beginPath()
            for (var j = 0; j < pts.length; j++) {
                var px = x0 + j * stepX
                var py = h - Math.min(1, pts[j] / mx) * (h - 8) - 4
                if (j === 0) ctx.moveTo(px, py)
                else ctx.lineTo(px, py)
            }

            /* 主色实线描边 */
            ctx.lineWidth = 1.5
            ctx.lineJoin = "round"
            ctx.strokeStyle = Theme.primary
            ctx.stroke()

            /* 半透明填充 */
            var lastPx = x0 + (pts.length - 1) * stepX
            var lastPy = h - Math.min(1, pts[pts.length - 1] / mx) * (h - 8) - 4
            ctx.lineTo(lastPx, h)
            ctx.lineTo(x0, h)
            ctx.closePath()
            var fill = ctx.createLinearGradient(0, 0, 0, h)
            fill.addColorStop(0, Qt.rgba(0.91, 0.365, 0.016, 0.16))
            fill.addColorStop(1, Qt.rgba(0.91, 0.365, 0.016, 0))
            ctx.fillStyle = fill
            ctx.fill()
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }

    /* ---- 数据接口 ---- */
    function push(value) {
        var pts = root.points.slice()
        pts.push(value)
        if (pts.length > root.capacity)
            pts = pts.slice(pts.length - root.capacity)
        root.points = pts
        if (value > root.maxValue)
            root.maxValue = value * 1.15
        chartCanvas.requestPaint()
    }

    function reset() {
        root.points = []
        root.maxValue = 1
        chartCanvas.requestPaint()
    }
}
