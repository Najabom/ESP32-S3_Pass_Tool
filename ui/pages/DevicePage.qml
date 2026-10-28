/* ============================================================================
 * DevicePage.qml —— 设备连接页（扫描/连接/配置/操作，全部真实调用）
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Dialogs
import Theme 1.0
import "../components"

Item {
    id: root

    /* ---- 状态 ---- */
    property var devices: []            // [display, ...]（BLE 扫描候选）
    property int selectedDevice: -1
    property bool connected: false
    property string connInfo: ""
    property var roleNames: []
    property string currentRole: ""
    property string loglevel: "info"
    property bool scanning: false        // 扫描进行中（按钮文案/禁用）
    property bool connecting: false      // 连接进行中（按钮文案/禁用）
    property string selfAvUrl: ""           // 选中的头像图片预览（本地路径，直接作 Image.source）
    property string selectedSelfAvFile: ""
    property bool utBusy: false          // 界面文本上传进行中（按钮文案/禁用）

    /* 企划短码实时预览：与设备 ip_code_from_text() 逐字节一致的 FNV-1a16 */
    function utf8Bytes(s) {
        var b = []
        for (var i = 0; i < s.length;) {
            var c = s.codePointAt(i)
            if (c > 0xFFFF) i += 2; else i += 1
            if (c < 0x80) b.push(c)
            else if (c < 0x800) b.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F))
            else if (c < 0x10000) b.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F))
            else b.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 0x3F), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F))
        }
        return b
    }
    function fnv1a16code(s) {
        var h = 2166136261
        var bs = utf8Bytes(s)
        for (var i = 0; i < bs.length; i++) {
            var c = bs[i]
            if (c >= 0x41 && c <= 0x5A) c += 0x20      /* ASCII 大写归一（同设备端） */
            h ^= c
            h = Math.imul(h, 16777619) >>> 0
        }
        h ^= h >>> 16
        var v = (h & 0xFFFF) >>> 0
        var hx = v.toString(16)
        while (hx.length < 4) hx = "0" + hx
        return hx
    }
    /* 与设备 trim_line/未知 key 规则对齐；无法编码的输入返回 null */
    function ipCode(t) {
        if (t === undefined || t === null) return null
        var s = String(t)
        s = s.replace(/[ \t\r\n]+$/, "")
        s = s.replace(/^[ \t]+/, "")
        if (s.length === 0 || s.charAt(0) === "#") return null
        var eq = s.indexOf("=")
        if (eq >= 0) {
            var key = s.substring(0, eq)
            if (key !== "my_name" && key !== "peer") return null
            s = s.substring(eq + 1).replace(/^[ \t]+/, "")
            if (s.length === 0) return null
        }
        return fnv1a16code(s)
    }
    Connections {
        target: backend
        function onScanDone(list) { root.devices = list; root.selectedDevice = -1; root.scanning = false }
        function onConnState(ok, info) {
            root.connecting = false
            root.connected = ok
            root.connInfo = info
            if (ok) { backend.readIpcfg() }
            if (!ok) {
                // 断开连接：清空全部设备数据（含角色列表，重连后 onRoleList 自动重新填充）。
                // 注意与"上传出错（仍连接但数据不清）"分开：上传错误走 transferFailed，
                // 不触发 connState(false) —— 队列数据保留，列表不清。
                root.roleNames = []
                root.currentRole = ""
                root.loglevel = "info"
                devNameInput.text = ""
                cfgRpt.itemAt(0).cfgInput.text = ""
                cfgRpt.itemAt(1).cfgInput.text = ""
                cfgRpt.itemAt(2).cfgInput.text = ""
                utLcInput.text = ""
                utStInput.text = ""
                utOpInput.text = ""
                root.selfAvUrl = ""
                for (var k = 0; k < 8; k++) {
                    var it2 = ipRpt.itemAt(k)
                    if (it2) it2.inputText = ""
                }
            }
        }
        function onRoleList(names) { root.roleNames = names }
        function onProfileLoaded(devname, uid, motto, uname) {
            // 连接后由 backend 异步读取并回填（不阻塞 GUI）
            devNameInput.text = devname
            cfgRpt.itemAt(0).cfgInput.text = uid
            cfgRpt.itemAt(1).cfgInput.text = motto
            cfgRpt.itemAt(2).cfgInput.text = uname
        }
        function onIpcfgReady(raw) {
            // 读回企划配置（空 = 全通）→ 逐格回填（多余格清空）
            var lines = raw.split("\n")
            for (var i = 0; i < 8; i++) {
                var it = ipRpt.itemAt(i)
                if (it) it.inputText = (i < lines.length) ? lines[i].trim() : ""
            }
        }
        function onCurrentRole(name) { root.currentRole = name }
        function onLoglevelChanged(lv) { root.loglevel = lv }
        function onSelfAvatarReady(path) {
            // 连接后自动载入设备上已有的本机头像（无则保持占位图并记日志）
            // backend 已返回 file:// URL 字符串（直接作为 Image.source）
            if (!path) { root.selfAvUrl = ""; return }
            root.selfAvUrl = String(path)
        }
        function onUiTextReady(name, lc, sub, op) {
            // 角色 ui_text 内容回填（无文件=全部 ""→清空输入框）
            if (utCombo.currentIndex >= 0 && utCombo.model[utCombo.currentIndex] === name) {
                utLcInput.text = lc
                utStInput.text = sub
                utOpInput.text = op
            }
        }
        function onTransferDone(ok, msg) {
            // 上传文本成功后回读内容（清除旧值/确认生效）
            root.utBusy = false
            if (ok && utCombo.currentIndex >= 0)
                backend.readUiText(utCombo.model[utCombo.currentIndex])
        }
    }

    /* ---- 绿点脉冲 ---- */
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

    component SectionHead: Row {
        property string zh: ""
        property string en: ""
        spacing: Theme.u3
        Rectangle { width: 3; height: 14; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
        Text {
            text: parent.zh
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fsBody
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
        contentWidth: pageCol.width
        contentHeight: pageCol.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: pageCol
            width: pageScroll.width
            spacing: Theme.u5

        Row {
            id: pageRow
            width: pageScroll.width
            spacing: Theme.u5

        /* ============ 左列：扫描与连接 ============ */
        Column {
            width: (parent.width - Theme.u5) / 2
            spacing: Theme.u4

            SectionHead { zh: "设备扫描"; en: "SCAN" }

            Row {
                spacing: Theme.u3
                NeonButton {
                    text: root.connected ? "断开连接" : (root.scanning ? "扫描中…" : "扫描")
                    active: true
                    opacity: root.scanning ? 0.6 : 1.0
                    iconSource: root.connected ? "../assets/ic_disconnect_w.svg" : "../assets/ic_scan_w.svg"
                    onClicked: {
                        if (root.connected) backend.disconnectDevice()
                        else if (!root.scanning) { root.scanning = true; backend.startScan() }
                    }
                }
                PulseDot {
                    anchors.verticalCenter: parent.verticalCenter
                    active: root.connected
                    dotColor: root.connected ? Theme.ok : Theme.textBody
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.connected ? root.connInfo + "  ·  已连接，修改即时生效"
                        : (root.devices.length ? "发现 " + root.devices.length + " 台设备" : "点击扫描发现本族设备")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsMicro
                    color: root.connected ? Theme.ok : Theme.textBody
                    width: 330
                    elide: Text.ElideRight
                }
            }

            /* 设备列表 */
            GlassPanel {
                width: parent.width
                height: 150
                ListView {
                    id: devList
                    anchors.fill: parent
                    anchors.margins: Theme.u3
                    model: root.devices
                    clip: true
                    spacing: Theme.u1
                    delegate: Rectangle {
                        width: devList.width - Theme.u2
                        height: 38
                        color: idx === root.selectedDevice ? Theme.aOrange15
                             : (dma.containsMouse ? Theme.aWhite06 : "transparent")
                        property int idx: index
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.u3
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.u3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.u3
                            Text {
                                text: String(index + 1).padStart(2, '0')
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: idx === root.selectedDevice ? Theme.primaryHi : Theme.textBody
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                id: ttitle
                                width: parent.width - 22 - Theme.u3 * 3
                                text: modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsSmall
                                elide: Text.ElideRight
                                color: idx === root.selectedDevice ? Theme.primaryHi : Theme.textBody
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: dma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedDevice = idx
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: root.devices.length === 0
                        text: "暂无设备 — 点击「扫描」"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsSmall
                        color: Theme.textBody
                    }
                }
            }



            NeonButton {
                visible: !root.connected
                text: root.connecting ? "连接中…" : "连接选中设备"
                active: !root.connecting
                opacity: root.connecting ? 0.6 : 1.0
                iconSource: "../assets/ic_device.svg"
                onClicked: {
                    if (root.connecting) return
                    if (root.selectedDevice < 0) { backend.toast("请先在列表中选择设备"); return }
                    root.connecting = true
                    backend.connectDevice(root.selectedDevice)
                }
            }

            /* 角色列表（行式：编号 + 名称 + ACTIVE 徽标 + 箭头） */
            SectionHead { zh: "角色列表"; en: "ROLES · CLICK TO SWITCH"; visible: root.roleNames.length > 0 }
            GlassPanel {
                width: parent.width
                height: root.roleNames.length ? Math.min(root.roleNames.length, 4) * 40 + Theme.u3 : 0
                visible: root.roleNames.length > 0
                ListView {
                    id: roleList
                    anchors.fill: parent
                    anchors.margins: Theme.u1
                    model: root.roleNames
                    clip: true
                    spacing: 2
                    delegate: Rectangle {
                        width: roleList.width - Theme.u2
                        height: 36
                        color: modelData === root.currentRole ? Theme.aOrange15
                             : (oma.containsMouse ? Theme.aWhite06 : "transparent")
                        transform: Translate {
                            x: oma.containsMouse ? 5 : 0
                            Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.u3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.u3
                            Text {
                                text: String(index + 1).padStart(2, '0')
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: modelData === root.currentRole ? Theme.primaryHi : Theme.textBody
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: modelData
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsSmall
                                font.bold: modelData === root.currentRole
                                color: modelData === root.currentRole ? Theme.primaryHi : Theme.textSecondary
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.u3
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.u3
                            Rectangle {
                                visible: modelData === root.currentRole
                                width: actLabel.implicitWidth + Theme.u3 * 2
                                height: 18
                                color: Theme.primary
                                Text {
                                    id: actLabel
                                    anchors.centerIn: parent
                                    text: "ACTIVE"
                                    font.family: Theme.fontMono
                                    font.pixelSize: 9
                                    font.letterSpacing: 1.5
                                    color: "#0A0A0A"
                                }
                            }
                            Text {
                                text: "→"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsSmall
                                color: oma.containsMouse ? Theme.primaryHi : "transparent"
                                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: oma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: backend.selectRole(modelData)
                        }
                    }
                }
            }

            /* 新建角色功能已移至「文件传输」页 */

            /* ---- 界面文本（角色级：<角色>/ui_text.txt） ---- */
            Column {
                width: parent.width
                spacing: Theme.u3
                SectionHead { zh: "界面文本"; en: "UI TEXT · PER ROLE" }
                    GlassPanel {
                        width: parent.width
                        height: 184
                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.u3
                            spacing: Theme.u2
                            Row {
                                width: parent.width
                                spacing: Theme.u2
                                ComboGlass {
                                    id: utCombo
                                    width: parent.width * 0.42
                                    model: root.roleNames
                                    placeholder: "目标角色"
                                    onPicked: function(index, value) { backend.readUiText(value) }
                                }
                                Rectangle {
                                    width: parent.width * 0.58 - Theme.u2
                                    height: 38
                                    color: Theme.aWhite03
                                    border.color: utLcInput.activeFocus ? Theme.primary : Theme.aWhite08
                                    border.width: 1
                                    clip: true
                                    TextInput {
                                        id: utLcInput
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.u2
                                        anchors.rightMargin: Theme.u2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsSmall
                                        color: Theme.textPrimary
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        selectByMouse: true
                                    }
                                    Text {
                                        visible: utLcInput.text === ""
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.u2
                                        anchors.rightMargin: Theme.u2
                                        text: "leftcol（≤13 英文）"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsSmall
                                        color: Theme.textBody
                                        verticalAlignment: TextInput.AlignVCenter
                                    }
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: Theme.u2
                                Rectangle {
                                    width: parent.width * 0.42
                                    height: 38
                                    color: Theme.aWhite03
                                    border.color: utStInput.activeFocus ? Theme.primary : Theme.aWhite08
                                    border.width: 1
                                    clip: true
                                    TextInput {
                                        id: utStInput
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.u2
                                        anchors.rightMargin: Theme.u2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsSmall
                                        color: Theme.textPrimary
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        selectByMouse: true
                                    }
                                    Text {
                                        visible: utStInput.text === ""
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.u2
                                        anchors.rightMargin: Theme.u2
                                        text: "sub_text（≤40 字符）"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsSmall
                                        color: Theme.textBody
                                        verticalAlignment: TextInput.AlignVCenter
                                    }
                                }
                                Rectangle {
                                    width: parent.width * 0.58 - Theme.u2
                                    height: 38
                                    color: Theme.aWhite03
                                    border.color: utOpInput.activeFocus ? Theme.primary : Theme.aWhite08
                                    border.width: 1
                                    clip: true
                                    TextInput {
                                        id: utOpInput
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.u2
                                        anchors.rightMargin: Theme.u2
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsSmall
                                        color: Theme.textPrimary
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        selectByMouse: true
                                    }
                                    Text {
                                        visible: utOpInput.text === ""
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.u2
                                        anchors.rightMargin: Theme.u2
                                        text: "op_name（右下角色名，可中文）"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fsSmall
                                        color: Theme.textBody
                                        verticalAlignment: TextInput.AlignVCenter
                                    }
                                }
                            }
                            Row {
                                width: parent.width
                                spacing: Theme.u2
                                NeonButton {
                                    width: parent.width * 0.42
                                    height: 38
                                    text: root.utBusy ? "上传中…" : "上传文本"
                                    iconSource: "../assets/ic_upload.svg"
                                    enabled: !root.utBusy
                                    onClicked: {
                                        if (root.utBusy) return
                                        if (utCombo.currentIndex < 0) {
                                            backend.toast("请先选择目标角色")
                                            return
                                        }
                                        var lc = utLcInput.text.trim()
                                        var st = utStInput.text.trim()
                                        var op = utOpInput.text.trim()
                                        root.utBusy = true
                                        backend.uploadUiText(utCombo.model[utCombo.currentIndex], lc, st, op)
                                    }
                                }
                                Text {
                                    width: parent.width * 0.58 - Theme.u2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "写入该角色 ui_text.txt 即时生效；留空 = 该元素不显示（无内置默认文案）。leftcol/sub_text 字库仅 ASCII"
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fsMicro
                                    color: Theme.textBody
                                    wrapMode: Text.Wrap
                                }
                            }
                        }
                    }
                }
        }

        /* ============ 右列：配置与操作 ============ */
        Column {
            width: (parent.width - Theme.u5) / 2
            spacing: Theme.u4

            SectionHead { zh: "设备配置"; en: "DEVICE CONFIG" }

            Repeater {
                id: cfgRpt
                model: [
                    { key: "uid", label: "UID（≤20 位数字）", slot: "setUid" },
                    { key: "motto", label: "寄语（≤64B UTF-8，约20个汉字）", slot: "setMotto" },
                    { key: "uname", label: "用户名（≤64B UTF-8，约20个汉字）", slot: "setUname" }
                ]
                delegate: Column {
                    // 属性别名提升：外部经 cfgRpt.itemAt(i).cfgInput 访问输入框
                    property alias cfgInput: cfgInputText
                    width: parent.width
                    spacing: Theme.u1
                    Text {
                        text: modelData.label
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.u3
                        Rectangle {
                            width: parent.width - 110
                            height: 36
                            color: Theme.aWhite03
                            border.color: cfgInputText.activeFocus ? Theme.primary : Theme.aWhite08
                            border.width: 1
                            clip: true
                            TextInput {
                                id: cfgInputText
                                anchors.fill: parent
                                anchors.margins: Theme.u2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsSmall
                                color: Theme.textPrimary
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                selectByMouse: true
                            }
                        }
                        NeonButton {
                            text: "保存"
                            iconSource: "../assets/ic_save.svg"
                            onClicked: {
                                var v = cfgInputText.text.trim()
                                if (v === "") { backend.toast("内容为空"); return }
                                var n = root.utf8Bytes(v).length
                                if (modelData.slot === "setUid") {
                                    if (n > 20) { backend.toast("UID 超长（≤20 字节）"); return }
                                    backend.setUid(v)
                                } else if (modelData.slot === "setMotto") {
                                    if (n > 64) { backend.toast("寄语超长（≤64 字节）"); return }
                                    backend.setMotto(v)
                                } else {
                                    if (n > 64) { backend.toast("用户名超长（≤64 字节）"); return }
                                    backend.setUname(v)
                                }
                            }
                        }
                    }
                }
            }

            /* 设备名（与名片配置输入框同宽对齐；写 0xFFEA 后设备重写 bt.txt 并重开广播） */
            Column {
                width: parent.width
                spacing: Theme.u1
                Text {
                    text: "设备名（≤15 字节，广播名/列表显示）"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textBody
                }
                Row {
                    width: parent.width
                    spacing: Theme.u3
                    Rectangle {
                        width: parent.width - 110
                        height: 36
                        color: Theme.aWhite03
                        border.color: devNameInput.activeFocus ? Theme.primary : Theme.aWhite08
                        border.width: 1
                        clip: true
                        TextInput {
                            id: devNameInput
                            anchors.fill: parent
                            anchors.margins: Theme.u2
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsSmall
                            color: Theme.textPrimary
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            selectByMouse: true
                        }
                    }
                    NeonButton {
                        text: "保存"
                        iconSource: "../assets/ic_save.svg"
                        onClicked: {
                            var v = devNameInput.text.trim()
                            if (v === "") { backend.toast("设备名不能为空"); return }
                            if (root.utf8Bytes(v).length > 15) { backend.toast("设备名超长（≤15 字节）"); return }
                            backend.setDeviceName(v)
                        }
                    }
                }
            }

            /* 日志级别 / 热重载 / 同步时间（并入设备配置） */
            Row {
                width: parent.width
                spacing: Theme.u3
                z: 10   /* 展开列表须盖过下方提示文字 */
                Column {
                    width: 150
                    spacing: Theme.u1
                    Text {
                        text: "日志级别（当前 " + root.loglevel + "）"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                    }
                    ComboGlass {
                        id: lvCombo
                        width: 150
                        model: ["verbose", "debug", "info", "warn", "error"]
                        onPicked: (index, value) => backend.setLoglevel(value)
                    }
                }
                NeonButton { text: "热重载配置"; iconSource: "../assets/ic_reload.svg"; width: (parent.width - 150 - Theme.u3 * 2) / 2; anchors.bottom: parent.bottom; onClicked: backend.triggerReload() }
                NeonButton { text: "同步时间"; iconSource: "../assets/ic_time.svg"; width: (parent.width - 150 - Theme.u3 * 2) / 2; anchors.bottom: parent.bottom; onClicked: backend.syncTime() }
            }
            /* ---- 本机名片头像（连接时自动从设备载入） ---- */
            SectionHead { zh: "本机头像"; en: "CARD AVATAR" }
            GlassPanel {
                width: parent.width
                height: 148
                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.u3
                    spacing: Theme.u4
                    Rectangle {
                        width: 120
                        height: 120
                        color: Theme.aWhite03
                        border.color: Theme.aWhite08
                        border.width: 1
                        Image {
                            anchors.fill: parent
                            anchors.margins: Theme.u1
                            source: selfAvUrl
                            fillMode: Image.PreserveAspectFit
                            sourceSize { width: 112; height: 112 }
                            onStatusChanged: if (status === Image.Error)
                                console.warn("头像加载失败:", String(selfAvUrl))
                        }
                        Text {
                            visible: selfAvUrl === ""
                            anchors.centerIn: parent
                            text: "未选择图片"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                        }
                    }
                    Column {
                        width: parent.width - 120 - Theme.u4 * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.u2
                        Text {
                            width: parent.width
                            text: "64×64 RGB565，黑边补齐；发卡时随名片发送。连接设备时会自动从设备载入"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                            wrapMode: Text.Wrap
                        }
                        NeonButton {
                            width: parent.width
                            height: 32
                            text: "选择图片…"
                            iconSource: "../assets/ic_folder_open.svg"
                            onClicked: selfAvDialog.open()
                        }
                        NeonButton {
                            width: parent.width
                            height: 32
                            text: "上传头像"
                            iconSource: "../assets/ic_upload.svg"
                            onClicked: {
                                if (selfAvUrl === "") { backend.toast("请先选择图片"); return }
                                backend.uploadSelfAvatar(selectedSelfAvFile)
                            }
                        }
                    }
                }
            }
            }
        }
            /* ---- 企划配置（设备隔离码表 8 格；每格一个企划标识，全部留空 = 全通） ---- */
            SectionHead { zh: "企划配置"; en: "PAIRING CODES" }
            GlassPanel {
                width: parent.width
                height: 246
                Column {
                    width: parent.width
                    spacing: Theme.u3
                    Grid {
                        id: ipGrid
                        width: parent.width
                        columns: 2
                        rowSpacing: Theme.u2
                        columnSpacing: Theme.u2
                        Repeater {
                            id: ipRpt
                            model: 8
                            delegate: Rectangle {
                                id: ipRect
                                property alias inputText: ipInput.text
                                width: (ipGrid.width - Theme.u2) / 2
                                height: 38
                                color: Theme.aWhite03
                                border.color: ipInput.activeFocus ? Theme.primary : Theme.aWhite08
                                border.width: 1
                                clip: true
                                Text {
                                    anchors.fill: parent
                                    anchors.margins: Theme.u2
                                    text: "企划标识 " + (index + 1)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fsSmall
                                    color: Theme.textBody
                                    verticalAlignment: Text.AlignVCenter
                                    visible: ipInput.text === ""
                                }
                                TextInput {
                                    id: ipInput
                                    anchors.fill: parent
                                    anchors.margins: Theme.u2
                                    anchors.rightMargin: ipHint.visible ? 44 + Theme.u2 : Theme.u2
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fsSmall
                                    color: Theme.textPrimary
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                }
                                Text {
                                    id: ipHint
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.u2
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: ipInput.text !== ""
                                    text: ipInput.text !== "" ? ("#" + root.ipCode(ipInput.text)) : ""
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fsMicro
                                    font.bold: true
                                    color: root.ipCode(ipInput.text) ? Theme.primaryHi : Theme.textSecondary
                                }
                            }
                        }
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.u3
                        Row {
                            width: (ipGrid.width - Theme.u2) / 2
                            height: 32
                            spacing: Theme.u2
                            NeonButton {
                                width: (parent.width - Theme.u2) / 2
                                height: parent.height
                                text: "保存到设备"
                                iconSource: "../assets/ic_save.svg"
                                onClicked: {
                                    var items = []
                                    for (var i = 0; i < ipRpt.count; i++) {
                                        var v = ipRpt.itemAt(i).inputText
                                        v = v.replace(/[\x00-\x20\x7f]/g, " ").trim()
                                        if (v !== "") items.push(v)
                                    }
                                    if (items.length > 8) { backend.toast("企划标识过多"); return }
                                    backend.saveIpcfg(items.join("\n"))
                                }
                            }
                            NeonButton {
                                width: (parent.width - Theme.u2) / 2
                                height: parent.height
                                text: "删除配置"
                                iconSource: "../assets/ic_trash.svg"
                                onClicked: backend.deleteIpcfg()
                            }
                        }
                        Text {
                            width: parent.width - (ipGrid.width - Theme.u2) / 2 - Theme.u3
                            height: 32
                            text: "保存：写入设备（≤8 个，双方交集一致才交换）；删除：恢复全通"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                            wrapMode: Text.Wrap
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }

    PageWheel {
        anchors.fill: parent
        outer: pageScroll
        wheels: [ { view: devList }, { view: roleList } ]
    }

    FileDialog {
        id: selfAvDialog
        title: "选择头像图片"
        fileMode: FileDialog.OpenFile
        nameFilters: ["图片 (*.png *.jpg *.jpeg *.bmp *.webp)"]
        onAccepted: {
            root.selfAvUrl = selectedFile
            root.selectedSelfAvFile = selectedFile.toString()
        }
    }
}
