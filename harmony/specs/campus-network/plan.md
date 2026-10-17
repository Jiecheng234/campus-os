# Implementation Plan: 校园网接入（网络信息查询、设备注销与验证码登录）

**Input**: Feature specification: `entry/src/main/ets/pages/campus/campus-network/spec.md`

**Note**: 本特性产物按用户要求与其余校园子页源码同区域放置（`entry/src/main/ets/pages/campus/campus-network/`），不创建 `spec/` 目录。

## Summary

为"校园 → 校园网络"子页接入真实校园网自助服务数据：一次性快照（余额/用量 + 账户信息 + 在线设备）+ 单设备注销（写操作，二次确认），并在服务端要求图形验证码时提供**页内验证码登录**（图片 + 输入 + 提交 + 换一张，失败自动换图），登录成功后自动重载数据。技术路径：在既有分层内做**加法式扩展**（HttpClient 增原始字节获取与带头表单 POST、CryptoUtils 增 RSA 公钥加密、CampusDataService 增"漫游返回 HTML"变体），新增一个校园网服务承载解析与登录流程，页面改造为真实/演示双模式 + 验证码态；会话失效沿用既有"两层恢复"。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `HttpClient`（RCP 封装）、`TsinghuaAuthService.withSessionRecovery`、`CampusDataService.getWebvpnCsrf` / 漫游能力、`@kit.CryptoArchitectureKit`（RSA/MD5/SHA，项目已用该 Kit）；无新增三方依赖
**State Management**: 沿用项目现有 **State Management V1**（`@Component` + `@State`），不做 V2 迁移
**Storage**: N/A（验证码与登录态均为内存态，不持久化）
**Testing**: `arkts_check` 静态检查 + `devecocli build` + 模拟器 UI 验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 打开页面 3s 内呈现数据；验证码态 ≤3s 出现；提交正确验证码后 5s 内出数据（SC-001/006）
**Constraints**: 演示模式零网络请求（SC-004）；异常 100% 可读中文错误（SC-005）；验证码失败 100% 自动换图（SC-007）；ArkTS 严格模式（禁 any/未类型化字面量/解构）
**Scale/Scope**: 新增 1 服务文件；改造 1 页面；**加法式**扩展 3 个共享文件（HttpClient / CryptoUtils / CampusDataService）；实体 4 个（余额/账户/设备/验证码登录表单）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/campus/campus-network/
├── spec.md              # Phase 1 产出（含修订记录）
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/
│   ├── HttpClient.ets                         # 扩展（加法）：getBytes(url) 取原始字节；postFormWithHeaders(url, form, headers)
│   ├── auth/
│   │   ├── TsinghuaAuthService.ets            # 复用：withSessionRecovery<T>(op, onReroam?, label)
│   │   └── SessionManager.ets                 # 改造：新增 getNetworkService()（已实现，保持）
│   └── campus/
│       ├── CampusDataService.ets              # 扩展（加法）：roamByYyfwidHtml(yyfwid) 返回漫游页 HTML（取账号名用）
│       ├── CampusCardService.ets              # 参考：服务结构与恢复范式
│       └── CampusNetworkService.ets           # 改造：新增验证码获取 + 验证码登录（快照/注销已实现）
├── utils/
│   └── CryptoUtils.ets                        # 扩展（加法）：rsaEncryptPkcs1(plain, publicKeyPem) → base64
└── pages/
    └── campus/
        └── NetworkPage.ets                    # 改造：新增页内验证码登录区块与状态
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。校园特性已在 `services/campus/` 与 `pages/campus/` 落地；本增量在同一约定内扩展：新能力落在新建的 `CampusNetworkService`，跨特性可复用的底层能力（原始字节获取、带自定义头 POST、RSA 公钥加密、漫游返回 HTML）落回既有共享文件，且全部为**新增方法**，不改动既有调用点（风险最小化）。不新增目录、不新增依赖、不新增资源。

## Complexity Tracking

> 无 Constitution 违背项。对 3 个共享文件的修改为"新增方法、不改既有签名"，属最小必要改动。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 修改 3 个共享文件（HttpClient/CryptoUtils/CampusDataService） | 验证码图片需原始字节、登录需带自定义头的表单 POST、密码需 RSA 公钥加密、账号名需漫游页 HTML——均为跨特性可复用能力，放在服务层最合适 | 在 `CampusNetworkService` 内自建私有 RCP/加密/漫游实现：与既有封装重复，且会绕过统一的 Cookie/重定向/字符集处理 |

## Research & Decisions

**Decision 1 — 会话失效恢复策略**
- **Decision**: 复用同一 WebVPN 会话；每次操作前先经"会话探测"（请求网络登录入口页，命中 WebVPN 登录页标记即视为失效），整体包在 `withSessionRecovery(operation, undefined, 'campus-network')` 内（默认 reroam 重漫游 info 门户，仍失败则完整重登录）。验证码专用错误短路直抛，不触发恢复。
- **Rationale**: 参考实现 `withNetworkRetry` 即"探测 + 恢复"两层；复用项目已验证的恢复链（校园卡/资讯已跑通）。
- **Alternatives considered**: 独立 `roamDefault` 漫游（仅取账号名时使用，作为登录内部步骤，不用于恢复）；仅单次重试（无法覆盖 WebVPN 会话整体失效）。

**Decision 2 — HTML 解析方式**
- **Decision**: 正则 + 轻量辅助函数（复刻参考 DOM 选择器语义：设备表、余额表、账户表、状态图标、允许设备数图标、登录表单元素）。
- **Rationale**: 项目约束禁三方解析库；既有校园卡/成绩/资讯均用正则并验证可行。
- **Alternatives considered**: ArkWeb 注入 JS 取 DOM（生命周期与复杂度成本高）。

**Decision 3 — 验证码要求的分支（修订）**
- **Decision**: 检测登录页验证码标记时抛出**专用类型错误**（`NetworkCaptchaRequiredError`，带稳定 code），页面捕获后进入**页内验证码登录态**（而非仅提示）；恢复链不对此类错误做重试。
- **Rationale**: 修订后的 FR-006/FR-010 要求页内完成验证码登录；专用错误类型保证错误分类清晰（会话失效 ≠ 需验证码）。
- **Alternatives considered**: 将其当作普通错误（无法区分"需登录"与"网络异常"，且会被恢复链误重试）。

**Decision 4 — 设备注销请求形态**
- **Decision**: 先 GET 网络首页取 CSRF（表单隐藏域），再以既有 `postForm` POST 到删除端点（端点含 id/user_mac 查询参数，百分号编码）；按成功标记判定，失败提取错误文本。
- **Rationale**: 对齐参考 `logoutNetworkDevice`；复用既有能力，无需新增。
- **Alternatives considered**: GET 删除（参考为 POST 且带 CSRF，GET 可能被拒）。

**Decision 5 — 二次确认交互**
- **Decision**: 全局 `AlertDialog.show`，含"取消 / 确认注销"；确认文案含设备权限、掩码 IP/MAC 与断网提示；进行中该行 busy 态。
- **Rationale**: 对齐 FR-004 与既有页面交互习惯。
- **Alternatives considered**: 自定义弹窗组件（文件与状态开销更大）。

**Decision 6 — 字符编码**
- **Decision**: 依赖 `HttpClient` 既有 charset 推断（响应头优先 → URL 标记回退 GBK → 严格 UTF-8 校验）。
- **Rationale**: 校园网自助页为 UTF-8 系统（实测探测响应可正常解析），无需额外标记。
- **Alternatives considered**: 强制 GBK（会对已重编码响应造成乱码）。**验证中若出现乱码**再补 URL 标记。

**Decision 7 — 验证码图片获取与展示（新增）**
- **Decision**: 新增 `HttpClient.getBytes(url)`（基于既有 RCP 会话与 Cookie 注入，取响应体原始字节），在校园网服务内转 Base64 并以 data URI 形式交给 `Image` 渲染；"换一张"通过在图片端点追加一次性随机查询参数规避缓存。
- **Rationale**: 验证码是二进制图片，既有 `get()` 返回的是按字符集解码后的文本，直接使用会损坏图片；data URI 是 ArkUI `Image` 的原生支持形态，无需落盘或额外权限。
- **Alternatives considered**: (a) 由 `Image` 直接加载网络地址——无法注入我们的手动 Cookie 会话；(b) ArkWeb 内嵌图片——需另行同步 Cookie 且耦合页面生命周期；(c) 解析为 PixelMap——需额外图片解码步骤，data URI 已足够。

**Decision 8 — 密码加密（新增）**
- **Decision**: 在 `CryptoUtils` 新增 `rsaEncryptPkcs1(plain, publicKeyPem)`：将登录页公开密钥（PEM）体部 Base64 解码为 DER，用 `createAsyKeyGenerator(...).convertKey(...)` 转为公钥对象，再以 `createCipher('RSA1024|PKCS1')` 加密并输出 Base64。
- **Rationale**: 参考实现使用 JSEncrypt 默认填充（PKCS#1 v1.5），服务端按该方式验签解密；`@kit.CryptoArchitectureKit` 已支持 RSA 与 PKCS1 填充，项目已在用该 Kit。
- **Alternatives considered**: (a) 复用 SM2（服务端公开密钥为 RSA，不可行）；(b) 自行实现 RSA 填充（重复造轮子且有安全风险）。
- **风险**: 密钥长度可能为 2048 位，需按实际长度选择算法串；实现时以"先按常见长度尝试、失败回退"或"从密钥 DER 长度推断"处理，并在报告与验证中记录。

**Decision 9 — 带自定义头的表单 POST（新增）**
- **Decision**: 在 `HttpClient` 新增 `postFormWithHeaders(url, formData, extraHeaders)`：请求体编码与既有 `postForm` 完全一致，另将 `X-CSRF-Token`、`X-Requested-With` 等头并入既有 RCP 请求头集合（复用既有手动重定向与 Cookie 逻辑）。
- **Rationale**: 参考实现的"校验用户"端点要求携带 CSRF 头与 `X-Requested-With: XMLHttpRequest`，且 Content-Type 带 charset；既有 `postForm` 无法附加。新增方法不影响既有调用点。
- **Alternatives considered**: 扩展现有 `postForm` 签名（波及既有全部调用点，回归面大）。

**Decision 10 — 登录账号名解析（新增）**
- **Decision**: 在 `CampusDataService` 新增 `roamByYyfwidHtml(yyfwid)`（复用既有漫游逻辑，返回漫游落点页 HTML；失败返回空串），校园网服务对其结果按参考正则提取邮箱账号名（信息门户用户信息页的用户信息子系统标识）。
- **Rationale**: 参考实现用 `roamDefault(用户信息 yyfwid)` 取邮箱前缀作为登录名；既有 `roamByYyfwid` 只返回布尔，未暴露 HTML，故补一个返回 HTML 的变体（既有方法保持不变）。
- **Alternatives considered**: 直接用已保存学号/账号作为登录名（用户已否决：可能不匹配服务端要求）。

**Decision 11 — 验证码失败自动换图（新增）**
- **Decision**: 提交失败或异常时，统一走"提示可读错误 + 自动刷新验证码图片 + 清空输入框"；验证码图片获取失败时同样给出可读错误与"换一张"入口。
- **Rationale**: 对齐用户确认的 UX 决策与 FR-013/SC-007；验证码一次性有效，失败后旧图必然失效，自动换图可减少用户操作。
- **Alternatives considered**: 仅提示、由用户手动"换一张"（用户已否决）。

## Data Model

**NetworkBalance（网络账户余额）**
| 字段 | 类型 | 说明 | 校验/兜底 |
|---|---|---|---|
| productName | string | 产品名 | 空 → ''（UI 显示 '—'） |
| usedBytes | string | 已用流量（原样文本） | 空 → '' |
| usedSeconds | string | 已用时长（原样文本） | 空 → '' |
| accountBalance | string | 账户余额（原样文本） | 空 → '' |
| settlementDate | string | 结算日期 | 空 → '' |

**NetworkAccountInfo（网络账户信息）**
| 字段 | 类型 | 说明 |
|---|---|---|
| username | string | 用户名（校园网账号） |
| contactEmail | string | 联系邮箱 |
| contactPhone | string | 联系电话 |
| contactLandline | string | 固定电话 |
| realName | string | 真实姓名 |
| status | string | 账户状态（首页状态图标文本） |
| userGroup | string | 用户组 |
| location | string | 所在位置 |
| allowedDevices | number | 允许在线设备数（首个数字，缺省 0） |

**NetworkDevice（在线设备）**
| 字段 | 类型 | 说明 | 校验 |
|---|---|---|---|
| key | number | 设备标识（行 data-key） | ≤0 丢弃 |
| ip4 | string | IPv4 | — |
| ip6 | string | IPv6 | — |
| loggedAt | string | 登录时间 | — |
| authPermission | string | 权限说明 | — |
| mac | string | MAC 地址 | — |

**NetworkSnapshot（快照聚合）**: `{ balance: NetworkBalance, account: NetworkAccountInfo, devices: NetworkDevice[] }`

**NetworkLogoutResult（注销结果）**: `{ ok: boolean, message: string }`

**CaptchaLoginForm（验证码登录表单，内部模型）**
| 字段 | 类型 | 说明 | 校验 |
|---|---|---|---|
| csrfToken | string | 登录页 meta 中的 CSRF 令牌（用于请求头） | 空 → 抛"缺少必要参数" |
| csrfInput | string | 登录表单隐藏域 CSRF | 空 → 抛"缺少必要参数" |
| publicKey | string | 登录页公开密钥（PEM） | 空 → 抛"缺少必要参数" |
| username | string | 账号名（邮箱前缀，漫游解析） | 空 → 抛"无法获取账号名" |
| encryptedPassword | string | RSA 加密后的密码（Base64） | 加密失败 → 抛"密码加密失败" |
| verifyCode | string | 用户输入验证码 | trim 后为空 → 抛"请输入验证码" |

**状态机（页面级，修订）**：`loading → (ok | error | captchaRequired)`；
验证码态：`captchaRequired(加载图片中) → ready(已出图) → submitting → (success → 重载 → ok | failure → 自动换图 + 提示 → ready)`；
注销：`idle → confirming → busy(key) → (ok → reload | error)`。

## Contracts & Interfaces

**服务契约（`CampusNetworkService`）**
- `getNetworkSnapshot(): Promise<NetworkSnapshot>`（已实现）——只读；探测 → 首页（余额 + 设备 + 状态）→ 账户信息 → 组装；包 `withSessionRecovery(..., 'campus-network')`。
- `logoutNetworkDevice(key: number, mac: string): Promise<NetworkLogoutResult>`（已实现）——写；探测 → 取 CSRF → `postForm` → 标记判定。
- `fetchCaptchaImage(): Promise<string>`（**新增**）——取验证码图片原始字节 → Base64 data URI；"换一张"由调用方以随机查询参数触发缓存规避（或本方法内置随机参数）。
- `loginNetworkWithCaptcha(code: string): Promise<void>`（**新增**）——解析表单参数 + 账号名 → RSA 加密密码 → 带自定义头校验用户 → 提交登录表单 → 复探测确认已登录；失败抛可读错误（含验证码错误）。
- `isNetworkCaptchaRequiredError(e: Object): boolean`（已实现）。

**共享能力契约（新增方法，均为加法）**
- `HttpClient.getBytes(url: string): Promise<Uint8Array>` —— 遍历既有会话（含 Cookie 注入与手动重定向），返回响应体原始字节。
- `HttpClient.postFormWithHeaders(url: string, formData: Record<string, string>, extraHeaders: Record<string, string>): Promise<HttpResponse>` —— 表单编码同 `postForm`，附加自定义请求头。
- `CryptoUtils.rsaEncryptPkcs1(plainText: string, publicKeyPem: string): string` —— 返回 Base64 密文（PKCS#1 v1.5）。
- `CampusDataService.roamByYyfwidHtml(yyfwid: string): Promise<string>` —— 返回漫游落点页 HTML；失败返回空串（不抛）。

**依赖契约（复用，不改）**
- `HttpClient.get` / `postForm`；`TsinghuaAuthService.withSessionRecovery`；`CampusDataService.getWebvpnCsrf`；`SessionManager.getNetworkService()`。

**UI 契约（`NetworkPage`，修订）**
- 头部：`DetailHeader` 标题"校园网络"，右侧刷新（加载中显示进度）。
- 区块顺序：余额/用量 Hero → 错误态（可重试）→ **验证码登录区块（仅验证码态显示：说明文案 + 验证码图片 + 输入框 + "提交" + "换一张"）** → 账户信息（InfoRow 组）→ 在线设备（列表 / 空态）。
- 验证码态行为：进入即自动取图；"换一张"刷新图片；"提交"期间禁用按钮并显示进行中；成功后自动重载并退出验证码态；失败时提示 + 自动换图 + 清空输入。
- 演示模式：`isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode()`；非真实模式使用内置示例，不发请求，不进入验证码态。
- 注销确认：`AlertDialog.show`（取消 / 确认注销）；成功后 toast + 重载；失败 toast 展示服务端原因；弹窗内 IP/MAC 掩码。
- 卡片布局遵循项目约定：`width('100%')` + `constraintSize({ maxWidth: '100%' })` + 左右 `margin` 16。

**外部端点契约（沿用参考服务的端点常量，经既有 WebVPN 会话访问）**
- 网络首页 / 用户信息 / 允许设备数 / 删除设备 / 验证码图片 / 校验用户 / 登录提交端点：沿用参考实现中的 token 与路径形态；端点常量集中定义于服务文件顶部。

## Changelog

| 时间 | 修改章节 | 变更与理由 |
|---|---|---|
| 2026-10-11（初版） | 全文 | 首版计划：快照 + 设备注销（FR-001～FR-009） |
| 2026-10-11（修订） | Summary / Technical Context / Project Structure / Complexity Tracking | 纳入验证码登录增量：新增 3 个共享文件加法式扩展、复杂度说明 |
| 2026-10-11（修订） | Research & Decisions | 修订 Decision 3（验证码改为页内登录）；新增 Decision 7（取图与展示）/8（RSA 加密）/9（带头表单 POST）/10（账号名解析）/11（失败自动换图） |
| 2026-10-11（修订） | Data Model | 新增 `CaptchaLoginForm` 内部模型；扩展页面状态机（验证码态） |
| 2026-10-11（修订） | Contracts & Interfaces | 新增 `fetchCaptchaImage` / `loginNetworkWithCaptcha` / `getBytes` / `postFormWithHeaders` / `rsaEncryptPkcs1` / `roamByYyfwidHtml`；修订 UI 契约（验证码区块） |
