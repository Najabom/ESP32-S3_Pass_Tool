/* ============================================================================
 * LogConsole.qml —— 底部日志台（收起 30px 状态条 / 展开抽屉，分级着色）
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Controls 2.15
import Theme 1.0

Rectangle {
    id: root

    /* ---- 对外 ---- */
    function append(level, text) {
        var c = level === "error" ? Theme.red
              : level === "warn" ? Theme.warn
              : Theme.textSecondary
        listModel.append({ lvl: level, txt: text, clr: c.toString() })
        if (listModel.count > 300)
            listModel.remove(0)
        lastText = text
        lastColor = c
        if (expanded)
            listView.positionViewAtEnd()
    }

    property bool expanded: false
    property string lastText: "就绪"
    property color lastColor: Theme.textBody

    color: "#E60D0D0D"
    border.color: Theme.aWhite08
    height: expanded ? 200 : 30
    Behavior on height {
        NumberAnimation {
            duration: Theme.durStd
            easing.type: Easing.OutCubic
        }
    }
    clip: true

    /* ---- 收起态：最近一条 ---- */
    Item {
        width: parent.width
        height: 30
        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.u4
            anchors.verticalCenter: parent.verticalCenter
            text: "LOG · RUNTIME"
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMicro
            font.letterSpacing: 1.2
            font.bold: true
            color: Theme.primary
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 150   /* 让位 LOG · RUNTIME 标签 */
            anchors.right: expandHint.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.lastText
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMicro
            color: root.lastColor
            elide: Text.ElideRight
        }
        Text {
            id: expandHint
            anchors.right: parent.right
            anchors.rightMargin: Theme.u3
            anchors.verticalCenter: parent.verticalCenter
            text: expanded ? "▼" : "▲"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            color: Theme.textSecondary
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: expanded = !expanded
        }
    }

    /* ---- 展开态：日志列表 ---- */
    ListView {
        id: listView
        anchors.top: parent.top
        anchors.topMargin: 30
        anchors.fill: parent
        anchors.margins: 0
        clip: true
        model: ListModel { id: listModel }
        delegate: Item {
            width: listView.width
            height: 18
            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.u4
                anchors.verticalCenter: parent.verticalCenter
                text: "[" + lvl + "] " + txt
                font.family: Theme.fontMono
                font.pixelSize: Theme.fsMicro
                color: clr
                elide: Text.ElideRight
                width: parent.width - Theme.u6
            }
        }
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    }
}
