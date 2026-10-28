/* ============================================================================
 * CropDialog.qml —— 裁剪弹窗（单数据流架构）
 *
 * 设计原则（防抖动铁律）：
 *   1. 交互事件只写三个源属性 cropW / cropX / cropY，绝不直接写 cropRect 几何；
 *   2. 裁剪框几何（x/y/width/height）全部由源属性【声明式绑定】派生，
 *      不存在任何命令式几何写入路径（无 refreshRect）；
 *   3. 所有鼠标坐标经 mapToItem(box) 换算到静止容器坐标系，
 *      与会移动的裁剪框/手柄完全解耦（手柄挂在框上，框动则其局部
 *      坐标系跟着动，相对读数被污染 => 振荡）。
 *
 * 固定 3:4 目标比例；限制：裁剪框宽 [min(240,maxCW), maxCW] 源像素。
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Controls 2.15
import Theme 1.0

Item {
    id: root

    property string source: ""        // 源文件路径（图片/GIF 显示预览，视频抽帧）
    property int srcWidth: 0
    property int srcHeight: 0
    property string videoFrame: ""    // 视频抽帧预览路径（backend.extractFrame 结果）
    property int rotation90: 0        // 旋转次数（0-3，顺时针 90° 步进）

    /* ── 源属性（唯一可写状态）────────────────────────── */
    property int cropW: 240           // 裁剪宽（源像素，高恒 4/3）
    property real cropX: 0.5          // 归一化 0..1（框左上角）
    property real cropY: 0.5

    signal applied(int cx, int cy, int cw, int ch, int rot)
    signal cancelled()

    function isVideo(p) {
        var e = String(p).toLowerCase().split(".").pop()
        return ["mp4", "avi", "mkv", "webm", "mov", "flv", "wmv", "ts"].indexOf(e) >= 0
    }

    /* ── 派生属性（全部 readonly 绑定，自动响应源变化）──── */
    readonly property int dW: (rotation90 % 2 === 1) ? srcHeight : srcWidth
    readonly property int dH: (rotation90 % 2 === 1) ? srcWidth : srcHeight
    readonly property int maxCW: Math.max(240, Math.min(dW, Math.floor(dH * 3 / 4)))
    readonly property int minCW: Math.min(240, maxCW)

    /* 未旋转 fit（图片布局尺寸） */
    readonly property real gwEff: srcWidth > 0 ? srcWidth : 320
    readonly property real ghEff: srcHeight > 0 ? srcHeight : 427
    readonly property real fitDs: box.width > 40 && box.height > 40
        ? Math.min(box.width / gwEff, box.height / ghEff) : 0.5
    readonly property real fitFW: gwEff * fitDs
    readonly property real fitFH: ghEff * fitDs

    /* 旋转后视觉占位（裁剪框数学统一坐标系） */
    readonly property real visW: (rotation90 % 2 === 1) ? fitFH : fitFW
    readonly property real visH: (rotation90 % 2 === 1) ? fitFW : fitFH
    readonly property real orgX: Math.max(0, (box.width - visW) / 2)
    readonly property real orgY: Math.max(0, (box.height - visH) / 2)

    /* 源像素宽 -> 显示像素（含 3:4 双向钳制链） */
    function dispPix(cwSrc) {
        if (visW <= 1 || visH <= 1) return { rw: 1, rh: 1 }
        var rw = Math.max(1, Math.min(cwSrc * fitDs, visW))
        var rh = Math.max(1, Math.min(rw * 4 / 3, visH))
        rw = Math.max(1, Math.min(rh * 3 / 4, visW))
        return { rw: rw, rh: rw * 4 / 3 }
    }
    readonly property var dispCur: dispPix(cropW)

    function clampCropW(v) {
        return Math.max(minCW, Math.min(maxCW, v))
    }

    function openDialog() {
        root.cropW = clampCropW(root.cropW)
        root.videoFrame = ""
        if (root.srcWidth > 0 && root.isVideo(root.source))
            root.videoFrame = backend.extractFrame(root.source)
        popup.open()
    }

    /* 源/尺寸变化自动重建帧：换源后 probe 完成（srcWidth 变化）时
     * 若弹窗仍开着且是视频源，立即重新抽帧覆盖旧预览 */
    function maybeRefreshFrame() {
        if (popup.opened && root.srcWidth > 0 && root.isVideo(root.source))
            root.videoFrame = backend.extractFrame(root.source)
    }
    onSourceChanged: maybeRefreshFrame()
    onSrcWidthChanged: maybeRefreshFrame()

    Popup {
        id: popup
        parent: Overlay.overlay
        width: 500
        height: 550
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape
        onClosed: root.cancelled()

        background: Rectangle {
            color: "#FA141414"
            border.color: Theme.primary
            border.width: 1
        }

        contentItem: Column {
            anchors.fill: parent
            anchors.margins: Theme.u5
            spacing: Theme.u3

            /* 标题 */
            Item {
                width: parent.width
                height: 22

                Rectangle {
                    width: 34
                    height: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.primary
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 40
                    anchors.verticalCenter: parent.verticalCenter
                    text: "裁剪画面 · CROP"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textSecondary
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 96
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.dW > 0
                          ? (root.dW + " × " + root.dH
                             + (root.rotation90 % 2 === 1 ? " ↻" : "")) : "尺寸未知"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textBody
                }

                /* 旋转 90° 按钮组（只写源属性） */
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.u2

                    NeonButton {
                        width: 42
                        height: 20
                        text: "⟲"
                        fontSize: 13
                        onClicked: {
                            root.rotation90 = (root.rotation90 + 3) % 4
                            root.cropW = root.clampCropW(root.cropW)
                        }
                    }
                    NeonButton {
                        width: 42
                        height: 20
                        text: "⟳"
                        fontSize: 13
                        onClicked: {
                            root.rotation90 = (root.rotation90 + 1) % 4
                            root.cropW = root.clampCropW(root.cropW)
                        }
                    }
                }
            }

            /* 尺寸标注（裁剪工作区上方居中） */
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.srcWidth > 0
                      ? Math.round(root.cropW) + " × " + Math.round(root.cropW * 4 / 3) + " px"
                      : "—"
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsSmall
                color: Theme.primaryHi
            }

            /* 图像区 */
            Rectangle {
                id: box
                width: parent.width
                height: 340
                color: Theme.aWhite03
                border.color: Theme.aWhite08
                border.width: 1
                clip: true

                /* 源图（图片/GIF/视频抽帧预览） */
                Image {
                    id: preview
                    anchors.centerIn: parent
                    visible: source !== ""
                    source: root.srcWidth > 0
                            ? ((root.isVideo(root.source) ? root.videoFrame : root.source)
                               ? Qt.url(root.isVideo(root.source) ? root.videoFrame : root.source) : "")
                            : ""
                    fillMode: Image.PreserveAspectFit
                    width: root.fitFW
                    height: root.fitFH
                    rotation: root.rotation90 * 90
                    Behavior on rotation { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                }

                /* 视频/未知占位 */
                Column {
                    anchors.centerIn: parent
                    visible: preview.source === ""
                    spacing: Theme.u2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "无预览"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsBody
                        color: Theme.textBody
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "拖动裁剪框（3:4），按源比例显示"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                    }
                }

                /* 裁剪框外遮罩（上下左右四块，全部绑定派生） */
                Rectangle {
                    color: "#A6000000"
                    x: 0; y: 0
                    width: Math.max(0, cropRect.x)
                    height: box.height
                }
                Rectangle {
                    color: "#A6000000"
                    x: cropRect.x + cropRect.width; y: 0
                    width: Math.max(0, box.width - cropRect.x - cropRect.width)
                    height: box.height
                }
                Rectangle {
                    color: "#A6000000"
                    x: cropRect.x; y: 0
                    width: cropRect.width
                    height: Math.max(0, cropRect.y)
                }
                Rectangle {
                    color: "#A6000000"
                    x: cropRect.x; y: cropRect.y + cropRect.height
                    width: cropRect.width
                    height: Math.max(0, box.height - cropRect.y - cropRect.height)
                }

                /* 裁剪框（几何纯绑定：唯一写入者是下面的源属性绑定链） */
                Rectangle {
                    id: cropRect
                    width: root.dispCur.rw
                    height: root.dispCur.rh
                    x: root.orgX + root.cropX * Math.max(0, root.visW - width)
                    y: root.orgY + root.cropY * Math.max(0, root.visH - height)
                    border.color: Theme.primary
                    border.width: 2
                    color: "transparent"

                    /* 移动：box 绝对坐标 + 按下快照，只写 cropX/cropY */
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        cursorShape: Qt.SizeAllCursor
                        property real startX: 0
                        property real startY: 0
                        property real startCX: 0
                        property real startCY: 0

                        onPressed: function(mouse) {
                            var b = mapToItem(box, mouse.x, mouse.y)
                            startX = b.x; startY = b.y
                            startCX = root.cropX; startCY = root.cropY
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed) return
                            var b = mapToItem(box, mouse.x, mouse.y)
                            var spanX = Math.max(1, root.visW - cropRect.width)
                            var spanY = Math.max(1, root.visH - cropRect.height)
                            root.cropX = Math.max(0, Math.min(1,
                                startCX + (b.x - startX) / spanX))
                            root.cropY = Math.max(0, Math.min(1,
                                startCY + (b.y - startY) / spanY))
                        }
                    }

                    /* 右下角调大小：box 绝对坐标增量 + 右下角锚定反推，只写 cropW/cropX/cropY */
                    MouseArea {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: -8
                        width: 18
                        height: 18
                        cursorShape: Qt.SizeFDiagCursor

                        property real startX: 0
                        property real startY: 0
                        property int startCW: 240
                        property real anchorRX: 0     // 按下时框右缘（box 坐标）
                        property real anchorBY: 0     // 按下时框下缘（box 坐标）

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.primaryHi
                            border.color: Theme.primary
                            border.width: 1
                            radius: 2
                        }

                        onPressed: function(mouse) {
                            var b = mapToItem(box, mouse.x, mouse.y)
                            startX = b.x; startY = b.y
                            startCW = root.cropW
                            anchorRX = cropRect.x + cropRect.width
                            anchorBY = cropRect.y + cropRect.height
                        }
                        onPositionChanged: function(mouse) {
                            if (!pressed || root.fitDs <= 0) return
                            var b = mapToItem(box, mouse.x, mouse.y)
                            var dx = (b.x - startX) / root.fitDs
                            var dy = (b.y - startY) / root.fitDs
                            var cw = root.clampCropW(
                                Math.round(startCW + (dx + dy) / 2))
                            var np = root.dispPix(cw)
                            /* 右下角锚定：由新尺寸反推左上角，再归一化写回 */
                            var nx = Math.max(root.orgX, anchorRX - np.rw)
                            var ny = Math.max(root.orgY, anchorBY - np.rh)
                            if (nx + np.rw > box.width)  nx = Math.max(root.orgX, box.width - np.rw)
                            if (ny + np.rh > box.height) ny = Math.max(root.orgY, box.height - np.rh)
                            root.cropW = cw
                            root.cropX = Math.max(0, Math.min(1,
                                (nx - root.orgX) / Math.max(1, root.visW - np.rw)))
                            root.cropY = Math.max(0, Math.min(1,
                                (ny - root.orgY) / Math.max(1, root.visH - np.rh)))
                        }
                    }
                }
            }

            /* 底部按钮：重置在左侧，取消和确定在右侧 */
            Row {
                width: parent.width
                spacing: Theme.u3

                NeonButton {
                    width: 100
                    height: 34
                    text: "重置居中"
                    onClicked: {
                        root.cropX = 0.5
                        root.cropY = 0.5
                        root.cropW = root.maxCW
                    }
                }

                Item { width: parent.width - 100 - 90 - 90 - Theme.u3 * 3; height: 1 }

                NeonButton {
                    width: 90
                    height: 34
                    text: "取消"
                    onClicked: popup.close()
                }

                NeonButton {
                    width: 90
                    height: 34
                    text: "确定"
                    active: true
                    onClicked: {
                        var cx = root.cropX, cy = root.cropY
                        var cw = Math.round(root.cropW)
                        var ch = Math.round(root.cropW * 4 / 3)
                        popup.close()
                        root.applied(Math.round(cx * Math.max(0, root.dW - cw)),
                                     Math.round(cy * Math.max(0, root.dH - ch)),
                                     cw, ch, root.rotation90)
                    }
                }
            }

            /* 提示（弹窗最底端） */
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "拖动方框移动 · 拖右下角调整大小 · 裁出画面缩放至 240 × 320"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsMicro
                color: Theme.textBody
            }
        }
    }
}
