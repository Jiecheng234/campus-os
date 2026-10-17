# Implementation Plan: 图书馆座位查询与预约（含取消与首页直达）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/library-seat/spec.md`

**Note**: 本特性产物按项目约定与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/library-seat/`），不创建 `spec/` 目录。本文件为 2026-10-16 的**合并更新**（在原"只读查询"计划上追加预约/取消/首页直达）。

## Summary

在既有**只读**图书馆座位能力（馆 → 楼层使用率 → 区域 → 座位 + 我的预约）之上，补齐写操作并接通首页入口：

1. **预约座位**：对"可用"座位发起预约（先二次确认），成功刷新"我的预约"。
2. **取消预约**："我的预约"中对可取消记录发起取消（先二次确认），成功刷新列表。
3. **首页直达**：首页"图书馆座位"入口一次点击直达座位页（复用既有待处理导航目标机制），移除"即将接入"提示。

技术路径：在既有 `LibrarySeatService`（服务层）内新增"访问令牌抓取 + 预约/取消写接口"，页面 `LibrarySeatPage` 增加确认弹窗与提交交互，`CampusPage` 增加直达子页分支，`HomePage` 入口改走既有 `emitNavigate`。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get` / `postForm`）、`TsinghuaAuthService.roamIdSubsystem`（id 漫游）+ `withSessionRecovery`（两层恢复）+ `getRoamCredentials`（userid）、`SessionManager`；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: 仅**内存**短时缓存访问令牌（access_token，约 5 分钟）；无持久化；令牌禁止明文落日志
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 进入 3s 内出馆列表与楼层使用率；切换日期 3s 内刷新；预约/确认后提交 ≤ 5s 出结果（SC-001/002/008）
**Constraints**: 演示模式读写零网络请求（SC-006）；异常 100% 可读中文错误（SC-007）；写操作日志无凭据明文（FR-019）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 扩展 1 个服务（写接口 + 令牌）、1 个浏览/预约组件（确认与提交）、入口直连 2 处（`CampusPage` 子页 + `HomePage` 入口）；实体 8 个（馆/楼层/区域/座位/预约记录/预约时段/访问令牌/日期选择）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/library-seat/
├── spec.md              # Phase 1 产出（2026-10-16 合并更新）
├── plan.md              # 本文件（/spec-plan 产出，2026-10-16 合并更新）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── auth/
│   │   ├── TsinghuaAuthService.ets            # 复用：roamIdSubsystem / withSessionRecovery / getRoamCredentials
│   │   └── SessionManager.ets                 # 复用：getLibrarySeatService()
│   └── campus/
│       └── LibrarySeatService.ets             # 扩展：访问令牌抓取 + book/cancel 写接口 + 预约记录可取消标识
└── pages/
    ├── CampusPage.ets                         # 改造：新增 subScreen 'library-seat' 直达分支
    ├── HomePage.ets                           # 改造：底部"图书馆座位" pill → emitNavigate（campusSub='library-seat'）
    └── campus/
        ├── ReservationPage.ets                # 复用（内联渲染 LibrarySeatPage；本轮基本不变）
        └── LibrarySeatPage.ets                # 扩展：座位预约动作 + 二次确认 + 取消动作 + 结果提示/防重复
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。写能力落在既有 `LibrarySeatService`（同文件内扩展，保证会话/解析范式一致）；UI 在既有 `LibrarySeatPage` 内扩展（确认弹窗 + 提交状态）；首页直达通过既有 `emitNavigate` 的待处理目标 + `CampusPage` 新增直达分支实现，**不重构**既有"场馆预约"入口与返回链。不新增目录、不新增依赖、不新增资源。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 子系统会话与会话恢复**
- **Decision**: 进入图书馆座院子系统采用**已具备的 id 漫游能力**（`roamIdSubsystem(图书馆座位子系统标识)`），并置"已激活"标记；所有读/写操作包在 `withSessionRecovery(op, reroam{重置标记 + 强制重漫游}, 'lib')` 内（默认层 1 用自定义 reroam，层 2 为完整重登录）。首个 home 页请求偶发失败忽略（对齐参考）。
- **Rationale**: 参考实现在该子系统上与宿舍电费同款 id 漫游；项目已验证该链路（电费）。使用自定义 reroam 使恢复命中正确子系统，而非默认 info 门户。
- **Alternatives considered**: (a) 默认 reroam（info 门户）——恢复后仍无法访问图书馆子系统，无效；(b) 每次操作都强制重漫游——开销大且可能触发登录节流。

**Decision 2 — 接口解析与错误语义**
- **Decision**: 图书馆接口返回 JSON；统一"取 JSON → 失败标记（status 为 false/false 字符串）→ 抛服务端 msg → 取 `data.list`（缺失则抛可读错误）"三步解析；所有解析用 `Record<string, Object>` + `asObjectArray`/`asRecord` 兜底辅助函数（对齐校园卡服务范式）。
- **Rationale**: 参考实现 `libFetchJson`/`libFetchList` 语义即此；错误可读性由统一解析保障（FR-011/SC-007）。
- **Alternatives considered**: 逐接口手写解析（重复且易漏失败分支）。

**Decision 3 — 页内多级导航形态**
- **Decision**: 层级（馆 → 楼层 → 区域 → 座位；以及"我的预约"）以**同一组件内的层级状态**表达，逐级前进/返回；`ReservationPage` 内联渲染该组件，返回即回到入口卡片。系统返回键语义由入口页既有返回链处理（子层级先逐级回退）。**新增** `CampusPage` 的 `library-seat` 直达分支，使首页入口可绕过卡片页直达本组件（`onBack` → 回校园主列表）。
- **Rationale**: 保持既有页内多级形态（回归最小）；直达分支只增加一个渲染入口，不改既有返回链。
- **Alternatives considered**: 仅经卡片页进入（首页直达体验差，不满足 FR-018）。

**Decision 4 — 楼层使用率聚合**
- **Decision**: 楼层列表先取馆下的楼层（子区域）清单；对**开放**的楼层并发拉取其区域列表并聚合"可用/总数"；单层失败仅置该层为 0 且不阻塞其余楼层（对齐参考的并发 + 容错）。未开放楼层不发请求。
- **Rationale**: 楼层自身无总数，必须由区域聚合；并发可满足 3s 内出数据（SC-001），容错保证部分可用（Edge Cases）。
- **Alternatives considered**: 串行聚合（楼层多时超时风险高）；只显示楼层不显示使用率（不满足 FR-004）。

**Decision 5 — 日期与时段语义（读写共用）**
- **Decision**: 仅"今天/明天"两种选择；座位查询与**预约提交**都需先取该区域的"可预约日/时段"列表并命中目标日期，得到时段标识（segmentId）与起止时间；若为今天，则起始时间取"当前时刻或更晚"。
- **Rationale**: 对齐参考实现语义；预约接口需 `segment`，与查询共用同一解析，避免口径不一。
- **Alternatives considered**: 提供任意日期（超出本轮范围）。

**Decision 6 — ~~只读边界~~（已被 Decision 8 取代）**
- **Decision**: ~~不实现预约/取消；仅提示"预约请前往官方小程序完成"。~~
- **Status**: **Superseded（2026-10-16）**：用户确认本轮接入预约 + 取消，只读边界解除。

**Decision 7 — 座位状态映射**
- **Decision**: 状态数值按约定映射为中文标签：可用 / 已预约 / 已被占用 / 其他→不可用；未知值安全回退为"不可用"。仅**可用**座位提供预约动作。
- **Rationale**: 参考模型注释即此语义；回退避免未知值导致 UI 异常。
- **Alternatives considered**: 直接展示原始数值（可读性差，违背中文 UI 约定）。

**Decision 8 — 访问令牌获取与写接口（新增）**
- **Decision**: 写操作前需取得**访问令牌**：自图书馆主页 HTML（`LIB_HOME_URL`）中"`access_token` 后的第一对引号内字符串"抓取，**内存缓存约 5 分钟**；`force=true` 跳过缓存。预约：`POST api.php/spaces/{seatId}/book`，表单体 `{access_token, userid(=学号), segment, type, operateChannel:'2'}`；取消：`POST api.php/profile/books/{bookingId}`，表单体 `{_method:'delete', id, userid, access_token, operateChannel:'2'}`。响应为 JSON，`status === 0` 视为成功；若失败文本命中 `token|令牌|过期|invalid` 则判定"令牌失效"，自动刷新令牌后重试一次。
- **Rationale**: 逐行对齐参考实现（`getLibraryAccessToken`/`bookLibrarySeat`/`cancelLibraryBooking`）；令牌短时缓存避免每次预约都重拉主页；令牌失效自愈满足 SC-011。
- **Alternatives considered**: (a) 不缓存令牌（每次重拉主页，慢且多请求）；(b) 令牌持久化（越权风险，无必要）。

**Decision 9 — 取消所需的记录标识（新增）**
- **Decision**: 既有"我的预约"解析仅取"位置/时间/状态"，**不足以取消**。需在 `LibraryBookingRecord` 增加**可取消标识**：从预约记录行的 `menuDel('…')` onclick 中提取取消 id（对齐参考 `delMatch`）；无该标识的记录视为不可取消（不提供取消动作）。
- **Rationale**: 取消接口按 `bookingId` 路径提交；无该 id 无法构造请求（FR-016）。
- **Alternatives considered**: 用"位置/时间"匹配取消（服务端不接受，不可行）。

**Decision 10 — 首页直达（新增）**
- **Decision**: 首页"图书馆座位"入口改走既有 `emitNavigate`（待处理导航目标）：写入 `tab=3`（校园）与 `campusSub='library-seat'`；`CampusPage` 新增 `subScreen === 'library-seat'` 分支**直接渲染** `LibrarySeatPage`（`onBack` → 回校园主列表）。移除该入口原有的"即将接入" toast。
- **Rationale**: 复用上一特性落地的待处理目标机制，冷启动首次点击即直达（FR-018/SC-010）；不触碰既有卡片页与返回链。
- **Alternatives considered**: (a) 仅跳到"场馆预约"卡片页（需再点一次，不满足"直达"）；(b) 直接改 `showLibrarySeat` 初始态（无法从外部传入，且影响卡片页语义）。

**Decision 11 — 提交确认与防重复（新增）**
- **Decision**: 预约/取消均以**二次确认**弹窗提交，确认框展示关键信息（预约：馆/楼层/区域/座位/日期/时段；取消：座位/时间/状态）；提交中禁用按钮并显示加载，避免重复提交（FR-014/FR-016/FR-020）；成功后刷新"我的预约"（预约再刷新当前座位状态）并给出结果提示（FR-017）。
- **Rationale**: 写操作具有后果且不可轻率，二次确认 + 防重复是安全底线；结果提示保证可感知。
- **Alternatives considered**: 点即提交（误触风险高）。

**Decision 12 — 演示模式写行为（新增）**
- **Decision**: 演示模式（未登录或演示开关开启）下，预约/取消**不发起任何网络请求**，给出可读提示（如"演示模式下不可提交"）。读取沿用内置示例。
- **Rationale**: 与既有"演示模式零网络请求"约定一致（FR-010/SC-006）。
- **Alternatives considered**: 模拟成功（可能误导用户以为已真实下单）。

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

**LibraryBookingRecord（预约记录）**: `id` · `pos`（座位位置）· `time` · `status` · **`cancelId`（新增；可取消标识，空串表示不可取消）**

**LibraryDaySegment（预约时段）**: `day` · `startTime` · `endTime` · `segmentId` · `today`（既有；读写共用）

**访问令牌缓存（新增，私有）**: `{ value: string, ts: number }`（内存；有效期约 5 分钟；`force` 跳过）

**LibraryBookResult（新增）**: `status: number` · `msg: string`（`status === 0` 视为成功；失败文本命中令牌关键字 → 令牌失效）

**DateChoice（日期选择）**: `0 = 今天` · `1 = 明天`

**页面层级状态（UI 状态机）**: `LIBRARY → FLOOR → SECTION → SEAT`，另含 `BOOKINGS`（我的预约）；任一层可回退到上一层；加载/错误/空态在各层独立维护；**新增**提交态（`booking`/`cancelling`）与确认弹窗可见态。

## Contracts & Interfaces

**服务契约（`LibrarySeatService` 扩展）**
- `getLibraryList(): Promise<LibraryInfo[]>` —— 只读（既有）。
- `getLibraryFloorList(libraryId: number, dateChoice: number): Promise<LibraryFloorInfo[]>` —— 只读（既有）。
- `getLibrarySectionList(floorId: number, dateChoice: number): Promise<LibrarySectionInfo[]>` —— 只读（既有）。
- `getLibrarySeatList(sectionId: number, dateChoice: number): Promise<LibrarySeatInfo[]>` —— 只读（既有）。
- `getLibraryBookingRecords(): Promise<LibraryBookingRecord[]>` —— 只读（既有；**扩展**：解析 `cancelId`）。
- **新增** `getLibraryAccessToken(force?: boolean): Promise<string>` —— 抓取/缓存访问令牌（`force` 跳过缓存）。
- **新增** `bookLibrarySeat(sectionId: number, seatId: number, seatType: number, dateChoice: number): Promise<LibraryBookResult>` —— 取目标日时段 → POST 预约；令牌失效自动刷新重试一次。
- **新增** `cancelLibraryBooking(bookingId: string): Promise<LibraryBookResult>` —— POST 取消；令牌失效自动刷新重试一次。
- 以上均包在统一的两层会话恢复内（label `lib`），异常抛可读中文错误；**日志不得输出令牌**。

**服务装配契约（`SessionManager`）**
- `static getLibrarySeatService(): LibrarySeatService` —— 单例（既有）。

**依赖契约（复用，不改）**
- `HttpClient.get(url: string): Promise<HttpResponse>`
- `HttpClient.postForm(url: string, form: Record<string, string>): Promise<HttpResponse>`（既有；写请求用）
- `TsinghuaAuthService.roamIdSubsystem(payload: string): Promise<void>`
- `TsinghuaAuthService.withSessionRecovery<T>(operation, onReroam?, label): Promise<T>`
- `TsinghuaAuthService.getRoamCredentials(): Promise<CampusCredentials>`（userid 取 `studentId`；缺失时抛"未登录"）

**UI 契约（入口直连 + 组件扩展）**
- `CampusPage`（改造）：新增 `subScreen === 'library-seat'` 分支 → 直接渲染 `LibrarySeatPage({ onBack: () => subScreen = '' })`；其余分支与 `ReservationPage` 语义不变。
- `HomePage`（改造）：底部"图书馆座位"入口 → `emitNavigate`（`tab=3`、`campusSub='library-seat'`）；移除"即将接入" toast；不影响其它跨页导航。
- `LibrarySeatPage`（扩展组件，输入 `onBack`）：
  - SEAT 层：**可用**座位提供"预约"动作 → 二次确认弹窗（馆/楼层/区域/座位/日期/时段）→ 提交 → 成功刷新 BOOKINGS 与该区域座位状态并提示。
  - BOOKINGS 层：**可取消**记录提供"取消"动作 → 二次确认 → 提交 → 成功刷新列表并提示。
  - 提交中：按钮禁用 + 加载态（防重复）。
  - 演示模式：写动作不发请求，给可读提示。
  - 移除"预约请前往官方小程序完成"等只读引导文案。
  - 各层加载/错误（可重试）/空态保持；卡片/列表遵循 `width('100%') + constraintSize({ maxWidth: '100%' })` + 左右 margin 16 约定。

**外部端点契约（沿用参考实现标识与路径形态）**
- 馆树 / 楼层 / 区域 / 可预约日时段 / 座位列表 / 我的预约：沿用既有常量。
- **新增常量**：预约 `…/api.php/spaces/{seatId}/book`；取消 `…/api.php/profile/books/{bookingId}`；令牌来源页 `…/home/web/f_second`（既有 `LIB_HOME_URL`）。端点常量集中定义于服务文件顶部。

## Changelog

- 2026-10-16：合并"接入图书馆座位预定并连接首页跳转"。
  - Summary/Technical Context/Project Structure 更新（写接口、令牌缓存、`CampusPage` 直达分支、`HomePage` 入口）。
  - Research & Decisions：新增 D8（令牌与写接口）、D9（取消标识解析）、D10（首页直达）、D11（二次确认与防重复）、D12（演示模式写行为）；D6（只读边界）标记为已被取代；D3/D5 增补直达与读写共用时段说明。
  - Data Model：`LibraryBookingRecord` 增 `cancelId`；新增访问令牌缓存与 `LibraryBookResult`。
  - Contracts：新增 `getLibraryAccessToken` / `bookLibrarySeat` / `cancelLibraryBooking` 及 UI 契约。
- 2026-10-11：初版（图书馆座位只读查询）。
