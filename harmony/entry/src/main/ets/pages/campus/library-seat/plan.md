# Implementation Plan: 图书馆座位查询（只读）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/library-seat/spec.md`

**Note**: 本特性产物按项目约定与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/library-seat/`），不创建 `spec/` 目录。

## Summary

为"场馆预约 → 图书馆座位"接入真实数据（只读）：馆列表 → 楼层（使用率，可用/总数）→ 区域（可用/总数/已预约）→ 座位（名称 + 状态），支持"今天/明天"切换，并展示"我的预约"记录。技术路径：在既有分层内新增一个只读服务（子系统的 id 漫游激活 + 两层会话恢复 + JSON 接口解析），新增一个页内多级浏览组件，并把既有"场馆预约"入口页接上（不新增校园页分发项）；预约/取消不迁移，以提示引导官方小程序。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get`）、`TsinghuaAuthService.roamIdSubsystem`（id 漫游）+ `withSessionRecovery`（两层恢复）、`SessionManager`；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: N/A（无持久化；不缓存访问令牌——本轮只读浏览不需要）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 进入 3s 内出馆列表与楼层使用率；切换日期 3s 内刷新（SC-001/002）
**Constraints**: 演示模式零网络请求（SC-006）；异常 100% 可读中文错误（SC-007）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 新增 1 个服务文件 + 1 个浏览组件；改造 1 个入口页；实体 6 个（馆/楼层/区域/座位/预约记录/日期选择）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/library-seat/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── auth/
│   │   ├── TsinghuaAuthService.ets            # 复用：roamIdSubsystem(payload) + withSessionRecovery<T>(op, onReroam?, label)
│   │   └── SessionManager.ets                 # 改造：新增 getLibrarySeatService()
│   └── campus/
│       ├── CampusDataService.ets              # 参考：id 漫游 + 恢复结构范式（宿舍电费段）
│       ├── CampusCardService.ets              # 参考：模型/JSON 解析/服务结构范式
│       └── LibrarySeatService.ets             # 新增：模型 + JSON 解析 + 只读服务
└── pages/
    └── campus/
        ├── ReservationPage.ets                # 改造：入口卡片 → 内联渲染图书馆座位组件；研读间/体育场馆提示"即将支持"
        └── LibrarySeatPage.ets                # 新增：页内多级浏览组件（馆 → 楼层 → 区域 → 座位 + 我的预约）
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。既有校园特性均落在 `services/campus/` + `pages/campus/`；本特性同构：只读服务单一文件承载模型/解析/编排，UI 作为一个可复用组件（`LibrarySeatPage`）由既有入口页（`ReservationPage`）**内联渲染**，从而**不修改 `CampusPage` 的分发与返回链**（回归面最小）。不新增目录、不新增依赖、不新增资源。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 子系统会话与会话恢复**
- **Decision**: 进入图书馆座院子系统采用**已具备的 id 漫游能力**（`roamIdSubsystem(图书馆座位子系统标识)`），并置"已激活"标记；所有读取操作包在 `withSessionRecovery(op, reroam{重置标记 + 强制重漫游}, 'lib')` 内（默认层 1 用自定义 reroam，层 2 为完整重登录）。首个 home 页请求偶发失败忽略（对齐参考）。
- **Rationale**: 参考实现在该子系统上与宿舍电费同款 id 漫游；项目已验证该链路（电费）。使用自定义 reroam 使恢复命中正确子系统，而非默认 info 门户。
- **Alternatives considered**: (a) 默认 reroam（info 门户）——恢复后仍无法访问图书馆子系统，无效；(b) 每次操作都强制重漫游——开销大且可能触发登录节流。

**Decision 2 — 接口解析与错误语义**
- **Decision**: 图书馆接口返回 JSON；统一"取 JSON → 失败标记（status 为 false/false 字符串）→ 抛服务端 msg → 取 `data.list`（缺失则抛可读错误）"三步解析；所有解析用 `Record<string, Object>` + `asObjectArray`/`asRecord` 兜底辅助函数（对齐校园卡服务范式）。
- **Rationale**: 参考实现 `libFetchJson`/`libFetchList` 语义即此；无 HTML 解析需求，错误可读性由统一解析保障（FR-011/SC-007）。
- **Alternatives considered**: 逐接口手写解析（重复且易漏失败分支）。

**Decision 3 — 页内多级导航形态**
- **Decision**: 层级（馆 → 楼层 → 区域 → 座位；以及"我的预约"）以**同一组件内的层级状态**表达，逐级前进/返回；入口页 `ReservationPage` 内联渲染该组件，返回即回到入口卡片。系统返回键语义由入口页既有返回链处理（子层级先逐级回退）。
- **Rationale**: 用户已选择"页内多级切换"；不新增 `CampusPage` 分发项可避免改动校园页与返回分发，风险最小。
- **Alternatives considered**: 独立子页面 + `CampusPage` 分发（文件与回归面更大）。

**Decision 4 — 楼层使用率聚合**
- **Decision**: 楼层列表先取馆下的楼层（子区域）清单；对**开放**的楼层并发拉取其区域列表并聚合"可用/总数"；单层失败仅置该层为 0 且不阻塞其余楼层（对齐参考的并发 + 容错）。未开放楼层不发请求。
- **Rationale**: 楼层自身无总数，必须由区域聚合；并发可满足 3s 内出数据（SC-001），容错保证部分可用（Edge Cases）。
- **Alternatives considered**: 串行聚合（楼层多时超时风险高）；只显示楼层不显示使用率（不满足 FR-004）。

**Decision 5 — 日期与时段语义**
- **Decision**: 仅"今天/明天"两种选择；座位查询需先取该区域的"可预约日/时段"列表并命中目标日期，得到时段标识与起止时间；若为今天，则起始时间取"当前时刻或更晚"（避免请求已过去的时段）。
- **Rationale**: 对齐参考实现语义（今天/明天 + 时段命中 + 今天起始时间钳制）。
- **Alternatives considered**: 提供任意日期（超出本轮范围，服务端可预约窗口有限）。

**Decision 6 — 只读边界**
- **Decision**: 不实现预约/取消；座位/区域等处的可预约提示仅给出"预约请前往官方小程序完成"的引导（对齐参考实现"下单走小程序"）。
- **Rationale**: 用户已确认只读优先；参考实现本身即只读浏览。
- **Alternatives considered**: 一并移植预约/取消（需访问令牌获取与写接口，风险与工作量另计）。

**Decision 7 — 座位状态映射**
- **Decision**: 状态数值按约定映射为中文标签：可用 / 已预约 / 已被占用 / 其他→不可用；未知值安全回退为"不可用"。
- **Rationale**: 参考模型注释即此语义；回退避免未知值导致 UI 异常。
- **Alternatives considered**: 直接展示原始数值（可读性差，违背中文 UI 约定）。

## Data Model

**LibraryInfo（图书馆）**
| 字段 | 类型 | 说明 | 兜底 |
|---|---|---|---|
| id | number | 标识 | 0 |
| zhName | string | 中文名 | '' |
| enName | string | 英文名 | '' |
| valid | boolean | 是否开放 | false |

**LibraryFloorInfo（楼层）**: `id` · `parentId`（所属馆）· `zhName` · `enName` · `valid` · `total`（聚合）· `available`（聚合）

**LibrarySectionInfo（区域）**: `id` · `zhName` · `enName` · `valid` · `total` · `available`（= max(0, total − unavailable)）· `reservedCount`

**LibrarySeatInfo（座位）**: `id` · `name`（缺省回退为 `#id`）· `status`（1 可用 / 6 已预约 / 7 已被占用 / 其他不可用）· `type`

**LibraryBookingRecord（预约记录）**: `id` · `pos`（座位位置）· `time` · `status`

**DateChoice（日期选择）**: `0 = 今天` · `1 = 明天`

**页面层级状态（UI 状态机）**: `LIBRARY → FLOOR → SECTION → SEAT`，另含 `BOOKINGS`（我的预约）；任一层可回退到上一层；加载/错误/空态在各层独立维护。

## Contracts & Interfaces

**服务契约（新增 `LibrarySeatService`）**
- `getLibraryList(): Promise<LibraryInfo[]>` —— 只读；漫游激活（幂等）→ 取馆列表。
- `getLibraryFloorList(libraryId: number, dateChoice: number): Promise<LibraryFloorInfo[]>` —— 取楼层 + 聚合各层可用/总数（开放层并发、单层容错）。
- `getLibrarySectionList(floorId: number, dateChoice: number): Promise<LibrarySectionInfo[]>` —— 取区域（可用/总数/已预约）。
- `getLibrarySeatList(sectionId: number, dateChoice: number): Promise<LibrarySeatInfo[]>` —— 先取目标日时段（今天起始时间钳制），再取座位与状态。
- `getLibraryBookingRecords(): Promise<LibraryBookingRecord[]>` —— 我的预约记录。
- 以上均包在统一的两层会话恢复内（label `lib`），异常抛可读中文错误。

**服务装配契约（`SessionManager`）**
- `static getLibrarySeatService(): LibrarySeatService` —— 单例；以 `getAuthService().getHttpClient()` 与 auth 构造（与 `getCampusCardService()` / `getNetworkService()` 同构）。

**依赖契约（复用，不改）**
- `HttpClient.get(url: string): Promise<HttpResponse>`
- `TsinghuaAuthService.roamIdSubsystem(payload: string): Promise<void>`
- `TsinghuaAuthService.withSessionRecovery<T>(operation, onReroam?, label): Promise<T>`
- `TsinghuaAuthService.getRoamCredentials(): Promise<CampusCredentials>`（凭证缺失时抛"未登录"）

**UI 契约（入口页改造 + 新组件）**
- `ReservationPage`（改造）：保留三张入口卡片；"图书馆座位预约"卡片 → 内联渲染 `LibrarySeatPage`（返回回到卡片）；"研读间预约"/"体育场馆预约" → 提示"即将支持"（不发起请求）。
- `LibrarySeatPage`（新增组件，输入 `onBack`）：
  - 顶部 `DetailHeader`（标题随层级变化或固定"图书馆座位"）+ 右上角刷新（加载中显示进度）。
  - 日期切换：`今天 / 明天` 分段控件（仅楼层及以下层级生效，用于刷新数据）。
  - LIBRARY 层：馆列表（默认选中开放馆）→ 展示所选馆的楼层列表（zhName + 可用/总数，未开放标记"未开放"）；入口"我的预约"。
  - FLOOR 层：区域列表（zhName + 可用/总数/已预约数）。
  - SECTION 层：座位列表（名称 + 状态标签，按状态着色）。
  - BOOKINGS 层：我的预约记录（位置/时间/状态）；无记录空态。
  - 各层均有加载/错误（可重试）/空态；演示模式下使用内置示例且零请求。
  - 卡片/列表布局遵循 `width('100%') + constraintSize({ maxWidth: '100%' })` + 左右 margin 16 约定。
- 只读提示：出现可预约语义处（如座位列表底部/区域行）提供"预约请前往官方小程序完成"的说明（toast 或说明文案）。

**外部端点契约（沿用参考服务的标识与路径形态）**
- 馆树 / 区域与日期 / 可预约日时段 / 座位列表 / 我的预约：沿用参考实现中的子系统 token 与 API 路径形态；端点常量集中定义于服务文件顶部。
