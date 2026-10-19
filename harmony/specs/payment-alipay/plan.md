# Implementation Plan: 支付宝支付基础设施（T02）

**Input**: Feature specification from `harmony/specs/payment-alipay/spec.md`

## Summary

提供一个与业务解耦的支付基础设施：`payCode → 支付宝 Deep Link` 的确定性构建与校验、通过系统外部链接能力外跳支付宝、在外跳前登记内存态“待回读”上下文、在 `EntryAbility.onForeground` 时投递一次性回读事件，供 T11/T12/T13 页面刷新余额/流水/订单。另提供仅 debug 可见的支付通道自检入口与启动自检，用于真机外跳和日志脱敏验收。

技术路径：新增 `services/payment/` 服务目录；复用现有 `utils/Logger`、`utils/I18n`、`emitter` 事件总线与 `EntryAbility` 生命周期；在 `module.json5` 声明支付宝 scheme 查询白名单；不新增第三方依赖、不改动 `src/` 与 `android/`。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: `@kit.AbilityKit`（`common.UIAbilityContext`、`bundleManager.canOpenLink`、`OpenLinkOptions`）、`@kit.BasicServicesKit`（`emitter`、`BusinessError`）、既有 `utils/Logger`、`utils/I18n`
**State Management**: 沿用项目现有 State Management V1（`@Component` + `@State` / `@StorageLink`），本特性不引入 V2
**Storage**: 无持久化；待回读上下文仅进程内存（已与用户确认）
**Testing**: `arkts_check` + `devecocli build`；启动期 `PaymentSelfTest` 覆盖链接构建/提取/回读事件；真机通过仅 debug 可见的支付通道自检入口人工确认外跳
**Target Platform**: HarmonyOS 手机/平板（当前项目 targetSdkVersion 6.1.1(24)）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 链接构建为纯内存同步操作，单次 < 1ms；回读事件在 `onForeground` 后 2s 内投递；启动自检不阻塞首页加载（总耗时目标 < 50ms）
**Constraints**: 不持久化支付码/二维码 URL/金额明文；日志不得出现凭据；不伪造支付成功；release 构建隐藏诊断入口；不实现子系统充值/下单 UI
**Scale/Scope**: 新增 2 个服务文件；修改 4 个既有文件（`EntryAbility.ets`、`SettingsPage.ets`、`I18n.ets`、`module.json5`）；新增 1 个 `querySchemes` 配置项；无新资源文件

## Project Structure

### Documentation (this feature)

```text
harmony/specs/payment-alipay/
├── feature.json
├── spec.md
├── plan.md
└── tasks.md
```

### Source Code (repository root)

```text
harmony/entry/src/main/ets/
├── services/
│   └── payment/
│       ├── AlipayPaymentService.ets      # 新增：链接构建/校验、可用性探测、外跳、待回读状态、回读事件
│       └── PaymentSelfTest.ets           # 新增：纯逻辑与事件总线的启动自检
├── entryability/
│   └── EntryAbility.ets                  # 修改：onForeground 投递回读事件；启动时运行支付自检
├── pages/
│   └── SettingsPage.ets                  # 修改：仅 debug 可见的支付通道自检入口与回读提示
└── utils/
    └── I18n.ets                          # 修改：新增 payment.* 中英文案键

harmony/entry/src/main/
├── module.json5                          # 修改：querySchemes 声明 alipayqr / alipays
└── resources/base/element/string.json    # 不新增权限，不需要改

harmony/
└── DEVELOPMENT.md                        # 修改：记录支付基础设施边界、诊断入口与已知限制
```

**Structure Decision**: 沿用既有项目架构，不引入 MVVM 迁移。支付基础设施属于跨子系统服务，放入既有 `services/` 下的新 `payment/` 子目录，与 `services/campus/`、`services/ai/` 同级；纯逻辑、事件总线与自检集中在两个文件，避免为一个基础设施特性拆出过多文件。UI 只增加一个仅 debug 可见的设置页诊断入口，不新增页面、不新增导航。

## Complexity Tracking

> 本特性无 Constitution 违背项；未引入新架构层、新依赖或持久化。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 无 | — | — |

## Research & Decisions

**Decision 1 — 外跳接口选择**
- **Decision**: 使用 `common.UIAbilityContext.openLink(link, { appLinkingOnly: false })` 作为主外跳接口；不使用显式 `startAbility` + Want 作为主路径。
- **Rationale**: HarmonyOS 官方文档将 `openLink` 列为 Deep Linking 的推荐接口；它能按 URI 匹配已安装应用，并在目标不存在时返回可捕获错误。显式 Want 需要知道支付宝的 bundleName/abilityName，跨设备版本不稳定。
- **Alternatives considered**: `startAbility` 隐式 Want（需要自行构造 Want，错误码更分散）；显式 Want（依赖支付宝包名，版本差异大）；`Web` 组件打开网页版（不是外跳，且会破坏“打开支付宝”的验收）。

**Decision 2 — 外跳前可用性探测**
- **Decision**: 外跳前调用 `bundleManager.canOpenLink` 探测 `alipayqr://platformapi/startapp`，失败再探测 `alipays://platformapi/startapp`；在 `module.json5` 的 `querySchemes` 中声明这两个 scheme。
- **Rationale**: 官方 FAQ 明确：未在 `querySchemes` 声明的 scheme 调用 `canOpenLink` 会抛 `17700056`，且直接外跳可能闪退。先探测可把“未安装/不可访问”变成可读结果，满足失败可读与不崩溃。
- **Alternatives considered**: 直接 `openLink` 并捕获异常（可用，但无法区分未安装与其他错误）；只探测 `alipayqr`（部分设备可能只注册 `alipays`）；不配置 `querySchemes`（会触发系统错误，违反验收）。

**Decision 3 — 返回 App 的检测点**
- **Decision**: 在 `EntryAbility.onForeground` 调用支付服务的 `notifyForeground()`，由服务判断是否存在待回读状态并投递事件；页面通过订阅接口接收。
- **Rationale**: 子页面是普通 `@Component`，没有 `onPageShow`；`onForeground` 是 UIAbility 从后台回到前台的稳定生命周期回调，能覆盖“从支付宝返回”。复用项目已有的 `emitter` 事件总线，与 `UiEvents` 模式一致。
- **Alternatives considered**: 页面 `onPageShow`（子组件不可用）；轮询 `AppStorage` 时间戳（延迟高、耗电）；`onNewWant`（只在热启动带 Want 时触发，返回场景不保证）。

**Decision 4 — 待回读状态的生命周期**
- **Decision**: 待回读状态仅保存在 `AlipayPaymentService` 的静态内存字段；调用 `openLink` 前写入，回到前台或外跳失败时清除；有效期 30 分钟；新支付覆盖旧支付。
- **Rationale**: 用户已确认不跨进程持久化。支付码/二维码 URL 属于敏感数据，不应落盘；进程被杀后页面重新挂载本就会重新查询余额/记录，无需补发陈旧事件。
- **Alternatives considered**: Preferences 持久化子系统+金额+时间（可跨进程补发，但增加陈旧误触发与隐私面）；持久化支付码（明确禁止）；SQLite（过度设计）。

**Decision 5 — 支付宝 scheme 回退**
- **Decision**: 主链接固定为 RN 基线 `alipayqr://platformapi/startapp?saId=10000007&qrcode=...`；若设备只注册 `alipays`，则用相同路径与参数构造 `alipays://...` 回退链接。
- **Rationale**: 保持与 RN 基线逐字符一致，同时提高 HarmonyOS 设备上的实际可达性；两个 scheme 都在 `querySchemes` 白名单内。
- **Alternatives considered**: 只支持 `alipayqr`（真机可能不可达）；只支持 `alipays`（与 RN 基线不一致）；同时打开两个（会重复拉起，禁止）。

**Decision 6 — 文案与错误码分层**
- **Decision**: 服务层只返回稳定状态码（`build_ready` / `launched` / `invalid_code` / `not_installed` / `launch_failed`）与 i18n 键（`payment.error.*`、`payment.link.ready`、`payment.launch.opened`），不返回中文文案；页面用既有 `I18n.t()` 本地化。
- **Rationale**: 遵循项目 i18n 规范“服务层禁止硬编码中文字面量”；T11/T12/T13 可复用同一套错误语义。
- **Alternatives considered**: 服务层直接返回中文（违反规范、英文环境不可用）；页面各自映射错误码（重复且易漂移）。

**Decision 7 — 诊断入口的形态**
- **Decision**: 在 `SettingsPage` 增加一个 `if (BuildProfile.DEBUG)` 包裹的“支付通道自检”分组：探测支付宝可访问性、打开测试 Deep Link、显示返回事件提示；release 构建不渲染。测试链接使用固定非支付测试码，并明确提示“不会发起支付”。
- **Rationale**: 真实设备外跳无法靠构建验证；设置页是现有页面，新增一个 debug-only 分组比新增测试页/导航更小。用户已确认允许该入口。
- **Alternatives considered**: 独立测试页（需要新页面注册与导航）；只提供 API 与日志（无法在真机点击触发）；放在子系统充值 UI（属于 T11/T12/T13，超出本特性）。

**Decision 8 — 自检与可验证性**
- **Decision**: 新增 `PaymentSelfTest`，在 `EntryAbility` 启动时运行；覆盖合法链接逐字符比对、空/空白/控制字符/URL 分隔符拒绝、二维码 URL 提取、回读事件一次性投递、无 pending 不投递、过期不投递、最新覆盖旧状态。自检只读写内存，不发起网络/外跳/支付。
- **Rationale**: 满足“URL 构建可验证”且不依赖设备；沿用项目既有启动自检风格，但独立文件避免改动 `Phase4SelfTest` 的已知 20/21 基线。
- **Alternatives considered**: 改 `Phase4SelfTest`（会改变既有基线，且与支付无关）；纯人工验证（不可回归）；引入测试框架（项目当前无单测基础设施）。

**Decision 9 — 日志脱敏**
- **Decision**: 日志只输出 `PAYMENT` 事件名、子系统、状态码、错误码、耗时；不输出支付码、二维码 URL、金额明文、Cookie、学号、API Key。错误对象只记录 `BusinessError.code`。
- **Rationale**: 满足验收“日志无凭据”；支付码可被用于拉起支付，属于敏感令牌。
- **Alternatives considered**: 输出支付码前缀便于排障（仍泄露，禁止）；输出完整 URL（包含支付码，禁止）；输出金额（非凭据但属于敏感财务信息，选择不输出）。

## Data Model

### CampusPaymentIntent（待回读支付意图）

| 字段 | 类型 | 说明 |
|---|---|---|
| `subsystem` | `string` | 子系统标识：`electricity` / `campusCard` / `sports` / `diagnostics` |
| `amount` | `number` | 调用方提供的金额；未知时传 `0`，仅用于回读提示，不写日志 |
| `startedAt` | `number` | 调用 `openLink` 前的毫秒时间戳 |

约束：仅内存；不序列化；不持久化；同一时刻最多一条，新值覆盖旧值；`startedAt` 超过 30 分钟视为过期。

### CampusPaymentLaunchResult（构建/外跳结果）

| 字段 | 类型 | 说明 |
|---|---|---|
| `status` | `string` | `build_ready` / `launched` / `invalid_code` / `not_installed` / `launch_failed` |
| `messageKey` | `string` | i18n 键，页面直接交给 `I18n.t()` |
| `errorCode` | `number` | 系统错误码；无错误时为 `0` |
| `url` | `string` | 仅构建成功时返回；页面不得记录到日志 |

### CampusPaymentReturnEvent（回读事件）

| 字段 | 类型 | 说明 |
|---|---|---|
| `intent` | `CampusPaymentIntent` | 待回读上下文摘要 |
| `elapsedMs` | `number` | 从 `startedAt` 到前台恢复的毫秒数 |

语义：只表示“用户已返回 CampusOS”，不表示支付成功；事件一次性投递后清除 pending。

### CampusPaymentProbeResult（诊断结果）

| 字段 | 类型 | 说明 |
|---|---|---|
| `available` | `boolean` | 是否至少有一个支付宝 scheme 可访问 |
| `scheme` | `string` | 实际可用的 scheme：`alipayqr` / `alipays` / 空串 |
| `messageKey` | `string` | `payment.diag.available` / `payment.diag.notInstalled` |

### 状态流转

```text
idle
  └─ 调用 openLink 前 → pending(subsystem, amount, startedAt)
       ├─ onForeground 且 elapsed <= 30min → 投递一次事件 → idle
       ├─ onForeground 且 elapsed > 30min  → 静默清除 → idle
       └─ 新 openLink 调用前 → 覆盖为最新 pending
  └─ 外跳失败/支付码无效 → idle（并清除旧 pending）
```

## Contracts & Interfaces

### 常量

- `CampusPaymentSubsystem`：`ELECTRICITY = 'electricity'`、`CAMPUS_CARD = 'campusCard'`、`SPORTS = 'sports'`、`DIAGNOSTICS = 'diagnostics'`
- `CampusPaymentStatus`：`BUILD_READY = 'build_ready'`、`LAUNCHED = 'launched'`、`INVALID_CODE = 'invalid_code'`、`NOT_INSTALLED = 'not_installed'`、`LAUNCH_FAILED = 'launch_failed'`
- `CampusPaymentI18n`：集中定义 `payment.error.invalidCode`、`payment.error.alipayNotInstalled`、`payment.error.launchFailed`、`payment.link.ready`、`payment.launch.opened`、`payment.return.refreshing`、`payment.return.unconfirmed`、`payment.diag.*` 等键，避免页面散落字符串

### AlipayPaymentService（新增，`services/payment/AlipayPaymentService.ets`）

| 方法 | 签名 | 语义 |
|---|---|---|
| 构建主链接 | `static buildDeepLink(payCode: string): string` | 合法时返回 RN 基线链接；非法时抛出不带敏感信息的 `Error` |
| 安全构建 | `static tryBuildDeepLink(payCode: string): CampusPaymentLaunchResult` | 不抛异常；非法时返回 `invalid_code` + `messageKey`，成功时返回 `build_ready` + `payment.link.ready` + `url` |
| 提取支付码 | `static extractPayCode(input: string): string` | 完整二维码 URL 取末段；裸码原样返回；无法提取返回空串 |
| 可用性探测 | `static isAlipayAvailable(): boolean` | 依次探测 `alipayqr`、`alipays`；捕获 `canOpenLink` 异常并返回 `false` |
| 当前 scheme | `static currentScheme(): string` | 返回实际可用的 scheme；都不可用返回空串 |
| 外跳 | `static launch(context: common.UIAbilityContext, payCode: string, subsystem: string, amount: number): Promise<CampusPaymentLaunchResult>` | 构建 → 探测 → `openLink` 前写入 pending；失败清除 pending；不返回“支付成功” |
| 登记 pending | `static beginPending(subsystem: string, amount: number, startedAt: number): void` | 写入/覆盖内存态；`startedAt` 供自检注入过期场景 |
| 查询 pending | `static peekPending(): CampusPaymentIntent \| null` | 返回当前 pending，不修改状态 |
| 清除 pending | `static clearPending(): void` | 外跳失败、用户取消、过期清理时使用 |
| 前台通知 | `static notifyForeground(): void` | 由 `EntryAbility.onForeground` 调用；有未过期 pending 时投递一次事件并清除 |
| 订阅回读 | `static subscribeReturn(handler: (event: CampusPaymentReturnEvent) => void): CampusPaymentReturnSubscription` | 注册监听；返回句柄供取消 |
| 取消订阅 | `static unsubscribeReturn(sub: CampusPaymentReturnSubscription): void` | 取消监听；页面 `aboutToDisappear` 调用 |

### 事件总线契约

- 事件 ID：`11001`（`EVT_PAYMENT_RETURN`；与 `UiEvents` 的 `10001` 不冲突）
- 事件数据：`Record<string, Object>`，字段 `subsystem`、`amount`、`startedAt`、`elapsedMs`
- 订阅方：任何页面/Manager；T02 只在 debug 设置页使用，T11/T12/T13 后续接入
- 投递语义：一次前台恢复最多一次；无 pending、过期、已清除时零次

### 配置契约

- `module.json5` 的 `module.querySchemes` 增加 `alipayqr` 与 `alipays`
- 不新增权限；`INTERNET` 等既有权限不变

### i18n 契约（新增键）

| 键 | 中文 | 英文 |
|---|---|---|
| `payment.error.invalidCode` | 支付码无效，请重试 | Payment code is invalid. Please try again. |
| `payment.error.alipayNotInstalled` | 未检测到支付宝，请先安装支付宝后重试 | Alipay was not found. Install Alipay and try again. |
| `payment.error.launchFailed` | 打开支付宝失败，请重试 | Could not open Alipay. Please try again. |
| `payment.error.unsupported` | 当前设备不支持外部支付链接 | This device does not support external payment links. |
| `payment.launch.opened` | 已请求打开支付宝，请完成支付 | Alipay was opened. Complete payment there. |
| `payment.return.refreshing` | 已返回 CampusOS，正在刷新余额与记录… | Back in CampusOS. Refreshing balance and records… |
| `payment.return.unconfirmed` | 未确认支付结果。若已完成支付，请刷新查看；若未支付，可重试。 | Payment is not confirmed. Refresh if you paid; retry if you did not. |
| `payment.diag.section` | 支付通道自检（仅调试） | Payment channel diagnostics (debug) |
| `payment.diag.probe` | 探测支付宝 | Check Alipay |
| `payment.diag.openTest` | 打开支付宝测试链接 | Open Alipay test link |
| `payment.diag.available` | 支付宝可用 | Alipay is available |
| `payment.diag.notInstalled` | 未检测到支付宝 | Alipay was not found |
| `payment.diag.noPayment` | 此操作不会发起支付 | This does not start a payment |
| `payment.diag.returned` | 已收到支付回读事件 | Payment return event received |

### UI 契约（仅 debug）

- `SettingsPage` 在 `BuildProfile.DEBUG` 为真时渲染“支付通道自检”分组；release 不渲染。
- 分组包含：探测行、打开测试链接按钮、最近回读提示文本。
- 点击“打开支付宝测试链接”后，若 `launch` 返回 `launched`，toast 使用 `payment.diag.noPayment`（不出现“支付成功”）；返回后由订阅回调显示 `payment.diag.returned`（诊断页不承诺刷新余额，`payment.return.refreshing` 留给 T11–T13）。

### 自检契约

- `PaymentSelfTest.runPaymentSelfTest(): Promise<number>` 返回失败数；成功时 0。
- 日志标签 `PaymentTest`；每条 `PASS` / `FAIL` 只包含用例名，不包含支付码。
- 自检不发起网络请求、不调用 `openLink`、不修改业务数据。
