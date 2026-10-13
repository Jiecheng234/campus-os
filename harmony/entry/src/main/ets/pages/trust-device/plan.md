# Implementation Plan: 信任此设备与会话门控（含退出登录回登录页）

**Input**: Feature specification: `entry/src/main/ets/pages/trust-device/spec.md`

**Note**: 本特性产物按项目约定与所属源码同区域放置（`entry/src/main/ets/pages/trust-device/`），不创建 `spec/` 目录。

## Summary

引入信任策略与登录态门控：登录页新增"信任此设备"选择（默认＝上次选择）；**信任→持久化凭证 / 不信任→仅内存会话**；设置页取消信任→标记 + **退出时清除**（强杀由**启动兜底**）；自动登录遇 2FA → **直接进入 2FA 界面**；**退出登录→整应用回登录页**。运行期会话复用完全不受影响（仅动"凭证是否落盘"与"退出/启动清理"）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `SessionManager`/`TsinghuaAuthService`（登录/2FA/自动登录）、`storage/SecureStorage`（ASSET 凭证）、`state/SettingsManager`（`trustDevice` 持久化）、`state/AuthManager`（登录态）、`storage/StorageKeys`、`entryability/EntryAbility`、`utils/I18n`；无新增三方依赖
**State Management**: 沿用 **V1**；跨页登录态经既有 `AuthManager` + 必要的 AppStorage 信号
**Storage**: 信任标记/上次选择→既有设置存储（或 `StorageKeys` 新增键）；凭证→ASSET（仅信任时写）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（含**冷启动/退出/强杀**三类场景）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Performance Goals**: 登录与冷启动无额外可感知延迟；门控切换即时
**Constraints**: 不信任**禁止**写凭证；强杀后启动必须兜底清除；**会话复用零影响**；日志无明文；演示零请求；ArkTS 严格模式
**Scale/Scope**: 改造 6 个既有文件；新增 1 个信任状态模块（可选并入 SettingsManager）；实体 3 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/trust-device/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── pages/
│   ├── LoginPage.ets                          # 改造：信任开关（默认=上次选择）+ 登录传参 + 2FA 提示
│   └── Index.ets                              # 改造：登录态门控（未登录/需 2FA → 登录页；退出 → 回登录页）
├── services/auth/
│   ├── SessionManager.ets                     # 改造：login(带信任标志)/tryAutoLogin(2FA→界面)/凭证清理
│   └── TsinghuaAuthService.ets                # 小幅改造（加法式）：login 支持“是否持久化凭证”
├── state/
│   ├── SettingsManager.ets                    # 复用/扩展：信任状态与“上次选择”、待清除标记
│   └── AuthManager.ets                       # 复用/扩展：登录态与“需 2FA”状态访问
├── storage/StorageKeys.ets                    # 扩展：待清除/上次选择键（如需要）
├── entryability/EntryAbility.ets              # 改造：退出时清除（钩子）+ 启动兜底清除
└── utils/I18n.ets                             # 扩展：login.*（需二次认证/信任说明等）文案
```

**Structure Decision**: **沿用既有架构**。本特性为**策略与门控**改造：以最小触点改动"登录时是否写凭证""退出/启动清理""登录态门控"三处；**不新增 UI 页面**（2FA 复用既有流程与视图）；**不引入依赖**。允许改动 `Index`/`EntryAbility`（本特性已解除此前"不改导航装配"约束）。

## Complexity Tracking

> 无 Constitution 违背项。触碰 `Index`/`EntryAbility`/认证服务属关键链路，以"**最小改动 + 回归自动登录与退出**"为约束（见 Decision 6）。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 改动 `EntryAbility` 与 `Index` | 退出清理与整应用门控只能在装配层实现 | 仅在设置页内刷新（既有做法）无法满足"整应用回登录页"与"退出清理" |

## Research & Decisions

**Decision 1 — 凭证持久化策略（不信任＝不写）**
- **Decision**: 登录成功时依据信任标志决定是否调用 `SecureStorage.saveCredentials`：**信任→写（ASSET）；不信任→不写（仅内存会话）**。读取凭证沿用既有"先内存、再 ASSET"逻辑。
- **Rationale**: 语义等价"退出即清除"，且**天然覆盖强杀/崩溃**（FR-004/FR-005）；实现最简、无时序风险。
- **Alternatives considered**: 先写后清（依赖退出钩子，强杀残留，需双保险）。

**Decision 2 — 信任状态与"上次选择"**
- **Decision**: 复用既有 `SettingsManager.isTrustDevice/setTrustDevice`（持久化 `settings.trustDevice`）作为**当前信任与"上次选择"**；新增**待清除标记**（`StorageKeys` 扩展，如 `@campusos/trust_pending_clear`）表示"取消信任后需清理已存凭证"。
- **Rationale**: 复用既有持久化，避免重复状态源（FR-002/FR-006/FR-007）。
- **Alternatives considered**: 新建独立信任存储（与既有 `trustDevice` 双写易不一致）。

**Decision 3 — 退出清理与启动兜底（双保险）**
- **Decision**: ①`EntryAbility` 正常退出钩子：若待清除标记为真 → 清凭证并复位标记；②应用启动（设置加载后）：若**未信任**或**待清除**为真 → 清凭证并复位标记。
- **Rationale**: 满足 FR-006/FR-005 与 SC-002/SC-003（强杀场景）；钩子不可靠时由启动兜底覆盖。
- **Alternatives considered**: 仅依赖退出钩子（强杀残留）；仅依赖启动兜底（不信任的当次运行仍可能留盘，但配合 Decision 1 已无残留）。

**Decision 4 — 登录页信任选择与传参**
- **Decision**: `LoginPage` 新增信任开关，初值＝`SettingsManager.isTrustDevice()`（无历史默认不勾选，通过新增"是否曾选择"标记区分）；登录调用把该选择传入 `SessionManager.login(credentials, trustDevice)`（**新增可选参数**，缺省沿用设置值，保证既有调用不被破坏）；成功后写回"上次选择"。
- **Rationale**: 满足 FR-001/FR-002/FR-003；加法式签名避免破坏既有调用点。
- **Alternatives considered**: 仅用设置页开关（无法在登录时选择）。

**Decision 5 — 自动登录遇 2FA 直接进界面**
- **Decision**: `tryAutoLogin` 命中 `TWO_FACTOR` 结果时：置 `AuthManager` 的"需 2FA"状态（含待验证上下文）→ **门控立即渲染登录页的 2FA 视图**，并给出可读提示（i18n `login.twoFactorRequired`）；非 2FA 失败仍回登录页并提示。
- **Rationale**: 满足 FR-009/FR-010/SC-004；复用既有 2FA 流程与视图（不新造页面）。
- **Alternatives considered**: 静默停在登录页（用户困惑，且"信任额度浪费"得不到及时处理）。

**Decision 6 — 整应用登录态门控（含退出回登录页）**
- **Decision**: `Index` 以**登录态**为唯一门控条件：未登录或"需 2FA"→ 渲染登录页（含 2FA 视图，不渲染底部 Tab）；已登录→渲染 Tabs。登录态由既有 `AuthManager` 驱动（退出登录/会话失效/门控信号变化即切换）。
- **Rationale**: 满足 FR-011/SC-005 并解决既有待办"退出登录后不整应用回登录页"；改动集中在 `Index` 一处。
- **Alternatives considered**: 各页自行判断登录态（分散、易漏）。

**Decision 7 — 会话复用零影响**
- **Decision**: 本特性**只在两个时点**触碰凭证（登录时是否落盘、退出/启动清理）；**绝不**清 Cookie、不重置会话、不打断漫游与请求；取消信任**不触发**任何会话操作。
- **Rationale**: 用户硬性要求（FR-008/SC-006）。
- **Alternatives considered**: 取消信任即清会话（会中断使用，违背要求）。

**Decision 8 — 自检与安全**
- **Decision**: 既有启动自检不得调用会写/清凭证的路径（必要时改为只读或跳过）；新增文案走 i18n（`login.*`/`settings.*`）；**日志不得输出凭证明文**（沿用既有 ASSET 日志规范）。
- **Rationale**: 满足 FR-013/FR-015/FR-016/SC-007，避免自检倒灌破坏策略。
- **Alternatives considered**: 保留自检原样（可能清/写凭证，破坏策略）。

## Data Model

**信任状态**: `trusted: boolean`（当前/上次选择，持久化） · `choiceMade: boolean`（是否曾选择，决定登录页默认值） · `pendingClear: boolean`（取消信任后待清除）

**凭证**: 学号/密码/指纹（既有 ASSET；**仅信任时写**）

**登录态**: `signedOut | needs2FA | signedIn`（门控依据）

## Contracts & Interfaces

**认证/会话（改造，保持兼容）**
- `SessionManager.login(credentials: CampusCredentials, trustDevice?: boolean): Promise<LoginResult>` —— 新增**可选**参数；缺省沿用设置值（既有调用零改动）
- `SessionManager.tryAutoLogin(): Promise<LoginResult | undefined>` —— 命中 2FA 时置"需 2FA"状态供门控渲染
- 信任读写：`SettingsManager.isTrustDevice/setTrustDevice`（复用）+ 待清除标记读写（新增）

**装配（改造）**
- `EntryAbility`：退出钩子清凭证（条件化）；启动兜底清除（条件化）
- `Index`：按登录态（`signedOut | needs2FA | signedIn`）渲染登录页 / Tabs
- `LoginPage`：信任开关（默认＝上次选择）+ 登录传参 + 2FA 视图（复用既有流程）+ 提示文案

**依赖契约（复用，不改语义）**
- `SecureStorage.saveCredentials/getCredentials/clearCredentials`（ASSET）、`AuthManager`（登录态）、`SettingsManager`（持久化）、`StorageKeys`（新增键）、`utils/I18n`（`t/tp`）

## 修订（2026-10-13）：退出登录凭证策略与登录页回填

**变更来源**：用户实测反馈——"信任设备 + 退出登录回到登录界面后，有保存凭证时应点击登录直达主页"。

**修订后的规则（覆盖上文相关表述）**
- **Decision 1 补充**：信任策略同时决定"**是否在退出登录时保留凭证**"——
  - **信任开启**：退出登录**仅清会话**（`AuthManager.reset()` / 清会话态），**保留 ASSET 中的凭证**；
  - **未信任**：退出登录（及退出/启动清理路径）**不得留下凭证残留**（沿用 Decision 1 的"不落盘/清除"策略）。
- **Decision 9（新增）— 登录页回填与一键直达主页**：
  - `LoginPage` 在初始化时（异步）读取既有凭证：若**信任开启且存在凭证** → **回填学号与密码**（密码输入框仍保持掩码可切换）；
  - 该场景下点击登录：**服务端未要求 2FA → 直接进入主页**（`SUCCESS → AUTHENTICATED → Index 门控渲染 Tabs`）；服务端要求 2FA → 进入 2FA 视图（既有路径）；
  - **不得**因回填而跳过后端校验（仍执行完整 `login`）。
- **受影响文件（在既有清单内）**：`pages/LoginPage.ets`（回填 + 直达主页确认）、`pages/SettingsPage.ets`（退出登录改为"仅清会话"）、必要时 `services/auth/SessionManager.ets`（`logout` 不再清凭证；凭证清理仅在"未信任/待清除"路径）；`utils/I18n.ets`（如需新增提示文案，如"凭证已保留，可直接登录"）。
- **回归要点**：未信任场景**仍**必须在退出/启动时清除凭证（SC-002/SC-003 不变）；`Index` 门控与 2FA 直达逻辑**不变**。
