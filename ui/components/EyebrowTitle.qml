/* ============================================================================
 * EyebrowTitle.qml —— 编辑风 Hero 页头
 *
 * 结构：eyebrow 行（橘红短横线呼吸 + mono 大写小字）→ 超大 900 字重标题，
 *       关键词带斜置马克笔底衬（primary，入场 scaleX 划入）。
 * 用法：EyebrowTitle { eyebrow: "STATUS MONITOR"; title: "状态监控";
 *                       highlight: "监控" }
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Column {
    id: root

    property string eyebrow: ""
    property string title: ""
    /* 标题中需要马克笔底衬的关键词（空 = 无底衬） */
    property string highlight: ""

    spacing: Theme.u2

    /* ---- eyebrow：短横线（呼吸） + mono 大写小字 ---- */
    Row {
        spacing: Theme.u3

        Rectangle {
            width: 34
            height: 3
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.primary

            transform: Scale {
                id: dashScale
                xScale: 1.0
                origin.x: 0
                origin.y: 1.5
            }
            SequentialAnimation {
                loops: Animation.Infinite
                NumberAnimation { target: dashScale; property: "xScale"; to: 1.45; duration: 1300; easing.type: Easing.InOutQuad }
                NumberAnimation { target: dashScale; property: "xScale"; to: 1.0; duration: 1300; easing.type: Easing.InOutQuad }
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.eyebrow.toUpperCase()
            font.family: Theme.fontMono
            font.pixelSize: Theme.fsMono
            font.letterSpacing: 1.6
            color: Theme.textBody
        }
    }

    /* ---- 大标题 + 马克笔底衬 ---- */
    Item {
        width: Math.max(titleText.implicitWidth, highlightText.implicitWidth)
        height: titleText.implicitHeight

        Text {
            id: titleText
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: root.title
            font.family: Theme.fontFamily
            font.pixelSize: 40
            font.weight: Font.Black
            font.letterSpacing: -1.5
            color: Theme.textPrimary
        }

        /* 斜置底衬（贴在关键词下方，rotate -1deg，入场划入） */
        Rectangle {
            id: marker
            visible: root.highlight !== "" && highlightText.width > 0
            x: highlightText.x
            width: highlightText.width
            height: 9
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            transform: Rotation { origin.x: 0; origin.y: marker.height / 2; angle: -1.2 }
            color: Theme.aOrange50
            transformOrigin: Item.Left

            scale: 0
            NumberAnimation on scale {
                from: 0; to: 1
                duration: 700
                easing.type: Easing.OutCubic
                running: marker.visible
            }
        }

        /* 关键词文本仅用于测量底衬位置（隐形） */
        Text {
            id: highlightText
            visible: false
            text: root.highlight
            font.family: titleText.font.family
            font.pixelSize: titleText.font.pixelSize
            font.weight: titleText.font.weight
            font.letterSpacing: titleText.font.letterSpacing
        }
    }
}
