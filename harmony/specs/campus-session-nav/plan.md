# Implementation Plan: 校园子功能会话自愈与跨页导航可靠性

**Input**: Feature specification from `entry/src/main/ets/pages/campus/campus-session-nav/spec.md`

**Note**: This template is filled in by the `/spec-plan` command.

## Summary

两项缺陷修复，均属"让既有能力表现一致、可预期"，不引入新数据源、不改解析/请求语义、不清 Cookie：

- **① 会话自愈对齐**：空教室（`fetchClassroomList` / `fetchClassroomState`）与体测（`fetchPEResult`）链路**当前已包在 `withSessionRecovery` 内**，但其 reroam 仅裸调 `roamByYyfwid`——门户会话失效时该调用**静默返回 false 且不自愈**。成绩域则通过 `ensureGradesRoam`（roam 失败 → `forceSessionRefreshOnce()` → 重试 roam）具备"roam 失败自愈"。本特性为 classroom/PETest 补齐同构自愈能力，并让 reroam 复位"已确保"标志 + 强制重漫游（对齐 `withLibRetry`/`withSportsRetry`）。
- **② 跨页导航一次到位**：`emitNavigate` 为即发即弃事件，冷启动时目标页（`TabContent` 惰性创建）尚未挂载订阅 → 首次点击丢失下钻目标。本特性在事件层引入**待处理导航目标**（内存态），并在目标页挂载时消费清除；覆盖 `campusSub` 与 `learningTab`。

## Technical Context

**Language/Version**: ArkTS / ArkUI（HarmonyOS；DevEco Studio 工具链，`DEVECO_HOME` 已配置）
**Primary Dependencies**: `@kit.*`、`@ohos.*`（内部 HttpClient / CookieManager / TsinghuaAuthService / SessionManager / emitter）
**State Management**: 保留项目既有 **State Management V1**（`@Component` + `@State`/`@StorageLink`/`@Watch`）；不迁移到 V2
**Storage**: 运行期内存态（待处理导航目标为进程内变量）；本特性不新增持久化
**Testing**: `arkts_check`（静态）→ `devecocli build --modules entry` → `devecocli run --skip-build --device 127.0.0.1:5555` 真机/模拟器手测
**Target Platform**: HarmonyOS（模拟器 Mate 80 Pro Max）
**Project Type**: mobile-app（既有 HarmonyOS 工程 `harmony/`）
**Performance Goals**: 会话自愈为用户可感知的一次性恢复，无额外常驻开销；待处理目标为 O(1) 读写
**Constraints**: ArkTS 严格模式；仅改授权清单文件；不改数据/请求语义、不清 Cookie；日志无凭证明文；可见文案走 i18n（zh/en 成对）
**Scale/Scope**: 约 2 个核心文件改动（`CampusDataService.ets`、`UiEvents.ets`）+ 2 个消费点（`CampusPage.ets`、`LearningPage.ets`）+ 至多 4 个条件性配合点（`HomePage.ets`/`Index.ets`/`ClassroomPage.ets`/`PETestPage.ets`）

## Project Structure

### Documentation (this feature)

```text
harmony/entry/src/main/ets/pages/campus/campus-session-nav/
├── feature.json         # feature_directory 记录（已存在）
├── spec.md              # Phase 1 输出
├── plan.md              # 本文件（/spec-plan 输出）
└── tasks.md             # Phase 3 输出
```

### Source Code (repository root)

既有工程架构（**不引入 MVVM，不重构目录**）。本特性涉及文件（相对 `harmony/`）：

```text
entry/src/main/ets/
├── services/campus/
│   └── CampusDataService.ets        # ① 核心：空教室/体测会话自愈（classroom/PETest）
├── state/
│   └── UiEvents.ets                 # ② 核心：待处理导航目标的存储与消费
├── pages/
│   ├── CampusPage.ets               # ② 消费点：挂载/事件时消费 campusSub
│   ├── LearningPage.ets             # ② 消费点：挂载/事件时消费 learningTab
│   ├── HomePage.ets                 # ② 条件性：emit 站点（若待处理目标写入 emitNavigate 则无需改动）
│   ├── Index.ets                    # ② 条件性：常驻 Tab 消费（当前无需改动）
│   └── ClassroomPage.ets            # ① 条件性：刷新/重试已走同一链路（预计无需改动）
└── pages/campus/
    └── PETestPage.ets               # ① 条件性：刷新/重试已走同一链路（预计无需改动）
```

**Structure Decision**: 沿用既有工程架构与目录约定（服务层 `services/`、事件层 `state/`、页面层 `pages/`），**不引入 MVVM 目录、不做结构迁移**。本特性为增量缺陷修复，改动集中在既有文件内的局部方法级调整，新增代码量小、文件数不增加，故不适用任何"新工程分层 tier"选型。

## Complexity Tracking

无 Constitution 违规项，无需填写。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （无） | — | — |

## Research & Decisions

### D1 — ① 的真正根因与修复边界（关键澄清）

- **Decision**: 承认"空教室/体测链路已包 `withSessionRecovery`（提交 `6bc40d42`）"这一代码事实，修复点落在 **reroam 与 roam 调用的自愈缺失**，而非"补 withSessionRecovery"。
- **Rationale**: 交接原文称"未包会话恢复"与仓库不符；照原文实施会命中"已存在"而实质零改动。真实差异为该两条链路缺少成绩域 `ensureGradesRoam` 的"roam 失败 → `forceSessionRefreshOnce()` → 重试 roam"自愈。
- **Alternatives considered**: (a) 严格照交接原文新增 `withSessionRecovery` → 落空；(b) 先补运行日志再定夺 → 用户已选定"自愈对齐"，故直接实施自愈对齐。

### D2 — ① ensured 标志的取舍（避免回归"每次状态查询重漫游"）

- **Decision**: 新增 `classroomRoamEnsured` / `petestRoamEnsured` 标志，并让 `ensureClassroomRoam(force)` / `ensurePetestRoam(force)` 带 `force` 形参：
  - 教学楼**列表**：`force = false`（命中标志即跳过，对齐 `ensureGradesRoam`）；
  - 教室**状态**：`force = true`（**保留**既有"每次状态查询都重新漫游 zhjw"的刻意设计，见 `doFetchClassroomStateHtml` 注释 L1740-1743）；
  - reroam：`标志复位 + ensureXxxRoam(true)`。
- **Rationale**: 直接照搬"带标志即跳过"会破坏状态查询的每次重漫游意图，导致长时间停留后切换周次再次超时（回归）。用 `force` 形参在保留既有语义的同时获得标志复位带来的可诊断性。
- **Alternatives considered**: (a) 完全不引入标志，仅做 roam 失败自愈 → 可用，但偏离用户选定的 `ensureXxxRoam` 同构形态，且缺少"会话瞬态复位"一致性；(b) 列表也 `force = true` → 标志失去意义。

### D3 — ① 自愈动作复用既有 `forceSessionRefreshOnce()`

- **Decision**: `ensureClassroomRoam` / `ensurePetestRoam` 中 roam 返回 false 时，复用既有私有 `forceSessionRefreshOnce()`（借统一恢复链触发一次完整重登），随后重试一次 roam。
- **Rationale**: 该方法是成绩域既有自愈手段，复用即"对齐成绩域"，避免新增第二套恢复语义；且其失败仅记日志不抛，交由外层 `withSessionRecovery` 兜底。
- **Alternatives considered**: 直接调用 `TsinghuaAuthService` 的完整重登 → 与 `forceSessionRefreshOnce` 重复造轮子，语义不一致。

### D4 — ② 待处理导航目标写入位置：收敛进 `emitNavigate`

- **Decision**: 在 `state/UiEvents.ets` 内维护模块级待处理目标（`campusSub` / `learningTab`），**由 `emitNavigate` 在 emit 的同时记录**待处理目标；另暴露 `takePendingCampusSub()` / `takePendingLearningTab()`（取值并清除）。
- **Rationale**: 所有 emit 站点（`HomePage`、`AIChatPage`）自动获得"未挂载也不丢失"的能力，避免逐站点改造导致遗漏；是对 `emitNavigate` 现有契约的纯增益。
- **Alternatives considered**: (a) 仅在 `HomePage` 写入 → 与交接字面一致，但 `AIChatPage` 等其它 emit 站点仍有同类冷启动缺陷，且需逐站点维护；(b) 新导出 `navigate()` 包裹函数替换所有调用点 → 改动面更大、风险更高。

### D5 — ② 消费与清除语义（字段级、防陈旧误触发）

- **Decision**: **字段级**消费——`CampusPage` 只消费/清除 `campusSub`，`LearningPage` 只消费/清除 `learningTab`。
  - 目标页**挂载时**（`aboutToAppear`）消费并清除对应字段；
  - 目标页**已挂载时**，既有实时订阅回调照常生效，并在应用后清除自己负责的字段；
  - 新导航目标天然覆盖旧目标（`emitNavigate` 每次都写两个字段，含空串）。
- **Rationale**: 若"任意事件清除整个目标"，会在"目标页未挂载 + 已挂载页收到事件"时把待处理目标一并清掉，导致目标页挂载后无目标可消费（新缺陷）。
- **Alternatives considered**: 整目标清除 → 上述竞态；持久化待处理目标 → 违反 FR-010（仅内存态）。

### D6 — ② `Index.ets` / `HomePage.ets` 是否需要改动

- **Decision**: **预计无需改动**。`Index` 为常驻 `@Entry`，其 tab 订阅在 `HomePage` 渲染前即注册，故 tab 切换始终实时生效；`HomePage` 的 `emitNavigate` 站点经 D4 自动获得写入能力。
- **Rationale**: 仅当验证阶段发现冷启动 tab 切换亦丢失时，才按需最小化修改 `Index.ets`（消费待处理 tab）。
- **Alternatives considered**: 预先在 `Index` 增加待处理 tab 消费 → 无证据的过度改动。

### D7 — ① 页面层是否需要改动

- **Decision**: `ClassroomPage.ets` / `PETestPage.ets` **预计无需改动**：其"刷新/重试"已复用同一 `load*/load()` → 服务层方法路径（FR-003 天然满足）。
- **Rationale**: 服务层自愈对页面透明；仅在验证阶段发现页面存在旁路重试入口时才最小化补齐。

### D8 — i18n

- **Decision**: 本特性**不新增可见文案**（错误/重试等沿用既有词条；`pe.*` 词条已存在）。除非实施中发现必须新增，才在 `I18n.ets` 以 zh/en 成对追加。
- **Rationale**: 满足 FR-009 且最小化改动面。

### Dependencies & Assumptions

- 依赖既有 `TsinghuaAuthService.withSessionRecovery` 与类内私有 `forceSessionRefreshOnce`、`SessionManager.getCampusDataService()`；均为现有能力，不改其契约。
- 依赖既有 `NavTarget` 结构与 `emitter` 订阅机制。
- 假设 ArkUI `Tabs` 的 `TabContent` 为惰性创建且切换后保留（`aboutToAppear` 首次显示时触发一次）；若验证推翻该假设，需按 D6 最小化补 `Index`。
- 假设 `forceSessionRefreshOnce` 在门户会话失效时可成功完成一次完整重登；若因 2FA 等不可完成，则回落为可读错误（属 spec 已声明的排除项）。

## Data Model

### 实体 1：待处理导航目标（Pending Nav Target）

- **承载位置**: `entry/src/main/ets/state/UiEvents.ets` 模块级内存变量（进程内、不持久化）。
- **字段**:
  - `campusSub: string` —— 校园子页标识（如 `'classroom'`）；空串表示无校园下钻意图。
  - `learningTab: string` —— 学习子标签（如 `'作业'`、`'通知'`）；空串表示无学习下钻意图。
- **生命周期**: `emitNavigate` 写入（每次覆盖两个字段）→ 目标页 `aboutToAppear` 或已挂载订阅回调消费任一字段并按字段清除 → 进程结束即消失。
- **校验/约束**: 仅字符串字段；不做额外归一化（与既有 `NavTarget` 字段语义一致）。

### 实体 2：子系统会话"已确保"状态（Subsystem Roam Ensured）

- **承载位置**: `entry/src/main/ets/services/campus/CampusDataService.ets` 实例字段。
- **字段**:
  - `classroomRoamEnsured: boolean`（默认 false）
  - `petestRoamEnsured: boolean`（默认 false）
- **状态转移**:
  - `false → true`：对应子系统 roam 成功。
  - `true → false`：`resetSessionState()`（退出/重登统一复位）时，及 `withSessionRecovery` 的 reroam 回调中（复位后强制重漫游）。
- **约束**: 教室**状态**查询始终以 `force = true` 调用，故该标志对其不产生"跳过漫游"效果（保护既有语义）。

## Contracts & Interfaces

### 契约 A —— 会话自愈（`CampusDataService`）

> 均为类内私有/公开方法行为契约；**不改变**任何 URL/表单/参数格式、解析函数、错误文案与 Cookie 行为。

| 成员 | 签名 | 行为契约 |
|------|------|----------|
| 新增字段 | `private classroomRoamEnsured: boolean` | 教室子系统会话"已确保"标志 |
| 新增字段 | `private petestRoamEnsured: boolean` | 体测子系统会话"已确保"标志 |
| 修改 | `resetSessionState(): void` | 追加复位上述两个标志（与 registrar/grades/ele 一致） |
| 新增 | `private ensureClassroomRoam(force: boolean): Promise<void>` | 若 `ensured && !force` 直接返回；否则 `roamByYyfwid(CLASSROOM_YYFWID)`；失败则 `forceSessionRefreshOnce()` 后重试一次；成功置 `ensured = true`。不抛（交由外层兜底） |
| 新增 | `private ensurePetestRoam(force: boolean): Promise<void>` | 同上，作用于 `PETEST_YYFWID` / `petestRoamEnsured` |
| 修改 | `doFetchClassroomListHtml()` | 漫游改用 `ensureClassroomRoam(false)`（其余不变） |
| 修改 | `doFetchClassroomStateHtml(...)` | 漫游改用 `ensureClassroomRoam(true)`（**保留**每次重漫游） |
| 修改 | `doFetchPEResultText()` | 漫游改用 `ensurePetestRoam(false)`（其余不变） |
| 修改 | `fetchClassroomList()` | `withSessionRecovery` 的 reroam 改为"复位 `classroomRoamEnsured` + `ensureClassroomRoam(true)`" |
| 修改 | `fetchClassroomState(...)` | 同上（label 可沿用 `campus-classroom-state`） |
| 修改 | `fetchPEResult()` | reroam 改为"复位 `petestRoamEnsured` + `ensurePetestRoam(true)`" |
| 不变 | `roamByYyfwid` / `parse*` / `ensureNotZhjwTimeout` / 会话超时文案 | 语义与文本保持不变 |

### 契约 B —— 待处理导航目标（`state/UiEvents.ets` 及其消费点）

| 成员 | 签名 | 行为契约 |
|------|------|----------|
| 新增（模块级状态） | `pendingCampusSub: string`、`pendingLearningTab: string` | 进程内待处理目标，默认空串 |
| 修改 | `emitNavigate(target: NavTarget): void` | **保留**原有 emit 行为，**追加**：将 `target.campusSub` / `target.learningTab` 覆盖写入待处理状态 |
| 新增 | `takePendingCampusSub(): string` | 返回当前 `campusSub` 待处理值并将其清空 |
| 新增 | `takePendingLearningTab(): string` | 返回当前 `learningTab` 待处理值并将其清空 |
| 修改 | `CampusPage.aboutToAppear()` | 订阅后：`takePendingCampusSub()` 非空则设 `subScreen`；实时订阅回调应用事件值后清除 `campusSub` 待处理值 |
| 修改 | `LearningPage.aboutToAppear()` | 订阅后：`takePendingLearningTab()` 非空则设 `activeTab`；实时订阅回调应用事件值后清除 `learningTab` 待处理值 |
| 条件性修改 | `Index.aboutToAppear()` | 仅当验证发现冷启动 tab 切换丢失时，消费待处理 tab |
| 条件性修改 | `HomePage.navigateTo(...)` | 仅当未采用 D4（写入收敛进 `emitNavigate`）时需要显式写入 |

### 契约 C —— 授权改动清单（硬约束）

允许修改的文件（相对 `D:\Develop\campus_os\campus-os\harmony`）：

1. `entry/src/main/ets/services/campus/CampusDataService.ets`（① 必需）
2. `entry/src/main/ets/state/UiEvents.ets`（② 必需）
3. `entry/src/main/ets/pages/CampusPage.ets`（② 必需）
4. `entry/src/main/ets/pages/LearningPage.ets`（② 必需）
5. `entry/src/main/ets/pages/HomePage.ets`（② 条件性）
6. `entry/src/main/ets/pages/Index.ets`（② 条件性）
7. `entry/src/main/ets/pages/ClassroomPage.ets`（① 条件性）
8. `entry/src/main/ets/pages/campus/PETestPage.ets`（① 条件性）
9. `entry/src/main/ets/utils/I18n.ets`（仅当必须新增文案，zh/en 成对）

**禁止**：清 Cookie/凭证、改解析语义、新增网络请求、提交 git。

### Success Criteria Traceability

| SC | 对应设计/契约 | 验证方式 |
|----|----------------|----------|
| SC-001 会话失效后一次重试恢复率 ≥90% | 契约 A（ensureClassroom/PetestRoam 自愈） | 真机：停留致会话失效 → 点"刷新/重试" |
| SC-002 冷启动"查空教室"首次直达 | 契约 B（pending campusSub） | 冷启动 → 首页点"查空教室" |
| SC-003 冷启动学习子标签首次直达 | 契约 B（pending learningTab） | 冷启动 → 首页点"添加 DDL"/"未读通知" |
| SC-004 非会话错误误触发重登率 = 0 | 仅对 roam 失败/会话超时页自愈；解析错误不触发 | 构造非会话错误场景 |
| SC-005 既有跨页导航回归失败数 = 0 | 契约 B 的字段级消费 + 实时订阅保留 | 逐一触发图书馆座位 pill / AI 跳转等 |

## Changelog

- 2026-10-15：初版计划（Phase 2 输出）。
