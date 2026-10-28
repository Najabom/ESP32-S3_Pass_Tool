/* ============================================================================
 * StatusPage.qml —— 状态监控页（真实数据）
 *
 * 布局：指标行（连接环 / 传输进度环 / 固件版本卡 / 角色数卡）
 *      + 速率历史曲线 + 设备信息面板。
 * 数据源：backend.connState / transferStats / roleList / currentRole
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0
import "../components"

Item {
    id: root

    /* ---- 绿点脉冲（在线呼吸光环，参考站 status-dot 语言） ---- */
    component PulseDot: Item {
        id: pd
        width: 10; height: 10
        property color dotColor: Theme.ok
        property bool active: true
        Rectangle {
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            color: pd.dotColor
            opacity: pd.active ? 1 : 0.35
        }
        Rectangle {
            visible: pd.active
            anchors.centerIn: parent
            width: 6; height: 6; radius: 3
            color: "transparent"
            border.color: pd.dotColor
            border.width: 1
            SequentialAnimation on scale {
                running: pd.active
                loops: Animation.Infinite
                NumberAnimation { to: 2.6; duration: 1400; easing.type: Easing.OutQuad }
                NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InQuad }
            }
            SequentialAnimation on opacity {
                running: pd.active
                loops: Animation.Infinite
                NumberAnimation { to: 0; duration: 1400 }
                NumberAnimation { to: 0.8; duration: 200 }
                PauseAnimation { duration: 300 }
            }
        }
    }

    /* ---- 状态镜像 ---- */
    property bool connected: false
    property string connInfo: "未连接"
    property string version: "—"
    property int roleCount: 0
    property string currentRole: "—"
    property string loglevel: "—"
    property real transferPct: 0
    property bool transferring: false

    Connections {
        target: backend
        function onConnState(ok, info) {
            root.connected = ok
            root.connInfo = info
            if (ok) {
                var m = info.match(/v([0-9.]+)\)/)
                if (m) root.version = m[1]
            } else {
                root.version = "—"
                root.roleCount = 0
                root.currentRole = "—"
                root.loglevel = "—"
            }
        }
        function onRoleList(names) { root.roleCount = names.length }
        function onCurrentRole(name) { root.currentRole = name }
        function onLoglevelChanged(lv) { root.loglevel = lv }
        function onTransferStats(speed, done, total, dir) {
            speedChart.push(speed)
        }
        function onUploadProgress(p) {
            root.transferPct = p / 100.0
            root.transferring = true
        }
        function onDownloadProgress(p) {
            if (p >= 0) root.transferPct = p / 100.0
            root.transferring = true
        }
        function onTransferDone(ok, msg) {
            root.transferring = false
            root.transferPct = 0
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.u5

        /* ---- 指标行 ---- */
        Row {
            width: parent.width
            spacing: Theme.u5

            RingGauge {
                width: (parent.width - Theme.u5 * 3) / 4
                height: 170
                label: "设备连接"
                valueText: root.connected ? "在线" : "离线"
                progress: root.connected ? 1.0 : 0.0
                accent: root.connected ? Theme.ok : Theme.red
            }
            RingGauge {
                width: (parent.width - Theme.u5 * 3) / 4
                height: 170
                label: "传输进度"
                valueText: root.transferring ? Math.round(root.transferPct * 100) + "%" : "空闲"
                progress: root.transferring ? root.transferPct : 0
                accent: Theme.primary
            }
            GlassPanel {
                width: (parent.width - Theme.u5 * 3) / 4
                height: 170
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.u2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.version === "—" ? "—" : "v" + root.version
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsDisplay
                        font.bold: true
                        color: Theme.primary
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "固件版本 · FIRMWARE"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        font.letterSpacing: 1
                        color: Theme.textBody
                    }
                }
            }
            GlassPanel {
                width: (parent.width - Theme.u5 * 3) / 4
                height: 170
                Column {
                    anchors.centerIn: parent
                    spacing: Theme.u2
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.connected ? String(root.roleCount).padStart(2, '0') : "—"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsDisplay
                        font.bold: true
                        color: Theme.primary
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "SD 卡角色 · ROLES"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        font.letterSpacing: 1
                        color: Theme.textBody
                    }
                }
            }
        }

        /* ---- 速率曲线 + 设备信息（并排分栏，弹性填满剩余高度） ---- */
        Row {
            width: parent.width
            height: parent.height - 170 - Theme.u5
            spacing: Theme.u5

            FlowChart {
                id: speedChart
                width: (parent.width - Theme.u5) * 0.54
                height: parent.height
            }

            /* 设备信息（行式列表：编号列 + hover 平移 + 扫描线头部） */
            GlassPanel {
                id: infoPanel
                width: (parent.width - Theme.u5) * 0.46
                height: parent.height
                clip: true

            ScanlineOverlay {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 44
                opacity: 0.35
            }

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Theme.u5
                anchors.leftMargin: Theme.u5
                anchors.rightMargin: Theme.u5
                spacing: Theme.u3

                Row {
                    spacing: Theme.u3
                    PulseDot { anchors.verticalCenter: parent.verticalCenter; active: root.connected; dotColor: root.connected ? Theme.ok : Theme.red }
                    Text {
                        text: "设备信息 · DEVICE TELEMETRY"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsBody
                        font.bold: true
                        color: Theme.primaryHi
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Repeater {
                    model: [
                        ["状态", root.connected ? "已连接" : "未连接"],
                        ["设备", root.connInfo],
                        ["当前角色", root.currentRole],
                        ["日志级别", root.loglevel]
                    ]
                    delegate: Item {
                        width: infoPanel.width - Theme.u7 * 2
                        height: 30
                        transform: Translate {
                            x: ma.containsMouse ? 5 : 0
                            Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            x: -Theme.u3; y: -2
                            width: parent.width + Theme.u6; height: parent.height + 4
                            color: ma.containsMouse ? Theme.aWhite04 : "transparent"
                        }
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.u4
                            Text {
                                width: 28
                                text: String(index + 1).padStart(2, '0')
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsSmall
                                color: ma.containsMouse ? Theme.primaryHi : Theme.textBody
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: 80
                                text: modelData[0]
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsSmall
                                color: Theme.textBody
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData[1]
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsSmall
                                color: Theme.textPrimary
                                elide: Text.ElideRight
                                width: infoPanel.width - Theme.u7 * 2 - 28 - Theme.u4 * 2 - 80
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }
            }
        }
    }
}
