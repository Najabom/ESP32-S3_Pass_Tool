/* ============================================================================
 * ComboGlass.qml —— 扁平下拉选择器（工业红橘）
 *
 * 弹出列表走 Popup(Overlay.overlay) 全局顶层渲染 —— z 只在同父兄弟间
 * 比较，内嵌展开会被之后声明的兄弟卡片整体盖住（透明感 + 下半截点不到）。
 * 配方与 CropDialog 一致：parent Overlay + mapToItem 定位 + 显式
 * open()/close()（visible 绑定在此环境不可靠）；底部越界自动向上翻。
 * ==========================================================================*/
import QtQuick 2.15
import QtQuick.Controls 2.15
import Theme 1.0

Item {
    id: root

    property var model: []
    property int currentIndex: -1
    property string placeholder: "请选择"
    signal picked(int index, string value)

    implicitWidth: 200
    implicitHeight: 38

    property bool expanded: false

    function openList() {
        const gp = root.mapToItem(Overlay.overlay, 0, 0)
        listPopup.x = gp.x
        const h = Math.min(root.model.length * 28 + Theme.u2, 160)
        if (gp.y + box.height + Theme.u1 + h > Overlay.overlay.height && gp.y > h)
            listPopup.y = gp.y - Theme.u1 - h       /* 底部越界 → 列表向上翻 */
        else
            listPopup.y = gp.y + box.height + Theme.u1
        root.expanded = true
        listPopup.open()
    }

    function closeList() {
        root.expanded = false
        listPopup.close()   // Popup 无 dismiss()，close() 才收起（曾 TypeError 致选中不收起）
    }

    /* ---- 收起态：当前值 ---- */
    Rectangle {
        id: box
        anchors.fill: parent
        color: hoverArea.containsMouse ? "#F20D0D0D" : "#E60D0D0D"
        border.color: expanded ? Theme.primary : (hoverArea.containsMouse ? Theme.aOrange35 : Theme.aWhite08)
        border.width: 1

        Behavior on border.color { ColorAnimation { duration: Theme.durFast; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: Theme.durFast } }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.u3
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentIndex >= 0 && root.currentIndex < root.model.length
                  ? root.model[root.currentIndex] : root.placeholder
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fsSmall
            color: root.currentIndex >= 0 ? Theme.textPrimary : Theme.textBody
            elide: Text.ElideRight
            width: parent.width - Theme.u7
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: Theme.u3
            anchors.verticalCenter: parent.verticalCenter
            text: expanded ? "▲" : "▼"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            color: expanded ? Theme.primaryHi : Theme.textSecondary
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.expanded ? root.closeList() : root.openList()
        }
    }

    /* ---- 展开列表：Overlay 顶层 Popup，任何卡片之上 ---- */
    Popup {
        id: listPopup
        parent: Overlay.overlay
        width: root.width
        height: Math.min(root.model.length * 28 + Theme.u2, 160)
        padding: 1
        modal: false
        closePolicy: Popup.CloseOnPressOutside | Popup.CloseOnEscape
        onClosed: root.expanded = false

        background: Rectangle {
            color: "#141414"
            border.color: Theme.primary
            border.width: 1
        }

        contentItem: ListView {
            clip: true
            model: root.model
            delegate: Item {
                width: ListView.view.width
                height: 28
                property int idx: index
                Rectangle {
                    anchors.fill: parent
                    color: idx === root.currentIndex ? Theme.aOrange15 : "transparent"
                }
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.u3
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsSmall
                    color: idx === root.currentIndex ? Theme.primaryHi : Theme.textSecondary
                    elide: Text.ElideRight
                    width: parent.width - Theme.u5
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.currentIndex = idx
                        root.picked(idx, modelData)
                        root.closeList()
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.aWhite06
                    visible: idx < root.model.length - 1
                }
            }
        }
    }
}
