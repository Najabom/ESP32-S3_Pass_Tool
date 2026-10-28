/* ============================================================================
 * ScanlineOverlay.qml —— CRT 扫描线纹理覆盖层
 *
 * 参考站缩略图语言：3px 周期横向细纹（白 alpha），覆盖在卡片图像区上。
 * 用法：在父级内 anchors.fill，置于内容之上、交互层之下。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Item {
    id: root

    property real lineOpacity: 0.5

    Canvas {
        id: scan
        anchors.fill: parent
        opacity: root.lineOpacity
        onPaint: {
            var ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.strokeStyle = "rgba(255,255,255,0.06)";
            ctx.lineWidth = 1;
            for (var y = 3; y < height; y += 4) {
                ctx.beginPath();
                ctx.moveTo(0, y + 0.5);
                ctx.lineTo(width, y + 0.5);
                ctx.stroke();
            }
        }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
}
