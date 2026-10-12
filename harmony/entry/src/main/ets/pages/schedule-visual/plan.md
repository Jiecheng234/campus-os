# Implementation Plan: 课表页视觉改进（块状重构）

**Input**: Feature specification: `entry/src/main/ets/pages/schedule-visual/spec.md`

**Note**: 本特性产物按项目约定与所属源码同区域放置（`entry/src/main/ets/pages/schedule-visual/`），不创建 `spec/` 目录。

## Summary

将课表页从"固定单格表格"重构为**块状课表**：新增一个纯展示网格组件（时间轴 + 日列头（星期+日期）+ 按节次堆叠的课程块），课程块**按课程名稳定配色**、**高度对应跨越节次数**、块内展示**课程名 + 完整多行地点**；`SchedulePage` 保留数据加载、周导航与加载/空态/错误行为；演示模式复用同一渲染。不新增数据请求、不改数据模型。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `CampusDataService.ScheduleEvent`（含 `location`）、`SchedulePage` 既有周导航逻辑、`Theme` 设计令牌、`components/Ui`；无新增三方依赖
**State Management**: 沿用 **State Management V1**（`@Component` + `@State`/`@Prop`）
**Storage**: N/A（不改存储）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（对照原项目视觉）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 打开课表 3s 内呈现；周切换流畅（无卡顿）
**Constraints**: 不新增请求；无横向溢出/无块遮挡；长文本安全裁剪；课表文案走 i18n（与 `i18n-migration` 协同）；ArkTS 严格模式
**Scale/Scope**: 新增 1 个展示组件；改造 1 个页面；实体 3 个（课程块/节次/配色）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/schedule-visual/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── components/
│   └── ScheduleGrid.ets                       # 新增：块状课表网格（纯展示）
├── pages/
│   └── SchedulePage.ets                       # 改造：数据→块模型、接入新网格、保留周导航与状态
├── services/campus/CampusDataService.ets      # 复用（不改）：ScheduleEvent（含 location）
└── utils/I18n.ets                             # 复用（不改，由 i18n-migration 扩词典）
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。课表渲染涉及"行列布局 + 跨行块 + 配色"，独立为**纯展示组件**（`components/ScheduleGrid.ets`，输入块数据与当周日期，无副作用），`SchedulePage` 只负责数据加载、周导航、状态与文案。**不新增目录、不新增依赖**。与 `i18n-migration` 协同：本组件不硬编码中文，静态字样（时间轴标签、星期、周次）使用该项特性定义的 `schedule.*` 键。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 块高实现方式（无绝对定位）**
- **Decision**: 每个"日列"为一个纵向堆叠容器（高度 = 大节数 × 单元高）；按节次顺序遍历：若某课程**起始**于该节 → 渲染高度 = `跨越节数 × 单元高` 的块；若该节被已渲染的跨节块**覆盖** → 跳过；否则渲染占位空单元。
- **Rationale**: 用"顺序堆叠 + 跳过被覆盖节次"天然得到跨节块高，避免绝对定位的越界/重叠风险（FR-001/FR-008/SC-004/SC-006）。
- **Alternatives considered**: `Stack` + `.position()` 绝对定位（跨列重叠与边界计算复杂，破版风险高）。

**Decision 2 — 课程配色（稳定性）**
- **Decision**: 以课程名为输入做**确定性散列**，映射到固定调色板（含足够对比度的前景色/背景色配对）；同名课程恒同色（跨周、跨会话一致）。
- **Rationale**: 满足 FR-002/SC-002，且无需服务端配色数据。
- **Alternatives considered**: 统一主题色（不满足需求）；按索引取色（跨周不稳定）。

**Decision 3 — 节次区间换算**
- **Decision**: 由事件起止时间映射节次区间——**起始**索引按各大节开始时间阈值判定（沿用既有 `periodIndexFor` 思路）；**结束**索引按"该节结束时间"判定（结束时间落在哪一节的区间内即为该节）。映射失败（异常时间）**跳过该课程**并记录日志，不阻塞渲染。
- **Rationale**: 既有数据只有起止时间（无节次字段），需可靠换算（FR-001/边界要求）。
- **Alternatives considered**: 仅按起始时间单节渲染（无法表达跨节课程，正是当前缺陷）。

**Decision 4 — 地点与文本裁剪**
- **Decision**: 块内自上而下为"课程名（可多行）→ 地点（多行）"；当块高受限时**优先保证课程名**，地点允许折行并在块高不足时安全裁剪（不溢出、不遮挡相邻块）；**空地点不渲染地点行**。
- **Rationale**: 满足 FR-003/SC-003 与边界要求（长地点不截断为单行、空地点不塌陷）。
- **Alternatives considered**: 单行截断（用户已否决）；固定行高（无法容纳完整地点）。

**Decision 5 — 日列头（星期 + 日期）**
- **Decision**: 头部左侧为时间轴列（占位），其后每列显示"星期简称 + 日期（MM-DD）"；日期由当周周一日期 + 列索引计算，随周次导航更新。
- **Rationale**: 满足 FR-005（跨周辨识）；日期与既有周范围标签一致（同一数据来源）。
- **Alternatives considered**: 仅星期（无法跨周辨识）。

**Decision 6 — 组件划分与状态保持**
- **Decision**: 新增 `components/ScheduleGrid.ets`（纯展示：输入课程块数组、当周日期的显示串、单元高）；`SchedulePage` 保留并**不改变**既有的周导航（‹ ›、回本周）、加载/空态/错误（可重试）与演示模式分支。
- **Rationale**: 满足 FR-006/SC-005（行为回归）并控制单文件体积。
- **Alternatives considered**: 全部内联在 `SchedulePage`（体积大、难以独立演进）。

**Decision 7 — 演示模式复用**
- **Decision**: 演示示例课程转换为与真实数据同构的块模型后交给同一网格组件渲染（仅数据来源不同）。
- **Rationale**: 满足 FR-007，且保证演示与真实视觉一致。
- **Alternatives considered**: 演示单独一套渲染（重复实现、易不一致）。

## Data Model

**ScheduleBlock（UI 块模型，新增，仅渲染用）**: `dayIndex: number`（0–6）· `startPeriod: number`（0–5）· `endPeriod: number`（0–5）· `title: string` · `location: string` · `colorIndex: number`（散列结果）

**节次表（既有）**: `PERIODS`（6 个大节起始时间）+ 新增各节**结束时间**常量（用于结束索引判定与时间轴显示）

**配色表（新增）**: 固定调色板：`{ background: string, foreground: string }[]`（≥6 组，保证文字对比度）

## Contracts & Interfaces

**组件契约（新增 `ScheduleGrid`）**
- 输入：`blocks: ScheduleBlock[]` · `dayLabels: string[]`（星期简称，i18n）· `dateLabels: string[]`（MM-DD）· `axisLabels: string[]`（时间轴"起-止"文案）· `cellHeight: number`
- 输出：纯展示（本轮无点击回调；如后续需要，可加 `onSelect(block)` 且不影响现实现）
- 约束：不发起请求、不读写存储、不硬编码中文（静态字样由调用方传入）

**页面契约（`SchedulePage`，改造）**
- 保持既有对外行为：周导航、回本周、加载/空态/错误（可重试）、演示模式分支**不变**
- 新增：把 `ScheduleEvent[]`（或演示示例）映射为 `ScheduleBlock[]`（含节次区间与配色索引）
- 文案：静态字样改用 i18n 键（`schedule.*`），并以 `@StorageLink('locale')` 订阅语言变化

**依赖契约（复用，不改）**
- `CampusDataService`（`ScheduleEvent`、课表拉取与周次/学期信息）
- `Theme`/`Radius`/`Space`/`FontSize` 设计令牌
