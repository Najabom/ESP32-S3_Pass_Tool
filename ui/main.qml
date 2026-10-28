/* ============================================================================
 * main.qml —— PassDeck 通行证控制台 · 主窗口壳（无边框扁平工业风）
 *
 * 结构：透明无边框窗 → 直角外壳（黑炭渐变背景 FX + 标题栏 + 扁平导航栏
 *      + 内容区 + 边缘缩放）→ Phase 2 起由 PageSwitcher 承载真页面。
 * 拖拽：标题栏 startSystemMove；缩放：8px 边缘 startSystemResize。
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Window 2.15
import Theme 1.0
import "components"
import "pages"

Window {
    id: win
    width: 1200
    height: 750
    minimumWidth: 1080
    minimumHeight: 700
    visible: true
    title: "PassDeck · 通行证控制台"
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowTranslucentBackground
    color: "transparent"

    /* ================= 直角外壳（承载一切） ================= */
    Rectangle {
        id: shell
        anchors.fill: parent
        color: "transparent"
        border.color: Theme.aWhite08
        border.width: 1
        clip: true

        /* ---- 背景特效层 ---- */
        BackgroundFX {
            id: bgFX
            anchors.fill: parent
        }

        /* ---- 标题栏（拖拽区 + 窗口控制，半透明 + 底部分割线） ---- */
        Rectangle {
            id: titleBar
            width: parent.width
            height: Theme.titleBarH
            color: Theme.aWhite03

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Theme.aWhite06
            }

            MouseArea {
                anchors.fill: parent
                onPressed: win.startSystemMove()
            }

            /* 中部：当前页名 */
            Text {
                anchors.centerIn: parent
                text: pageTitle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsSmall
                color: Theme.textBody
            }

            /* 最小化 / 关闭（直角） */
            Rectangle {
                id: btnMin
                anchors.right: btnClose.left
                anchors.rightMargin: Theme.u1
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 28
                color: minHover.containsMouse ? Theme.aWhite08 : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "─"
                    font.family: Theme.fontFamily
                    font.pixelSize: 14
                    color: Theme.textSecondary
                }
                MouseArea {
                    id: minHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: win.showMinimized()
                }
            }
            Rectangle {
                id: btnClose
                anchors.right: parent.right
                anchors.rightMargin: Theme.u2
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 28
                color: closeHover.containsMouse ? "#33FF3B30" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: closeHover.containsMouse ? Theme.red : Theme.textSecondary
                }
                MouseArea {
                    id: closeHover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: win.close()
                }
            }
        }

        /* ---- 左侧玻璃导航栏 ---- */
        GlowNavRail {
            id: nav
            anchors.left: parent.left
            anchors.top: titleBar.bottom
            anchors.bottom: parent.bottom
            currentIndex: navIndex
            onNavRequested: function(index) {
                navIndex = index
                switchPage()
            }
        }

        /* ---- 状态滚动条（ticker 语言：LIVE 实心块 + 无缝循环；内容随连接态切换） ---- */
        TickerBar {
            id: tickerBar
            anchors.left: nav.right
            anchors.leftMargin: 1
            anchors.right: parent.right
            anchors.rightMargin: 1
            anchors.top: titleBar.bottom
            z: 5
            items: devConnected ? [
                "NODE " + devName,
                "FW " + devVersion + " · BLE GATT READY",
                "ESP-NOW NFC STANDBY",
                "MJPG PLAYER ACTIVE"
            ] : [
                "SYSTEM STANDBY",
                "NO DEVICE LINK",
                "ESP-NOW NFC STANDBY",
                "LOCAL SD IDLE"
            ]
        }

        /* ---- 内容区 ---- */
        Item {
            id: contentHost
            anchors.left: nav.right
            anchors.right: parent.right
            anchors.top: tickerBar.bottom
            anchors.bottom: parent.bottom
            anchors.margins: Theme.u5
            anchors.bottomMargin: 38   /* 让位日志台 */

            /* 页面切换层（淡出→换内容→淡入上移） */
            Rectangle {
                id: pageLayer
                anchors.fill: parent
                color: "transparent"
                opacity: 1
                y: 0

                /* 页面 Hero 头（编辑风：eyebrow 横线呼吸 + 巨标题 + 马克笔底衬） */
                EyebrowTitle {
                    id: pageHero
                    anchors.top: parent.top
                    anchors.left: parent.left
                    eyebrow: pageKicker
                    title: pageTitle
                    highlight: pageHighlight
                }
                Text {
                    id: pageSubText
                    anchors.top: pageHero.bottom
                    anchors.topMargin: Theme.u1
                    anchors.left: parent.left
                    text: pageSub
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMicro
                    font.letterSpacing: 0.8
                    color: Theme.textBody
                }

                /* ---- 页面容器（四页常驻，visible 切换） ---- */
                Item {
                    id: pageStack
                    anchors.top: pageSubText.bottom
                    anchors.topMargin: Theme.u4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    StatusPage   { anchors.fill: parent; visible: navIndex === 0 }
                    DevicePage   { anchors.fill: parent; visible: navIndex === 1 }
                    FileMakerPage { anchors.fill: parent; visible: navIndex === 2 }
                    TransferPage { anchors.fill: parent; visible: navIndex === 3 }
                    CardLogPage  { anchors.fill: parent; visible: navIndex === 4 }
                    AboutPage    { anchors.fill: parent; visible: navIndex === 5 }
                }
            }
        }

        /* ---- 底部日志台（收起 30px / 展开抽屉） ---- */
        LogConsole {
            id: logConsole
            anchors.left: nav.right
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            z: 30
        }

        /* ---- 右上角轻提示（顶层） ---- */
        ToastHost {
            id: toastHost
        }
    }

    /* ================= 网格视差（hover 跟踪，不拦截事件） ================= */
    HoverHandler {
        id: parallaxHover
        onPointChanged: {
            if (win.contentItem) {
                bgFX.setPointer(point.position.x / win.width - 0.5,
                                point.position.y / win.height - 0.5)
            }
        }
    }

    /* ================= 边缘缩放（8px） ================= */
    MouseArea { width: 8; height: parent.height; x: 0; y: 0; cursorShape: Qt.SizeHorCursor;
        onPressed: win.startSystemResize(Qt.LeftEdge) }
    MouseArea { width: 8; height: parent.height; x: parent.width - 8; y: 0; cursorShape: Qt.SizeHorCursor;
        onPressed: win.startSystemResize(Qt.RightEdge) }
    MouseArea { width: parent.width; height: 8; x: 0; y: 0; cursorShape: Qt.SizeVerCursor;
        onPressed: win.startSystemResize(Qt.TopEdge) }
    MouseArea { width: parent.width; height: 8; x: 0; y: parent.height - 8; cursorShape: Qt.SizeVerCursor;
        onPressed: win.startSystemResize(Qt.BottomEdge) }
    MouseArea { width: 12; height: 12; x: 0; y: 0; cursorShape: Qt.SizeFDiagCursor;
        onPressed: win.startSystemResize(Qt.LeftEdge | Qt.TopEdge) }
    MouseArea { width: 12; height: 12; x: parent.width - 12; y: 0; cursorShape: Qt.SizeBDiagCursor;
        onPressed: win.startSystemResize(Qt.RightEdge | Qt.TopEdge) }
    MouseArea { width: 12; height: 12; x: 0; y: parent.height - 12; cursorShape: Qt.SizeBDiagCursor;
        onPressed: win.startSystemResize(Qt.LeftEdge | Qt.BottomEdge) }
    MouseArea { width: 12; height: 12; x: parent.width - 12; y: parent.height - 12; cursorShape: Qt.SizeFDiagCursor;
        onPressed: win.startSystemResize(Qt.RightEdge | Qt.BottomEdge) }

    /* ================= 后端信号接线 ================= */
    Connections {
        target: backend
        function onLogMessage(level, text) {
            logConsole.append(level, text)
        }
        function onToastMessage(msg, ms) {
            toastHost.show(msg, false, ms)
        }
        function onConnState(ok, info) {
            devConnected = ok
            if (ok) {
                var sp = info.split(" ")[0] || ""
                devName = sp.toUpperCase()
                var m = info.match(/v([0-9.]+)\)/)
                devVersion = m ? "V" + m[1].toUpperCase() : "—"
            } else {
                devName = ""
                devVersion = "—"
            }
        }
    }

    /* ================= 页面状态 ================= */
    property int navIndex: 0
    property bool devConnected: false
    property string devName: ""
    property string devVersion: "—"
    property string pageTitle: "状态监控"
    property string pageKicker: pageKickers[0]
    property string pageHighlight: pageHighlights[0]
    property string pageSub: "设备实时状态 · 传输速率历史"

    property var pageTitles: ["状态监控", "设备连接", "文件制作", "文件传输", "名片记录", "关于"]
    property var pageKickers: ["STATUS MONITOR", "DEVICE LINK", "FILE MAKER", "FILE TRANSFER", "CARD LOG", "ABOUT"]
    property var pageHighlights: ["监控", "连接", "制作", "传输", "记录", "关于"]
    property var pageSubs: [
        "设备实时状态 · 传输速率历史",
        "扫描并连接通行证设备",
        "ffmpeg 素材转换 · 符合通行证格式",
        "本地素材 ⇄ 设备 SD 卡",
        "设备交换到的名片档案",
        "版本与设计说明"
    ]

    function switchPage() {
        pageTitle = pageTitles[navIndex]
        pageKicker = pageKickers[navIndex]
        pageHighlight = pageHighlights[navIndex]
        pageSub = pageSubs[navIndex]
        /* 快速轻量浮入：单次 y 下沉 → 浮回，透明度全程不变（避免双闪） */
        pageSink.start()
    }

    SequentialAnimation {
        id: pageSink
        NumberAnimation { target: pageLayer; property: "y"; to: 14; duration: 40;
            easing.type: Easing.OutCubic }
        NumberAnimation { target: pageLayer; property: "y"; to: 0; duration: 220;
            easing.type: Easing.OutCubic }
    }
}
