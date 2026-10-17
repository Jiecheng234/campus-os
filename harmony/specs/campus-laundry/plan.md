# Implementation Plan: 宿舍洗衣机信息（只读）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/campus-laundry/spec.md`

**Note**: 本特性产物按项目约定与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/campus-laundry/`），不创建 `spec/` 目录。

## Summary

在既有"校园 → 宿舍"页内新增"洗衣机"子层（与电费并列切换），展示宿舍洗衣机**只读**实时信息：楼宇分组（洁力：紫荆/南区/双清/其他；海乐生活）→ 楼层 → 机台（洗衣机/洗鞋机/烘干机）状态（空闲/使用中/异常）+ 洁力剩余时间（ETA）/更新时间/位置。

技术路径：新增只读服务 `LaundryService`（第三方公开接口，无鉴权；平台分支 + 多平台容错）；新增浏览组件 `LaundryPage`（楼宇分组 → 楼层/机台）；改造既有 `DormitoryPage`（顶部"电费 / 洗衣机"分段切换）；经 `SessionManager` 单例装配。**不引入新依赖、不新增权限、不做 MVVM 迁移**。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get` / `postJson`，均为标量/对象 JSON body）、`SessionManager`（单例装配范式）；**无** `TsinghuaAuthService` 会话依赖；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: N/A（无持久化）
**Testing**: `arkts_check` + `devecocli build` + 模拟器验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Performance Goals**: 进入子层 3s 内出楼宇分组；点楼宇 3s 内出楼层/机台（SC-001/002）
**Constraints**: 演示模式零网络请求（SC-004）；异常 100% 可读中文错误（SC-005）；不依赖登录态（FR-009）；不新增权限（FR-013）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 新增 1 个服务 + 1 个浏览组件；改造 1 个页面（宿舍）+ 1 处装配（SessionManager）；实体 5 个（平台/楼宇/分组/机台/楼层）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/campus-laundry/
├── feature.json         # 特性目录记录
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── auth/SessionManager.ets                # 改造：新增 getLaundryService() 单例
│   └── campus/
│       └── LaundryService.ets                 # 新增：模型 + 平台分支 + 解析 + 容错（只读）
└── pages/
    └── campus/
        ├── DormitoryPage.ets                  # 改造：顶部"电费 / 洗衣机"分段切换，洗衣机层渲染 LaundryPage
        └── LaundryPage.ets                    # 新增：楼宇分组 → 楼层/机台 浏览组件（只读）
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。只读服务单文件承载模型/解析/平台分支/容错；UI 作为一个可复用组件（`LaundryPage`）由既有"宿舍"页（`DormitoryPage`）**内联渲染**（与 `LibrarySeatPage` 由 `ReservationPage` 内联渲染同构）；从而**不修改 `CampusPage` 的分发与返回链**（回归面最小）。不新增目录（除本特性产物）、不新增依赖/资源。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 网络与会话（不依赖登录态）**
- **Decision**: 洗衣机数据来自第三方洗衣平台**公开接口**，**不使用** WebVPN/校园 Cookie 与会话；直接经既有 `HttpClient`（`get`/`postJson`）访问。楼宇列表在真实/演示之外的可用性不依赖登录（FR-009）。
- **Rationale**: 对齐参考实现（原生 `fetch` 直连第三方，无鉴权）。
- **Alternatives considered**: 走 WebVPN 包装（第三方主机非校园域，不适用）。

**Decision 2 — 服务形态与装配**
- **Decision**: 新增只读服务 `LaundryService`（构造仅需 `HttpClient`）；经既有 `SessionManager` 新增 `static getLaundryService()` 单例装配（`new LaundryService(getAuthService().getHttpClient())`）。服务方法一律返回严格模型、异常抛可读中文错误。
- **Rationale**: 与既有服务装配范式一致；服务层承担解析/容错，页面仅编排展示（可测、可复用）。
- **Alternatives considered**: 在页面内直接请求（解析/容错散落，难维护）。

**Decision 3 — 多平台容错（楼宇列表）**
- **Decision**: 楼宇列表并发请求两平台并以"部分成功"语义合并：任一平台失败仍展示其它平台数据；两侧均失败才抛可读错误。状态列表按平台分支：洁力 = 状态接口 +（尽力而为的）位置映射接口；海乐 = 三类目并发拉取后合并。
- **Rationale**: 对齐参考实现（`Promise.allSettled` 容错 + 海乐三类目并发）。
- **Alternatives considered**: 全或无（单平台抖动即整体失败，体验差）。

**Decision 4 — 状态与 ETA 解析**
- **Decision**: 洁力机台状态由**状态文本**映射：含"待机/空闲"→空闲；含"工作/运转/运行"→使用中；其余→异常；剩余时间取文本中"剩余…数字"；更新时间取"更新…时间"。海乐机台由 `state` 数值映射：1→空闲、2→使用中、其余→异常，无剩余时间。
- **Rationale**: 对齐参考实现的文本/数值语义（服务端未提供结构化状态）。
- **Alternatives considered**: 仅展示原始文本（不可读、不可排序/着色）。

**Decision 5 — 分组与排序**
- **Decision**: 洁力楼宇按名称含"紫荆/南区/双清"分别归入"紫荆公寓/南区宿舍/双清公寓"，其余归"其他位置"；海乐仅保留名称含"清华"者，组名"海乐生活"；仅保留非空分组。组内/楼层/机台按"先数字后名称"排序（机台另以位置优先）。
- **Rationale**: 对齐参考实现的分组/排序，保证列表可预期。
- **Alternatives considered**: 原样顺序（阅读体验差）。

**Decision 6 — 页面形态**
- **Decision**: 在既有 `DormitoryPage` 顶部增加"电费 / 洗衣机"分段切换；选中"洗衣机"时内联渲染新组件 `LaundryPage`（楼宇分组 → 楼层/机台，逐级返回 + 右上角刷新）。**不新增** `CampusPage` 入口（用户选定"宿舍页内子层"）。
- **Rationale**: 与 RN"宿舍服务"聚合语义一致；回归面最小。
- **Alternatives considered**: 新增校园主入口独立页（与用户选择不符）。

**Decision 7 — 演示模式**
- **Decision**: 演示模式（未登录或演示开关开启）下使用内置示例楼宇/楼层/机台，**零网络请求**。
- **Rationale**: 与项目"演示模式零网络请求"约定一致（FR-010/SC-004）。
- **Alternatives considered**: 仍发起请求（可能因网络失败而不稳定）。

**Decision 8 — 权限**
- **Decision**: 复用既有 `ohos.permission.INTERNET`（`module.json5` 已声明），**不新增权限**（FR-013）。
- **Rationale**: 第三方 HTTPS 直连仅需网络权限，项目已具备。
- **Alternatives considered**: 无。

## Data Model

**LaundryPlatform（平台）**: `'jieli'`（洁力）/ `'haile'`（海乐生活）

**LaundryBuilding（楼宇）**: `id: string` · `name: string` · `platform: LaundryPlatform`

**LaundryBuildingGroup（楼宇分组）**: `name: string` · `buildings: LaundryBuilding[]`

**LaundryMachine（机台）**: `type: string`（洗衣机/洗鞋机/烘干机）· `name: string` · `floor: string` · `status: 'idle' | 'working' | 'error'` · `etaMinutes: number`（-1 表示无/不适用）· `updatedAt: string` · `location: string`

**LaundryFloor（楼层）**: `name: string` · `machines: LaundryMachine[]`

**状态映射与解析**: 洁力（文本解析：空闲/使用中/异常 + 剩余分钟 + 更新时间）；海乐（数值映射：1/2/其他；无剩余时间）。

**页面层级状态（UI 状态机）**: `GROUP`（楼宇分组）→ `FLOOR`（楼层/机台）；逐级可返回；加载/错误/空态各层独立维护。

## Contracts & Interfaces

**服务契约（新增 `LaundryService`，只读）**
- `getLaundryBuildings(): Promise<LaundryBuildingGroup[]>` —— 并发两平台、部分成功合并、全失败抛可读错误。
- `getLaundryFloors(building: LaundryBuilding): Promise<LaundryFloor[]>` —— 按平台分支取机台并按楼层聚合（洁力：状态 + 位置；海乐：三类目并发）。
- 异常（HTTP 非 2xx / 非 JSON / 平台错误码 / 结构不符）一律抛可读中文错误。

**服务装配契约（`SessionManager` 改造）**
- `static getLaundryService(): LaundryService` —— 单例；以 `getAuthService().getHttpClient()` 构造（与既有 `getLibrarySeatService()` 同构，但不注入 auth）。

**依赖契约（复用，不改）**
- `HttpClient.get(url: string): Promise<HttpResponse>`
- `HttpClient.postJson(url: string, jsonBody: Record<string, JsonBodyValue>): Promise<HttpResponse>`（本特性请求体为标量/对象，`postJson` 足够）

**UI 契约（`DormitoryPage` 改造 + 新组件）**
- `DormitoryPage`（改造）：顶部"电费 / 洗衣机"分段切换；选中"洗衣机"时内联渲染 `LaundryPage`；既有电费内容与返回链不变。
- `LaundryPage`（新增组件）：
  - `GROUP` 层：楼宇分组列表（分组名 + 楼宇行：名称 + 平台标签）；点击楼宇进入 `FLOOR` 层。
  - `FLOOR` 层：楼层与机台列表（机台：类型 + 名称/位置 + 状态标签着色；空闲/使用中/异常；洁力展示剩余时间与更新时间）。
  - 右上角刷新（加载中显示进度）；各层加载/错误（可读中文 + 重试）/空态；逐级返回。
  - 演示模式：使用内置示例、零请求。
  - 卡片/列表遵循 `width('100%') + constraintSize({ maxWidth: '100%' })` + 左右 margin 16 约定。

**外部端点契约（沿用参考实现标识与形态；不在此列出完整 URL）**
- 洁力：楼宇（tower）、状态（status，按楼宇）、位置映射（清华 app，按楼宇查询）。
- 海乐：楼宇（nearPosition，固定坐标）、设备（deviceDetailPage，按位置 + 类目）。端点常量集中定义于服务文件顶部。

## Changelog

- 2026-10-16：初版计划（宿舍洗衣机信息只读接入）。
