# Feature Specification: i18n 批次二（校园子页 / 学习详情页 / 顶层页文案迁移）

**Created**: 2026-10-16
**Status**: Draft
**Input**: User description: "i18n 下一批次（可立即开工，机械但量大）：校园子页 + 学习子页详情页 + ClassroomPage/GradesPage/PlaceholderPage 文案迁移为词典键（复用已就绪的 I18n 框架与 tr() 范式）"（经澄清：按**实际硬编码清单**执行并复核已迁移页；**只译 UI 静态文案**，服务数据/演示示例不译；spec 产物新建 `utils/i18n-batch2/`）。

## Overview

将仍为硬编码的 UI **静态文案**迁移为 `I18n` 词典键，复用既有框架（`t()`/`tp()` + `@StorageLink('locale')`），实现中英运行时切换。**服务返回的数据与演示示例数据不翻译**；本特性为纯文案迁移，**不改变页面逻辑、布局与数据流**。

**目标页（实际清单）**
- 校园子页（9）：`FinancePage`、`MailPage`、`MailComposeView`、`MailDetailView`、`NetworkPage`、`NewsPage`、`ProgramPage`、`ReservationPage`、`SportsBookingPage`
- 顶层页（3）：`ClassroomPage`、`GradesPage`、`PlaceholderPage`
- 学习详情（4+1）：`CourseDetailPage`、`FileDetailPage`、`HomeworkDetailPage`、`NotificationDetailPage`、`WebViewerPage`
- 已迁移页复核（5）：`LibrarySeatPage`、`LibraryRoomPage`、`DormitoryPage`、`LaundryPage`、`PETestPage`（补齐遗漏硬编码）

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 校园子页文案双语 (Priority: P1)

用户在"校园"下进入财务/邮箱（列表/撰写/详情）/校园网/资讯/培养方案/场馆预约/体育预约等子页，界面静态文案（标题、按钮、空态、错误、提示、标签）随语言设置显示中文或英文。

**Why this priority**: 校园子页是用户高频入口，硬编码中文在英文模式下直接破坏可用性。

**Independent Test**: 切到英文后逐一进入上述子页，界面上无残留中文静态文案（数据除外）。

**Acceptance Scenarios**:

1. **Given** 语言为英文，**When** 进入财务/邮箱/校园网/资讯/培养方案/场馆预约/体育预约页，**Then** 标题、按钮、状态、错误与提示均为英文
2. **Given** 语言为中文，**When** 进入同一批页面，**Then** 文案为中文（与迁移前一致）
3. **Given** 页面处于加载/错误/空态，**When** 渲染，**Then** 状态文案同样随语言切换

---

### User Story 2 - 顶层页文案双语 (Priority: P1)

`ClassroomPage`（空教室）、`GradesPage`（成绩）、`PlaceholderPage`（占位页）的静态文案随语言切换。

**Why this priority**: 三个页面由校园页直达，属主路径。

**Independent Test**: 英文模式下进入三页，无残留中文静态文案。

**Acceptance Scenarios**:

1. **Given** 语言为英文，**When** 进入空教室/成绩/占位页，**Then** 标题、表头、状态、按钮、空态均为英文
2. **Given** 存在动态计数/周次等，**When** 渲染，**Then** 使用参数化词条（占位符）而非硬编码拼接

---

### User Story 3 - 学习详情页文案双语 (Priority: P1)

课程详情、文件详情、作业详情、通知详情、网页浏览（WebViewer）页的静态文案随语言切换。

**Why this priority**: 学习详情是高频深链路径。

**Independent Test**: 英文模式下进入四个详情页与 WebViewer，无残留中文静态文案。

**Acceptance Scenarios**:

1. **Given** 语言为英文，**When** 进入课程/文件/作业/通知详情页，**Then** 标题、字段标签、操作按钮、状态与提示均为英文
2. **Given** 进入 WebViewer，**When** 渲染工具栏/提示，**Then** 文案随语言切换（网页正文本身不译）

---

### User Story 4 - 已迁移页复核与即时刷新 (Priority: P2)

复核已迁移页（图书馆座位/研读间/宿舍/洗衣机/体测）补齐遗漏硬编码；所有目标页在切换语言时**即时重渲染**。

**Why this priority**: 避免"部分迁移"造成的混杂文案，并保证切换体验一致。

**Independent Test**: 逐页扫描无遗漏；在设置页切换语言后返回目标页，文案立即变更（无需重启）。

**Acceptance Scenarios**:

1. **Given** 已迁移页存在遗漏硬编码，**When** 复核，**Then** 补齐为词典键
2. **Given** 任一目标页可见，**When** 在设置切换语言，**Then** 返回该页文案已即时更新

---

### Edge Cases

- 服务数据（课程名、邮件主题/正文、资讯标题/正文、餐厅/楼宇名、学号等）保持原样，**不翻译**
- 演示模式内置示例数据保持原样，**不翻译**
- 词典未命中：沿用回退链（当前语言 → 中文 → 可读占位），禁止空白或键名外泄
- 动态文案（计数/周次/名称）：使用 `tp()` 占位符，禁止硬编码拼接
- 仅文案迁移：不得改变布局、交互、数据请求或业务逻辑

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 目标页的所有**可见静态文案** MUST 经 `t()/tp()` 取值；迁移后 MUST NOT 残留硬编码中文可见文案
- **FR-002**: 新词条 MUST 按既有前缀约定命名（`campus.*`/`mail.*`/`network.*`/`news.*`/`program.*`/`reservation.*`/`sports.*`/`classroom.*`/`grades.*`/`learning.*`/`webviewer.*`/`common.*`/`status.*`），且 **zh/en 成对**
- **FR-003**: 服务返回数据与演示示例数据 MUST NOT 被翻译
- **FR-004**: 目标页 MUST 订阅 `@StorageLink('locale')`，语言切换后**即时重渲染**
- **FR-005**: 含变量文案 MUST 使用 `tp()` 占位符（如 `{n}`/`{name}`），不得以字符串拼接替代
- **FR-006**: 回退链 MUST 沿用既有语义（未命中 → 中文 → 可读占位），禁止空白/键名外泄
- **FR-007**: 迁移 MUST NOT 改变页面逻辑、布局、交互与数据流（纯文案迁移）
- **FR-008**: 已迁移页（LibrarySeat/LibraryRoom/Dormitory/Laundry/PETest）MUST 复核并补齐遗漏硬编码文案
- **FR-009**: 词典键 MUST 唯一且 zh/en 成对；不得与既有键冲突
- **FR-010**: 迁移后 MUST 通过 `arkts_check` 与构建（ArkTS 严格模式）

### Key Entities *(include if feature involves data)*

- **I18n 词条**：键（唯一）、中文文案、英文文案（成对）
- **目标页清单**：校园子页 9 / 顶层页 3 / 学习详情 4+1 / 已迁移页复核 5
- **不译内容**：服务数据、演示示例数据、网页正文/邮件正文等富文本

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 目标页迁移后**硬编码中文可见文案残留数 = 0**（静态扫描 + 英文模式走查）
- **SC-002**: 切换 zh↔en 后目标页文案**即时切换成功率 = 100%**（无需重启）
- **SC-003**: 新增词条 **zh/en 成对率 = 100%**，无重复/冲突键
- **SC-004**: 服务数据与演示示例**被翻译处数 = 0**
- **SC-005**: 页面逻辑/布局/数据流**回归失败数 = 0**（迁移前后行为一致）
- **SC-006**: `arkts_check` 0 错误（唯一允许噪声 = `Logger.ets` 的 BuildProfile），构建成功

## Assumptions

- 复用既有 `I18n` 框架与 `tr()` 范式（`t()`/`tp()`/`@StorageLink('locale')`）
- 仅迁移 UI 静态文案；数据与演示示例不译
- `WebViewerPage` 纳入范围（其网页正文不译）
- 纯文案迁移，不新增依赖、不改布局/逻辑
- 词典规模将显著增长（单文件 `I18n.ets`）；如体量过大可按前缀分组维护，但**对外 API 不变**

## Open Questions

- 演示示例数据是否在后续批次补充英文版本（本期不译）
- 富文本（邮件正文/资讯正文/Markdown）是否需要在渲染层做语言相关处理（本期不涉及）
