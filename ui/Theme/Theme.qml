/* ============================================================================
 * Theme.qml —— 设计令牌单例（Design Tokens）
 *
 * 风格定位："工业红橘" —— 扁平、克制、凌厉、深色科技风
 *   纯黑→炭灰渐变底 + 橘红强调 + 白 alpha 半透明面板（毛玻璃通透层叠）
 *   全直角、1px 细边框、高对比度、数据感。
 *
 * 硬性规则：
 *   - 禁止蓝/紫/青及其衍生色
 *   - 圆角一律 0（全直角）
 *   - 橘红仅用于强调（按钮/激活/进度/关键数据/hover 焦点）
 *   - 发光仅出现在 hover/激活，用半透明橘红描边模拟，克制使用
 * ==========================================================================*/
pragma Singleton
import QtQuick 2.15

QtObject {
    // ================= 背景 =================
    readonly property color bgDeep:         "#0A0A0A"
    readonly property color bgHi:           "#1A1A1A"

    // ================= 主色与状态色 =================
    readonly property color primary:        "#E85D04"
    readonly property color primaryHi:      "#FF6D00"
    readonly property color red:            "#FF3B30"
    readonly property color ok:             "#4CAF50"
    readonly property color warn:           "#FFB454"

    // ================= 灰阶文本 =================
    readonly property color textPrimary:    "#FFFFFF"
    readonly property color textSecondary:  "#CCCCCC"
    readonly property color textBody:       "#888888"

    // ================= 白 alpha 系（半透明面板/边框/分割） =================
    readonly property color aWhite03:       "#08FFFFFF"
    readonly property color aWhite04:       "#0AFFFFFF"
    readonly property color aWhite05:       "#0DFFFFFF"
    readonly property color aWhite06:       "#0FFFFFFF"
    readonly property color aWhite08:       "#14FFFFFF"
    readonly property color aWhite10:       "#1AFFFFFF"
    readonly property color aWhite12:       "#1FFFFFFF"

    // ================= 橘 alpha 系（边框/发光/强调底） =================
    readonly property color aOrange15:      "#26E85D04"
    readonly property color aOrange25:      "#40E85D04"
    readonly property color aOrange35:      "#59E85D04"
    readonly property color aOrange50:      "#80E85D04"

    // ================= 面板（毛玻璃通透层叠） =================
    readonly property color panelFill:      aWhite04
    readonly property color panelFillHi:    aWhite08
    readonly property color panelBorder:    aWhite08
    readonly property color panelBorderHi:  aOrange35
    readonly property color insetFill:      "#0D0D0D"

    // ================= 动效（ease-out 150~300ms） =================
    readonly property int durFast: 150
    readonly property int durStd:  250
    readonly property int durSlow: 300

    // ================= 间距（8px 网格） =================
    readonly property int u1: 4
    readonly property int u2: 8
    readonly property int u3: 12
    readonly property int u4: 16
    readonly property int u5: 24
    readonly property int u6: 32
    readonly property int u7: 48

    // ================= 圆角（全直角，规范硬性规定） =================
    readonly property int rSmall: 0
    readonly property int rMed:   0
    readonly property int rLarge: 0

    // ================= 排版 =================
    /* 字体：单一族名（本环境 Qt Quick 不支持 font.families 复数属性；雅黑含拉丁字形，中英文统一无衬线，
     * 且避免 font.family 逗号栈整串被当作不存在族名导致中文回落宋体） */
    readonly property string fontFamily: "Microsoft YaHei UI"
    /* 等宽字体（工业档案感）：标签/编号/版本/状态/日志/数据刻度专用，配大写+宽字距 */
    readonly property string fontMono: "Consolas"
    readonly property int fsDisplay: 28
    readonly property int fsTitle:   20
    readonly property int fsBody:    14
    readonly property int fsSmall:   12
    readonly property int fsMicro:   11
    readonly property int fsMono:    10

    // ================= 布局 =================
    readonly property int navWidth:   220
    readonly property int titleBarH:  44
}
