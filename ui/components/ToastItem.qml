/* ============================================================================
 * ToastItem.qml —— 单条 Toast（由 ToastHost 动态创建，勿直接使用）
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Rectangle {
    id: root

    property string message: ""
    property bool errorStyle: false
    property var host: null
    property bool dropping: false          /* 已被挤旧/手动关闭，退场中 */
    property bool settled: false           /* 首帧就位后开启 Behavior（防初始定位被动画化） */
    property int lifetimeMs: 2600          /* 停留时长：生命底线跑完即退场 */

    width: parent ? parent.width : 380
    height: msgText.implicitHeight + Theme.u5 * 2
    color: "#E6121212"
    border.color: errorStyle ? Theme.red : Theme.aWhite12
    border.width: 1
    opacity: 0
    x: Theme.u5
    z: 100

    /* 被挤出槽位（触底上滚 / 手动关闭）时平滑移动到新位置 */
    Behavior on y {
        enabled: root.settled
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    /* 左侧色条：普通橘红 / 错误红 */
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        color: root.errorStyle ? Theme.red : Theme.primary
    }

    Text {
        id: msgText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Theme.u4
        anchors.verticalCenter: parent.verticalCenter
        text: root.message
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fsBody
        color: Theme.textPrimary
        wrapMode: Text.WrapAnywhere
    }

    /* 进度底线（剩余停留时间） */
    Rectangle {
        id: lifeLine
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        height: 2
        width: root.width
        color: root.errorStyle ? Theme.red : Theme.primary
        opacity: 0.8
    }

    /* 入场：滑入淡入 → 启动生命周期动画 */
    SequentialAnimation {
        id: enterAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1; duration: Theme.durFast;
                easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "x"; to: 0; duration: Theme.durFast;
                easing.type: Easing.OutCubic }
        }
        ScriptAction { script: lifeAnim.restart() }
    }

    /* 生命周期：底线收缩 lifetimeMs → 滑出淡出 → 销毁 */
    SequentialAnimation {
        id: lifeAnim
        NumberAnimation { target: lifeLine; property: "width"; from: root.width; to: 0;
            duration: root.lifetimeMs; easing.type: Easing.Linear }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 0; duration: Theme.durStd;
                easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "x"; to: Theme.u5 * 2; duration: Theme.durStd;
                easing.type: Easing.InCubic }
        }
        ScriptAction { script: root.destroy() }
    }

    /* 点击关闭：快速淡出销毁 */
    SequentialAnimation {
        id: fadeOutAnim
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: Theme.durFast;
            easing.type: Easing.OutCubic }
        ScriptAction { script: root.destroy() }
    }

    function enter() {
        lifeAnim.stop()
        fadeOutAnim.stop()
        enterAnim.restart()
    }

    function dismiss() {
        if (root.dropping) return
        root.dropping = true
        enterAnim.stop()
        lifeAnim.stop()
        fadeOutAnim.restart()
    }

    /* 销毁后通知宿主重排（剩余条目自动平滑上滚） */
    Component.onDestruction: {
        if (host)
            host.relayout()
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.dismiss()
    }
}
