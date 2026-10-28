/* ============================================================================
 * TransferPage.qml —— 文件传输中心（真实数据）
 *
 * 布局：源/目标设备卡（本地文件 → 设备角色目录）+ 流动进度条
 *      + 速率/大小/剩余时间统计 + 上传/下载控制组。
 * 数据源：backend.uploadFile/downloadFile/uploadProgress/transferStats
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Dialogs
import Theme 1.0
import "../components"

Item {
    id: root

    /* 素材传输提示：仅本次运行首次进入传输页弹一条长通知（推荐直写 SD，蓝牙仅备用） */
    property bool sdTipShown: false
    onVisibleChanged: if (visible && !root.sdTipShown) {
        root.sdTipShown = true
        backend.toastFor("素材推荐直接写入 SD 卡（取出插读卡器放入角色目录）；蓝牙传输仅作备用，适合零星小文件", 10000)
    }

    /* ---- 状态 ---- */
    property string localPath: ""
    property string localDir: ""        // 本地目录（配合目标"全部"整目录上传）
    property var roleNames: []
    property int targetRoleIdx: -1
    property string targetFile: "all"   // 默认与 fileCombo 第 0 项「全部」一致（曾遗留 "loop.mjpeg" 致单文件下载）
    property real progress: -1
    property string direction: "up"
    property real speedKBs: 0
    property real doneBytes: 0
    property bool delArmed: false   // 删除角色双态确认
    property real totalBytes: 0
    property bool busy: false       // 上传/下载进行中
    property int stagedCount: 0     // 新建角色素材暂存数（>0 显示开始上传）
    property var stagedFiles: []
    property var roleFiles: []        // 角色素材清单 [(名称, 大小|None)]
    property string roleFilesFor: ""  // 清单所属角色名
    property int tfIdx: 0             // 当前传输文件序号（1 起）
    property int tfTotal: 0           // 本次传输文件总数
    property string tfLabel: ""       // 当前传输文件名
    /* ---- 固件更新（有线烧录）状态 ---- */
    property var comPorts: []            // 可用串口（scanComPorts）
    property string fwBinPath: ""        // 已选固件文件（merged bin）
    property string fwLog: ""            // 烧录日志末行
    property int fwPct: -1               // esptool 进度 0..100
    property bool fwBusy: false          // 烧录进行中
    property bool fwOk: false            // 上次烧录结果
    property bool fwKeep: true           // 烧录模式：保留设备设置（只写应用分区）

    function fmtBytes(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(2) + " MB"
        if (b >= 1024) return (b / 1024).toFixed(1) + " KB"
        return Math.round(b) + " B"
    }
    /* 素材浮窗定位：显示于素材数文字正下方，右缘与文字对齐，靠边时收进屏内 */
    function posRoleTip() {
        var r = roleFilesLine.mapToItem(filesTip.parent, 0, 0)
        filesTip.height = 16 + 15 * Math.min(root.roleFiles.length, 10)
                         + (root.roleFiles.length > 10 ? 16 : 0)
        filesTip.x = Math.max(6, Math.min(r.x,
                                          filesTip.parent.width - filesTip.width - 6))
        var py = r.y + roleFilesLine.height + 5
        if (py + filesTip.height > filesTip.parent.height - 6)
            py = Math.max(6, r.y - filesTip.height - 5)
        filesTip.y = py
    }

    /* 目标角色选定 → 查询设备端素材清单（改/传前先看到现状） */
    function pickRole(name) {
        var idx = root.roleNames.indexOf(name)
        if (idx >= 0) root.targetRoleIdx = idx
        if (name !== "") {
            root.roleFilesFor = name
            backend.probeRoleFiles(name)
        }
    }
    function fmtEta() {
        if (speedKBs <= 0 || totalBytes <= 0 || doneBytes <= 0) return "—"
        var s = (totalBytes - doneBytes) / (speedKBs * 1024)
        if (s > 3600) return Math.round(s / 3600) + " h"
        if (s > 60) return Math.round(s / 60) + " min"
        return Math.max(1, Math.round(s)) + " s"
    }

    Connections {
        target: backend
        function onRoleList(names) { root.roleNames = names }
        function onRoleFilesReady(name, files) {
            if (name === root.roleFilesFor) {
                root.roleFiles = files
            }
        }
        function onConnState(ok, info) {
            if (!ok) {
                // 与角色列表解耦：断连/上传出错不清 roleNames（重连后
                // onRoleList 自动刷新），只清依赖设备实时状态的清单
                root.roleFiles = []
                root.roleFilesFor = ""
            }
        }
        function onStagedReady(name, count, total, paths) {
            root.stagedCount = count
            root.stagedFiles = paths
        }
        function onTransferFile(idx, total, label) {
            root.tfIdx = idx
            root.tfTotal = total
            root.tfLabel = label
        }
        function onTransferStats(speed, done, total, dir) {
            root.speedKBs = speed
            root.doneBytes = done
            root.totalBytes = total
            root.direction = dir
        }
        function onUploadProgress(p) {
            root.direction = "up"
            root.busy = true
            root.progress = p >= 0 ? p / 100.0 : -1
        }
        function onDownloadProgress(p) {
            root.direction = "down"
            root.busy = true
            root.progress = p >= 0 ? p / 100.0 : -1
        }
        function onComPorts(ports) { root.comPorts = ports }
        function onFlashLog(line, pct) {
            root.fwLog = line
            if (pct >= 0) root.fwPct = pct
        }
        function onFlashDone(ok, msg) {
            root.fwBusy = false
            root.fwOk = ok
            backend.toast(msg)
        }
        function onTransferDone(ok, msg) {
            root.progress = -1
            root.speedKBs = 0
            root.busy = false
            root.tfIdx = 0
            root.tfTotal = 0
            root.tfLabel = ""
            root.stagedCount = 0      // 上传会话结束，清暂存状态
            root.stagedFiles = []
            /* 刷新由 backend 单点触发（uploadFile/_batch_upload_thread finally），
             * 此处不再并发调用——双触发会两次 30s 超时弹双失败 toast */
            const act = root.direction === "down" ? "下载" : "上传"
            backend.toast((ok ? act + "完成：" : act + "失败：") + msg)
        }
    }

    component CardHead: Row {
        property string zh: ""
        property string en: ""
        spacing: Theme.u3
        Rectangle { width: 3; height: 12; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: parent.zh
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fsSmall
            font.bold: true
            color: Theme.primaryHi
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: "· " + parent.en
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMicro
            font.letterSpacing: 1.5
            color: Theme.textBody
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Flickable {
        id: pageScroll
        anchors.fill: parent
        clip: true
        contentWidth: width
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: contentCol
            width: parent.width
            spacing: Theme.u4

        /* ---- 编辑角色：源/目标卡行（整体标题） ---- */
        CardHead { zh: "编辑角色"; en: "EDIT ROLE" }
        Row {
            width: parent.width
            spacing: Theme.u5

            /* 源：本地文件 */
            GlassPanel {
                width: (parent.width - Theme.u5) / 2
                clip: true
                ScanlineOverlay { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 38; opacity: 0.3 }
                Column {
                    anchors.fill: parent
                    anchors.margins: Theme.u5
                    spacing: Theme.u3
                    CardHead { zh: "源 · 本地文件"; en: "LOCAL SOURCE" }
                    Row {
                        width: parent.width
                        spacing: Theme.u3
                        Rectangle {
                            width: parent.width - 96 - 96 - Theme.u3 * 2
                            height: 36
                            color: Theme.aWhite03
                            border.color: Theme.aWhite08
                            border.width: 1
                            clip: true
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.u3
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.localPath !== "" ? root.localPath
                                     : (root.localDir !== "" ? "[目录] " + root.localDir : "未选择文件或目录")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: (root.localPath === "" && root.localDir === "") ? Theme.textBody : Theme.textPrimary
                                elide: Text.ElideMiddle
                            }
                        }
                        NeonButton {
                            text: "文件…"
                            iconSource: "../assets/ic_folder.svg"
                            onClicked: fileDialog.open()
                        }
                        NeonButton {
                            text: "文件夹…"
                            iconSource: "../assets/ic_folder_open.svg"
                            onClicked: srcDirDlg.open()
                        }
                    }
                }
            }

            /* 目标：设备角色目录 */
            GlassPanel {
                width: (parent.width - Theme.u5) / 2
                /* clip 必须关：ComboGlass 下拉列表要溢出面板完整显示，
                 * 否则下方文字被自身功能框切断 */
                ScanlineOverlay { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 38; opacity: 0.3 }
                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.u5
                    /* 标题 → 下拉框行 → 提示/素材数整组（竖排，组整体居中于
                     * “下拉框下沿 ～ 卡面板下沿”区域） */
                    CardHead { id: tHead; zh: "目标 · 设备角色目录"; en: "DEVICE TARGET" }
                    Row {
                        id: tCombos
                        width: parent.width
                        spacing: Theme.u3
                        anchors.top: tHead.bottom
                        anchors.topMargin: Theme.u3
                        ComboGlass {
                            id: fileCombo
                            width: (parent.width - Theme.u3) / 2
                            model: ["全部", "loop.mjpeg", "intro.mjpeg", "portrait.bin", "ui_text.txt"]
                            currentIndex: 0
                            onPicked: function(index, value) { root.targetFile = (value === "全部" ? "all" : value) }
                        }
                        ComboGlass {
                            id: roleCombo
                            width: (parent.width - Theme.u3) / 2
                            model: root.roleNames
                            placeholder: "目标角色"
                            onPicked: function(index, value) { root.pickRole(value) }
                        }
                    }
                    Column {
                        id: txtGroup
                        width: parent.width
                        spacing: 2
                        anchors.top: tCombos.bottom
                        anchors.topMargin: Math.max(0, (parent.height - tCombos.y
                                        - tCombos.height - 26) / 2)
                        /* portrait 可传格式常驻提示：位于素材数文字上方 */
                        Text {
                            width: parent.width
                            text: "portrait 支持直传图片：jpg / jpeg / png / bmp / webp（自动转 64x64 RGB565）"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.textBody
                            elide: Text.ElideRight
                        }
                        /* 素材数文字行（悬浮查看明细） */
                        Item {
                            width: parent.width
                            height: 15
                            Text {
                                id: roleFilesLine
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.roleFilesFor !== ""
                                text: root.roleFilesFor + " · 素材 " + root.roleFiles.length + " 项（悬浮查看）"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textSecondary
                                elide: Text.ElideRight
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: { root.posRoleTip(); filesTip.open() }
                                    onExited: filesTip.close()
                                }
                            }
                        }
                    }
                }
            }
        }

        /* ---- 新建角色 / 删除角色（并排各 50%） ---- */
        Row {
            width: parent.width
            spacing: Theme.u3

            Column {
                width: parent.width * 0.65
                spacing: Theme.u2
                CardHead { zh: "新建角色"; en: "NEW ROLE" }
                GlassPanel {
                    id: newGlass
                    width: parent.width
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.u3
                        spacing: Theme.u2
                        Row {
                            width: parent.width
                            spacing: Theme.u2
                            Rectangle {
                                width: parent.width
                                height: 34
                                color: Theme.aWhite03
                                border.color: newRoleInput.activeFocus ? Theme.primary : Theme.aWhite08
                                border.width: 1
                                clip: true
                                TextField {
                                    id: newRoleInput
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.u2
                                    anchors.rightMargin: Theme.u2
                                    topPadding: 0
                                    bottomPadding: 0
                                    leftPadding: 0
                                    rightPadding: 0
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fsSmall
                                    color: Theme.textPrimary
                                    verticalAlignment: TextInput.AlignVCenter
                                    selectByMouse: true
                                    placeholderText: "角色名（如：ROLE_A）"
                                    placeholderTextColor: Theme.textBody
                                    background: Item {}
                                }
                            }
                        }
                        Row {
                            width: parent.width
                            spacing: Theme.u3
                            NeonButton {
                                text: "导入文件夹"
                                iconSource: "../assets/ic_folder_open.svg"
                                onClicked: {
                                    var nm = newRoleInput.text.trim()
                                    if (nm === "") { backend.toast("先输入角色名"); return }
                                    roleDirDlg.selectedRoleName = nm
                                    roleDirDlg.open()
                                }
                            }
                            Text {
                                width: parent.width - 110 - Theme.u3
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.stagedCount > 0
                                      ? root.stagedFiles.join("\n")
                                      : "素材白名单：loop.mjpeg / intro.mjpeg / portrait.bin（导入后点下方「开始上传」）"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: root.stagedCount > 0 ? Theme.primaryHi : Theme.textBody
                                wrapMode: root.stagedCount > 0 ? Text.WrapAnywhere : Text.Wrap
                                elide: Text.ElideRight
                                maximumLineCount: 2
                            }
                        }
                    }
                }
            }

            Column {
                width: parent.width * 0.35
                spacing: Theme.u2
                CardHead { zh: "删除角色"; en: "DELETE ROLE" }
                GlassPanel {
                    id: delGlass
                    width: parent.width
                    height: newGlass.height   // 与新建角色卡等高对齐
                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.u3
                        spacing: Theme.u2
                        ComboGlass {
                            id: delRoleCombo
                            width: parent.width
                            model: root.roleNames
                            placeholder: "选择要删除的角色"
                        }
                        NeonButton {
                            id: delRoleBtn
                            text: "删除角色"
                            danger: true
                            width: parent.width
                            iconSource: "../assets/ic_trash.svg"
                            onClicked: {
                                if (root.delArmed) {
                                    root.delArmed = false
                                    delRoleBtn.text = "删除角色"
                                    backend.deleteRole(delRoleCombo.model[delRoleCombo.currentIndex])
                                    return
                                }
                                if (delRoleCombo.currentIndex < 0) {
                                    backend.toast("请先选择要删除的角色")
                                    return
                                }
                                root.delArmed = true
                                delRoleBtn.text = "确认删除？"
                                backend.toast("再次点击确认删除角色: " + delRoleCombo.model[delRoleCombo.currentIndex])
                                disArmTimer.restart()
                            }
                        }
                        Text {
                            width: parent.width
                            text: "删除后不可恢复，包含该角色的全部素材"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                            wrapMode: Text.Wrap
                        }
                        Timer {
                            id: disArmTimer
                            interval: 3000
                            onTriggered: {
                                root.delArmed = false
                                delRoleBtn.text = "删除角色"
                            }
                        }
                    }
                }
            }
        }

        /* ---- 进度条 + 统计（压扁：默认分辨率下给控制组留足空间） ---- */
        GlassPanel {
            width: parent.width
            height: 110
            Column {
                anchors.fill: parent
                anchors.margins: Theme.u4
                spacing: Theme.u3

                Item {
                    width: parent.width
                    height: 18

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.u3
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: dirLabel.implicitWidth + Theme.u3 * 2
                            height: 20
                            color: root.progress >= 0 ? Theme.primary : "transparent"
                            border.color: root.progress >= 0 ? Theme.primary : Theme.aWhite08
                            border.width: 1
                            Text {
                                id: dirLabel
                                anchors.centerIn: parent
                                text: (root.direction === "up" ? "▲ 上传" : "▼ 下载") + (root.progress >= 0 ? "" : " 待机")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: root.progress >= 0 ? "#0A0A0A" : Theme.textBody
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.progress < 0 ? "" : Math.round(root.progress * 100) + "%"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSmall
                            font.bold: true
                            color: Theme.primaryHi
                        }
                        Item { width: Theme.u4; height: 1 }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.speedKBs > 0 ? root.speedKBs.toFixed(1) + " KB/s" : "— KB/s"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSmall
                            color: Theme.textSecondary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.doneBytes > 0 ? fmtBytes(root.doneBytes) + " / " + (root.totalBytes > 0 ? fmtBytes(root.totalBytes) : "?") : ""
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSmall
                            color: Theme.textSecondary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.progress < 0 ? "" : "ETA " + fmtEta()
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fsSmall
                            color: root.progress < 0 ? "transparent" : Theme.primaryHi
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(parent.width * 0.5, 360)
                        text: root.tfTotal > 1
                              ? "文件 " + root.tfIdx + " / " + root.tfTotal + " · " + root.tfLabel
                              : (root.tfTotal === 1 ? "文件 " + root.tfLabel : "")
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textSecondary
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }
                }

                FlowProgressBar {
                    width: parent.width
                    height: 22
                    progress: root.progress
                    direction: root.direction
                }
            }
        }

        /* ---- 控制组 ---- */
        Row {
            spacing: Theme.u4
            NeonButton {
                text: "开始上传"
                active: true
                iconSource: "../assets/ic_upload.svg"
                onClicked: {
                    // 检测意图：暂存上传 > 新建流程 > 编辑已有角色（状态组合判定，零猜测）
                    // ① 新建角色素材已暂存 → 目标角色名随暂存，无需选角色
                    if (root.stagedCount > 0) {
                        root.progress = 0
                        backend.startStagedUpload()
                        return
                    }
                    // ② 姓名框有值但无暂存 → 新建流程缺素材文件夹
                    if (newRoleInput.text.trim() !== "") {
                        backend.toast("缺少必填项目：素材文件夹")
                        return
                    }
                    // ③ 编辑已有角色：未选目标角色
                    var role = roleCombo.currentIndex >= 0 ? roleCombo.model[roleCombo.currentIndex] : ""
                    if (role === "") { backend.toast("缺少必填项目：目标角色"); return }
                    // ④ 「全部」未选源文件夹
                    if (root.targetFile === "all") {
                        if (root.localDir === "") { backend.toast("缺少必填项目：源文件夹"); return }
                        root.progress = 0
                        backend.uploadAll(root.localDir, role)
                        return
                    }
                    // ⑤ 未选本地文件
                    if (root.localPath === "") { backend.toast("缺少必填项目：本地文件"); return }
                    root.progress = 0
                    backend.uploadFile(root.localPath, role, root.targetFile)
                }
            }
            NeonButton {
                text: "开始下载"
                iconSource: "../assets/ic_download.svg"
                onClicked: {
                    var role = roleCombo.currentIndex >= 0 ? roleCombo.model[roleCombo.currentIndex] : ""
                    if (role === "") { backend.toast("缺少必填项目：目标角色"); return }
                    root.progress = 0
                    if (root.targetFile === "all") {
                        backend.downloadAll(role)   // 自动存 <程序根>/Downloads/<角色名>/
                        return
                    }
                    backend.downloadFile("/sdcard/" + role + "/" + root.targetFile,
                                         root.targetFile)
                }
            }
            NeonButton {
                text: "停止"
                danger: true
                visible: root.busy
                iconSource: "../assets/ic_stop.svg"
                onClicked: backend.cancelTransfer()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth > 420 ? 420 : implicitWidth
                text: "下载的角色与文件在上方目标卡中选择；选「全部」时将整包传输该角色全部素材，均保存到程序根目录 Downloads/<角色名>/"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsMicro
                color: Theme.textBody
                wrapMode: Text.Wrap
            }
        }

        /* ---- 固件更新（有线烧录，esptool） ---- */
        Row {
            width: parent.width
            spacing: Theme.u3
            Column {
                width: parent.width * 0.62
                spacing: Theme.u2
                CardHead { zh: "固件更新"; en: "FIRMWARE (WIRED)" }
                GlassPanel {
                    id: fwGlass
                    width: parent.width
                    Column {
                        id: fwCol
                        anchors.fill: parent
                        anchors.leftMargin: Theme.u3
                        anchors.rightMargin: Theme.u3
                        anchors.topMargin: 5
                        anchors.bottomMargin: 5
                        spacing: Theme.u1
                                                Row {
                            width: parent.width
                            spacing: Theme.u2
                            ComboGlass {
                                id: fwPortCombo
                                width: 150
                                height: 36
                                model: root.comPorts
                                placeholder: "串口 COMx"
                            }
                            NeonButton {
                                text: "刷新"
                                width: 84
                                height: 36
                                onClicked: backend.scanComPorts()
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 150 - 84 - Theme.u2 * 2
                                clip: true
                                elide: Text.ElideLeft
                                text: root.fwBinPath === ""
                                      ? "未选择固件文件（firmware_merged.bin）"
                                      : root.fwBinPath
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textBody
                            }
                        }
                                                                        Row {
                            width: parent.width
                            height: 34
                            spacing: Theme.u2
                            Rectangle {
                                id: fwKeepBtn
                                width: 112
                                height: 34
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.fwKeep ? Theme.aOrange15 : Theme.aWhite05
                                border.color: root.fwKeep ? Theme.primary : Theme.aWhite12
                                border.width: 1
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        root.fwKeep = !root.fwKeep
                                        backend.toast(root.fwKeep
                                                      ? "保留设备设置：只写应用分区，NVS/字库分区不动"
                                                      : "全量模式：整片镜像写入（含分区表，NVS 将被重置）")
                                    }
                                }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.fwKeep ? "✓" : ""
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsSmall
                                        font.bold: true
                                        color: Theme.primaryHi
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "保留设备设置"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsMicro
                                        color: Theme.textPrimary
                                    }
                                }
                            }
                            NeonButton {
                                width: 117
                                height: 34
                                text: "选择固件"
                                iconSource: "../assets/ic_folder_open.svg"
                                onClicked: fwDlg.open()
                            }
                            NeonButton {
                                width: 117
                                height: 34
                                text: root.fwBusy ? "烧录中…" : "开始烧录"
                                active: !root.fwBusy && root.fwBinPath !== ""
                                danger: true
                                onClicked: {
                                    if (root.fwBusy) return
                                    if (fwPortCombo.currentIndex < 0) {
                                        backend.toast("请先选择串口（点「刷新」扫描）")
                                        return
                                    }
                                    root.fwBusy = true
                                    root.fwOk = false
                                    root.fwPct = -1
                                    backend.flashFirmware(fwPortCombo.model[fwPortCombo.currentIndex],
                                                          root.fwBinPath, root.fwKeep)
                                }
                            }
                        }
                                                Row {
                            width: parent.width
                            height: 30
                            spacing: Theme.u2
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                clip: true
                                elide: Text.ElideRight
                                visible: !root.fwBusy
                                text: root.fwLog === ""
                                      ? (root.fwOk ? "上次烧录成功" : "设备需通过 USB 连接本机（COM 口）")
                                      : root.fwLog
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: root.fwOk ? Theme.primaryHi : Theme.textBody
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                clip: true
                                elide: Text.ElideRight
                                visible: root.fwBusy
                                text: root.fwPct >= 0
                                      ? "烧录中 " + root.fwPct + "%"
                                      : "正在连接芯片 / 擦写…"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: Theme.primaryHi
                            }
                        }
                    }
                }
            }
            Column {
                width: parent.width * 0.38
                spacing: Theme.u2
                CardHead { zh: "注意事项"; en: "NOTES" }
                GlassPanel {
                    width: parent.width
                    height: fwGlass.height
                                        Column {
                        anchors.fill: parent
                        anchors.margins: Theme.u3
                        spacing: 2
                        Text {
                            width: parent.width
                            text: "✓ 保留设备设置（默认勾选）"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                            color: Theme.primaryHi
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "只写应用分区（0x10000 起）。UI 选项、档案、校准、分区表全保留。"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.textBody
                        }
                        Text {
                            width: parent.width
                            text: "✗ 全量整片镜像（取消勾选）"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                            color: Theme.red
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "整片 0x0 写入含分区表，NVS 被重置；若 SD 卡有快照（config/nvs_backup.txt）则自动回填关键设置。"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.textBody
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: "两模式均不动 SD 内容；烧录中勿断电拔线，完成自动重启。"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: Theme.textSecondary
                        }
                    }
                }
            }
        }
        }
        contentHeight: contentCol.height + 24
    }

    FileDialog {
        id: fileDialog
        title: "选择要上传的文件"
        fileMode: FileDialog.OpenFile
        nameFilters: ["素材文件 (*.mjpeg *.bin *.txt)", "portrait 图片（jpg/jpeg/png/bmp/webp，自动转 64x64）", "所有文件 (*)"]
        onAccepted: {
            root.localDir = ""
            root.localPath = selectedFile.toString().replace(/^file:\/\/\//, "").replace(/\//g, "\\")
        }
    }
    /* 素材选择对话框 */
    FileDialog {
        id: fwDlg
        title: "选择固件文件（firmware_merged.bin）"
        fileMode: FileDialog.OpenFile
        nameFilters: ["固件镜像 (*.bin)", "所有文件 (*)"]
        onAccepted: {
            root.fwBinPath = selectedFile.toString().replace(/^file:\/\/\//, "").replace(/\//g, "\\")
            root.fwLog = ""
            root.fwOk = false
        }
    }
    FolderDialog {
        id: srcDirDlg
        title: "选择本地素材目录（用于「全部」上传）"
        onAccepted: {
            root.localPath = ""
            root.localDir = selectedFolder.toString().replace(/^file:\/\/\//, "").replace(/\//g, "\\")
        }
    }
    FolderDialog {
        id: roleDirDlg
        property string selectedRoleName: ""
        title: "选择角色素材文件夹"
        onAccepted: backend.importRoleFolder(selectedRoleName, selectedFolder)
    }

    /* 角色素材明细浮窗：黑底细边框，前台（Overlay）显示 */
    Popup {
        id: filesTip
        parent: Overlay.overlay
        width: 232
        padding: 8
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        background: Rectangle {
            color: "#141414"
            border.color: Theme.primary
            border.width: 1
        }
        contentItem: Column {
            spacing: 2
            Repeater {
                model: root.roleFiles.length > 10 ? 10 : root.roleFiles.length
                delegate: Row {
                    width: 214
                    height: 15
                    spacing: Theme.u2
                    Text {
                        width: 132
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.roleFiles[index][0] || "(无名)"
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        color: Theme.textPrimary
                        elide: Text.ElideMiddle
                    }
                    Text {
                        width: 76
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.roleFiles[index][1] !== null
                              ? root.fmtBytes(root.roleFiles[index][1]) : ""
                        horizontalAlignment: Text.AlignRight
                        font.family: Theme.fontMono
                        font.pixelSize: 9
                        color: Theme.textSecondary
                        elide: Text.ElideRight
                    }
                }
            }
            Text {
                width: 214
                visible: root.roleFiles.length > 10
                text: "… 其余 " + (root.roleFiles.length - 10) + " 项"
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Theme.textBody
            }
        }
    }
    PageWheel {
        anchors.fill: parent
        outer: pageScroll
    }

}
