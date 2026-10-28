/* ============================================================================
 * BackgroundFX.qml —— 全局背景（网格 + 光斑呼吸 + 鼠标视差）
 *
 * 参考站语言：32px 细网格线 + 两个角落光斑缓慢呼吸 + 指针视差微偏移。
 * 网格用 Canvas 一次绘制后 grabImage，由两个 Image 无缝循环平移（低成本漂移）。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Rectangle {
    id: root

    color: Theme.bgDeep

    /* 渐变底：黑 → 炭灰 */
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0A0A0A" }
            GradientStop { position: 1.0; color: "#1A1A1A" }
        }
    }

    /* ---- 角落光斑 ×2（橘红径向 SVG，呼吸） ---- */
    Image {
        width: parent.width * 0.55
        height: width
        x: -parent.width * 0.12
        y: -parent.height * 0.25
        source: "../assets/glow_orange.svg"
        fillMode: Image.Stretch
        opacity: 0.35

        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { to: 1.08; duration: 7000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0; duration: 7000; easing.type: Easing.InOutSine }
        }
    }
    Image {
        width: parent.width * 0.45
        height: width
        x: parent.width * 0.72
        y: parent.height * 0.68
        source: "../assets/glow_orange.svg"
        fillMode: Image.Stretch
        opacity: 0.22

        SequentialAnimation on scale {
            loops: Animation.Infinite
            NumberAnimation { to: 1.0; duration: 9000; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.08; duration: 9000; easing.type: Easing.InOutSine }
        }
    }

    /* ---- 网格层（视差容器） ---- */
    Item {
        id: gridLayer
        anchors.fill: parent
        anchors.margins: -40
        Behavior on x { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }

        Canvas {
            id: fullGrid
            anchors.fill: parent
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                ctx.strokeStyle = "rgba(255,255,255,0.05)";
                ctx.lineWidth = 1;
                for (var x = 0.5; x < width; x += 32) {
                    ctx.beginPath();
                    ctx.moveTo(x, 0);
                    ctx.lineTo(x, height);
                    ctx.stroke();
                }
                for (var y = 0.5; y < height; y += 32) {
                    ctx.beginPath();
                    ctx.moveTo(0, y);
                    ctx.lineTo(width, y);
                    ctx.stroke();
                }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }
    }

    /* 对外接口：指针归一化坐标 (-0.5..0.5)，由 main.qml 喂入；Behavior 提供平滑 */
    function setPointer(nx, ny) {
        gridLayer.x = nx * 8;
        gridLayer.y = ny * 6;
    }
}
