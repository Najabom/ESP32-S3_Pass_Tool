/* ============================================================================
 * GlassPanel.qml —— 扁平毛玻璃面板（全站基底卡片）
 *
 * 直角 + 白 alpha 半透明底 + 1px 细边框。可选 hoverable：
 * 悬停上浮 2px + 边框转橘红 + 半透明橘红外描边（克制发光）。
 * 子内容放入 content 插槽。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Item {
    id: root

    /* ---- 对外属性 ---- */
    property color fill: Theme.panelFill
    property color borderColor: Theme.panelBorder
    property bool hoverable: false
    property real glossHeight: 0    // 已废弃（兼容旧引用）
    property bool showSheen: false  // 已废弃
    property bool showGloss: false  // 已废弃

    implicitWidth: 200
    implicitHeight: 120

    /* 悬停上浮 + 微放大（仅 hoverable 卡片；参考站卡片语言） */
    y: hoverArea.containsMouse && hoverable ? -4 : 0
    scale: hoverArea.containsMouse && hoverable ? 1.008 : 1.0
    Behavior on y { NumberAnimation { duration: Theme.durStd; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: Theme.durStd; easing.type: Easing.OutCubic } }

    /* 悬停橘红外描边（克制发光，直角） */
    Rectangle {
        visible: hoverable
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        border.color: Theme.aOrange35
        border.width: 1
        opacity: hoverArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durStd; easing.type: Easing.OutCubic } }
    }

    /* 底部落影（hover 加深，模拟 box-shadow） */
    Rectangle {
        visible: hoverable
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 2
        height: 14
        gradient: Gradient {
            GradientStop { position: 0; color: "#26000000" }
            GradientStop { position: 1; color: "#00000000" }
        }
    }
    Rectangle {
        visible: hoverable
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 2
        height: 20
        opacity: hoverArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durStd; easing.type: Easing.OutCubic } }
        gradient: Gradient {
            GradientStop { position: 0; color: "#4D000000" }
            GradientStop { position: 1; color: "#00000000" }
        }
    }

    /* 面板本体：半透明底 + 1px 边框（直角）
     * 注意：clip 必须关——ComboGlass 等子项的下拉列表要能
     * 溢出面板完整显示；各子项自行用 clip 约束自身边界。 */
    Rectangle {
        id: panelRect
        anchors.fill: parent
        color: root.fill
        border.color: hoverable && hoverArea.containsMouse ? Theme.panelBorderHi : root.borderColor
        border.width: 1
        clip: false

        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }

        /* ---- 内容插槽 ---- */
        Item {
            id: contentItem
            anchors.fill: parent
        }
    }

    default property alias content: contentItem.data

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: hoverable
        acceptedButtons: Qt.NoButton
    }
}
