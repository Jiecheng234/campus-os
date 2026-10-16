# Implementation Plan: 会话复位统一（子系统"已确保"标志与瞬态缓存）

**Input**: Feature specification: `entry/src/main/ets/services/auth/session-reset-unification/spec.md`

**Note**: 本特性产物按项目约定与其余认证/服务层源码同区域放置（`entry/src/main/ets/services/auth/session-reset-unification/`），不创建 `spec/` 目录。

## Summary

将各校园子服务的瞬态会话态**统一纳入既有单一复位入口** `SessionManager.resetSessionState()`：为各服务新增一致签名的 `resetSessionState()`（无参、同步、幂等、不抛），入口在既有 3 个触发点（登录成功 / 2FA 成功 / 退出登录）逐一扇出（仅对已实例化服务，异常隔离）。

覆盖服务：`CampusDataService`（既有）、`SportsService`、`LibrarySeatService`（含访问令牌/时段缓存）、`LibraryRoomService`（含 cab 账号号）、`MailService`（邮件会话）、`CampusCardService`（账号缓存）。**不**改 Cookie/凭证、**不**复位认证服务 csrf；`CampusNetworkService` 无瞬态态、无改动。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `SessionManager`（单例装配与复位入口）、各 campus 服务；无新增依赖
**State Management**: N/A（纯服务层复位，不涉及 UI 状态）
**Storage**: N/A（复位的是进程内内存态；不触及 Cookie/凭证/偏好）
**Testing**: `arkts_check` + `devecocli build` + 模拟器验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性 / 横切加固）
**Performance Goals**: 复位为 O(1) 内存操作，无网络请求、无 I/O
**Constraints**: 不强制实例化服务（SC-002）；不清 Cookie/凭证（SC-003）；不改 csrf 语义（SC-004）；复位异常不中断流程（SC-005）；ArkTS 严格模式
**Scale/Scope**: 1 处入口改造（`SessionManager`）+ 5 个服务新增复位方法（`SportsService`/`LibrarySeatService`/`LibraryRoomService`/`MailService`/`CampusCardService`）；`CampusDataService` 既有不变

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/services/auth/session-reset-unification/
├── feature.json         # 特性目录记录
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/services/
├── auth/
│   └── SessionManager.ets                     # 改造：resetSessionState() 扇出到各已实例化服务（异常隔离）
└── campus/
    ├── CampusDataService.ets                  # 既有：已有 resetSessionState()（不变）
    ├── SportsService.ets                      # 改造：新增 resetSessionState()
    ├── LibrarySeatService.ets                 # 改造：新增 resetSessionState()（含访问令牌/时段缓存）
    ├── LibraryRoomService.ets                 # 改造：新增 resetSessionState()（含 cab 账号号）
    ├── MailService.ets                        # 改造：新增 resetSessionState()（清邮件会话）
    └── CampusCardService.ets                  # 改造：新增 resetSessionState()（清账号缓存）
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。这是**服务层横切加固**：复位方法落在各服务自身（各服务最了解自己的瞬态态），唯一扇出点落在既有 `SessionManager`（其本身即"认证/会话协调层"），与既有 `CampusDataService.resetSessionState()` 范式一致扩展。不新增目录（除本特性产物）、不新增依赖、不新增 UI/资源。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 复位入口保持唯一**
- **Decision**: 沿用既有 `SessionManager.resetSessionState()`（私有静态）作为**唯一扇出点**；3 个触发点（登录成功、2FA 成功、退出登录）不变。
- **Rationale**: 既有设计已确立"单一入口 + 门控广播前复位"的时序；本特性只扩展扇出面，不改时序（避免破坏"登录成功后门控广播前复位"的约束）。
- **Alternatives considered**: 新增第二处复位入口（时序风险，且违背单一入口）。

**Decision 2 — 各服务统一复位方法签名**
- **Decision**: 各服务新增 `resetSessionState(): void`（无参、**同步**、幂等、不抛）。服务内部只清自己的瞬态态，返回 `void`。
- **Rationale**: 与既有 `CampusDataService.resetSessionState()` 签名一致；同步保证入口可在登录/退出关键路径内安全调用；不抛便于入口简化。
- **Alternatives considered**: 各服务自定义方法名（难统一、易漏接）。

**Decision 3 — 惰性安全（不强制实例化）**
- **Decision**: 入口仅对**已实例化**的服务调用复位（`if (sessionManager.xService !== undefined) xService.resetSessionState()`），沿用既有的 `campusDataService !== undefined` 判据。
- **Rationale**: 复位不应触发懒加载（避免无谓实例化与潜在副作用）；未实例化服务的瞬态态本为初值，无需复位（FR-003/SC-002）。
- **Alternatives considered**: 直接调用 getter（会创建实例，违背惰性）。

**Decision 4 — 异常隔离**
- **Decision**: 每个服务的复位调用以 `try/catch` 包裹（或依赖服务方法不抛）；单服务异常不中断其余复位与登录/退出流程（FR-006/SC-005）。
- **Rationale**: 复位位于登录/退出关键路径，任何异常都会放大为登录异常。
- **Alternatives considered**: 不隔离（单点异常阻断登录）。

**Decision 5 — 边界（不触碰 Cookie/凭证/csrf）**
- **Decision**: 复位仅清进程内瞬态标志/缓存；**不**清 Cookie、**不**动凭证、**不**复位认证服务 csrf（保持既有学习会话语义）。
- **Rationale**: 既有注释已明确"登录成功后复位 csrf 会导致学习页 `no_csrf`"；Cookie/凭证语义由信任策略与调用方处理（FR-004/FR-005/SC-003/SC-004）。
- **Alternatives considered**: 一并复位 csrf（已知回归）。

**Decision 6 — 各服务复位内容（逐服务）**
- **Decision**:
  - `SportsService`：`sportsSessionEnsured = false`
  - `LibrarySeatService`：`libAccessEnsured = false`；`accessTokenValue = ''`；`accessTokenTs = 0`；`lastDaySegment = undefined`
  - `LibraryRoomService`：`cabLoginEnsured = false`；`cabAccNo = -1`
  - `MailService`：`session = undefined`
  - `CampusCardService`：`accountUser = ''`；`accountCardId = ''`
- **Rationale**: 逐一对应各服务的瞬态态（见既有字段清单）；确保重登后重新建立会话（FR-001/FR-002）。
- **Alternatives considered**: 只复位"已确保"标志（漏掉令牌/账号/会话缓存，仍可能复用陈旧态）。

**Decision 7 — `CampusNetworkService` 与 `TsinghuaAuthService`**
- **Decision**: `CampusNetworkService` 无瞬态态字段（不新增无操作复位）；`TsinghuaAuthService` 的 csrf/凭证保持既有处理。
- **Rationale**: 无态可复位；auth 层语义需保持（FR-005/FR-008）。
- **Alternatives considered**: 为形态一致加空方法（无收益、易误解）。

## Data Model

**瞬态会话态（被复位对象，进程内内存态）**

| 服务 | 瞬态字段 | 复位值 |
|---|---|---|
| `CampusDataService`（既有） | `registrarRoamEnsured`/`gradesRoamEnsured`/`classroomRoamEnsured`/`petestRoamEnsured`/`eleSessionEnsured`/`learnReady`/`scheduleStatus`/`semesterFirstDay`/`currentSemester`/`trace` | 既有逻辑（不变） |
| `SportsService` | `sportsSessionEnsured` | `false` |
| `LibrarySeatService` | `libAccessEnsured` / `accessTokenValue` / `accessTokenTs` / `lastDaySegment` | `false` / `''` / `0` / `undefined` |
| `LibraryRoomService` | `cabLoginEnsured` / `cabAccNo` | `false` / `-1` |
| `MailService` | `session`（Coremail 会话） | `undefined` |
| `CampusCardService` | `accountUser` / `accountCardId` | `''` / `''` |
| `CampusNetworkService` | （无） | — |

**统一复位入口**: `SessionManager.resetSessionState()` —— 逐一扇出各已实例化服务的 `resetSessionState()`。

## Contracts & Interfaces

**各服务契约（新增 `resetSessionState(): void`）**
- `SportsService.resetSessionState(): void` —— 清体育子系统会话标志。
- `LibrarySeatService.resetSessionState(): void` —— 清图书馆座院子系统会话标志 + 访问令牌/时段缓存。
- `LibraryRoomService.resetSessionState(): void` —— 清研读间 cab 登录标志 + 账号号缓存。
- `MailService.resetSessionState(): void` —— 清邮件会话（Coremail）。
- `CampusCardService.resetSessionState(): void` —— 清校园卡账号/卡号缓存。
- 约定：**无参、同步、幂等、不抛**；仅清本服务瞬态态；不触及 Cookie/凭证/网络。

**入口契约（`SessionManager` 改造）**
- `private static resetSessionState(): void` —— 逐一调用**已实例化**服务的 `resetSessionState()`（`!== undefined` 判据），每个调用**异常隔离**；不触发懒加载；调用点（登录成功 / 2FA 成功 / 退出登录）与既有时序不变。

**依赖契约（复用，不改）**
- `SessionManager` 既有单例字段与 getter（`campusDataService`/`sportsService`/`librarySeatService`/`libraryRoomService`/`mailService`/`campusCardService`）。
- `TsinghuaAuthService`（不新增复位调用）。

**边界契约**
- 不复位：Cookie、持久化凭证、`TsinghuaAuthService.csrfToken`、演示模式设置、进行中的请求。

## Changelog

- 2026-10-16：初版计划（会话复位统一：各服务复位方法 + 单一入口扇出）。
