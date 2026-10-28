/* ============================================================================
 * CardLogPage.qml —— 名片记录（查看设备 SD 卡交换到的名片）
 *
 * 同 MAC 自动合并为一张卡：显示相遇次数 + 每次相遇时间（UTC unix 秒，
 * 按本机时区渲染并标注偏移）。点击 → 个人信息页风格详情弹窗：
 *   立绘大头像 + 姓名/UID/设备名 + 寄语 + 素材图片直显 + 相遇记录列表。
 * 数据源：backend.readCards() → cardsLoaded；readCardMedia(mac12) → cardMediaReady
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Controls 2.15
import Theme 1.0
import "../components"

Item {
    id: root

    property var cards: []           // 按 MAC 合并后的卡片
    property bool loading: false
    property bool devCon: false      // 设备是否已连接（onConnState 维护）
    property string loadingHint: ""
    property var detailCard: null    // 详情弹窗当前名片
    property string detailPortrait: ""  // 弹窗立绘 PNG 路径
    property string detailAvatar: ""    // 弹窗头像 PNG 路径
    property bool mediaLoading: false

    function tzSuffix() {
        var o = -new Date().getTimezoneOffset()
        var sign = o < 0 ? "-" : "+"
        var h = Math.abs(Math.floor(o / 60))
        var m = Math.abs(o) % 60
        return sign + h + (m > 0 ? ":" + (m < 10 ? "0" + m : "" + m) : "")
    }

    function fmtTime(up, withTz) {
        if (!up || up <= 0) return "—"
        // 设备端未校准时存储的是相对秒（上电起算 ≤ 数分钟）；PC 同步时间后是真实
        // unix 秒（约 1.7e9）。用阈值 1e9 区分：低于则视为未校准，显示相对 HH:MM:SS。
        if (up < 1e9) {
            var hh = Math.floor(up / 3600), mm = Math.floor(up % 3600 / 60), ss = up % 60
            function p2(n) { return n < 10 ? "0" + n : "" + n }
            return "上电后 " + (hh > 0 ? hh + ":" : "") + p2(mm) + ":" + p2(ss) + "（未校准）"
        }
        var d = new Date(up * 1000)
        function p(n) { return n < 10 ? "0" + n : "" + n }
        var s = d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
             + " " + p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds())
        if (withTz) s += " UTC" + root.tzSuffix()
        return s
    }

    /* 按 MAC 合并（保留每次相遇时间），按最近相遇降序 */
    function groupCards(list) {
        var map = {}
        for (var i = 0; i < list.length; i++) {
            var c = list[i]
            var k = String(c.mac || "")
            if (k === "") continue
            if (!map[k]) {
                map[k] = { mac: k, count: 1, meets: [c],
                           seq: c.seq, up: c.up, uname: c.uname, name: c.name,
                           uid: c.uid, motto: c.motto,
                           avatar: c.avatar, portrait: c.portrait, stk: c.stk }
            } else {
                map[k].count++
                map[k].meets.push(c)
                map[k].up = c.up
                map[k].seq = c.seq
                if (c.ip) map[k].ip = c.ip
            }
        }
        var out = []
        for (var m in map) out.push(map[m])
        out.sort(function (a, b) { return b.up - a.up })
        return out
    }

    function mac12(c) {
        return String(c.mac || "").replace(/:/g, "").toLowerCase()
    }

    function openDetail(c) {
        root.detailCard = c
        root.detailPortrait = ""
        root.detailAvatar = ""
        root.mediaLoading = true
        backend.readCardMedia(root.mac12(c))
        detailPopup.open()
    }

    /* 自动刷新：切到本页时 + 设备连接成功时 */
    function doRefresh() {
        if (root.loading) return
        if (!root.devCon) {
            root.loadingHint = "未连接设备"
            return
        }
        root.loading = true
        root.loadingHint = "正在读取设备名片记录…"
        backend.readCards()
    }

    onVisibleChanged: {
        if (root.visible) root.doRefresh()
    }

    Connections {
        target: backend
        function onCardsLoaded(cards) {
            root.cards = root.groupCards(cards)
            root.loading = false
            root.loadingHint = cards.length === 0 ? "暂无名片记录（设备未收到过名片交换）" : ""
        }
        function onCardsFailed(err) {
            root.loading = false
            root.loadingHint = "名片读取失败：" + err + "（可稍后重试）"
        }
        function onCardMediaReady(mac, pp, ap) {
            if (!root.detailCard || root.mac12(root.detailCard) !== mac) return
            root.detailPortrait = pp
            root.detailAvatar = ap
            root.mediaLoading = false
        }
        function onConnState(ok, info) {
            root.devCon = ok
            if (ok) root.doRefresh()
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: Theme.u4
        spacing: Theme.u4

        /* 工具栏：刷新按钮 + 计数 */
        Row {
            width: parent.width
            spacing: Theme.u3
            NeonButton {
                text: "刷新记录"
                active: true
                iconSource: "../assets/ic_refresh_w.svg"
                onClicked: root.doRefresh()
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.loading ? root.loadingHint
                     : (root.cards.length > 0 ? "共 " + root.cards.length + " 位联系人" : root.loadingHint)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsSmall
                color: Theme.textBody
            }
        }

        /* 联系人列表（合并视图） */
        Rectangle {
            width: parent.width
            height: parent.height - 52
            color: Theme.aWhite03
            border.color: Theme.aWhite08
            border.width: 1
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Theme.u2
                clip: true
                model: root.cards
                spacing: Theme.u2

                ScrollBar.vertical: ScrollBar {
                    width: 6
                    policy: ScrollBar.AsNeeded
                }

                delegate: Rectangle {
                    width: list.width - Theme.u3
                    height: 76
                    color: idx % 2 === 0 ? Theme.aWhite03 : Theme.aWhite05
                    border.color: hoverM.containsMouse ? Theme.aOrange35 : Theme.aWhite08
                    border.width: 1
                    property int idx: index

                    Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

                    MouseArea {
                        id: hoverM
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openDetail(modelData)
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.u3
                        anchors.verticalCenter: parent.verticalCenter
                        text: "›"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsTitle
                        color: hoverM.containsMouse ? Theme.primaryHi : Theme.textBody
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.u3
                        spacing: Theme.u1
                        Row {
                            width: parent.width
                            spacing: Theme.u2
                            Text {
                                text: "相遇 ×" + modelData.count
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: Theme.primaryHi
                                font.bold: true
                            }
                            Text {
                                text: root.fmtTime(modelData.up)
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textBody
                            }
                            Text {
                                text: modelData.mac
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textSecondary
                            }
                        }
                        Text {
                            width: parent.width
                            text: (modelData.uname ? modelData.uname : "—")
                                + "  ·  " + (modelData.name ? modelData.name : "—")
                                + "  ·  UID " + (modelData.uid ? modelData.uid : "—")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsSmall
                            font.bold: true
                            color: Theme.textPrimary
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: "寄语: " + (modelData.motto ? modelData.motto : "—")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                            elide: Text.ElideRight
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: list.count === 0
                    text: root.loading ? "正在读取…" : "暂无名片记录"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsBody
                    color: Theme.textBody
                }
            }
        }
    }

    /* ---- 名片详情弹窗（个人信息页风格） ---- */
    Popup {
        id: detailPopup
        parent: Overlay.overlay
        visible: root.detailCard !== null
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 460
        height: 580
        modal: true
        focus: true
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        onClosed: root.detailCard = null

        background: Rectangle {
            color: "#FA141414"
            border.color: Theme.primary
            border.width: 1
            radius: 0
        }

        contentItem: Column {
            anchors.fill: parent
            anchors.margins: Theme.u5
            spacing: Theme.u3

            /* 头部：立绘 + 姓名信息 */
            Row {
                width: parent.width
                height: 128
                spacing: Theme.u4

                Rectangle {
                    width: 128
                    height: 128
                    color: Theme.aWhite05
                    border.color: Theme.aWhite08
                    border.width: 1

                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: root.detailPortrait !== "" ? String(root.detailPortrait) : ""
                        fillMode: Image.PreserveAspectFit
                        cache: false
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.detailPortrait === ""
                        text: root.mediaLoading ? "…" : "无立绘"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                    }
                }

                Column {
                    width: parent.width - 128 - Theme.u4
                    height: 128
                    spacing: Theme.u2

                    Text {
                        width: parent.width
                        text: root.detailCard
                              ? (root.detailCard.uname ? root.detailCard.uname : "未知")
                                + " · " + (root.detailCard.name ? root.detailCard.name : "—")
                              : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsTitle
                        font.bold: true
                        color: Theme.textPrimary
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: "UID  " + (root.detailCard ? (root.detailCard.uid || "—") : "")
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsSmall
                        color: Theme.primaryHi
                    }

                    Text {
                        width: parent.width
                        text: root.detailCard ? root.detailCard.mac : ""
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                    }

                    Text {
                        width: parent.width
                        text: root.detailCard
                              ? ("相遇 " + root.detailCard.count + " 次 · 最近 " + root.fmtTime(root.detailCard.up, true))
                              : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                        elide: Text.ElideRight
                    }
                }
            }

            /* 寄语 */
            Rectangle {
                width: parent.width
                height: 46
                color: Theme.aWhite03
                border.color: Theme.aWhite08
                border.width: 1

                Text {
                    anchors.fill: parent
                    anchors.margins: Theme.u3
                    text: "「" + (root.detailCard && root.detailCard.motto
                                 ? root.detailCard.motto : "这个人很懒，什么都没写") + "」"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsSmall
                    color: Theme.textSecondary
                    verticalAlignment: Text.AlignVCenter
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                }
            }

            /* 素材区：图片直显 */
            Item {
                width: parent.width
                height: 110

                Item {
                    width: parent.width
                    height: 14

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
                        text: "素材 · MEDIA"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textSecondary
                    }
                }

                Row {
                    anchors.top: parent.top
                    anchors.topMargin: 20
                    anchors.left: parent.left
                    spacing: Theme.u3

                    Column {
                        spacing: Theme.u1
                        Text {
                            text: "头像"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                        }
                        Rectangle {
                            width: 64
                            height: 64
                            color: Theme.aWhite05
                            border.color: Theme.aWhite08
                            border.width: 1
                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: root.detailAvatar !== ""
                                        ? String(root.detailAvatar) : ""
                                fillMode: Image.PreserveAspectFit
                                cache: false
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: root.detailAvatar === ""
                                text: root.mediaLoading ? "…" : "无"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textBody
                            }
                        }
                    }

                    Column {
                        spacing: Theme.u1
                        Text {
                            text: "立绘"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fsMicro
                            color: Theme.textBody
                        }
                        Rectangle {
                            width: 64
                            height: 64
                            color: Theme.aWhite05
                            border.color: Theme.aWhite08
                            border.width: 1
                            Image {
                                anchors.fill: parent
                                anchors.margins: 1
                                source: root.detailPortrait !== ""
                                        ? String(root.detailPortrait) : ""
                                fillMode: Image.PreserveAspectFit
                                cache: false
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: root.detailPortrait === ""
                                text: root.mediaLoading ? "…" : "无"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textBody
                            }
                        }
                    }
                }
            }

            /* 相遇记录 */
            Column {
                width: parent.width
                height: 152

                Item {
                    width: parent.width
                    height: 14

                    Rectangle {
                        width: 34
                        height: 3
                        x: 0
                        y: parent.height / 2 - Math.round(height / 2)
                        color: Theme.primary
                    }
                    Text {
                        x: 40
                        y: parent.height / 2 - Math.round(height / 2)
                        text: "相遇记录 · MEETINGS"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textSecondary
                    }
                }

                Rectangle {
                    y: 20
                    width: parent.width
                    height: 128
                    color: Theme.aWhite03
                    border.color: Theme.aWhite08
                    border.width: 1
                    clip: true

                    ListView {
                        id: meetList
                        anchors.fill: parent
                        anchors.margins: Theme.u1
                        model: root.detailCard ? root.detailCard.meets : []
                        spacing: 0

                        ScrollBar.vertical: ScrollBar {
                            width: 4
                            policy: ScrollBar.AsNeeded
                        }

                        delegate: Rectangle {
                            width: meetList.width - Theme.u2
                            height: 26
                            color: mIdx % 2 === 0 ? "transparent" : Theme.aWhite05
                            property int mIdx: index

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.u2
                                anchors.verticalCenter: parent.verticalCenter
                                text: "第 " + (modelData.seq ? "#" + modelData.seq + "  " : "")
                                      + "次 · " + root.fmtTime(modelData.up, true)
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                color: Theme.textSecondary
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.u2
                                anchors.verticalCenter: parent.verticalCenter
                                visible: modelData.ip && modelData.ip !== "0000"
                                text: "企划 " + modelData.ip
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsMicro
                                font.bold: true
                                color: Theme.primaryHi
                            }
                        }
                    }
                }
            }

            /* 底部：关闭 */
            Row {
                width: parent.width
                height: 34
                spacing: Theme.u3

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 90 - Theme.u3
                    text: "时间均为本机时区 (UTC" + root.tzSuffix() + ") · 设备端存储 UTC 时间戳"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMicro
                    color: Theme.textBody
                    elide: Text.ElideRight
                }

                NeonButton {
                    width: 90
                    height: 32
                    text: "关闭"
                    onClicked: detailPopup.close()
                }
            }
        }
    }
    PageWheel {
        anchors.fill: parent
        wheels: [ { view: list } ]
    }

}
