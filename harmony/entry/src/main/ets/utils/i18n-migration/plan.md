# Implementation Plan: i18n 后续迁移（核心骨架 + 高频页）

**Input**: Feature specification: `entry/src/main/ets/utils/i18n-migration/spec.md`

**Note**: 本特性产物按项目约定与所属源码同区域放置（`entry/src/main/ets/utils/i18n-migration/`），不创建 `spec/` 目录。

## Summary

在既有 i18n 框架之上扩词典（按页面前缀）与新增参数化翻译，并把**底部导航 + 首页/学习/课表/校园/AI/登录**的用户可见静态文案迁移为词典键，页面通过 `@StorageLink('locale')` 订阅实现**即时双语**；未迁移页面保持中文且无键名外泄；仅改文案，不动业务逻辑与数据。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `utils/I18n.ets`（词典 + `t()` + AppStorage `locale`）、`SettingsManager`（语言持久化）、`components/Ui`（头部/区块组件，文案由调用方传入）；无新增三方依赖
**State Management**: 沿用 **State Management V1**；语言状态经 **AppStorage `'locale'`** 跨页订阅
**Storage**: 沿用既有语言持久化（不新增存储）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（中英切换、无键名外泄、功能回归）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 语言切换后首批页面 ≤1 秒完成文案切换（SC-001）
**Constraints**: 仅改文案；业务数据不翻译；词典 zh/en 成对；未迁移页回退中文且无键名外泄；ArkTS 严格模式
**Scale/Scope**: 扩展 1 个框架文件；改造 7 个页面（+ 视需要的 2 个数据文案文件）；实体 3 个（词条/导航项/状态文案）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/utils/i18n-migration/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── utils/
│   └── I18n.ets                               # 改造：扩词典（nav/home/learning/schedule/campus/ai/login/status）+ 新增 tp() 参数化
├── pages/
│   ├── Index.ets                              # 改造：底部导航标签 + 语言订阅
│   ├── HomePage.ets                           # 改造：首页文案（+ 视需要 HomeData.ets 的 UI 文案）
│   ├── LearningPage.ets                       # 改造：学习页文案（+ 视需要 LearningData.ets 的 UI 文案）
│   ├── SchedulePage.ets                       # 改造：课表页文案（与 schedule-visual 协同）
│   ├── CampusPage.ets                         # 改造：校园页文案（入口标题/副标题/状态）
│   ├── LoginPage.ets                          # 改造：登录页文案（+ 既有弃用提示 API 顺带清理）
│   └── ai/AIChatPage.ets                      # 改造：AI 页文案
└── pages/SettingsPage.ets                     # 参考：已验证的 @StorageLink + tr() 范式（不改）
```

**Structure Decision**: **沿用既有项目架构**。i18n 正文集中于既有 `utils/I18n.ets`（单文件扩词典，避免多词典文件的加载与合并复杂度）；页面侧沿用**设置页已验证的范式**（`@StorageLink('locale')` + 页面私有 `tr()` 读取 `this.locale`），保证切换即时重渲染。**不新增目录、不新增依赖、不改导航装配结构**（仅改其中文案与订阅）。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | ----------- | ------------------------------- |

## Research & Decisions

**Decision 1 — 词典组织**
- **Decision**: 在既有 `I18n.ets` 内**按页面前缀**扩词典（`nav.*` / `home.*` / `learning.*` / `schedule.*` / `campus.*` / `ai.*` / `login.*` / `status.*` / `common.*`），单文件维护。
- **Rationale**: 规模可控（首批数百条级）；单文件避免多词典合并与热重载复杂度；前缀便于定位与后续批次追加。
- **Alternatives considered**: 按模块拆多词典文件（当前规模无需）；引入三方 i18n 库（与"无新增依赖"约束冲突）。

**Decision 2 — 参数化文案**
- **Decision**: 新增 `static tp(key: string, args: Record<string, string>): string`：模板中使用 `{name}` 占位，进行**安全替换**（未提供参数时保留占位符原文而非抛错），并复用 `t()` 的回退链。
- **Rationale**: 满足 FR-009（含变量文案）且不与既有 `t(key, locale?)` 重载冲突。
- **Alternatives considered**: 字符串拼接（顺序耦合、易错）；重载 `t()` 增加参数（与既有重载语义混淆）。

**Decision 3 — 即时切换机制（沿用已验证范式）**
- **Decision**: 每个迁移页面声明 `@StorageLink('locale') locale: string`，并定义页面私有 `tr(key)`（内部调用 `I18n.t(key, this.locale)`）供 UI 使用；由 `locale` 建立渲染依赖，切换即重渲染。
- **Rationale**: 设置页已用该范式验证通过（静态 `I18n.t()` 调用**不建立**渲染依赖，仅"显式读取 `this.locale` 的元素"才变脏）；避免全局广播/重建页面。
- **Alternatives considered**: 全局事件广播强制刷新（可能打断用户操作）；重启生效（不满足 SC-001）。

**Decision 4 — 迁移边界（业务数据不翻译）**
- **Decision**: 仅迁移**静态 UI 文案**（标题、区块名、按钮、行标签、占位、状态与错误提示）；**业务数据**（课程名、邮件主题、通知标题、机构名、日期格式由本地化函数处理）保持原样。
- **Rationale**: 满足 FR-011 与 SC-002（残留中文率仅针对静态文案）。
- **Alternatives considered**: 翻译数据（不可行且违背语义）。

**Decision 5 — 数据文案文件处理**
- **Decision**: 若 `HomeData.ets` / `LearningData.ets` 中存在**面向 UI 的静态文案**（如问候语模板、区块名），一并迁移为键；若为业务/示例数据，保持原样。迁移前后保持函数签名不变。
- **Rationale**: 避免"页面已迁移但数据文件仍硬编码中文"的残留（FR-002），同时不破坏数据契约。
- **Alternatives considered**: 一律不动数据文件（可能残留中文）；大改为数据+文案分层（超出范围）。

**Decision 6 — 共享组件文案来源**
- **Decision**: **不改** `components/Ui` 各组件的默认文案/结构，由调用方传入已翻译字符串（组件保持与 i18n 解耦）。
- **Rationale**: 避免组件对 i18n 产生依赖与全局状态耦合；迁移集中在页面侧。
- **Alternatives considered**: 组件内部调用 `t()`（耦合框架、且组件默认值语义模糊）。

**Decision 7 — 未迁移范围的回退保证**
- **Decision**: 未迁移页面**不调用** `t()`（保持硬编码中文），因此天然满足"回退中文且无键名外泄"；同时对**已迁移页面**，词典缺项按 `t()` 既有回退链处理（当前语言 → 中文 → 可读占位）。
- **Rationale**: 满足 FR-008/SC-003；不引入"半迁移"页面的键名外泄风险。
- **Alternatives considered**: 全量替换后逐页补键（中间态易泄漏键名）。

## Data Model

**翻译词条（扩展）**: 键（带页面前缀）→ `{ zh: string, en: string }`

**参数化模板**: 值中可含 `{name}` 占位（由 `tp()` 安全替换）

**导航项**: 标签键（`nav.home`/`nav.learning`/`nav.schedule`/`nav.campus`/`nav.ai`/`nav.settings`）+ 页面标识

**状态文案**: 加载中 / 空态 / 失败 / 重试 / 演示提示（前缀 `status.*`）

## Contracts & Interfaces

**框架契约（`I18n`，改造后）**
- `static t(key: string, locale?: string): string` —— 既有语义不变（回退链：当前/指定语言 → 中文 → 可读占位）
- `static tp(key: string, args: Record<string, string>): string` —— **新增**：参数化翻译（`{name}` 安全替换；缺参保留原文）
- `static setLocale(locale: string): void` / `static getLocale(): string` —— 既有（校验 + AppStorage + 持久化）

**页面契约（迁移范式）**
- 页面声明 `@StorageLink('locale') locale: string`；私有 `tr(key)` = `I18n.t(key, this.locale)`；`trp(key, args)` = `I18n.tp(key, args)`
- 所有静态文案经 `tr/trp` 输出；**不得**残留硬编码中文
- 页面函数签名/对外组件入参**不变**（仅文案来源变化）

**依赖契约（复用，不改）**
- `SettingsManager.setLocale`（持久化）、`AppStorage 'locale'`（运行时订阅）
- `components/Ui`（组件不改，文案由调用方传入）
