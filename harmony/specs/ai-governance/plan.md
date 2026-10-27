# Implementation Plan: AI 治理（审计持久化 + 权限 UI）

**Input**: Feature specification from `harmony/specs/ai-governance/spec.md`

## Summary

在现有 AI Agent 治理链（`dryRun → 确认 → run → verify`）外侧增加两个能力：**审计落盘**与**能力授权**。审计从 `AgentService` 的内存数组改为"内存 + preferences 持久化"双写，写入前按 RN 基线规则脱敏，上限 200 条；设置页内嵌展示最近 6 条，可展开、可二次确认清空。权限沿用已有的 `AgentTools.all(disabledPermissions)` 过滤能力，新增禁用集合的持久化与内存缓存；`runAgent` 构建工具清单时过滤，执行前再做一次权限门禁，拒绝时返回可读结果并写审计。UI 沿用项目现有的"标签页内 `subScreen` 切换 + `BackDispatcher`"模式，不引入路由框架。

## Technical Context

**Language/Version**: ArkTS / ArkUI（HarmonyOS NEXT，项目现有 SDK 版本；`.ets` 严格模式）  
**Primary Dependencies**: `@kit.ArkData`（preferences）、现有 `PreferencesStorage`、`I18n`、`components/Ui`（`DetailHeader`/`SectionHeader`/`StatusBadge`/`EmptyHint`）、`state/BackDispatcher`  
**State Management**: 沿用项目现有 ArkUI 状态管理 V1（`@Component` / `@State` / `@StorageLink` / `@Watch`）；不迁移 V2  
**Storage**: preferences 明文 JSON，键 `@campusos/action_audit`（已预留）与新增 `@campusos/ai_disabled_permissions`；仅存脱敏后的审计内容  
**Testing**: `arkts_check` + `devecocli build` + `check lint`；模拟器端 `verify_ui` 覆盖设置页与权限页  
**Target Platform**: HarmonyOS 手机（当前验证设备为 Mate 80 Pro Max 模拟器）  
**Project Type**: mobile-app（单 entry 模块）  
**Performance Goals**: 单次工具调用的审计持久化不阻塞 agent 循环（异步、串行队列）；设置页首屏在无审计记录时不产生额外等待；200 条记录加载与渲染无可感知卡顿  
**Constraints**: 日志与审计不得出现敏感明文；审计上限 200 条；不改变工具风险分级与确认要求；不新增工具；不破坏现有确认链；服务层不硬编码中文界面文案  
**Scale/Scope**: 45 个已注册工具、约 27 个权限键、审计上限 200 条、2 个新增 UI 面（内嵌审计面板 + 权限子页）、4 个新增源码文件

## Project Structure

### Documentation (this feature)

```text
harmony/specs/ai-governance/
├── feature.json
├── spec.md
├── plan.md
└── tasks.md            # Phase 3 产出
```

### Source Code (repository root)

```text
harmony/entry/src/main/ets/
├── domain/
│   └── ActionTypes.ets                  # 修改：AuditRecord 增加权限/预览/验证字段
├── storage/
│   ├── StorageKeys.ets                  # 修改：登记 AI_DISABLED_PERMISSIONS
│   ├── ActionAuditStore.ets             # 新增：审计持久化 + 脱敏 + 变更信号
│   └── AIPermissionStore.ets            # 新增：禁用权限集合（持久化 + 内存缓存）
├── services/ai/
│   ├── AgentService.ets                 # 修改：schema 过滤、执行前门禁、审计双写
│   └── AgentTools.ets                   # 修改：仅补充按名查询的只读辅助（不改注册表）
├── pages/
│   ├── SettingsPage.ets                 # 修改：subScreen、审计面板、权限入口
│   ├── Index.ets                        # 修改：设置标签的返回归属
│   └── settings/
│       ├── AIAuditPanel.ets             # 新增：最近 6 条 + 展开 + 清空
│       └── AIPermissionsPage.ets        # 新增：按权限键分组的开关页
├── state/
│   └── BackDispatcher.ets               # 修改：增加 SETTINGS 归属
├── entryability/
│   └── EntryAbility.ets                 # 修改：启动预加载禁用权限集合
└── utils/
    └── I18n.ets                         # 修改：新增治理相关中英文案
```

**Structure Decision**: 沿用项目现有分层（`pages/` / `state/` / `services/` / `storage/` / `domain/` / `components/`），不引入 MVVM 迁移。新增文件按既有职责落位：持久化与脱敏进 `storage/`，权限与审计的 UI 进 `pages/settings/`，Agent 编排仍留在 `services/ai/AgentService.ets`。共 4 个新增文件、7 个修改文件；权限分组与视图模型作为页面私有结构，不单独建 `viewmodel/`，因为该页面只有单一数据源（工具注册表 + 禁用集合），拆层不会带来可测性收益。

## Complexity Tracking

无超出既有架构的复杂度项：不新增模块、不新增第三方依赖、不引入路由或数据库。

## Research & Decisions

### D1. 审计记录以什么形式持久化

- **Decision**: 复用 `PreferencesStorage`（preferences，键 `@campusos/action_audit`），以 JSON 字符串数组保存，新记录在前，上限 200 条；写前完成脱敏。
- **Rationale**: 项目内所有非凭证持久化都走 `PreferencesStorage`；数据量上限 200 条、单条为短文本，preferences 足够；RN 基线同样使用键值存储。避免为小数据量引入 RDB。
- **Alternatives considered**: 关系型数据库（迁移与初始化成本高，无查询需求）；独立文件（与现有清理/备份路径不一致）；仅内存（无法满足"跨重启保留"）。

### D2. 为什么不直接在 `appendAuditRecord` 里同步写盘

- **Decision**: `AgentService` 继续维护内存数组（供同步读取），同时把记录投递到 `ActionAuditStore` 的异步串行队列；持久化失败只记脱敏日志，不影响工具结果。
- **Rationale**: 工具执行链是 `async` 的，但审计写入若 `await` 会引入额外延迟与失败传播风险；技能契约明确要求"审计异常吞掉，不影响对话"。串行队列可避免快速连续调用时的读-改-写竞争。
- **Alternatives considered**: 在 agent 循环内 `await` 写盘（失败会影响对话）；每次全量覆盖写（并发丢记录）；内存数组上限 100（与 RN 的 200 不一致）。

### D3. 权限状态的读取路径

- **Decision**: 新建 `AIPermissionStore`，启动时 `ensureLoaded()` 把禁用集合读入静态内存缓存，提供同步 `isDisabled(permission)` 与异步 `setEnabled()`；`runAgent` 开始时 `await ensureLoaded()`。
- **Rationale**: 工具清单构建（同步）与执行前门禁（同步）都需要即时读取权限；每次调用都读 preferences 会引入异步等待并可能读到旧值。启动预加载 + 写时即更新内存，保证"切换后下一次请求即生效"。
- **Alternatives considered**: 直接读 `SettingsManager`（职责混杂，且设置对象无权限字段）；每次 `runAgent` 读一次 preferences（执行前门禁仍可能读到旧值，且需要额外异步点）；只存内存（重启丢失，违反 SC/FR-010）。

### D4. 执行前门禁放在哪里

- **Decision**: 放在 `AgentService` 的工具派发路径：先 `AgentTools.byName(name)` 取到工具，再判断 `AIPermissionStore.isDisabled(tool.permission)`；命中则在 `dryRun`/确认/执行之前返回拒绝结果并写审计。`AgentTools.all(disabledPermissions)` 仍负责下发给模型的清单过滤。`AgentTools.byName` 保持"注册表全量查找"，不因禁用而返回 `undefined`。
- **Rationale**: 需求要求区分"未知工具"与"已关闭能力"；若把权限过滤塞进 `byName`，两者会共用同一条 `未知工具` 文案，无法给出可读拒绝。把门禁放在 `AgentService` 可保证任何调用路径（包括模型强行点名）都经过同一检查，且不会绕过。
- **Alternatives considered**: 只在 `byName` 过滤（拒绝文案不可区分）；只在 UI 层禁用入口（模型仍可直接调用，不可靠）；在 `AgentTools` 内部做全局拦截（注册表变成有状态对象，测试与复用变差）。

### D5. 审计 UI 的承载方式

- **Decision**: 设置页内嵌 `AIAuditPanel`（最近 6 条 + 展开 + 清空）；AI 权限使用独立子页 `AIPermissionsPage`，由 `SettingsPage` 的 `subScreen` 状态切换，沿用 `CampusPage` 的 `subScreen + onBack` 模式；为系统返回键新增 `BackOwner.SETTINGS` 并在 `Index.activeBackOwner()` 中映射设置标签。
- **Rationale**: 与 RN 基线一致（审计内嵌、权限独立页）；项目没有路由栈，所有子页均由集线页本地状态驱动，`BackDispatcher` 已为此设计。若引入 `Navigation`/`router` 会形成第二套导航模型。
- **Alternatives considered**: 两者都做独立页（改动面更大，且审计入口仍需设置页）；两者都内嵌（`SettingsPage` 已 1000+ 行，27 行权限开关会使其难以维护）；`bindSheet` 弹层（27 行开关不适合弹层高度）。

### D6. 审计列表如何感知新记录

- **Decision**: `ActionAuditStore` 在追加/清空后向 `AppStorage` 写入 `auditTick` 时间戳；`AIAuditPanel` 通过 `@StorageLink('auditTick') + @Watch` 重新加载。
- **Rationale**: 设置页常驻于标签容器，切回时不一定重新 `aboutToAppear`；现有 `aiConfigTick` 已用同一模式解决"配置变更后跨页刷新"，复用可降低理解成本。
- **Alternatives considered**: 每次切换标签重新加载（依赖不可靠的可见性回调）；手动刷新按钮（增加一次点击且容易忘记）；轮询（无必要开销）。

### D7. 脱敏规则与落点

- **Decision**: 审计落盘前统一脱敏：对参数对象按键名递归处理（命中 `password|passwd|pwd|secret|token|cookie|captcha|verification|api.?key|credential|fingerprint|trade.?password|phone|mobile|email|student.?id|owner.?id|user.?id|member.*id|idserial|card.?id|account|acc.?no|identity|idcard|mac|ip4|ip6` 即打码或替换为 `[REDACTED]`）；字符串上限 500、数组上限 20、深度上限 5；对摘要类纯文本再做手机号/邮箱/11 位数字的兜底打码。结果 JSON 上限 2000。
- **Rationale**: 与 RN 的 `actionAuditStorage` 对齐，用户在两端看到一致的脱敏行为；同时覆盖 Harmony 侧"参数摘要是字符串"的形态，避免只做对象脱敏而漏掉摘要。
- **Alternatives considered**: 只做对象脱敏（摘要字符串仍可能带手机号）；只做正则字符串脱敏（嵌套键名命中不了）；不落参数只落工具名（审计价值不足）。

### D8. 拒绝文案的语言

- **Decision**: 拒绝结果包含稳定错误码、权限键与可读文案；文案通过 `I18n.t()` 取当前语言，服务层不写死中文。结果同时回灌给模型与工具轨迹，用户在对话中能看到与当前语言一致的解释。
- **Rationale**: 工具结果会进入 `ToolTrace.result` 并被渲染，硬编码中文会在英文界面暴露中文；而纯错误码对模型不友好。`I18n.t` 已有"未命中回退中文"的兜底，风险可控。
- **Alternatives considered**: 服务层硬编码中文（违反项目 i18n 约定）；只返回 `permission_disabled` 代码（模型与用户都难以理解）。

### D9. 风险等级的展示

- **Decision**: 保持 `ToolRisk` 现有四级（`NONE/LOW/MEDIUM/HIGH`）与各工具的赋值不变；权限页按注册表聚合出"最高风险"，标签映射为：`NONE→只读`、`LOW→可写`、`MEDIUM→中风险`、`HIGH→高风险`；`requiresConfirmation=true` 的类别额外显示"写操作会继续要求二次确认"。
- **Rationale**: 非目标明确"不改变现有风险分级"；页面只需要呈现，不需要重新分级。
- **Alternatives considered**: 引入 RN 的五级 `ToolRisk`（会改动所有工具赋值，超出范围）。

### D10. 新增存储键必须先登记

- **Decision**: 在 `StorageKeys.ets` 增加 `AI_DISABLED_PERMISSIONS`（值为 `@campusos/ai_disabled_permissions`，与 RN 基线同名），并在 `StorageKeysMap` 接口中登记；`ACTION_AUDIT` 直接复用已预留键。
- **Rationale**: 项目契约要求"新增键必须先登记到 `StorageKeys.ets`"，集中管理可避免键名漂移与清理遗漏。
- **Alternatives considered**: 在 store 内定义私有常量（违反契约，且清理逻辑无法枚举）。

## Data Model

### AuditRecord（扩展 `domain/ActionTypes.ets`）

| 字段 | 类型 | 说明 | 约束 |
|---|---|---|---|
| `id` | string | 记录标识 | 非空、唯一 |
| `timestamp` | string | ISO 时间 | 非空 |
| `toolName` | string | 工具内部名 | 非空 |
| `toolTitle` | string | 工具展示名 | 可空 |
| `risk` | string | 现有 `ToolRisk` 字符串 | 不改分级 |
| `permission` | string | 所属权限键（新增） | 可空（历史记录） |
| `confirmation` | string | `ConfirmationStatus` | 四态 |
| `status` | string | `ActionExecutionStatus` | 三态 |
| `success` | boolean | `status === success` | 派生 |
| `confirmed` | boolean | `confirmation === approved` | 派生 |
| `parameters` | string | 参数摘要（展示用） | 脱敏、≤500 |
| `paramsJson` | string | 脱敏后的参数 JSON（新增） | ≤500 |
| `previewAffectedResource` | string | 预览里的影响资源（新增） | 脱敏、可空 |
| `result` | string | 结果 JSON 片段 | 脱敏、≤2000 |
| `resultSummary` | string | 结果摘要 | 脱敏、可空 |
| `errorMessage` | string | 错误/拒绝原因 | 脱敏、可空 |
| `verificationOk` | boolean | 验证是否通过（新增） | 无验证时 false |
| `verificationMessage` | string | 验证说明（新增） | 脱敏、可空 |

**持久化形态**：上述对象的 JSON 数组，新记录在索引 0，长度 ≤ 200。

### PermissionGroup（权限页视图模型，页面私有）

| 字段 | 类型 | 说明 |
|---|---|---|
| `permission` | string | 权限键，分组唯一标识 |
| `title` | string | 类别展示名（按业务域映射，i18n key 兜底） |
| `toolTitles` | string[] | 该权限下工具展示名 |
| `toolCount` | number | 工具数量 |
| `maxRisk` | ToolRisk | 该组最高风险 |
| `requiresConfirmation` | boolean | 是否存在需确认工具 |
| `enabled` | boolean | 当前是否启用 |

### DisabledPermissionSet

- 形态：`string[]`，仅保存被禁用的权限键。
- 规则：去重、字典序排序；空数组等价于"全部启用"；读取时过滤非字符串项；损坏/缺失回退空数组。

### 存储键与容量

| 键 | 值 | 上限 | 失败处理 |
|---|---|---|---|
| `@campusos/action_audit` | 审计记录 JSON 数组 | 200 条 | 读取回退空数组；写入失败仅记日志 |
| `@campusos/ai_disabled_permissions` | 禁用权限键 JSON 数组 | 无（≤27） | 读取回退空数组；写入失败回滚内存并提示 |

## Contracts & Interfaces

### ActionAuditStore（新增，`storage/ActionAuditStore.ets`）

```text
static async load(): Promise<AuditRecord[]>
static async append(record: AuditRecord): Promise<boolean>
static async clear(): Promise<void>
static sanitizeParamsJson(args: Record<string, Object>): string
static sanitizeText(value: string, maxLength: number): string
```

约束：`load` 永不抛出；`append` 串行执行、失败返回 false 且不抛出；`append`/`clear` 成功后更新 `AppStorage` 的 `auditTick`；`sanitize*` 不修改入参。

### AIPermissionStore（新增，`storage/AIPermissionStore.ets`）

```text
static ensureLoaded(): Promise<void>
static isLoaded(): boolean
static getDisabled(): string[]
static isDisabled(permission: string): boolean
static async setEnabled(permission: string, enabled: boolean): Promise<boolean>
static async resetAll(): Promise<boolean>
```

约束：`ensureLoaded` 幂等、永不抛出；`getDisabled` 返回副本；`isDisabled` 为同步判定（未加载时按"未禁用"处理）；`setEnabled` 先更新内存再持久化，持久化失败回滚内存并返回 false。

### AgentService（修改，`services/ai/AgentService.ets`）

```text
static async runAgent(...): Promise<string>                     // 行为扩展：加载权限、过滤工具清单
private static async executeToolCall(...): Promise<Record<string, Object>>  // 行为扩展：执行前权限门禁
private static async appendAuditRecord(...): Promise<void>      // 签名变更：异步双写
static getAuditRecords(): AuditRecord[]                          // 保持同步内存读取
static clearAuditRecords(): void                                 // 清空内存并触发持久化清空（异步、失败吞掉）
```

行为契约：

1. `runAgent` 开始时 `await AIPermissionStore.ensureLoaded()`，并以 `AIPermissionStore.getDisabled()` 构建工具清单。
2. `executeToolCall` 在 `dryRun` 之前判定权限；被禁用时：派发 `onToolStart`、返回 `{ error, permission, tool }` 形态的可读结果、派发 `onToolEnd`（状态 `error`）、写审计，且不调用 `dryRun`/`run`/`verify`。
3. 未被禁用时，确认链顺序与现有实现完全一致。
4. `appendAuditRecord` 先更新内存（上限 200），再投递 `ActionAuditStore.append`；持久化异常被捕获。
5. 所有日志只允许输出工具名、状态、条数，不输出参数与结果正文。

### AgentTools（修改，`services/ai/AgentTools.ets`）

```text
static all(disabledPermissions?: string[]): AgentToolDef[]   // 已存在，签名不变
static byName(name: string): AgentToolDef | undefined        // 保持全量查找
static permissionKeys(): string[]                            // 新增：注册表中去重后的权限键（权限页用）
```

约束：`byName` 不承担权限过滤；权限门禁由 `AgentService` 统一执行。

### SettingsPage / 子页契约（修改 + 新增）

```text
AIPermissionsPage({ onBack: () => void })      // 新增子页组件
AIAuditPanel({})                                // 新增内嵌面板（无外部入参）
subScreen: string                               // '' | 'aiPermissions'
```

约束：进入权限子页时注册 `BackDispatcher.push(BackOwner.SETTINGS, handler)`，离开或销毁时移除；`Index.activeBackOwner()` 在设置标签返回 `BackOwner.SETTINGS`。

### I18n 契约（新增键，`utils/I18n.ets`）

```text
settings.aiPermissions / settings.aiPermissionsSummary
settings.aiPermissionEnabledCount / settings.aiPermissionRestoreAll
settings.aiPermissionToggleFailed
settings.aiPermissionRiskNone / RiskLow / RiskMedium / RiskHigh
settings.aiPermissionWriteConfirmNote
settings.aiActionRecords / settings.aiActionRecordsEmpty
settings.aiActionRecordsClear / settings.aiActionRecordsClearTitle / settings.aiActionRecordsClearMessage
settings.aiActionStatusSuccess / Error / Cancelled
settings.aiActionConfirmNotRequired / Approved / Denied / Unavailable
settings.aiActionPermission / Confirm / Params / Result / Error / Verification / Preview
settings.aiActionVerificationPass / VerificationFail
settings.aiActionClearDone / settings.aiActionRefresh
ai.permissionDisabled
```

约束：每个键提供 `zh` 与 `en`；占位符使用 `{name}` 形态并配合 `tp()`。

### 持久化与日志契约

```text
StorageKeys.ACTION_AUDIT            = '@campusos/action_audit'
StorageKeys.AI_DISABLED_PERMISSIONS = '@campusos/ai_disabled_permissions'
AppStorage 信号键：auditTick（number，仅时间戳，不承载记录内容）
```

约束：`auditTick` 与审计内容均不得包含参数原文；日志标签沿用 `AgentService` / 新增 `ActionAudit` / `AIPermission`，只记录数量与状态。
