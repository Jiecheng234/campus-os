# Implementation Plan: i18n 批次二（校园子页 / 学习详情页 / 顶层页文案迁移）

**Input**: Feature specification: `entry/src/main/ets/utils/i18n-batch2/spec.md`

**Note**: 本特性产物按项目约定与既有 i18n 特性同区域放置（`entry/src/main/ets/utils/i18n-batch2/`）。

## Summary

将 17 个目标页（校园 9 + 顶层 3 + 学习详情 4+1）中仍**硬编码**的 UI 静态文案迁移为 `I18n` 词典键，并复核 5 个已迁移页的遗漏。复用既有框架（`t()`/`tp()` + `@StorageLink('locale')`），实现中英即时切换。**纯文案迁移**：不改逻辑/布局/数据流；服务数据与演示示例不译。

技术路径：扩列 `utils/I18n.ets` 词典（按前缀分组、zh/en 成对）→ 各页按既有迁移范式接入 `@StorageLink('locale')` + `tr()`/`trp()` 并替换字面量 → 静态扫描收口。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `utils/I18n.ets`（`I18n.t`/`I18n.tp`）、`@StorageLink('locale')`；无新增依赖
**State Management**: 沿用 V1（`@StorageLink('locale')` 订阅语言）
**Storage**: N/A（locale 持久化沿用既有 `SettingsManager.setLocale`）
**Testing**: `arkts_check` + `devecocli build` + 模拟器走查（中/英切换）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量 / 纯文案迁移）
**Performance Goals**: 无新增运行时开销（词典查找与既有页面一致）
**Constraints**: 不改逻辑/布局/数据流（SC-005）；数据与演示示例不译（SC-004）；词条 zh/en 成对且唯一（SC-003）；ArkTS 严格模式
**Scale/Scope**: 17 个目标页 + 5 个复核页；`I18n.ets` 词典显著扩列（预计数百键）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/utils/i18n-batch2/
├── feature.json         # 特性目录记录
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── utils/I18n.ets                              # 改造：扩列词典（按前缀分组，zh/en 成对）
├── pages/
│   ├── campus/FinancePage.ets                  # 迁移
│   ├── campus/MailPage.ets                     # 迁移
│   ├── campus/MailComposeView.ets              # 迁移
│   ├── campus/MailDetailView.ets               # 迁移
│   ├── campus/NetworkPage.ets                  # 迁移
│   ├── campus/NewsPage.ets                     # 迁移
│   ├── campus/ProgramPage.ets                  # 迁移
│   ├── campus/ReservationPage.ets              # 迁移
│   ├── campus/SportsBookingPage.ets            # 迁移
│   ├── ClassroomPage.ets                       # 迁移
│   ├── GradesPage.ets                          # 迁移
│   ├── PlaceholderPage.ets                     # 迁移
│   ├── learning/CourseDetailPage.ets           # 迁移
│   ├── learning/FileDetailPage.ets             # 迁移
│   ├── learning/HomeworkDetailPage.ets         # 迁移
│   ├── learning/NotificationDetailPage.ets     # 迁移
│   ├── learning/WebViewerPage.ets              # 迁移
│   ├── campus/LibrarySeatPage.ets              # 复核补齐
│   ├── campus/LibraryRoomPage.ets              # 复核补齐
│   ├── campus/DormitoryPage.ets                # 复核补齐
│   ├── campus/LaundryPage.ets                  # 复核补齐
│   └── campus/PETestPage.ets                   # 复核补齐
```

**Structure Decision**: **沿用既有项目架构**。i18n 不引入新目录/依赖；页面按既有"已迁移页范式"（`@StorageLink('locale')` + 私有 `tr()`/`trp()`）就地迁移；词典集中在既有 `I18n.ets`（对外 API 不变）。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 词典组织（单文件扩列，前缀分组）**
- **Decision**: 在既有 `utils/I18n.ets` 内按前缀分组扩列（`campus.*`/`mail.*`/`network.*`/`news.*`/`program.*`/`reservation.*`/`sports.*`/`classroom.*`/`grades.*`/`learning.*`/`webviewer.*`/`common.*`/`status.*`），保持 `I18nEntry { zh, en }` 形态与 `t()`/`tp()` API 不变。
- **Rationale**: 与既有框架/迁移范式一致，改动面小、可机械执行；对外 API 稳定。
- **Alternatives considered**: 按前缀拆多词典文件（需改 `I18n` 合并逻辑，超出"纯文案迁移"范围）。

**Decision 2 — 页面接入范式（复用已迁移页写法）**
- **Decision**: 每个目标页：`import { I18n } from '<rel>/utils/I18n'`；`@StorageLink('locale') locale: string = 'zh'`；私有 `tr(key)` / `trp(key,args)`；只替换**可见静态字面量**，数据绑定原样保留。
- **Rationale**: 与 `CampusPage`/`SettingsPage`/`LibrarySeatPage` 等已迁移页完全一致，保证即时刷新与回退链。
- **Alternatives considered**: 全局单例读取 locale（无订阅、不即时刷新）。

**Decision 3 — 动态文案参数化**
- **Decision**: 含变量文案（计数/周次/名称/日期）一律 `tp('key', { 'n': ..., 'name': ... })`；不得拼接硬编码片段。
- **Rationale**: FR-005；避免"半句翻译"。
- **Alternatives considered**: 拼接（英文语序会错）。

**Decision 4 — 数据与演示示例不译**
- **Decision**: 仅替换 UI 静态文案；服务字段（课程名/邮件主题/资讯标题/楼宇名/学号等）与演示示例数据保持原样。
- **Rationale**: FR-003/SC-004；数据由服务端/示例决定，翻译会失真。
- **Alternatives considered**: 也译演示数据（超出本轮范围）。

**Decision 5 — 已迁移页复核**
- **Decision**: 对 `LibrarySeat`/`LibraryRoom`/`Dormitory`/`Laundry`/`PETest` 做**可见中文字面量扫描**，补齐遗漏并新建词条（复用已有前缀）。
- **Rationale**: FR-008；消除"部分迁移"混杂。
- **Alternatives considered**: 不复核（残留风险）。

**Decision 6 — 收口校验**
- **Decision**: 迁移后对目标页做**硬编码中文可见文案扫描**（排除注释/数据/示例）+ `arkts_check` + 构建；并在英文模式走查即时切换。
- **Rationale**: SC-001/SC-002/SC-006。
- **Alternatives considered**: 仅人工走查（易漏）。

**Decision 7 — 不改逻辑/布局**
- **Decision**: 迁移只替换字符串表达式；不得改动组件结构、样式、请求与状态流。
- **Rationale**: FR-007/SC-005。

## Data Model

**I18nEntry（既有）**: `zh: string` · `en: string`

**词条命名约定（前缀 → 页面）**

| 前缀 | 页面 |
|---|---|
| `campus.finance.*` | FinancePage |
| `mail.*` | MailPage / MailComposeView / MailDetailView |
| `campus.network.*` | NetworkPage |
| `campus.news.*` | NewsPage |
| `campus.program.*`（既有） | ProgramPage |
| `campus.reservation.*` | ReservationPage |
| `campus.sports.*` | SportsBookingPage |
| `classroom.*` | ClassroomPage |
| `campus.grades.*` | GradesPage |
| `common.placeholder.*` | PlaceholderPage |
| `learning.course.*` / `learning.file.*` / `learning.homework.*` / `learning.notification.*` | 学习详情页 |
| `webviewer.*` | WebViewerPage |
| `common.*` / `status.*`（既有，必要时复用） | 通用 |

**不译数据**: 服务字段、演示示例、网页正文/邮件正文（富文本）。

## Contracts & Interfaces

**I18n（既有 API，不改）**
- `I18n.t(key: string, locale?: string): string`
- `I18n.tp(key: string, args: Record<string, string>, locale?: string): string`
- locale 运行时状态：`AppStorage['locale']`（页面 `@StorageLink('locale')` 订阅）

**页面接入契约（每页）**
- `@StorageLink('locale') locale: string = 'zh'`
- `private tr(key: string): string { return I18n.t(key, this.locale); }`
- `private trp(key: string, args: Record<string, string>): string { return I18n.tp(key, args, this.locale); }`
- 仅替换可见静态文案；数据绑定/逻辑不变。

**校验契约**
- 硬编码中文可见文案扫描（排除注释、数据字段、示例）→ 目标页残留 = 0（SC-001）
- 词条 zh/en 成对且无重复（SC-003）

## Changelog

- 2026-10-16：初版计划（i18n 批次二：17 目标页 + 5 复核页；纯静态文案迁移）。
