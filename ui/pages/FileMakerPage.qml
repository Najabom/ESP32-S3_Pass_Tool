/* ============================================================================
 * FileMakerPage.qml —— 文件制作（ffmpeg 素材转换，辅助编辑编码文件）
 *
 * 布局：源文件/输出位置 → 输出设置（带标签：类型/fps/质量/裁剪/起止）
 *      → 转换与上传。裁剪通过 CropDialog 弹窗（3:4 框拖拽 + 尺寸滑块）。
 * 数据源：backend.makeFile/makeDone/probeSource/sourceProbed/uploadFile
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs
import Theme 1.0
import "../components"

Item {
    id: root

    property string srcPath: ""
    property string outDir: ""
    property string outType: "loop.mjpeg"
    property string lastOut: ""          // 最近一次生成成功的输出路径
    property bool busy: false            // 转换或上传进行中
    property string estText: ""          // 预估大小显示（空不显示）
    property int srcW: 0
    property int srcH: 0
    property int srcDur: 0
    property bool ffOk: false
    property var cropRect: null          // [cx, cy, cw, ch, rot] 源像素（QML 弹窗结果）
    property string lastProbeSrc: ""     // 上次探测的源（变化时重置 cropRect）

    function fmtBytes(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(2) + " MB"
        if (b >= 1024) return (b / 1024).toFixed(1) + " KB"
        return Math.round(b) + " B"
    }

    function fmtSec(s) {
        var t = Math.max(0, Math.round(s))
        var m = Math.floor(t / 60)
        var ss = t % 60
        return m + ":" + (ss < 10 ? "0" : "") + ss
    }

    /* 设置档变化 → 稍候（防滑块连续触发）发起预估计算 */
    function armEst() {
        if (root.srcPath === "" || root.outType === "portrait.bin") return
        root.estText = "估算中…"
        estTimer.restart()
    }
    Timer {
        id: estTimer
        interval: 900
        repeat: false
        onTriggered: {
            if (root.srcPath === "" || root.outType === "portrait.bin") return
            var se = startSlider.value + "," + endSlider.value
            var cx = root.cropRect ? root.cropRect[0] : "0"
            var cy = root.cropRect ? root.cropRect[1] : "0"
            var cw = root.cropRect ? root.cropRect[2] : "0"
            var ch = root.cropRect ? root.cropRect[3] : "0"
            var rot = root.cropRect ? root.cropRect[4] : 0
            backend.estimateMake(root.srcPath, root.outType,
                                 fpsCombo.currentIndex >= 0 ? fpsCombo.model[fpsCombo.currentIndex] : "10",
                                 qualCombo.currentIndex >= 0 ? qualCombo.model[qualCombo.currentIndex] : "3",
                                 "center", se, cx, cy, cw, ch, rot)
        }
    }

    /* ---- 源文件 / 输出位置 ---- */
    GlassPanel {
        id: srcCard
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 96

        Column {
            anchors.fill: parent
            anchors.margins: Theme.u4
            spacing: Theme.u2

            Row {
                width: parent.width
                spacing: Theme.u3

                NeonButton {
                    id: srcBtn
                    width: (parent.width - Theme.u3) / 2
                    height: 32
                    text: "选择源文件"
                    iconSource: "../assets/ic_folder.svg"
                    iconSize: 15
                    onClicked: srcDialog.open()
                }

                NeonButton {
                    id: outBtn
                    width: (parent.width - Theme.u3) / 2
                    height: 32
                    text: "输出位置"
                    iconSource: "../assets/ic_folder_open.svg"
                    iconSize: 15
                    onClicked: outDirDialog.open()
                }
            }

            Text {
                width: parent.width
                text: root.srcPath !== "" ? "源: " + root.srcPath : "源: 未选择（视频 / GIF / 图片）"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsMicro
                color: root.srcPath !== "" ? Theme.textSecondary : Theme.textBody
                elide: Text.ElideMiddle
            }

            Text {
                width: parent.width
                text: root.outDir !== "" ? "输出: " + root.outDir : "输出: 源文件同目录"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsMicro
                color: root.outDir !== "" ? Theme.textSecondary : Theme.textBody
                elide: Text.ElideMiddle
            }
        }

        FileDialog {
            id: srcDialog
            title: "选择源文件"
            fileMode: FileDialog.OpenFile
            onAccepted: {
                root.srcPath = srcDialog.selectedFile.toString().replace("file:///", "")
                root.cropRect = null
                backend.probeSource(root.srcPath)
            }
        }

        FolderDialog {
            id: outDirDialog
            title: "选择输出目录"
            onAccepted: {
                root.outDir = outDirDialog.selectedFolder.toString().replace("file:///", "")
                root.outDir = root.outDir.replace(/\//g, "\\")
            }
        }
    }

    /* ---- 输出设置 ---- */
    GlassPanel {
        id: outCard
        z: 10
        anchors.top: srcCard.bottom
        anchors.topMargin: Theme.u3
        anchors.left: parent.left
        anchors.right: parent.right
        height: 196

        Column {
            anchors.fill: parent
            anchors.margins: Theme.u4
            spacing: Theme.u2

            Row {
                width: parent.width
                spacing: Theme.u3
                Text { width: (parent.width - Theme.u3 * 2) / 3; text: "输出文件"; font.family: Theme.fontFamily; font.pixelSize: Theme.fsMicro; color: Theme.textBody }
                Text { width: (parent.width - Theme.u3 * 2) / 3; text: "帧率 fps"; visible: root.outType !== "portrait.bin"; font.family: Theme.fontFamily; font.pixelSize: Theme.fsMicro; color: Theme.textBody }
                Text { width: (parent.width - Theme.u3 * 2) / 3; text: "质量 q"; visible: root.outType !== "portrait.bin"; font.family: Theme.fontFamily; font.pixelSize: Theme.fsMicro; color: Theme.textBody }
            }

            Row {
                width: parent.width
                spacing: Theme.u3

                ComboGlass {
                    id: typeCombo
                    width: (parent.width - Theme.u3 * 2) / 3
                    height: 32
                    model: ["loop.mjpeg", "intro.mjpeg", "portrait.bin"]
                    placeholder: "输出文件"
                    currentIndex: 0
                    onPicked: function(index, value) {
                        root.outType = value
                        root.armEst()
                    }
                }

                ComboGlass {
                    id: fpsCombo
                    width: (parent.width - Theme.u3 * 2) / 3
                    height: 32
                    model: ["8", "10", "12", "15", "20", "24", "30"]
                    placeholder: "帧率"
                    currentIndex: 1
                    visible: root.outType !== "portrait.bin"
                    onPicked: root.armEst()
                }

                ComboGlass {
                    id: qualCombo
                    width: (parent.width - Theme.u3 * 2) / 3
                    height: 32
                    model: ["2", "3", "4", "5", "6", "8", "10", "12"]
                    placeholder: "质量"
                    currentIndex: 1
                    visible: root.outType !== "portrait.bin"
                    onPicked: root.armEst()
                }
            }

            Row {
                width: parent.width
                spacing: Theme.u3
                visible: root.outType !== "portrait.bin"

                Text { width: (parent.width - Theme.u3 * 2) / 3; text: "画面裁剪"; font.family: Theme.fontFamily; font.pixelSize: Theme.fsMicro; color: Theme.textBody }
                Text { width: (parent.width - Theme.u3 * 2) / 3; text: "开始时间"; font.family: Theme.fontFamily; font.pixelSize: Theme.fsMicro; color: Theme.textBody }
                Text { width: (parent.width - Theme.u3 * 2) / 3; text: "结束时间"; font.family: Theme.fontFamily; font.pixelSize: Theme.fsMicro; color: Theme.textBody }
            }

            Row {
                width: parent.width
                spacing: Theme.u3
                visible: root.outType !== "portrait.bin"

                NeonButton {
                    id: cropBtn
                    width: (parent.width - Theme.u3 * 2) / 3
                    height: 32
                    text: root.cropRect
                          ? "裁剪 " + root.cropRect[2] + "×" + root.cropRect[3]
                          : "裁剪…"
                    iconSource: root.cropRect ? "../assets/ic_crop_w.svg" : "../assets/ic_crop.svg"
                    iconSize: 15
                    active: root.cropRect !== null
                    enabled: root.srcPath !== "" && root.srcW > 0
                    onClicked: cropDialog.openDialog()
                }

                Column {
                    width: (parent.width - Theme.u3 * 2) / 3
                    height: 32
                    spacing: 0

                    Slider {
                        id: startSlider
                        width: parent.width
                        height: 20
                        from: 0
                        to: Math.max(1, root.srcDur)
                        value: 0
                        stepSize: 1
                        onValueChanged: {
                            if (root.srcDur > 0 && endSlider.value <= value)
                                endSlider.value = value + 1
                            root.armEst()
                        }
                        background: Rectangle {
                            x: startSlider.leftPadding
                            y: startSlider.topPadding + startSlider.availableHeight / 2 - 2
                            width: startSlider.availableWidth
                            height: 4
                            color: Theme.aWhite06
                            Rectangle {
                                width: startSlider.visualPosition * parent.width
                                height: 4
                                color: Theme.primary
                            }
                        }
                        handle: Rectangle {
                            x: startSlider.leftPadding
                               + startSlider.visualPosition * (startSlider.availableWidth - width)
                            y: startSlider.topPadding + startSlider.availableHeight / 2 - height / 2
                            width: 10
                            height: 10
                            color: Theme.primaryHi
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        text: root.srcDur > 0 ? root.fmtSec(startSlider.value) : "—"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textSecondary
                    }
                }

                Column {
                    width: (parent.width - Theme.u3 * 2) / 3
                    height: 32
                    spacing: 0

                    Slider {
                        id: endSlider
                        width: parent.width
                        height: 20
                        from: 0
                        to: Math.max(1, root.srcDur)
                        value: Math.max(1, root.srcDur)
                        stepSize: 1
                        onValueChanged: {
                            if (root.srcDur > 0 && startSlider.value >= value)
                                startSlider.value = value - 1
                            root.armEst()
                        }
                        background: Rectangle {
                            x: endSlider.leftPadding
                            y: endSlider.topPadding + endSlider.availableHeight / 2 - 2
                            width: endSlider.availableWidth
                            height: 4
                            color: Theme.aWhite06
                            Rectangle {
                                width: endSlider.visualPosition * parent.width
                                height: 4
                                color: Theme.primary
                            }
                        }
                        handle: Rectangle {
                            x: endSlider.leftPadding
                               + endSlider.visualPosition * (endSlider.availableWidth - width)
                            y: endSlider.topPadding + endSlider.availableHeight / 2 - height / 2
                            width: 10
                            height: 10
                            color: Theme.primaryHi
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        text: root.srcDur > 0 ? root.fmtSec(endSlider.value) : "—"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textSecondary
                    }
                }
            }

            Text {
                width: parent.width
                text: root.outType === "portrait.bin"
                      ? "头像素材：自动缩放 64x64 小端 RGB565（8 KB），不含裁剪/时间参数"
                      : (root.srcW > 0
                         ? "源 " + root.srcW + "×" + root.srcH + (root.ffOk ? "" : "  · 未找到 ffmpeg")
                         : "选择源文件后自动探测尺寸")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsMicro
                color: root.ffOk || root.outType === "portrait.bin" ? Theme.textBody : Theme.red
            }
        }
    }

    /* ---- 转换与上传 ---- */
    GlassPanel {
        id: runCard
        anchors.top: outCard.bottom
        anchors.topMargin: Theme.u3
        anchors.left: parent.left
        anchors.right: parent.right
        height: 64

        Column {
            anchors.fill: parent
            anchors.margins: Theme.u4
            spacing: Theme.u3

            Row {
                width: parent.width
                spacing: Theme.u3

                NeonButton {
                    id: makeBtn
                    width: 120
                    height: 36
                    text: "生成"
                    iconSource: "../assets/ic_tools_w.svg"
                    active: true
                    enabled: !root.busy && root.srcPath !== ""
                    onClicked: {
                        var se = startSlider.value + "," + endSlider.value
                        var cx = root.cropRect ? root.cropRect[0] : "0"
                        var cy = root.cropRect ? root.cropRect[1] : "0"
                        var cw = root.cropRect ? root.cropRect[2] : "0"
                        var ch = root.cropRect ? root.cropRect[3] : "0"
                        var rot = root.cropRect ? root.cropRect[4] : 0
                        root.estText = "预估中…"
                        backend.makeFile(root.srcPath, root.outType,
                                         fpsCombo.currentIndex >= 0 ? fpsCombo.model[fpsCombo.currentIndex] : "10",
                                         qualCombo.currentIndex >= 0 ? qualCombo.model[qualCombo.currentIndex] : "3",
                                         "center", se, cx, cy, cw, ch, root.outDir, rot)
                        root.busy = true
                    }
                }

                Column {
                    width: parent.width - makeBtn.width - Theme.u3
                    height: 40
                    spacing: 2

                    Text {
                        width: parent.width
                        text: root.busy ? "正在转换，请稍候…"
                             : (root.lastOut !== "" ? "输出: " + root.lastOut : "输出到所选目录（默认源目录）")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsSmall
                        color: root.busy ? Theme.warn : Theme.textBody
                        elide: Text.ElideMiddle
                    }

                    Text {
                        width: parent.width
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: root.estText.indexOf("超过") >= 0 ? Theme.red : Theme.textBody
                        text: root.estText
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }

    /* ---- 裁剪弹窗 ---- */
    CropDialog {
        id: cropDialog
        anchors.centerIn: parent
        source: root.srcPath
        srcWidth: root.srcW
        srcHeight: root.srcH
        cropW: root.srcW > 0
               ? Math.min(240, Math.max(1, Math.min(root.srcW, Math.floor(root.srcH * 3 / 4))))
               : 240

        onApplied: {
            root.cropRect = [cx, cy, cw, ch, rot]
            backend.toast("已设置裁剪 " + cw + "×" + ch
                          + (rot % 2 === 1 ? "（已旋转 90°）" : ""))
            root.armEst()
        }
    }

    Connections {
        target: backend
        function onSourceProbed(w, h, ff, dur) {
            if (root.lastProbeSrc !== root.srcPath) {
                root.lastProbeSrc = root.srcPath
                root.cropRect = null   // 换源后旧裁剪框不适用于新源，重置
            }
            root.srcW = w
            root.srcH = h
            root.srcDur = dur
            root.ffOk = ff
            startSlider.value = 0
            endSlider.value = Math.max(1, dur)
            if (w > 0 && !ff && root.outType !== "portrait.bin")
                backend.toast("未找到 ffmpeg，无法生成视频素材")
            root.armEst()
        }
        function onMakeDone(ok, msg, outPath, size) {
            root.busy = false
            if (ok) {
                root.lastOut = outPath + "（" + root.fmtBytes(size) + "）"
                root.estText = size > 3 * 1024 * 1024 ? "(超 3MB 上限，设备端可能存不下)" : ""
                backend.toast("素材制作完成")
            } else {
                root.lastOut = ""
                backend.toast("素材制作失败：" + msg)
            }
        }
        function onMakeEstimate(bytes) {
            root.estText = bytes > 0
                ? "预估大小 " + root.fmtBytes(bytes) + " / 上限 3MB"
                  + (bytes > 3 * 1024 * 1024 ? "（将拒绝生成，可降低质量/帧率）" : "")
                : "无法预估（正常生成）"
        }
        function onUploadProgress(p) { root.busy = true }
        function onDownloadProgress(p) { root.busy = true }
        function onTransferDone(ok, msg) { root.busy = false }
    }
}
