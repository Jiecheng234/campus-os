# Implementation Plan: 课表交互增强（时间指示线 / 课程详情 / 扩展色板）

**Input**: Feature specification from `harmony/specs/schedule-interaction/spec.md`

## Summary

在既有块状课表组件 `ScheduleGrid` 与页面 `SchedulePage` 上做**增量改造**，不引入新页面路由、不新增网络请求：

1. 课程块点击 → 页面底部 `bindSheet` 弹层展示六项课程信息；
2. 本周视图在「今天」日列内以 Stack 叠加层绘制横向时间指示线，由页面每 60 秒驱动；
3. 调色板 8 → 16 组，颜色分配改为「课名散列基址 + 本周内线性探测顺延」，在 16 门以内保证零撞色。

## Technical Context

**Language/Version**: ArkTS / ArkUI（沿用项目现有 HarmonyOS SDK 与 `build-profile.json5` 配置）
**Primary Dependencies**: `@kit.ArkUI`（`bindSheet`、组件能力）、项目内 `Theme`、`I18n`、`CampusDataService`、`Log`
**State Management**: 沿用项目现有 ArkTS 状态管理 V1（`@State` / `@Prop` / `@StorageLink`），不引入 V2，不做状态管理迁移
**Storage**: 无新增持久化；详情数据仅驻留页面内存
**Testing**: `devecocli build` 构建校验 + 真机/模拟器 `devecocli run` + `verify_ui` 截图核对 + `devecocli log` 关键日志
**Target Platform**: HarmonyOS 手机（沿用 `harmony/` 工程既有设备配置）
**Project Type**: mobile-app
**Performance Goals**: 点击课程块到弹层出现 ≤ 300ms；每分钟一次的时间线刷新不得引起整页明显卡顿
**Constraints**: 不新增网络请求；不修改 `CampusDataService` 的教务事件模型；不改变周导航与加载/空态/错误语义
**Scale/Scope**: 1 个页面、1 个展示组件、1 个词典文件；单周课程块常规量级（≤ 40 块）

## Project Structure

### Documentation (this feature)

```text
harmony/specs/schedule-interaction/
├── feature.json
├── spec.md
├── plan.md              # This file
└── tasks.md             # /spec-tasks output
```

### Source Code (repository root)

```text
harmony/entry/src/main/ets/
├── components/
│   └── ScheduleGrid.ets      # 调色板扩容、配色分配算法、点击回调、时间指示线叠加层
├── pages/
│   └── SchedulePage.ets      # 课程块字段补全、两段式配色、详情弹层、计时器、i18n 接线
└── utils/
    └── I18n.ets              # 新增 schedule.detail.* 文案（zh/en）
```

**Structure Decision**: 沿用项目既有架构（`pages/` + `components/` + `utils/`），**不引入 MVVM 目录或迁移**。本特性是既有页面的增量交互能力，改动集中在 2 个 ArkTS 文件 + 1 个词典文件，新建独立 `viewmodel/` 或 `service/` 只会增加跳转成本，无职责收益。

## Complexity Tracking

无结构偏离；不新增架构层、不新增路由、不新增数据源。

## Research & Decisions

### 决策 1：时间指示线在日列内部用 Stack 叠加，而不是整表绝对定位

- **Decision**: 在 `ScheduleGrid.DayColumnBuilder` 外层包一层 `Stack({ alignContent: Alignment.TopStart })`；仅当该列是「今天」时，追加一个宽度 100%、高度 2vp 的横向线，用 `.offset({ y })` 定位到计算出的纵向位置，并关闭其命中测试避免遮挡课程点击。
- **Rationale**: 7 个日列使用 `layoutWeight(1)` 均分，构建期拿不到像素宽度；若在整表 Stack 上按 `dayIndex × 列宽` 计算 x，需要额外测量与窗口变化处理。列内叠加天然跟随列宽，布局改动最小。
- **Alternatives considered**: 整表叠层 + 百分比 x 定位（需要精确列宽，脆弱）；把指示线做成课程块样式插入槽位（会破坏顺序堆叠与高度语义）。

### 决策 2：页面持有 60 秒计时器，网格组件保持纯展示

- **Decision**: `SchedulePage` 维护当前分钟数与今日列索引，通过 props 传给 `ScheduleGrid`；`ScheduleGrid` 只负责把分钟数换算为纵向偏移并渲染。计时器在 `aboutToAppear` 启动、`aboutToDisappear` 清理，页面重新可见时立即重算。
- **Rationale**: 与既有「页面负责数据、组件负责渲染」的边界一致；避免组件内部持有生命周期与定时器状态，便于验证与后续复用。
- **Alternatives considered**: 组件内自持计时器（职责下移，组件不再纯展示）；每帧定时（无必要，浪费）。

### 决策 3：详情采用单一 `bindSheet` 底部弹层

- **Decision**: 页面根节点绑定唯一的 `bindSheet`，用 `detailVisible` 布尔与 `detailBlock` 选中块驱动；弹层高度固定（约 360vp），内容区包一层 `Scroll` 以保证超长课程名/地点可滚动查看；保留关闭按钮，`dragBar: false` 并在 `onWillDismiss` 中拦截 `SLIDE_DOWN` 以禁用下滑关闭；`onDisappear` 时清空选中块。
- **Rationale**: 项目已有 `bindSheet` 成熟用法（`SettingsPage` / `AIChatPage`），单节点单绑定可避免多次 `bindSheet` 相互覆盖；无需新增路由，关闭后天然保留周次与滚动位置。
- **Alternatives considered**: 子屏详情页（需要 `subScreen` 分支与返回栈，改动面大）；`AlertDialog`（内容区高度受限，长课程名/地点展示不佳）。

### 决策 4：配色采用「散列基址 + 本周内线性探测」

- **Decision**: 保留 `scheduleColorIndexForTitle` 作为基址函数（散列后对 16 取模）。新增分配函数：先取本周不同课程名并**按字典序排序**，依次以基址落位，若该色已被其它课程占用则线性探测下一个空闲色；本周不同课程名超过 16 个时，剩余课程回落到各自基址。
- **Rationale**: 排序保证同一周内分配结果与接口返回顺序无关，跨次渲染稳定；未撞车课程始终落在基址，跨周保持同色；只有真正冲突的课程会顺延，满足「16 门以内零撞色」。
- **Alternatives considered**: 纯散列（实测演示数据仍有 2 对撞色）；按出现顺序分配（受接口排序影响）；按课名排序直接取色（跨周颜色整体漂移）。

### 决策 5：详情所需字段在 UI 模型内补全，不改服务层

- **Decision**: 在 `ScheduleBlock` 上新增 `date`、`startTime`、`endTime` 三个展示字段，由页面映射事件时填充；演示数据同步补齐。`CampusDataService.ScheduleEvent` 保持不变。
- **Rationale**: 服务层模型被多个子系统共用，改动风险高于收益；这三个字段在页面映射阶段已全部可得。
- **Alternatives considered**: 扩展 `CampusDataService.ScheduleEvent`（无必要，扩大回归面）；弹层反查原始事件（需要额外索引，易错）。

### 决策 6：时间指示线的可见边界与课间吸附

- **Decision**: 当前分钟数早于 08:00 或晚于 21:45 → 不渲染；落在某个大节区间内 → 按节内比例插值；落在两个大节之间的间隔 → 吸附到相邻节边界（上一节结束位置）。
- **Rationale**: 课表网格只覆盖 6 个大节；在空白时段画线会让用户误判有课。吸附避免线落在无意义的空白行。
- **Alternatives considered**: 全天 0–24 时线性映射（与网格刻度不一致）；间隔内隐藏线（会造成「线闪烁」）。

## Data Model

### 课程块（UI 模型，`components/ScheduleGrid.ets`）

| 字段 | 类型 | 现状 | 本特性变化 |
|---|---|---|---|
| `dayIndex` | number | 0–6（周一为 0） | 不变 |
| `startPeriod` | number | 0–5 | 不变 |
| `endPeriod` | number | 0–5 | 不变 |
| `title` | string | 课程名 | 不变 |
| `location` | string | 地点，可为空 | 不变 |
| `colorIndex` | number | 0–7 | 取值范围扩展为 0–15，赋值方式改为集中分配 |
| `date` | string | 无 | 新增：`YYYY-MM-DD`，用于详情日期展示 |
| `startTime` | string | 无 | 新增：课程开始时间原文（`HH:mm`） |
| `endTime` | string | 无 | 新增：课程结束时间原文，可为空 |

### 配色条目（`components/ScheduleGrid.ets`）

- 结构不变：背景色 / 文字色 / 边框色三元组；
- 数量由 8 组扩展为 16 组，新增 8 组须与既有一致为浅色底、深色文字、同色系边框；
- 文字与背景对比度不低于现有 8 组的最低值。

### 时间指示状态（页面态 + 组件入参）

| 名称 | 位置 | 含义 |
|---|---|---|
| `nowMinuteOfDay` | 页面 `@State` → 组件 `@Prop` | 当前时刻距 0 点的分钟数；`-1` 表示未初始化 |
| `todayIndex` | 页面计算 → 组件 `@Prop` | 今天对应的列索引 0–6；非本周固定 `-1` |
| 指示线偏移 | 组件内部派生 | 由 `nowMinuteOfDay` 与 6 大节起止时间换算出的 vp 值；`-1` 表示隐藏 |

### 详情弹层状态（页面态）

| 名称 | 类型 | 含义 |
|---|---|---|
| `detailVisible` | boolean | 弹层是否展开 |
| `detailBlock` | `ScheduleBlock`（可为空） | 当前选中的课程块；关闭时清空 |

## Contracts & Interfaces

### `ScheduleGrid` 组件契约（新增/变更）

| 成员 | 类型 | 方向 | 说明 |
|---|---|---|---|
| `blocks` | `ScheduleBlock[]` | 入 | 不变 |
| `axisLabels` | `string[]` | 入 | 不变 |
| `dayLabels` | `string[]` | 入 | 不变 |
| `dateLabels` | `string[]` | 入 | 不变 |
| `cellHeight` | number | 入 | 不变 |
| `leftWidth` | number | 入 | 不变 |
| `todayIndex` | number | 入（新增） | 0–6 表示今天所在列；`-1` 表示不显示指示线 |
| `nowMinuteOfDay` | number | 入（新增） | 当前分钟数；`-1` 表示无有效时间 |
| `onBlockSelect` | `(block: ScheduleBlock) => void` | 入（新增） | 课程块点击回调；默认空实现 |

### 导出函数契约（`components/ScheduleGrid.ets`）

| 名称 | 签名语义 | 约束 |
|---|---|---|
| `scheduleColorIndexForTitle` | 课程名 → 基址颜色索引 | 返回值始终落在 `[0, 调色板长度)`；同名恒定 |
| `assignScheduleColorIndexes` | 本周课程名列表 → 课名到颜色索引的映射 | 输入去重后按字典序分配；≤16 个不同课名时值两两不同；超过 16 个时剩余项回落基址 |

### 页面内部契约（`pages/SchedulePage.ets`）

- 计时器：`aboutToAppear` 启动、`aboutToDisappear` 清理，间隔 60 秒；回调只更新当前分钟数与今日列索引，不触发网络请求。
- 周次与指示线：仅 `weekOffset === 0` 时 `todayIndex` 有效；切换周时立即失效。
- 详情弹层：根节点唯一 `bindSheet`；打开前写入选中块，关闭后清空并保持当前周次与滚动位置。
- 配色：课程块先完成映射，再统一调用分配函数回填 `colorIndex`；演示数据走同一分配函数。

### i18n 契约（`utils/I18n.ets`，`schedule.` 前缀，zh/en 双语）

| key | 用途 | 占位符 |
|---|---|---|
| `schedule.detail.title` | 弹层标题 | 无 |
| `schedule.detail.date` | 日期行标签 | 无 |
| `schedule.detail.weekday` | 星期行标签 | 无 |
| `schedule.detail.periods` | 节次行标签 | 无 |
| `schedule.detail.time` | 时间行标签 | 无 |
| `schedule.detail.periodRange` | 节次区间文案 | `{start}` / `{end}`（1 基） |
| `schedule.detail.noLocation` | 地点为空占位 | 无 |
| `schedule.location` | 地点行标签（复用既有键） | 无 |

### 日志契约（便于验证，不面向用户）

- 指示线仅在跨大节边界或进入隐藏态时输出一次当前日期索引、当前分钟数与计算偏移（每分钟不重复），便于在 08:00–21:45 之外通过日志复核换算逻辑；
- 配色分配在课名数超过调色板容量时输出一次告警日志，说明进入复用分支。
