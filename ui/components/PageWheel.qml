/* ============================================================================
 * PageWheel.qml —— 页级滚轮平滑与滚动链控制
 *
 * 用法（页根内最后一个子项，铺满页面，z 高于内容即可）：
 *   PageWheel {
 *       anchors.fill: parent
 *       outer: pageScroll                  // 页面级 Flickable/ListView（无则 null）
 *       wheels: [ { view: devList }, ... ] // 页面内的可滚子项（ListView/Flickable）
 *   }
 *
 * 行为（物理模型，速度脉冲 + 摩擦衰减）：
 *   1) 滚轮一律由本层接管（MouseArea acceptedButtons: Qt.NoButton，不抢点击/悬停）。
 *      鼠标一格滚轮 → 给该视图累加一个速度冲量；此后每 16ms 积分位移并按
 *      摩擦系数衰减，直到低于阈值停表。连续滚动时冲量叠加 ⇒ 快滚加速连贯、
 *      慢滚单格以衰减滑行收尾 —— 不存在"逐格一段动画"的顿挫感。
 *   2) 命中路由：指针落在某个内层可滚项上 → 只滚它，并在其到达边界后仍消费事件，
 *      绝不再把滚动带给整页（"滑到底把页面一起带走" 即此修复）。
 *   3) 指针不在任何内层项上 → 滚外层页面；无可滚外层则忽略。
 *
 * 触控板 pixelDelta → 逐像素直跟（煞停惯性后移动，无动画，天然平滑）。
 *
 * 注：Qt Quick Controls 的 Popup 渲染在窗口 overlay 层（高于页内容），
 * 下拉列表等弹出层不受本层影响，滚轮由 Popup 自身原生处理。
 * ==========================================================================*/
import QtQuick 2.15

Item {
    id: pw

    property Item outer: null            // 页面级可滚容器（null = 无整页滚动）
    property var wheels: []              // [{ view: Flickable|ListView }, ...]
    property real notchImpulse: 1.30     // 一格产生的初始速度（px/ms）
    property real friction: 0.017        // 每 ms 摩擦（指数衰减系数）：单格滑行约 76px/190ms
    property real maxVel: 3.0            // 速度上限（px/ms），快滚也保持可控（每帧最大 ~48px）

    // 内部：视图注册表（平行数组）
    property var _views: []
    property var _vels: []               // 当前速度 px/ms（>0 向下）
    property bool _ticking: false

    function _regFor(v) {
        var idx = pw._views.indexOf(v)
        if (idx >= 0) return idx
        pw._views.push(v)
        pw._vels.push(0)
        return pw._views.length - 1
    }

    function _maxY(v) {
        return Math.max(0, v.contentHeight - v.height)
    }

    function _kick(v, impulse) {
        var idx = pw._regFor(v)
        var cur = pw._vels[idx]
        var nv = cur + impulse
        // 方向反转（含从静止起步）必须即时生效，不被摩擦拖滞
        if ((cur > 0.001 && nv < -0.001) || (cur < -0.001 && nv > 0.001)) nv = impulse
        if (nv > pw.maxVel) nv = pw.maxVel
        else if (nv < -pw.maxVel) nv = -pw.maxVel
        pw._vels[idx] = nv
        if (!pw._ticking) {
            pw._ticking = true
            phyTimer.start()
        }
    }

    /* 命中路由：true = 已消费 */
    function _route(x, y, impulse) {
        for (var i = 0; i < pw.wheels.length; i++) {
            var v = pw.wheels[i].view
            if (!v || !v.visible) continue
            var p = v.mapFromItem(pw, x, y)
            if (p.x >= 0 && p.y >= 0 && p.x <= v.width && p.y <= v.height) {
                pw._kick(v, impulse)
                return true
            }
        }
        if (pw.outer && pw.outer.visible) {
            pw._kick(pw.outer, impulse)
            return true
        }
        return false
    }

    function _impulse(pixelDelta, angleDelta) {
        if (pixelDelta.y !== 0) return 0     // 触控板走直跟路径
        if (angleDelta.y === 0) return 0
        return -angleDelta.y / 120 * pw.notchImpulse   // 负角度=向下滚动
    }

    Timer {
        id: phyTimer
        interval: 16
        repeat: true
        onTriggered: {
            var any = false
            var dt = 16
            var decay = Math.exp(-pw.friction * dt)
            for (var i = pw._views.length - 1; i >= 0; i--) {
                var v = pw._views[i]
                if (!v) { pw._views.splice(i, 1); pw._vels.splice(i, 1); continue }
                var vel = pw._vels[i]
                if (vel === 0) continue
                var next = v.contentY + vel * dt
                var maxY = pw._maxY(v)
                if (next <= 0) {
                    v.contentY = 0
                    pw._vels[i] = 0
                } else if (next >= maxY) {
                    v.contentY = maxY
                    pw._vels[i] = 0
                } else {
                    v.contentY = next
                    pw._vels[i] = vel * decay
                    if (Math.abs(pw._vels[i]) < 0.02) pw._vels[i] = 0
                    else any = true
                }
            }
            if (!any) {
                pw._ticking = false
                phyTimer.stop()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: (event) => {
            if (event.pixelDelta.y !== 0) {
                // 触控板：直跟（煞停惯性后移动），命中规则同滚轮
                var hit = false
                for (var i = 0; i < pw.wheels.length; i++) {
                    var v = pw.wheels[i].view
                    if (!v || !v.visible) continue
                    var p = v.mapFromItem(pw, event.x, event.y)
                    if (p.x >= 0 && p.y >= 0 && p.x <= v.width && p.y <= v.height) {
                        pw._vels[i] = 0
                        v.contentY = Math.max(0, Math.min(pw._maxY(v), v.contentY - event.pixelDelta.y))
                        hit = true
                        break
                    }
                }
                if (!hit && pw.outer && pw.outer.visible) {
                    var oi = pw._regFor(pw.outer)
                    pw._vels[oi] = 0
                    pw.outer.contentY = Math.max(0, Math.min(pw._maxY(pw.outer), pw.outer.contentY - event.pixelDelta.y))
                }
            } else {
                var imp = pw._impulse(event.pixelDelta, event.angleDelta)
                if (imp !== 0) pw._route(event.x, event.y, imp)
            }
            event.accepted = true
        }
    }
}
