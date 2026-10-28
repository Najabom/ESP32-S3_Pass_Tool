# DESIGN_SPEC.md —— 工业红橘设计规范

调性：扁平 · 克制 · 凌厉 · 工业感 · 深色科技 · 红黑灰橘点缀 · 半透明通透 · 高对比度 · 数据感

## 1. 配色令牌（Theme/Theme.qml）

| 令牌 | 值 | 用途 |
|---|---|---|
| `bgDeep` / `bgHi` | `#0A0A0A` / `#1A1A1A` | 背景垂直渐变（BackgroundFX） |
| `primary` | `#E85D04` | 主强调：激活态、进度、关键数字、hover 边框 |
| `primaryHi` | `#FF6D00` | hover 提亮档、激活文字 |
| `red` | `#FF3B30` | 危险操作、错误状态 |
| `ok` | `#4CAF50` | 成功/在线 |
| `warn` | `#FFB454` | 警告 |
| `textPrimary` / `textSecondary` / `textBody` | `#FFFFFF` / `#CCCCCC` / `#888888` | 标题 / 次级 / 正文辅助 |
| `aWhite03..12` | 白 alpha 8 个档 | 面板底、边框、hover 底色 |
| `aOrange15/25/35/50` | 橘红 alpha 4 档 | 强调边框、发光描边、选中底色 |

**禁用**：一切蓝、紫、青及衍生色。

## 2. 几何

- **全直角，radius = 0**（无任何圆角）
- 边框一律 1px 细线：普通 `aWhite08`；hover/focus `primary` 或 `aOrange35`
- 分割用细线或半透明色差，不用阴影
- 间距网格：u1-u7 = 4/8/12/16/24/32/48

## 3. 质感

- 扁平为主，无拟物高光、无复杂渐变
- 毛玻璃感 = 背景橘红光斑（右上 10% / 左下 6%）+ 面板白 alpha 半透明层叠
- 发光节制：仅 hover/激活时外圈 1px `aOrange25` 描边（间距 -3px），不用 MultiEffect（有布局偏移前科）

## 4. 字体与排版

- 字体栈：Segoe UI, Microsoft YaHei UI
- 字号：display 28 / title 20 / body 14 / small 12 / micro 11
- 层级：大标题白粗体 + 左侧 4px 橘红竖条标记；节标题 `primaryHi` 粗体；正文 `textSecondary`；辅助 `textBody`
- 关键数字/标签用橘红高亮（数据感）

## 5. 动效

| 场景 | 时长/曲线 |
|---|---|
| 颜色过渡（hover 等） | durFast 150ms OutCubic |
| 标准过渡（展开/切换淡入） | durStd 250ms OutCubic |
| 大幅动画（弧线/页面切换） | durSlow 300ms OutCubic |
| 进度条前沿光标 | 150ms 跟随 |

- 卡片 hover：上浮 -2px + 边框换橘红 + 微光（GlassPanel `hoverable: true`）
- 按钮：默认透明+细白边 → hover 橘红边框白字+外圈微光 → active 实心橘红 → pressed 深一档
- Toast：滑入 150ms → 进度底线 2.6s 线性收缩 → 滑出淡出；点击立即消失

## 6. 组件清单（ui/components/）

| 组件 | 说明 |
|---|---|
| BackgroundFX | 黑炭渐变 + 双橘红光斑 |
| GlassPanel | 直角半透明卡片；可选 hoverable 上浮 |
| NeonButton | 三态直角按钮（默认/hover/active/danger）；iconSource 可选 |
| GlowNavRail | 导航栏：橘红左条指示 + 灰/橘双态线性图标 |
| FlowProgressBar | 橘红实色填充 + 白色前沿光标；indeterminate 光段往复贴框 |
| RingGauge | 270° 弧线指标卡 + 端点方块光标 |
| FlowChart | 速率折线（橘红 1.5px + 16% 渐隐填充 + 极淡网格） |
| ComboGlass | 扁平下拉：focus 橘红边框、选中橘红 15% 底 |
| LogConsole | 底部日志台：黑底、LOG 橘红、err 红/warn 橘 |
| ToastHost / ToastItem | 右上角轻提示堆叠（≤4 条） |

## 7. 图标规范（ui/assets/ic_*.svg）

- 24×24 viewBox，stroke 1.5，round cap/join，fill none
- 导航图标双态：`ic_x.svg`（#888888）/ `ic_x_hi.svg`（#FF6D00）
- 按钮图标随文字色：active 白、默认 #CCCCCC
