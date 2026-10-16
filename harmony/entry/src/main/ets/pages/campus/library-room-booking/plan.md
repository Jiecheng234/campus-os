# Implementation Plan: 研读间预约（含取消与成员邀请）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/library-room-booking/spec.md`

**Note**: 本特性产物按项目约定与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/library-room-booking/`），不创建 `spec/` 目录。

## Summary

在既有只读研读间能力（类型 → 近 5 天 → 资源 + 我的预约）之上补齐写操作：**预约**（选日期/时段 + 成员邀请 + 二次确认 + 提交 + 刷新）与**取消**（按记录 uuid + 二次确认 + 刷新）。

技术路径：扩展既有 `LibraryRoomService`（新增 POST JSON 能力 + 预约/取消/成员搜索接口 + 资源占用区间解析）；扩展既有 `LibraryRoomPage`（RESOURCE 层预约入口与时段/成员表单、BOOKINGS 层取消入口、二次确认与防重复）；复用既有 cab 会话与两层恢复（`withCabRetry`/`assureCabSession`）。**不引入新依赖、不新增目录（除本特性产物目录）、不做 MVVM 迁移**。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get` / `postJsonRaw`）、`TsinghuaAuthService.cabLogin` + `withSessionRecovery` + `getRoamCredentials`、`SessionManager.getLibraryRoomService()`；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: N/A（无持久化；账号标识 `cabAccNo` 为会话内缓存，已在既有服务中）
**Testing**: `arkts_check` + `devecocli build` + 模拟器验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 成员搜索 3s 内返回（SC-003）；提交后 ≤5s 出结果（SC-001/002）
**Constraints**: 演示模式读写零网络请求（SC-005）；异常 100% 可读中文错误（SC-006）；写操作日志无凭据明文（FR-014）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 扩展 1 个服务（POST + 3 方法 + 占用解析）、1 个页面（预约/取消交互 + 确认弹窗）；实体 6 个（类型/资源/成员/预约记录/时段/账号标识）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/library-room-booking/
├── feature.json         # 特性目录记录
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── auth/
│   │   ├── TsinghuaAuthService.ets            # 复用：cabLogin / withSessionRecovery / getRoamCredentials
│   │   └── SessionManager.ets                 # 复用：getLibraryRoomService()
│   └── campus/
│       └── LibraryRoomService.ets             # 扩展：POST JSON + 预约/取消/成员搜索 + 资源占用区间
└── pages/
    └── campus/
        └── LibraryRoomPage.ets                # 扩展：RESOURCE 层预约入口与表单、BOOKINGS 层取消、二次确认与防重复
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。写能力落在既有 `LibraryRoomService`（同文件内扩展，复用 cab 会话/解析范式）；UI 在既有 `LibraryRoomPage` 内扩展（确认弹窗 + 表单 + 提交态）；既有入口（`ReservationPage` 卡片）与 `CampusPage` 分发**不变**（本特性无首页直达需求）。不新增目录（除本特性产物）、不新增依赖/资源。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 会话与恢复（复用）**
- **Decision**: 所有读写包在既有 `withCabRetry` 内（reroam = 复位 cab 标记 + `ensureCabLogin(true)`），写操作前经既有 `assureCabSession()`（cab 登录 + 账号校验，成功缓存 `cabAccNo`）。
- **Rationale**: 与既有只读链路一致；写操作需 `appAccNo`，正是 `assureCabSession` 的产物。
- **Alternatives considered**: 新造会话机制（重复且不一致）。

**Decision 2 — POST JSON 能力（新增）**
- **Decision**: 既有 `cabFetch` 仅 GET。新增私有 `cabPostJson(url, bodyJsonText)`：用 `HttpClient.postJsonRaw(url, jsonText)` 提交 `application/json`，随后统一"非 JSON / `code !== 0` → 可读错误 → 返回 `data`"解析（与 `cabFetch` 同构）。
- **Rationale**: 研读间写接口 body 含**数组**（`resvMember`/`resvDev`/`addServices`），`postJson` 的 `Record<string, JsonBodyValue>` 仅标量、无法表达；`postJsonRaw` 可直接提交手写 JSON 文本。
- **Alternatives considered**: 用 `postForm`（服务端期望 JSON，不匹配）；改动 `postJson` 支持数组（越界且影响面大）。

**Decision 3 — 资源占用区间解析（新增）**
- **Decision**: 既有 `LibRoomResource` 仅解析占用**条数**（`usageCount`）；为满足"提交前校验时段未占用"（FR-004），**追加**占用区间字段（`usageList`：起止时间，必要时含标题/归属），保留 `usageCount` 不变。
- **Rationale**: 客户端需据区间做重叠判断；仅条数不足。
- **Alternatives considered**: 仅依赖服务端拒绝后提示（体验差，且无法在确认前阻止）。

**Decision 4 — 时间与规则校验（新增）**
- **Decision**: 时段输入为 `HH:mm`，**分钟须为 5 的倍数**；提交格式对齐参考 `toRoomTimestamp`：`resvBeginTime`/`resvEndTime` = `YYYY-MM-DD HH:mm:00`。提交前校验：结束晚于开始；时长在 `minMinute`/`maxMinute` 内；落于开放时间（`openStart`/`openEnd`）内；人数（=1+成员数）在 `minUser`/`maxUser` 内；与占用区间不重叠。
- **Rationale**: 逐项对齐参考 dryRun 的业务校验，保证服务端可接受且体验可预期（SC-007）。
- **Alternatives considered**: 不做客户端校验（服务端拒绝后再提示，体验差）。

**Decision 5 — 成员搜索（新增）**
- **Decision**: `GET …/ic-web/account/getMembers?page=1&pageNum=10&key={关键词}`（复用既有 `cabFetch` 解析）；结果项映射为 `{accNo, label(姓名), department}` 并**脱敏展示**（学号打码）；所选 `accNo` 作为提交 body 的 `resvMember` 数组。
- **Rationale**: 对齐参考 `fuzzySearchLibraryId`；`resvMember` 需要账号标识。
- **Alternatives considered**: 不提供成员选择（多人房间 minUser>1 无法预约）。

**Decision 6 — 二次确认与防重复（新增）**
- **Decision**: 预约/取消均以二次确认弹窗提交（预约：房间/日期/时段/人数或成员；取消：房间/时间）；提交中禁用按钮 + 加载态（`busyKey` 或等价），防重复（FR-006/FR-013）。
- **Rationale**: 写操作有公共资源后果，确认 + 防重复为安全底线。
- **Alternatives considered**: 点即提交（误触风险高）。

**Decision 7 — 演示模式（新增）**
- **Decision**: 演示模式（未登录或演示开关开启）下，预约/取消/成员搜索均**不发起请求**，给出可读提示；浏览沿用内置示例。
- **Rationale**: 与项目"演示模式零网络请求"约定一致（FR-011/SC-005）。
- **Alternatives considered**: 模拟成功（可能误导）。

**Decision 8 — 取消（新增）**
- **Decision**: 取消 `POST …/ic-web/reserve/delete`，body `{uuid}`；`uuid` 取自既有预约记录（`LibRoomBookRecord.uuid` 已解析）；成功后刷新列表。
- **Rationale**: 对齐参考 `cancelLibraryRoomBooking`；既有记录已含 uuid，无需新增解析。
- **Alternatives considered**: 无。

**Decision 9 — 页面形态与入口（复用）**
- **Decision**: 在既有 `LibraryRoomPage` 的 RESOURCE 层承载"预约"（表单：日期沿用当前所选日；时段起止 + 成员）与 BOOKINGS 层承载"取消"；**不新增** `CampusPage` 分发项，仍经既有"场馆预约"卡片进入（本特性无首页直达）。
- **Rationale**: 回归面最小；用户本轮未要求首页跳转。
- **Alternatives considered**: 新增独立页与直达分支（超出本轮范围）。

## Data Model

**LibRoomBrief / LibRoomKind / LibRoomBookRecord / LibRoomUserInfo**：沿用既有（`LibRoomBookRecord.uuid` 用于取消）。

**LibRoomResource（扩展）**: 既有字段（`devId`/`devName`/`kindId`/`kindName`/`minMinute`/`maxMinute`/`cancelMinute`/`minUser`/`maxUser`/`openStart`/`openEnd`/`usageCount`）+ **新增 `usageList: LibRoomUsage[]`**（起止；用于重叠校验）。

**LibRoomUsage（新增）**: `id` · `startText`（起止文本或时间戳字符串）· `endText` · `title` · `owner`（仅供重叠判断与展示，不承诺展示明细）。

**LibRoomMember（新增，成员搜索结果）**: `accNo: number` · `label: string`（姓名）· `department: string`。

**LibRoomBookRequest（新增，入参聚合）**: `devId: number` · `date: string`（YYYY-MM-DD）· `startTime: string`（HH:mm）· `endTime: string`（HH:mm）· `memberAccNos: number[]`。

**LibRoomBookResult（新增）**: `ok: boolean` · `message: string`。

**时段/账号标识**: 日期取自既有"近 5 天"选择；`cabAccNo` 由既有 `assureCabSession` 缓存。

## Contracts & Interfaces

**服务契约（`LibraryRoomService` 扩展）**
- `getRoomKindList(): Promise<LibRoomKind[]>` —— 只读（既有）。
- `getRoomResourceList(dateYmd: string, kindId: number): Promise<LibRoomResource[]>` —— 只读（既有；**扩展** `usageList` 解析）。
- `getRoomBookingRecords(): Promise<LibRoomBookRecord[]>` —— 只读（既有）。
- **新增** `getRoomMemberCandidates(keyword: string): Promise<LibRoomMember[]>` —— 成员模糊搜索（`GET`）。
- **新增** `bookLibraryRoom(req: LibRoomBookRequest): Promise<LibRoomBookResult>` —— 校验（时间/时长/开放/人数/占用）→ `POST …/ic-web/reserve`（JSON body：`sysKind:1`、`appAccNo`、`memberKind:1`、`resvBeginTime`/`resvEndTime`（`YYYY-MM-DD HH:mm:00`）、`testName:''`、`resvKind:2`、`resvProperty:0`、`appUrl:''`、`resvMember:[…]`、`resvDev:[devId]`、`memo:''`、`captcha:''`、`addServices:[]`）→ `code===0` 成功。
- **新增** `cancelRoomBooking(uuid: string): Promise<LibRoomBookResult>` —— `POST …/ic-web/reserve/delete`（JSON body `{uuid}`）。
- **新增（私有）** `cabPostJson(url: string, bodyJsonText: string): Promise<Object | undefined>`。
- 所有公开读写均包在既有 `withCabRetry`（label `cab`）内；异常抛可读中文错误；日志禁止输出凭据明文。

**依赖契约（复用，不改）**
- `HttpClient.get(url)` / `HttpClient.postJsonRaw(url, jsonText, extraHeaders?)`
- `TsinghuaAuthService.cabLogin()` / `withSessionRecovery<T>(operation, onReroam?, label)` / `getRoamCredentials()`
- `SessionManager.getLibraryRoomService()`

**UI 契约（`LibraryRoomPage` 扩展）**
- RESOURCE 层：资源行新增"预约"入口 → 预约表单（日期沿用当前所选日；时段起止 `HH:mm`；成员搜索/添加/移除；显示规则提示：开放时间/时长限制/人数上下限）→ 二次确认 → 提交（禁用防重复）→ 成功刷新 BOOKINGS 并提示。
- BOOKINGS 层：记录新增"取消"入口 → 二次确认（房间/时间）→ 提交 → 成功刷新列表并提示。
- 演示模式：写动作不发请求，给可读提示；移除"请在官方小程序完成"只读引导文案。
- 布局：全宽卡片配 `constraintSize({ maxWidth: '100%' })` + 左右 margin 约定；新增文案走 i18n（zh/en 成对）。

**外部端点契约（沿用参考标识与路径形态）**
- 类型/资源/记录/用户信息：沿用既有常量。
- **新增常量**：预约 `…/ic-web/reserve`；取消 `…/ic-web/reserve/delete`；成员搜索 `…/ic-web/account/getMembers?page=1&pageNum=10&key=`。集中定义于服务文件顶部。

## Changelog

- 2026-10-16：初版计划（研读间预约：预约 + 取消 + 成员邀请）。
