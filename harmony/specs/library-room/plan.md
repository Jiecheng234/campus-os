# Implementation Plan: 研读间查询（只读，含子系统登录）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/library-room/spec.md`

**Note**: 本特性产物按项目约定与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/library-room/`），不创建 `spec/` 目录。

## Summary

为"场馆预约 → 研读间"接入真实数据（只读）：先完成**研读间专用登录**（取动态认证地址 → 跟随重定向解析登录标识 → 经既有 id 漫游建立子系统会话 → 用户信息校验账号一致），随后浏览 研读间类型 → 近 5 天日期 → 资源（房间名/人数区间/开放时间/开放标记），并展示"我的预约"记录。技术路径：在认证服务新增 `cabLogin`（**仅新增方法、不改既有**）、在 `HttpClient` 新增"跟随重定向取最终地址"能力、新增一个研读间只读服务、新增一个页内多级组件并由既有"场馆预约"入口页内联渲染；预约/取消不迁移。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get`，含手动重定向与 Cookie 注入）、`TsinghuaAuthService`（`roamIdSubsystem` / `getRoamCredentials` / `withSessionRecovery`）、`SessionManager`；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: N/A（会话与账号缓存在内存；无持久化）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 进入 5s 内出类型列表（含一次子系统登录）；选日期 3s 内出资源（SC-001/002）
**Constraints**: 演示模式零网络请求（SC-005）；异常 100% 可读中文错误（SC-006）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 新增 1 个服务文件 + 1 个浏览组件；`HttpClient` 与 `TsinghuaAuthService` 各加 1 个方法（加法式）；改造 1 个入口页与 1 处装配；实体 4 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/library-room/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── HttpClient.ets                         # 扩展（加法）：resolveFinalUrl(url) 跟随重定向返回最终地址
│   ├── auth/
│   │   ├── TsinghuaAuthService.ets            # 扩展（加法）：cabLogin() 完成研读间专用登录与账号校验
│   │   └── SessionManager.ets                 # 改造：新增 getLibraryRoomService()
│   └── campus/
│       ├── LibrarySeatService.ets             # 参考：只读服务 + withSessionRecovery 自定义 reroam 范式
│       ├── CampusCardService.ets              # 参考：模型 / JSON 解析辅助范式
│       └── LibraryRoomService.ets             # 新增：模型 + JSON 解析 + 研读间只读服务
└── pages/
    └── campus/
        ├── ReservationPage.ets                # 改造：研读间卡片 → 内联渲染 LibraryRoomPage
        └── LibraryRoomPage.ets                # 新增：页内多级（类型/近 5 天 → 资源 + 我的预约）
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。与图书馆座位同构：只读服务单一文件；UI 作为可复用组件由既有入口页**内联渲染**（不修改 `CampusPage.ets`）。研读间专用登录属"认证能力"，按参考实现与项目既有先例（`roamCardPolicy` 落在认证服务）落在 `TsinghuaAuthService`；"跟随重定向取最终地址"是通用网络能力，落在 `HttpClient`。两者**均为新增方法，不改既有签名与行为**。不新增目录、不新增依赖、不新增资源。

## Complexity Tracking

> 无 Constitution 违背项。对 2 个共享文件的修改为"新增方法、不改既有调用点"，属最小必要改动。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 修改 `HttpClient.ets` 与 `TsinghuaAuthService.ets` | 研读间登录需"跟随重定向取最终地址"（否则无法解析登录标识）与一次性子系统登录编排；二者是跨特性可复用的底层能力 | 在研读间服务内自建 RCP 请求与登录编排：重复既有 Cookie/重定向/漫游逻辑，且绕开统一封装 |

## Research & Decisions

**Decision 1 — 研读间专用登录（cab 登录）落点与流程**
- **Decision**: 在 `TsinghuaAuthService` 新增 `cabLogin(): Promise<void>`：①请求"认证地址"接口（响应为 JSON，取其中地址字段；少数环境可能为纯地址文本，做兼容）→ ②如地址非 WebVPN 域则以等价的 WebVPN 前缀替换 → ③`HttpClient.resolveFinalUrl(...)` 跟随重定向取最终地址 → ④从最终地址中解析 `/login/form/<标识>` 的登录标识（保留 `?`/`#` 之后的完整尾串）→ ⑤`roamIdSubsystem(标识)` 建立子系统会话 → ⑥请求"用户信息"接口校验：业务码为 0 且返回账号与当前登录账号一致，否则抛可读错误。
- **Rationale**: 逐行对齐参考实现的 `cabLogin`；仅引用既有 `roamIdSubsystem`，无需新漫游机制；落在认证服务与项目先例一致。
- **Alternatives considered**: (a) 放在研读间服务内（把用户信息端点与账号比对移出认证层）——与参考实现和项目先例不一致；(b) 引入新的漫游类型——无必要。

**Decision 2 — "跟随重定向取最终地址"能力**
- **Decision**: 在 `HttpClient` 新增 `resolveFinalUrl(url: string): Promise<string>`：以 GET 发起请求，沿用既有的请求头/Cookie 注入与手动重定向循环，**返回最终落点地址**（不再返回响应体）。
- **Rationale**: 既有 `manualRedirect` 已逐跳解析重定向目标，但只返回响应体；新增方法复用同一逻辑仅改变返回值，最小改动即可满足 cab 登录第 ③ 步。
- **Alternatives considered**: (a) 暴露内部"最终地址"字段（隐式状态，易被后续请求污染）；(b) 在服务层自建重定向循环（重复实现）。

**Decision 3 — 会话装配与恢复**
- **Decision**: 研读间服务内维护"会话已建立"标记与账号号缓存；`assureCabSession()` 校验用户信息（最多两轮：失败则强制重登后复查）；所有读取包在 `withSessionRecovery(op, reroam{重置标记 + 强制重登}, 'cab')` 中（label `cab`，reroam 走研读间自己的重登录）。
- **Rationale**: 对齐参考 `ensureCabLogin` / `withCabRetry` / `assureCabSession` 语义；复用项目已验证的恢复链。
- **Alternatives considered**: 默认 reroam（info 门户）——恢复后无法访问研读间子系统，无效。

**Decision 4 — 日期范围与格式**
- **Decision**: 展示"近 5 天"（今天起偏移 0–4 天）；资源请求使用 `yyyyMMdd` 形式，列表展示使用 `YYYY-MM-DD` 形式；"我的预约"查询区间为"今天 → 今天+6 天"（`YYYY-MM-DD`）。
- **Rationale**: 逐项对齐参考实现（近 5 天与 7 天查询窗口）。
- **Alternatives considered**: 仅今天/明天（与图书馆座位一致但与参考不同）；可自定义日期（超范围）。

**Decision 5 — 接口解析与错误语义**
- **Decision**: 研读间接口统一"JSON 解析 → 业务码非 0 则抛服务端消息 → 取 data"三步；解析用 `Record<string, Object>` + `asRecord`/`asObjectArray` 兜底；非 JSON 抛可读错误（附截断片段）。
- **Rationale**: 对齐参考 `cabFetch`；保障 FR-009 / SC-006。
- **Alternatives considered**: 逐接口手写解析（重复且易漏错误分支）。

**Decision 6 — 只读边界**
- **Decision**: 不实现预约与取消；在类型/资源处给出"完整下单请在官方小程序完成"的引导（对齐参考 footer 文案语义）。
- **Rationale**: 用户已确认只读；参考实现亦如此。
- **Alternatives considered**: 一并移植预约与取消（需成员搜索与写接口，超出本轮）。

**Decision 7 — 页内多级与入口**
- **Decision**: 研读间组件内部两层（类型列表含"近 5 天"日期项 → 该类型某天的资源列表），另含"我的预约"视图；由 `ReservationPage` 的"研读间预约"卡片**内联渲染**（返回回到卡片），不改 `CampusPage.ets`。
- **Rationale**: 与图书馆座位保持一致的交互与最小回归面；用户已确认"页内多级"形态。
- **Alternatives considered**: 独立子页面 + 校园页分发（回归面更大）。

## Data Model

**LibRoomKind（研读间类型）**: `kindId: number` · `kindName: string` · `roomCount: number` · `rooms: LibRoomBrief[]`

**LibRoomBrief（类型下房间简述）**: `devId: number` · `devName: string` · `minReserveMinute: number`

**LibRoomResource（某类型某天的资源）**: `devId` · `devName` · `kindId` · `kindName` · `labId` · `labName` · `roomId` · `roomName` · `limitCount` · `maxMinute` · `minMinute` · `cancelMinute` · `maxUser` · `minUser` · `openStart: string` · `openEnd: string` · `usageCount: number`（当日占用条数；明细不展示）

**LibRoomBookRecord（我的预约）**: `uuid: string` · `rsvId: number` · `owner: string` · `ownerId: string` · `date: string` · `beginText: string` · `endText: string` · `devName: string` · `kindName: string` · `membersText: string`（成员名拼接）

**LibRoomUserInfo（账号校验）**: `pid: string` · `accNo: number`

**页面状态机**: `KIND（类型列表 + 展开的日期项）→ RESOURCE（某类型某天资源）`；另有 `BOOKINGS`；各态独立维护加载/错误/空态；"近 5 天"以日期项表达（不引入全局日期切换）。

## Contracts & Interfaces

**服务契约（新增 `LibraryRoomService`）**
- `getRoomKindList(): Promise<LibRoomKind[]>` —— 只读；确保会话 → 取类型与房间。
- `getRoomResourceList(dateYmd: string, kindId: number): Promise<LibRoomResource[]>` —— 只读；确保会话 → 取该类型该天资源。
- `getRoomBookingRecords(): Promise<LibRoomBookRecord[]>` —— 只读；查询窗口"今天 → +6 天"。
- 以上均包在 `withSessionRecovery(..., 'cab')` 内；异常抛可读中文错误。

**认证契约（`TsinghuaAuthService` 新增）**
- `cabLogin(): Promise<void>` —— 完成研读间专用登录与账号校验（见 Decision 1）；失败抛可读错误。
- `HttpClient.resolveFinalUrl(url: string): Promise<string>` —— GET 跟随重定向返回最终地址（见 Decision 2）。

**服务装配契约（`SessionManager`）**
- `static getLibraryRoomService(): LibraryRoomService` —— 单例；以 `getAuthService().getHttpClient()` 与 auth 构造（与 `getLibrarySeatService()` 同构）。

**依赖契约（复用，不改）**
- `HttpClient.get(url: string): Promise<HttpResponse>`
- `TsinghuaAuthService.roamIdSubsystem(payload: string): Promise<void>`
- `TsinghuaAuthService.getRoamCredentials(): Promise<CampusCredentials>`
- `TsinghuaAuthService.withSessionRecovery<T>(operation, onReroam?, label): Promise<T>`

**UI 契约**
- `ReservationPage`（改造）："研读间预约"卡片 → 内联渲染 `LibraryRoomPage`（返回回到卡片）；"体育场馆预约"保持提示"即将支持"。
- `LibraryRoomPage`（新增组件，输入 `onBack`）：
  - 顶部 `DetailHeader`/自绘 HeaderBar + 右上角刷新（加载中显示进度）。
  - KIND 态：类型卡片（类型名 + "N 个房间"），点击展开"近 5 天"日期项；点击日期项进入 RESOURCE 态。
  - RESOURCE 态：资源卡片（房间名（含 `最少~最多人` 区间）、类型名、开放时间、开放/未开放徽标）；空态；返回回到 KIND 态。
  - BOOKINGS 态：我的预约记录（房间/类型/日期与起止/成员）；空态；从 KIND 态入口进入。
  - 各态均有加载（含"正在建立研读间会话"提示）/错误（可读中文 + 重试）/空态；演示模式使用内置示例且零请求。
  - 只读引导文案；卡片布局遵循 `width('100%') + constraintSize({ maxWidth: '100%' })` + 左右 margin 16。

**外部端点契约（沿用参考服务的标识与路径形态）**
- 认证地址接口 / 用户信息接口（认证服务内使用）；房间类型 / 资源列表 / 我的预约（研读间服务内使用）；端点常量集中定义于各自文件顶部。
