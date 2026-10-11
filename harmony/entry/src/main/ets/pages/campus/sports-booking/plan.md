# Implementation Plan: 体育场馆查询（只读）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/sports-booking/spec.md`

**Note**: 本特性产物按项目约定与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/sports-booking/`），不创建 `spec/` 目录。

## Summary

为"场馆预约 → 体育场馆"接入真实数据（只读）：固定场馆清单（默认第一个）→ 近 7 天日期 → 该场馆当日资源（时段/场地/费用/可预约/已锁定）+ 限额与联系电话；另提供"我的预约记录"合并列表（未支付 + 已支付，含可取消/可支付标记，仅展示）。技术路径：复用现有"通用漫游"能力建立体育场馆子系统会话（该端点与本项目既有漫游端点一致），新增一个只读服务（GBK HTML 脚本变量/函数调用的正则解析 + 记录表解析），新增一个页内组件并由既有"场馆预约"入口页内联渲染；下单/支付/退订不迁移。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（`get`，含字符集推断与手动重定向）、`CampusDataService.roamByYyfwidHtml`（通用漫游，返回落点页 HTML）、`TsinghuaAuthService.withSessionRecovery`、`SessionManager`；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: N/A（无持久化）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 进入 3s 内出限额与资源；切换场馆/日期 3s 内刷新（SC-001/002）
**Constraints**: 演示模式零网络请求（SC-005）；异常 100% 可读中文错误（SC-006）；**中文 0 乱码**（GBK 正确解码，SC-007）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 新增 1 个服务文件 + 1 个浏览组件；改造 1 个入口页与 1 处装配；实体 4 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/sports-booking/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── HttpClient.ets                         # 复用（字符集推断）；如实测乱码再补 URL 编码标记（加法式）
│   ├── auth/
│   │   └── SessionManager.ets                 # 改造：新增 getSportsService()
│   └── campus/
│       ├── CampusDataService.ets              # 复用：roamByYyfwidHtml（通用漫游）；必要时扩展 URL 包装主机映射（加法式）
│       ├── LibrarySeatService.ets             # 参考：只读服务 + withSessionRecovery 范式
│       ├── LibraryRoomService.ets             # 参考：会话装配 + 登录校验范式
│       └── SportsService.ets                  # 新增：模型 + HTML 解析 + 只读服务
└── pages/
    └── campus/
        ├── ReservationPage.ets                # 改造：体育场馆卡片 → 内联渲染 SportsBookingPage
        └── SportsBookingPage.ets              # 新增：场馆/日期选择 + 资源列表 + 我的预约记录
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。与图书馆座位/研读间同构：只读服务单一文件承载模型与解析；UI 作为可复用组件由既有入口页**内联渲染**（不修改 `CampusPage.ets`）。会话建立复用既有 `roamByYyfwidHtml`（其端点与参考实现的通用漫游端点一致），因此**无需新增认证方法**；若漫游落点地址形态需要额外主机包装，仅对既有 URL 包装做**加法式映射**。不新增目录、不新增依赖、不新增资源。

## Complexity Tracking

> 无 Constitution 违背项。潜在改动均限于"新增方法/新增映射"，不改既有签名与行为。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| （条件性）扩展 `CampusDataService` 的 URL 包装主机映射 | 若通用漫游落点为原始主机地址，需包装为对应的 WebVPN 前缀才能建立子系统会话 | 在服务内自建包装表：与既有包装逻辑重复，且分散维护 |

## Research & Decisions

**Decision 1 — 子系统会话（通用漫游）**
- **Decision**: 复用既有 `CampusDataService.roamByYyfwidHtml(体育场馆子系统标识)` 建立子系统会话；所有读取包在 `withSessionRecovery(op, ensureSportsSession, 'sports')` 内（reroam 即重新执行通用漫游）。
- **Rationale**: 参考实现的通用漫游端点与本项目 `roamByYyfwid` **指向同一门户端点**，能力已具备，无需新增认证方法。
- **Alternatives considered**: 新增专用 `cabLogin` 式方法（无必要，体育场馆走通用漫游）；默认 info 门户 reroam（无法建立体育场馆会话）。

**Decision 2 — 漫游落点地址的包装**
- **Decision**: 启用前先确认漫游返回地址形态；若为原始主机地址（非 WebVPN 域），在既有 URL 包装中**补充体育场馆主机 → 其 WebVPN 前缀的映射**（加法式，不影响既有 zhjw 分支）；以日志（漫游落点/最终地址）确认包装是否命中。
- **Rationale**: 参考实现的 URL 包装包含主机→前缀映射表；本项目包装为精简版（仅 zhjw）。体育场馆主机与既有分支不同，需要时补齐。
- **Alternatives considered**: 忽略漫游落点（仅发漫游请求不跟进）——子系统会话可能未真正建立；(b) 硬编码单一主机判断（不可扩展）。

**Decision 3 — HTML 解析（GBK + 脚本变量/函数调用）**
- **Decision**: 采用正则解析（项目约定，禁三方 HTML 库）：①限额取自页面脚本中的限额变量（支持 `'数字'` / `"数字"` / 裸数字三种形态与带/不带 `var`）；②资源来自脚本函数调用序列（资源推送、费用、预约状态、状态颜色四类调用），以资源标识为键合并；③资源状态字段按参考语义映射（可网约、锁定、支付状态、用户类型）。
- **Rationale**: 页面为脚本驱动（非 JSON），参考实现即正则/选择器解析；项目已有多处脚本变量解析经验（体测/课表）。
- **Alternatives considered**: HTML 解析库（项目禁）；ArkWeb 注入 JS（复杂度高）。

**Decision 4 — 字符编码（中文不乱码）**
- **Decision**: 依赖 `HttpClient` 既有字符集推断（响应头 charset 优先 → URL 标记回退 GBK → 严格 UTF-8 字节嗅探）；若实测乱码，则在 URL 标记表中补充体育场馆子系统标识（加法式）。
- **Rationale**: 参考实现注明体育场馆页面默认 GBK；现有嗅探机制在 GBK 场景已多次验证（课表/成绩）。
- **Alternatives considered**: 强制 GBK（会对已重编码响应造成乱码）。

**Decision 5 — 预约记录解析（未支付 + 已支付合并）**
- **Decision**: 未支付订单页解析表格行：按参考的**子节点索引**取列（列序与参考一致），并从行内脚本调用（支付/退订）正则中提取支付标识与预约标识；已支付订单页同理解析后**合并**；逐行容错（单行失败跳过）。实现时先打印首行诊断日志以核对列序（项目曾因子节点索引语义踩坑）。
- **Rationale**: 逐项对齐参考实现；列序与索引语义是该页面解析的关键风险点。
- **Alternatives considered**: 仅解析未支付（不满足 FR-007 的合并要求）。

**Decision 6 — 场馆清单与日期**
- **Decision**: 场馆为**固定清单常量**（对齐参考的 8 个场馆：名称/场馆标识/项目标识）；日期为**近 7 天**（今天起偏移 0–6 天），默认今天。
- **Rationale**: 参考即固定清单；用户已确认近 7 天与默认今天。
- **Alternatives considered**: 自定义场馆标识（超出范围）；近 5 天（与用户确认不符）。

**Decision 7 — 只读边界**
- **Decision**: 不实现下单、支付与退订；在资源与记录处给出"下单与支付请通过官方渠道完成"引导；记录的"可取消/可支付"仅作信息标注。
- **Rationale**: 用户已确认只读；写操作涉及验证码、支付深链与退订，风险另计。
- **Alternatives considered**: 一并迁移写操作（超出本轮）。

**Decision 8 — 页内形态与入口**
- **Decision**: 单组件内两视图（资源浏览 / 我的预约记录），资源浏览含"场馆 chips + 近 7 天日期行 + 限额/电话 + 资源列表"；由 `ReservationPage` 的"体育场馆预约"卡片**内联渲染**（返回回到卡片），不改 `CampusPage.ets`。
- **Rationale**: 与图书馆座位/研读间一致的交互与最小回归面。
- **Alternatives considered**: 独立子页面 + 校园页分发（回归面更大）。

## Data Model

**SportsVenue（场馆）**: `name: string` · `gymId: string` · `itemId: string`（固定清单）

**SportsResource（资源）**: `resId: string` · `resHash: string` · `timeSession: string` · `fieldName: string` · `overlaySize: number` · `canNetBook: boolean` · `cost: number` · `bookId: string` · `locked: boolean` · `userType: string` · `paymentStatus: boolean`

**SportsResourceInfo（资源总量信息）**: `count: number`（已用）· `init: number`（上限）· `phone: string` · `data: SportsResource[]`

**SportsRecord（预约记录）**: `name: string` · `field: string` · `time: string` · `price: string` · `method: string` · `bookTimestamp: number` · `bookId: string` · `payId: string`

**页面状态**: `RESOURCES`（默认视图：场馆/日期/限额/资源）与 `RECORDS`（我的预约记录）；各自维护加载/错误/空态。

## Contracts & Interfaces

**服务契约（新增 `SportsService`）**
- `getSportsResources(venue: SportsVenue, dateYmd: string): Promise<SportsResourceInfo>` —— 只读；建立/恢复会话 → 并发取"限额 + 联系电话 + 资源列表" → 组装。
- `getSportsRecords(): Promise<SportsRecord[]>` —— 只读；未支付与已支付合并；逐行容错。
- 场馆清单以模块常量导出（页面直接用）。
- 上述均包在 `withSessionRecovery(..., 'sports')` 内；异常抛可读中文错误。

**服务装配契约（`SessionManager`）**
- `static getSportsService(): SportsService` —— 单例；以 `getAuthService().getHttpClient()` 与 `getCampusDataService()` 构造（与 `getLibrarySeatService()` 同构）。

**依赖契约（复用，不改）**
- `CampusDataService.roamByYyfwidHtml(yyfwid: string): Promise<string>`
- `HttpClient.get(url: string): Promise<HttpResponse>`
- `TsinghuaAuthService.withSessionRecovery<T>(operation, onReroam?, label): Promise<T>`

**UI 契约**
- `ReservationPage`（改造）："体育场馆预约"卡片 → 内联渲染 `SportsBookingPage`（返回回到卡片）。
- `SportsBookingPage`（新增组件，输入 `onBack`）：
  - 头部（标题"体育场馆"）+ 右上角刷新（加载中显示进度）。
  - RESOURCES 视图：场馆 chips（默认第一个）+ "近 7 天"日期行（默认今天）+ 限额行（已用/上限）+ 联系电话行（有值时）+ 资源卡片列表（时段、场地、费用、可预约/已锁定标注）；空态。
  - RECORDS 视图：合并列表（名称/场地/时间/价格/支付方式 + 可取消/可支付标注）；空态；返回回到资源视图。
  - 各视图均有加载/错误（可读中文 + 重试）/空态；演示模式使用内置示例且零请求。
  - 只读引导文案；卡片布局遵循 `width('100%') + constraintSize({ maxWidth: '100%' })` + 左右 margin 16。

**外部端点契约（沿用参考服务的标识与路径形态）**
- 资源首页（含限额）/ 资源明细 / 联系电话 / 未支付订单 / 已支付订单：沿用参考实现中的子系统 token 与路径形态；端点常量集中定义于服务文件顶部。
