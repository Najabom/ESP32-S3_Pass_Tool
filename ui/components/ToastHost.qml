/* ============================================================================
 * ToastHost.qml —— 右上角轻提示堆叠（工业红橘）
 *
 * 用法（main.qml 挂顶层）：
 *   ToastHost { id: toastHost }
 *   toastHost.show("消息")          // 普通提示
 *   toastHost.show("错误", true)    // 错误样式（红）
 *
 * 行为：直角半透明卡片 + 橘红左条；滑入 → 停留 2.6s → 淡出销毁；
 *      堆叠向下生长，底部触到窗口底边时整列自动向上滚动（顶部条目顺滑
 *      滚出可视区，不被清除），始终让最新一条可见；条目到期/点击关闭后
 *      余下列自动上移补位。顶部让开标题栏（titleBarH 下方）。
 * ==========================================================================*/
import QtQuick 2.15
import Theme 1.0

Item {
    id: root

    anchors.top: parent.top
    anchors.topMargin: Theme.titleBarH + 26 + Theme.u4   /* 标题栏 + ticker 高度，不遮挡横幅 */
    anchors.right: parent.right
    anchors.rightMargin: Theme.u5
    width: 380
    height: col.height
    z: 100
    clip: true                                   /* 滚出顶部时在边缘裁切，不压标题栏 */

    /* 触底后的整列上滚位移（0=贴顶原样，负值=上滚）；由 yRoll 平滑驱动 */
    property real yShift: 0

    /* 视口可用高度（ToastHost 所在窗口内容区高度） */
    property real viewH: parent ? parent.height : 600
    onViewHChanged: scheduleAdjust()

    Column {
        id: col
        y: root.yShift
        anchors.right: parent.right
        spacing: Theme.u2
        width: parent.width
        height: implicitHeight
        /* 高度后续变化（增删/文字换行结算）→ 帧末重新贴合 */
        onHeightChanged: root.scheduleAdjust()
    }

    /* 触底判定/上滚：内容底端越过窗口底边时，把整列上移 clamp 到恰好贴底 */
    function adjustY() {
        var limit = viewH - root.anchors.topMargin - Theme.u5      /* 底边留白 */
        var over = col.height - limit
        var target = over <= 0 ? 0 : -over
        if (Math.abs(target - yRoll.to) > 0.5 || !yRoll.running) {
            yRoll.to = target
            yRoll.restart()
        }
    }

    /* 帧末贴合：Column 高度在布局后才结算，连发多条时统一到下一帧重算 */
    function scheduleAdjust() {
        Qt.callLater(adjustY)
    }

    NumberAnimation {
        id: yRoll
        target: root
        property: "yShift"
        duration: 240
        easing.type: Easing.OutCubic
    }

    /* 旧名 relayout（ToastItem 销毁回调），语义=重新贴合 */
    function relayout() {
        scheduleAdjust()
    }

    function show(msg, isError, ms) {
        var comp = Qt.createComponent("ToastItem.qml")
        if (comp.status !== Component.Ready) {
            console.warn("[Toast] create failed:", comp.errorString())
            return
        }
        var item = comp.createObject(col, {
            message: msg,
            errorStyle: !!isError,
            lifetimeMs: (ms && ms > 0) ? ms : 2600,
            host: root
        })
        item.settled = true          /* 首帧已就位，之后位移全部动画化 */
        item.enter()
        scheduleAdjust()             /* 若已触底则整列自动上滚 */
    }
}
