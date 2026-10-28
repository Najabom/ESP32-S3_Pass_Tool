/* ============================================================================
 * GlowNavRail.qml —— 左侧导航栏（phase-btn 编辑风）
 *
 * 旋转环 brand-mark + PASSDECK / mono 副标 + phase-btn 风格菜单：
 *   直角边框卡、名称 + 右侧 mono 编号（01/02/03/04）、
 *   active = primary 实心黑字，hover = 上浮 + 边框亮 + 箭头右移。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Rectangle {
    id: root

    /* ---- 对外属性 ---- */
    property int currentIndex: 0
    signal navRequested(int index)

    /* ---- 外观：半透明深底（毛玻璃层叠） + 右侧细分割线 ---- */
    width: Theme.navWidth
    color: Theme.aWhite03
    border.color: Theme.aWhite08
    border.width: 1

    /* ---- Logo 区：旋转环 brand-mark + 双行字 ---- */
    Item {
        id: logoZone
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.titleBarH + Theme.u3
        anchors.topMargin: Theme.u2

        /* 自转圆环 + 角部小方块 */
        Item {
            id: brandMark
            anchors.left: parent.left
            anchors.leftMargin: Theme.u5
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26

            Rectangle {
                anchors.centerIn: parent
                width: 18
                height: 18
                radius: 9
                color: "transparent"
                border.color: Theme.textPrimary
                border.width: 2

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 10000
                    loops: Animation.Infinite
                }
            }
            Rectangle {
                x: 17
                y: 17
                width: 8
                height: 8
                color: Theme.primary
                border.color: Theme.textPrimary
                border.width: 1
            }
        }

        Column {
            anchors.left: brandMark.right
            anchors.leftMargin: Theme.u3
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                text: "PASSDECK"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fsBody
                font.bold: true
                font.letterSpacing: 1.5
                color: Theme.textPrimary
            }
            Text {
                text: "PASS CONSOLE"
                font.family: Theme.fontMono
                font.pixelSize: 9
                font.letterSpacing: 2
                color: Theme.primaryHi
            }
        }
    }

    /* ---- 顶部细分割线 ---- */
    Rectangle {
        anchors.top: logoZone.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.aWhite06
    }

    /* ---- 菜单项模型 ---- */
    property var items: [
        { label: "状态监控", icon: "ic_status" },
        { label: "设备连接", icon: "ic_device" },
        { label: "文件制作", icon: "ic_tools" },
        { label: "文件传输", icon: "ic_transfer" },
        { label: "名片记录", icon: "ic_cards" },
        { label: "关于", icon: "ic_about" }
    ]

    Column {
        id: menuCol
        anchors.top: logoZone.bottom
        anchors.topMargin: Theme.u4
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Theme.u2

        Repeater {
            model: root.items.length
            delegate: Rectangle {
                id: itemBox
                width: menuCol.width - Theme.u4 * 2
                height: 52
                x: Theme.u4
                clip: true

                property int idx: index
                readonly property bool active: idx === root.currentIndex

                color: active ? Theme.primary : (mArea.containsMouse ? Theme.aWhite05 : Theme.aWhite03)
                border.color: active ? Theme.primary : (mArea.containsMouse ? Theme.aWhite12 : Theme.aWhite08)
                border.width: 1

                Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }

                /* hover 微上浮 */
                transform: Translate {
                    y: mArea.containsMouse && !itemBox.active ? -2 : 0
                    Behavior on y { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                }

                /* 图标（三态：灰 / hover 橘 / 激活黑——实心底上须深色） */
                Image {
                    id: itemIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.u4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18
                    source: "../assets/" + root.items[idx].icon
                            + (itemBox.active ? "_b.svg"
                               : (mArea.containsMouse ? "_hi.svg" : ".svg"))
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                /* 名称 */
                Text {
                    anchors.left: itemIcon.right
                    anchors.leftMargin: Theme.u3
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.items[idx].label
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsBody
                    font.bold: itemBox.active
                    color: itemBox.active ? "#0A0A0A"
                         : (mArea.containsMouse ? Theme.textPrimary : Theme.textSecondary)
                    Behavior on color { ColorAnimation { duration: Theme.durFast } }
                }

                /* 右侧 mono 编号 + 箭头 */
                Text {
                    id: numText
                    anchors.right: arrow.left
                    anchors.rightMargin: Theme.u2
                    anchors.verticalCenter: parent.verticalCenter
                    text: "0" + (idx + 1)
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fsMono
                    font.letterSpacing: 1.5
                    color: itemBox.active ? "#0A0A0A" : Theme.textBody
                    opacity: itemBox.active ? 0.62 : 0.8
                }
                Text {
                    id: arrow
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.u3
                    anchors.verticalCenter: parent.verticalCenter
                    text: itemBox.active ? "●" : "→"
                    font.pixelSize: 13
                    color: itemBox.active ? "#0A0A0A" : Theme.primaryHi

                    transform: Translate {
                        x: mArea.containsMouse && !itemBox.active ? 4 : 0
                        Behavior on x { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
                    }
                }

                /* 悬停 + 点击 */
                MouseArea {
                    id: mArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (idx !== root.currentIndex)
                            root.navRequested(idx)
                    }
                }
            }
        }
    }

    /* ---- 底部版本水印（mono） ---- */
    Text {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Theme.u4
        anchors.horizontalCenter: parent.horizontalCenter
        text: "V0.9.2 · BLE LINK"
        font.family: Theme.fontMono
        font.pixelSize: Theme.fsMono
        font.letterSpacing: 1.2
        color: Theme.textBody
        opacity: 0.7
    }
}
