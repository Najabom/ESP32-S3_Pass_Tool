/* ============================================================================
 * AboutPage.qml —— 关于页（版本 / 用途）
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0
import "../components"

Item {
    Column {
        anchors.fill: parent
        spacing: Theme.u5

        GlassPanel {
            width: parent.width
            height: 170
            Row {
                anchors.fill: parent
                anchors.margins: Theme.u5
                spacing: Theme.u5
                Image {
                    source: "../assets/logo.svg"
                    sourceSize.width: 84
                    sourceSize.height: 84
                    anchors.verticalCenter: parent.verticalCenter
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.u2
                    Text {
                        text: "PassDeck 通行证控制台 V1.0"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsTitle
                        font.bold: true
                        color: Theme.textPrimary
                    }
                    Text {
                        text: "ESP32 桌面通行证设备的 PC 端蓝牙管理工具"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsSmall
                        color: Theme.textSecondary
                    }
                    Text {
                        text: "扫描 · 连接 · 素材传输 · 配置热重载 · 名片编辑"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.textBody
                    }
                    Text {
                        text: "PySide6 / QML · bleak BLE · 工业红橘设计语言"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fsMicro
                        color: Theme.primary
                        opacity: 0.9
                    }
                }
            }
        }

        GlassPanel {
            width: parent.width
            height: 150
            Column {
                anchors.fill: parent
                anchors.margins: Theme.u5
                spacing: Theme.u3
                Text {
                    text: "使用提示"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsBody
                    font.bold: true
                    color: Theme.primaryHi
                }
                Text {
                    text: "· 设备上电后自动广播（识别码匹配的通行证设备），「设备连接」页扫描即可发现\n" +
                          "· 上传前请确认目标角色与文件名——覆盖 loop.mjpeg 会立即改变设备显示\n" +
                          "· Windows 原生蓝牙配对后几秒自动断开属正常行为，请始终使用本工具连接"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fsSmall
                    color: Theme.textSecondary
                    lineHeight: 1.6
                }
            }
        }
    }
}
