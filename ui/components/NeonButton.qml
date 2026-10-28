/* ============================================================================
 * NeonButton.qml —— 扁平直角按钮（工业红橘）
 *
 * 三态：
 *   默认    透明底 + 1px 白 alpha 边框 + 中灰文字
 *   hover   橘红边框 + 白字 + 半透明橘红外描边（克制发光）
 *   active  橘红实心填充 + 白字（主操作）
 *   danger  红色系（危险操作）
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Rectangle {
    id: root

    /* ---- 对外属性 ---- */
    property string text: ""
    property string iconSource: ""
    property bool active: false          // 主操作：橘红实心
    property bool danger: false          // 危险/错误
    property int iconSize: 16
    property int fontSize: Theme.fsBody

    signal clicked()

    /* ---- 隐式尺寸 ---- */
    implicitWidth: Math.max(96, contentRow.implicitWidth + Theme.u6)
    implicitHeight: 36

    /* ---- 外观（直角扁平） ---- */
    color: {
        if (danger) return mArea.pressed ? "#26FF3B30" : "transparent"
        if (active) return mArea.pressed ? "#C24A03" : (mArea.containsMouse ? Theme.primaryHi : Theme.primary)
        return mArea.pressed ? Theme.aWhite05 : (mArea.containsMouse ? Theme.aWhite08 : "transparent")
    }
    border.width: 1
    border.color: {
        if (danger) return mArea.containsMouse ? Theme.red : "#80FF3B30"
        if (active) return mArea.containsMouse ? Theme.primaryHi : Theme.primary
        return mArea.containsMouse ? Theme.primary : Theme.aWhite10
    }
    clip: true

    Behavior on color { ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }

    /* hover 橘红外描边（克制发光，直角） */
    Rectangle {
        visible: !root.active && !root.danger
        anchors.fill: parent
        anchors.margins: -3
        color: "transparent"
        border.color: Theme.aOrange25
        border.width: 1
        opacity: mArea.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
    }

    /* 斜向 shine 光带（hover 一次性扫过；参考站 shine-sweep 语言） */
    Rectangle {
        id: shine
        visible: false
        width: 36
        height: parent.height * 3
        y: -(parent.height)
        x: -80
        rotation: 18
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: "#00FFFFFF" }
            GradientStop { position: 0.5; color: "#55FFFFFF" }
            GradientStop { position: 1; color: "#00FFFFFF" }
        }
    }
    SequentialAnimation {
        id: shineAnim
        ScriptAction { script: { shine.visible = true } }
        ParallelAnimation {
            NumberAnimation { target: shine; property: "x"; from: -80; to: root.width + 40; duration: 1250; easing.type: Easing.InOutQuad }
            NumberAnimation { target: shine; property: "opacity"; from: 0.9; to: 0.4; duration: 1250 }
        }
        ScriptAction { script: { shine.visible = false; shine.x = -80 } }
    }

    /* ---- 内部布局 ---- */
    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Theme.u2
        Image {
            visible: root.iconSource !== ""
            source: root.iconSource
            width: root.iconSize
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.enabled ? 0.9 : 0.35
        }
        Text {
            text: root.text
            font.family: Theme.fontFamily
            font.pixelSize: root.fontSize
            font.bold: root.active
            color: {
                if (!root.enabled) return Theme.textBody
                if (root.active) return "#FFFFFF"
                if (root.danger) return mArea.containsMouse ? "#FFFFFF" : Theme.red
                return mArea.containsMouse ? Theme.textPrimary : Theme.textSecondary
            }
            Behavior on color { ColorAnimation { duration: Theme.durFast } }
        }
    }

    /* ---- 交互 ---- */
    scale: mArea.pressed ? 0.95 : 1.0     // 按压确认动效（微缩放回弹）
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutCubic } }

    MouseArea {
        id: mArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onEntered: shineAnim.restart()
    }
}
