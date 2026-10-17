# Implementation Plan: 清华邮件接入（Coremail 读写）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/campus-mail/spec.md`

**Note**: 本特性产物按项目约定与校园子页源码同区域放置（`entry/src/main/ets/pages/campus/campus-mail/`），不创建 `spec/` 目录。

## Summary

为"校园邮件"接入 Coremail 真实数据（读写）：建立/维护 Coremail 会话（`sid`），实现文件夹与邮件列表（分页）、详情阅读（受控 Web 渲染正文 + 附件元信息）、关键词搜索，以及写操作（标记已读、删除、移动、发送）。技术路径：新增一个邮件服务（会话建立复用既有"通用漫游"+ 新增的"取最终地址"能力，接口调用复用 `HttpClient.postJson`），将现有 `MailPage.ets` 改造为真实/演示双模式并采用页内多级（列表 → 详情 → 撰写），撰写与详情拆为独立组件以控制单文件体积。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get` / `postJson` / `resolveFinalUrl`，含 Cookie 管理）、`CampusDataService.roamByYyfwidHtml`（通用漫游）、`TsinghuaAuthService.withSessionRecovery`、`SessionManager`、ArkWeb `Web`（受控正文渲染，已有先例）；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`）
**Storage**: N/A（会话为内存态，约 20 分钟缓存；无持久化）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 列表 3s / 详情 3s / 搜索 5s / 写操作反馈 ≤5s（SC-001~004）
**Constraints**: 演示模式零请求（SC-006）；异常 100% 可读中文错误（SC-007）；正文 0 脚本 0 乱码（SC-008）；写操作二次确认；ArkTS 严格模式
**Scale/Scope**: 新增 1 服务文件 + 2 视图组件；改造 1 个既有页面与 1 处装配；实体 7 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/campus-mail/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── HttpClient.ets                         # 复用：get / postJson / resolveFinalUrl
│   ├── auth/
│   │   └── SessionManager.ets                 # 改造：新增 getMailService()
│   └── campus/
│       ├── CampusDataService.ets              # 复用：roamByYyfwidHtml（通用漫游）
│       ├── LibraryRoomService.ets             # 参考：会话装配 + 错误语义范式
│       └── MailService.ets                    # 新增：模型 + 会话 + Coremail 接口 + 容错解析
└── pages/
    └── campus/
        ├── MailPage.ets                       # 改造：真实/演示 + 页内多级（列表/文件夹/搜索）
        ├── MailDetailView.ets                 # 新增：详情渲染（含受控 Web 正文 + 附件元信息）
        └── MailComposeView.ets                # 新增：撰写/发送表单
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。邮件为单个校园子页，但涉及多级视图与较大渲染量，故在"服务单文件 + 页面组件"的既有范式下，把**详情与撰写拆为两个仅被本页内联渲染的组件**（控制单文件体积、便于独立维护）。入口沿用现有 `MailPage.ets`，**不修改 `CampusPage.ets`**（不新增分发项）。不新增目录、不新增依赖、不新增资源。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — Coremail 会话建立与维护**
- **Decision**: 会话＝①经**信息门户漫游**（复用 `roamByYyfwidHtml(信息门户子系统标识)`）建立门户会话；②对"邮箱门户地址"与"Coremail 入口地址"依次**跟随重定向取最终地址**（复用 `HttpClient.resolveFinalUrl`）并从最终地址/地址参数中**解析 `sid`**；③以该地址再取一次（完成 Coremail 侧跳转与 Cookie 落地）；④会话内存缓存约 20 分钟；⑤接口返回会话失效类错误码时**清空缓存并强制重建一次**再重试。
- **Rationale**: 与参考实现逐项对应（门户漫游 → 解析 sid → 同步 Cookie → 缓存 + 失效自愈）；所需"取最终地址"能力已在本项目的校园网特性中实现并可复用。
- **Alternatives considered**: 每次请求都重建会话（开销大且可能触发风控）；依赖 `sid` 仅从 Cookie 解析（参考证明需 URL 与 Cookie 双路径兜底）。

**Decision 2 — 接口调用形态与列表多形态回退**
- **Decision**: 业务调用统一为"JSON POST（`func` 查询参数 + JSON 体）"，复用 `HttpClient.postJson`；列表按参考顺序**依次尝试多种形态**（线程列表 / 扁平列表 × 排序字段）并在全空时再尝试一次**兼容接口**；任一形态返回可用数据即终止；全部失败返回空结果（UI 空态 + 可重试）。会话失效类错误码在调用层自动重建会话并重试一次。
- **Rationale**: Coremail 在不同账户设置下返回结构不同（参考实现即为多形态回退）；容错是可用性的关键。
- **Alternatives considered**: 只实现单一形态（在部分账户下列表恒为空）；一次性失败即报错（体验差）。

**Decision 3 — 列表/详情解析的容错策略**
- **Decision**: 不假设固定字段路径：列表解析采用"递归寻找邮件数组 + 递归寻找总数"的策略并逐项映射（发件人/收件人/主题/日期/未读/星标/含附件/摘要），映射失败的条目跳过；若"总数 > 0 但解析出 0 条"则抛**可读错误**（提示结构不兼容、可重试）。发件人/收件人等联系人字段兼容"字符串 / 对象 / 数组"三种形态。
- **Rationale**: 参考实现即如此（`findMessageArrays`/`findTotal`/`parseContacts`）；避免因字段漂移导致整页不可用。
- **Alternatives considered**: 严格按固定字段解析（上游一变更即全挂）。

**Decision 4 — 富文本正文渲染（禁脚本、防乱码）**
- **Decision**: 正文分两路：纯文本直接以文本组件展示；富文本采用**受控 Web 渲染**——与"资讯详情"同款方案（构造最小 HTML 文档 + CSP 禁脚本、禁文件访问、禁缩放、关暗色，同步 WebVPN Cookie 后加载，`loadData` 五参齐全）；正文为空时展示占位文案。
- **Rationale**: 复用项目已验证的渲染方案（资讯详情），满足 SC-008（0 脚本、0 乱码）与附件不外链下载的约束。
- **Alternatives considered**: 自研富文本组件（成本高）；直接注入原始 HTML 不设 CSP（安全风险）。

**Decision 5 — 写操作（标记已读/删除/移动/发送）**
- **Decision**: ①**标记已读**：打开详情后调用"更新邮件信息"接口置已读；失败**不阻塞阅读**（仅记日志/toast），返回列表时以刷新为准；②**删除**：`AlertDialog.show` 二次确认后调用删除接口，成功 toast + 刷新；③**移动**：先选择目标文件夹（弹窗/列表）再二次确认，调用"更新邮件信息"接口改所属文件夹；④**发送**：撰写表单（收件人/抄送/主题/正文）+ 必填校验 + 二次确认 + 调用撰写接口；失败保留表单内容并展示服务端消息；成功后提示并返回列表（已发送需刷新可见）。
- **Rationale**: 与参考实现的接口与语义一致（`mbox:updateMessageInfos` / `mbox:deleteMessages` / `mbox:compose`）；不可逆操作需确认（FR-009~FR-011）。
- **Alternatives considered**: 无确认直接执行（误操作风险）；草稿保存（本轮明确不在范围）。

**Decision 6 — 页内多级与组件拆分**
- **Decision**: `MailPage.ets` 持有导航状态（LIST / DETAIL / COMPOSE）与列表态（文件夹、搜索词、分页）；`MailDetailView.ets` 与 `MailComposeView.ets` 为仅被本页内联渲染的组件（输入：数据 + 回调）。返回语义：详情/撰写 → 列表；列表 → 关闭订阅页（沿用既有返回链）。
- **Rationale**: 控制单文件体积与职责边界，同时保持"不新增校园页分发项"的最小回归面。
- **Alternatives considered**: 全部塞进一个文件（体积大、可读性差）；新增独立路由页（回归面大）。

**Decision 7 — 演示模式与只读/写边界**
- **Decision**: `isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode()`；非真实模式使用内置示例数据、**零网络请求**，且写操作**不发起请求**（给出提示）。
- **Rationale**: 与既有页面约定一致（FR-001/SC-006）。
- **Alternatives considered**: 演示模式仍尝试真实请求（违背零请求约束）。

## Data Model

**MailFolder**: `id: number` · `name: string` · `system: string`（inbox/drafts/sent/deleted/junk）

**MailContact**: `name: string` · `address: string`

**MailAttachment**: `id: string` · `name: string` · `size: number`（仅元信息）

**MailMessageSummary**: `id` · `fid: number` · `from: MailContact[]` · `to: MailContact[]` · `subject` · `date` · `unread: boolean` · `flagged: boolean` · `hasAttachment: boolean` · `brief`

**MailMessageDetail**（继承摘要）: `cc: MailContact[]` · `contentText: string` · `contentHtml: string` · `attachments: MailAttachment[]`

**MailListResult**: `messages: MailMessageSummary[]` · `total: number`

**ComposeDraft**: `to: string` · `cc: string` · `bcc: string` · `subject: string` · `content: string`

**页面状态机**: `LIST（文件夹 + 搜索 + 分页）→ DETAIL（+ 已读标记副作用）→ COMPOSE（发送）`；各态独立维护加载/错误/空态。

## Contracts & Interfaces

**服务契约（新增 `MailService`）**
- `ensureMailSession(force?: boolean): Promise<void>` —— 建立/重建 Coremail 会话（缓存 20 分钟；失效自愈：清缓存 + 强制重建一次）
- `listMessages(fid: number, start: number, limit: number): Promise<MailListResult>` —— 多形态回退解析；无法解析时抛可读错误
- `searchMessages(pattern: string, start: number, limit: number): Promise<MailListResult>`
- `readMessage(id: string): Promise<MailMessageDetail>` —— 详情（正文 + 附件 + 抄送）
- `markRead(ids: string[], read: boolean): Promise<void>`
- `deleteMessages(ids: string[]): Promise<void>`
- `moveMessages(ids: string[], fid: number): Promise<void>`
- `sendMail(draft: ComposeDraft): Promise<void>`
- 以上除会话方法外均包在"会话失效自愈 + 可读错误"的调用包装内。

**服务装配契约（`SessionManager`）**
- `static getMailService(): MailService` —— 单例；以 `getAuthService().getHttpClient()`、`getCampusDataService()` 与 auth 构造（与 `getLibrarySeatService()` 同构）。

**依赖契约（复用，不改）**
- `HttpClient.get` / `HttpClient.postJson` / `HttpClient.resolveFinalUrl`
- `CampusDataService.roamByYyfwidHtml(yyfwid)`
- 受控 Web 渲染（ArkWeb `Web` + `loadData` 五参 + CSP 禁脚本），与资讯详情同款

**UI 契约**
- `MailPage`（改造）：头部（标题"校园邮件"+ 右上角"撰写"与"刷新"）+ 文件夹切换 chips + 搜索框 + 列表（发件人/主题/摘要/时间/未读与附件标记）+ 未读计数 + "加载更多" + 空态/错误态；演示模式零请求。
- `MailDetailView`（新增）：收发抄送/主题/时间/正文（纯文本或受控 Web）/附件元信息列表；操作入口（删除/移动）；返回列表。
- `MailComposeView`（新增）：收件人/抄送/主题/正文输入 + 发送（必填校验 + 二次确认）；失败保留内容。
- 布局遵循 `width('100%') + constraintSize({ maxWidth: '100%' })` + 左右 margin 16；日期选择/工具行等同等样式需带左右 margin。

**外部端点契约（沿用参考服务的路径与函数名形态）**
- 邮箱门户地址 / Coremail 入口地址（会话解析）；JSON 接口以 `func` 参数区分：列表（线程/扁平）、搜索、更新邮件信息（已读/移动）、删除、撰写发送；兼容接口作为列表回退。端点与函数名集中定义于服务文件顶部。
