# Implementation Plan: 选课系统服务（CourseRegService）

**Input**: Feature specification from `D:\Develop\campus_os\campus-os\harmony\specs\course-registration-service\spec.md`

## Summary

在现有校园服务架构内新增 `CourseRegService`，复用 `SessionManager` / `TsinghuaAuthService` 的登录态、`HttpClient` 的 Cookie/重定向/GBK 解码能力，提供学期列表、已选课程、课余量搜索、选课、退课五类能力。服务通过 `SessionManager.getCourseRegService()` 单例暴露，错误统一为“错误码 + i18n key + 可重试标志”，日志只记录非敏感阶段信息。本轮不提供 UI、不注册 AI 工具；选课/退课的真实增删测试因当前非开放时段推迟。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS，沿用 `harmony/` 现有 SDK 与构建配置）  
**Primary Dependencies**: 现有 `HttpClient`、`CookieManager`、`TsinghuaAuthService`、`SessionManager`、`utils/EncodingUtils`、`utils/I18n`、`utils/Logger`；不引入第三方 HTML 解析库  
**State Management**: N/A（纯服务层；不新增 UI 状态，不改动现有 V1/V2 状态管理）  
**Storage**: N/A（仅进程内“会话已激活”布尔标志；不持久化任何课程数据）  
**Testing**: `arkts_check` + `devecocli build`；纯解析函数 fixture 自测；真实模式只读手工验证（学期/已选/搜索）；选课/退课写入验证推迟到开放时段  
**Target Platform**: HarmonyOS 手机端（现有 CampusOS 应用）  
**Project Type**: mobile-app（既有工程增量）  
**Performance Goals**: 正常网络下三类只读接口均在 10 秒内返回；每个进程最多一次会话激活，避免重复漫游；不增加轮询或后台请求  
**Constraints**: WebVPN 会话、GBK 响应解码、表单 token 校验；日志与错误详情不得包含 token/Cookie/学号/密码；服务层不硬编码中文文案  
**Scale/Scope**: 1 个新服务、1 个领域类型文件、1 个 HTML 解析工具、1 个解析自测文件；修改 `SessionManager`、`I18n`、`Phase4SelfTest` 三个共享文件（均为加法式改动）

## Project Structure

### Documentation (this feature)

```text
D:\Develop\campus_os\campus-os\harmony\specs\course-registration-service\
├── spec.md              # 需求规格（已完成）
├── plan.md              # 本文件
└── tasks.md             # 任务拆解（下一阶段生成）
```

### Source Code (repository root)

```text
D:\Develop\campus_os\campus-os\harmony\entry\src\main\ets\
├── domain\
│   └── CourseRegTypes.ets                 # 替换现有占位类型，对齐 RN 领域模型
├── services\
│   ├── campus\
│   │   └── CourseRegService.ets           # 新增：选课系统服务
│   └── auth\
│       └── SessionManager.ets             # 修改：单例 getter + 复位登记
└── utils\
    ├── CourseRegHtml.ets                  # 新增：纯 HTML 解析函数
    ├── CourseRegSelfTest.ets              # 新增：解析 fixture 自测
    ├── Phase4SelfTest.ets                 # 修改：调用解析自测
    └── I18n.ets                           # 修改：新增 courseReg.* 文案键
```

**Structure Decision**: 沿用项目现有架构（`domain/` 类型 + `services/campus/` 服务 + `utils/` 解析工具），不引入 MVVM 目录、不迁移状态管理、不改页面层。现有 `CourseRegTypes.ets` 是未被任何代码引用的占位类型，本轮直接替换为 RN 对齐模型，不保留旧字段。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 修改 `SessionManager`（高危文件） | 需求明确要求“SessionManager 单例”；现有所有校园服务均通过该入口暴露并登记复位 | 让调用方自行 new 服务会破坏单例、Cookie 共享与退出复位约定，且 T14 需要统一入口 |
| 修改 `I18n.ets`（跨特性大文件） | 服务层禁止硬编码中文，错误必须返回可本地化 key | 把中文放回服务层违反 AGENTS.md 的新代码约定；另建翻译表会绕开既有 `I18n.t()` |
| 修改 `Phase4SelfTest.ets` | 解析逻辑需要可重复的 fixture 自测，且项目已有启动自检入口 | 不接自检则纯解析函数没有执行入口，验证会退化为人工读代码 |
| 新增 `CourseRegHtml.ets` 而非全部塞进服务 | 解析逻辑无网络依赖、可独立自测；服务文件保持会话/错误/日志职责 | 单文件会超过可维护体量，且解析回归无法独立定位 |

## Research & Decisions

### RD-01 会话激活：默认漫游优先，门户漫游兜底

- **Decision**: 每个进程首次调用前先执行“空 yyfwid 默认漫游”（`onlineAppRedirect` → `roamingurl` → 落点页）；落点命中登录页或漫游失败时，回退调用 `TsinghuaAuthService.roamIdSubsystem(INFO_PORTAL_YYFWID)`。成功后置进程内 `crSessionEnsured=true`；登录/退出复位时清除。
- **Rationale**: RN 的 `CR_ROAM_PAYLOAD` 为空串，默认漫游最接近原行为；`campus-endpoints` 技能明确提示该值需要移植确认。信息门户漫游是项目已验证的通用 WebVPN 会话建立路径，作为兜底可避免空 yyfwid 在线上失效时整个服务不可用。
- **Alternatives considered**: 只用空 yyfwid（单一失败点）；只用门户漫游（每次含完整 ID 登录，较重且偏离 RN）；不做缓存（每次请求都漫游，延迟与风控风险高）。

### RD-02 写操作不自动重试 POST

- **Decision**: 选课/退课的“取表单页 + 取 token”预检走会话恢复；真正提交的 POST 只发一次。网络异常返回 `NETWORK`（可重试标志为真，但不自动重试）；响应显示会话失效返回 `SESSION_EXPIRED`；业务拒绝返回 `REJECTED`。
- **Rationale**: `withSessionRecovery` 会对失败操作整体重跑；若包住写 POST，超时后重试可能造成重复选课/退课。预检是幂等 GET，可安全恢复；写请求必须由调用方在明确失败后决定是否重试。
- **Alternatives considered**: 与 RN 一样整体包恢复（有重复提交风险）；完全不恢复（会话刚失效时写操作必然失败，体验差）。

### RD-03 HTML 解析：正则 + 容错跳过坏行，不引入 DOM 库

- **Decision**: 新增 `CourseRegHtml.ets`，用正则解析 `<option>`、`.trr2` 行、`<td>` 单元格、`p.yeM` 分页脚注、`input[name=token]`、`showMsg("…")`，并提供 HTML 实体解码与标签剥离。缺列行跳过并计数，不中断整页解析。
- **Rationale**: 项目现状无共享 HTML 解析库，`CampusDataService` / `CampusNetworkService` / `SportsService` 均用正则；新增依赖会扩大构建与 ArkTS 兼容风险。纯函数便于 fixture 自测。
- **Alternatives considered**: 引入第三方 DOM 解析库（ArkTS 兼容与包体风险）；复用 `SM2Crypto` 的登录页提取器（只覆盖认证表单，不覆盖课程表格）。

### RD-04 错误契约：`CourseRegError` + i18n key

- **Decision**: 所有失败抛 `CourseRegError`，字段为 `code: CourseRegErrorCode`、`messageKey: string`、`retryable: boolean`、`detail: string`（已脱敏、截断）。`message` 设为错误码文本（非用户文案），调用方用 `I18n.t(messageKey)` 本地化。错误码至少覆盖：未登录、会话过期、网络、HTTP、解析、无学期、无表单 token、业务拒绝、未确认、不支持类型、参数非法、服务端异常。
- **Rationale**: 满足“失败可读 + 服务层不硬编码中文”；结构化码便于 T14 做分支与审计，`retryable` 便于 UI 决定是否展示重试。
- **Alternatives considered**: 纯 `Error('中文')`（违反新代码约定）；结果对象（与现有服务风格差异大，调用方需处处判空）。

### RD-05 GBK 与表单编码

- **Decision**: 响应解码完全复用 `HttpClient`：选课系统 token 已在 `GBK_URL_MARKERS` 中，GET/POST 响应会自动按 GBK 解码。请求体沿用 `postForm` 的 UTF-8 percent 编码（与 RN `stringifyForm` 一致）。中文课程名搜索的真实效果列入只读验证关注点；若线上返回异常，再单独评估 GBK 请求编码，不在本任务中擅自改变协议。
- **Rationale**: 响应 GBK 是明确需求且已有成熟实现；请求编码改动会影响 token/semester 等字段，风险高于收益。RN 线上行为是 UTF-8，先保持对齐。
- **Alternatives considered**: 全量改用 `gb2312PercentEncode` 手拼请求体（需新增 HttpClient 原始表单能力，且可能破坏现有字段）；只对 `p_kcm` 特殊编码（字段级分叉，难维护）。

### RD-06 现有占位类型直接替换

- **Decision**: `domain/CourseRegTypes.ets` 当前 4 个类（`CrSemester`/`SelectedCourse`/`CourseSearchParams`/`CrRemainingInfo`）无任何引用；本轮按 RN 领域模型替换，不保留 `startDate`/`endDate`/`keyword`/`department` 等占位字段。
- **Rationale**: 占位字段与真实接口不匹配，保留会误导 T14 与后续页面；无消费者意味着替换是安全的重构。
- **Alternatives considered**: 新建 `CourseRegistrationTypes.ets` 并保留旧文件（留下两套易混淆模型）；在旧类上追加字段（字段语义冲突）。

### RD-07 日志脱敏

- **Decision**: 统一 tag `CourseReg`。允许记录：操作名、学期 ID、课程号、课序号、页码、HTTP 状态、响应长度、耗时、错误码、`retryable`。禁止记录：表单 token、Cookie、学号、密码、完整表单体、完整 URL（URL 含 WebVPN token）。服务端业务消息仅在 debug 日志中截断输出，且先剥离 HTML/控制字符。
- **Rationale**: 满足验收“不记录 token/学号明文”，同时保留可诊断阶段信息。
- **Alternatives considered**: 完全不记日志（排障困难）；记录完整请求体（直接违反验收）。

### RD-08 写操作成功判定

- **Decision**: 只认服务端 `showMsg` 的明确成功文案（包含“成功”且不含否定词）为成功；明确失败词（失败/错误/不能/无法/未开放/已满/冲突/超出/重复/不存在/超时）归为 `REJECTED`；其余归为 `UNCONFIRMED`，不声称成功，由 T14 回查已选列表确认。
- **Rationale**: RN 的 AI 工具对 `deleteCourse` 无条件返回 `success:true`，存在假成功风险；本服务必须保守。
- **Alternatives considered**: 只返回原始消息由调用方判断（每个调用方重复实现且易错）；把所有非空消息都当成功（假成功）。

### RD-09 服务不判断演示模式

- **Decision**: `CourseRegService` 不读取 `SettingsManager.demoMode`；演示模式由页面/T14 在调用前短路，服务只处理真实网络。
- **Rationale**: 与 `CampusDataService` 等现有服务一致；服务层不应依赖 UI/设置状态，便于单测与复用。
- **Alternatives considered**: 服务内直接返回 mock 数据（会把演示数据混入真实结果，且 T14 难以区分）。

### RD-10 会话复位登记

- **Decision**: `CourseRegService.resetSessionState()` 只清 `crSessionEnsured`；`SessionManager.resetSessionState()` 按现有“判空 + try/catch”范式登记该服务。
- **Rationale**: 避免跨登录残留“已激活”标志；遵循 `session-reset-unification` 已建立的契约。
- **Alternatives considered**: 不复位（退出再登录后可能跳过必要的子系统漫游）。

## Data Model

### 实体与字段

| 类型 | 字段 | 约束 |
|---|---|---|
| `CrSemester` | `id: string`、`name: string` | `id` 非空，形如 `YYYY-YYYY-N`；`name` 非空 |
| `SelectedCourse` | `type: string`、`will: number`、`id: string`、`seq: string`、`name: string`、`time: string`、`teacher: string`、`credit: number`、`secondary: boolean` | `will` ∈ {1,2,3}；`secondary` 由“是/否”映射；缺列行跳过 |
| `CrRemainingInfo` | `id: string`、`seq: number`、`name: string`、`capacity: number`、`remaining: number`、`queue: number`、`teacher: string`、`time: string` | 数字字段解析失败按 0 处理；缺列行跳过 |
| `CrRemainingSearchResult` | `currPage: number`、`totalPage: number`、`totalCount: number`、`courses: CrRemainingInfo[]` | 无分页脚注时回退 `1/1/0`；列表可为空 |
| `CourseSearchParams` | `semester: string`、`page: number`（默认 1）、`id: string`、`name: string`、`dayOfWeek: number`（0=未指定）、`period: number`（0=未指定） | `semester` 非空；`page >= 1`；`dayOfWeek` 1–7；`period` 1–12 |

> 注：RN 未传 `page` 时发送 `-1`，本实现按 spec 默认 `1`；真机只读验证时对比两者响应，不在本任务中猜测改动。
| `SelectCourseParams` | `semester: string`、`priority: string`、`courseId: string`、`courseSeq: string`、`will: number` | `priority` ∈ {`bx`,`xx`,`rx`,`ty`}；`will` ∈ {1,2,3}；其余字段非空 |
| `DropCourseParams` | `semester: string`、`courseId: string`、`courseSeq: string` | 全部非空 |

### 枚举与常量

- `CourseRegPriority`：`BX='bx'`、`XX='xx'`、`RX='rx'`、`TY='ty'`；提供 `isSupported(value)` 与 `fieldKey(priority)` 映射（`bx→bxk`、`xx→xxk`、`rx→rx`、`ty→rxTy`，与 RN 一致）。
- 志愿（will）：仅允许 1/2/3 数值；已选课程解析时文本映射“第一志愿→1、第二志愿→2、其他→3”（`willStringToNumber`），不单独定义 `CourseRegWill` 类型。
- `CourseRegErrorCode`：`NOT_LOGGED_IN`、`SESSION_EXPIRED`、`NETWORK`、`HTTP`、`PARSE`、`NO_SEMESTER`、`NO_FORM_TOKEN`、`REJECTED`、`UNCONFIRMED`、`UNSUPPORTED_PRIORITY`、`INVALID_PARAM`、`SERVER`。
- `CourseRegI18n`：错误码到 i18n key 的静态映射常量。

### 状态转换（写操作）

| 起点 | 事件 | 终点 | 说明 |
|---|---|---|---|
| 空闲 | 参数不合法 | 参数错误 | 不发起网络请求 |
| 空闲 | 预检 GET 失败 | 会话/网络/HTTP/解析错误 | 预检可安全重试 |
| 预检成功 | 缺少 token | `NO_FORM_TOKEN` | 不提交 POST |
| 预检成功 | POST 网络失败 | `NETWORK` | 不自动重试，避免重复提交 |
| 预检成功 | 响应为 WebVPN/ID 登录页 | `NOT_LOGGED_IN` | 不自动重试 POST；明确超时文案才归 `SESSION_EXPIRED` |
| 预检成功 | `showMsg` 明确成功 | 成功 | 返回服务端消息 |
| 预检成功 | `showMsg` 明确失败 | `REJECTED` | `retryable=false` |
| 预检成功 | `showMsg` 语义不明 | `UNCONFIRMED` | 调用方必须回查已选列表 |

## Contracts & Interfaces

### 服务公开接口

```text
CourseRegService
  constructor(http: HttpClient, auth: TsinghuaAuthService)
  getAvailableSemesters(): Promise<CrSemester[]>
  getSelectedCourses(semesterId: string): Promise<SelectedCourse[]>
  searchRemaining(params: CourseSearchParams): Promise<CrRemainingSearchResult>
  selectCourse(params: SelectCourseParams): Promise<string>
  dropCourse(params: DropCourseParams): Promise<string>
  resetSessionState(): void
```

约定：

- 所有失败抛 `CourseRegError`；成功返回数据或服务端成功消息。
- `getSelectedCourses` 的空学期返回 `[]`，不抛错。
- `selectCourse` / `dropCourse` 仅在明确成功时返回消息；业务拒绝与未确认均抛错。
- `resetSessionState()` 无参、同步、幂等、不抛。

### 单例入口

```text
SessionManager
  static getCourseRegService(): CourseRegService
```

- 构造依赖：`SessionManager.getAuthService().getHttpClient()` 与 `SessionManager.getAuthService()`。
- 在 `resetSessionState()` 中按现有范式登记：判空 + try/catch。

### 错误契约

```text
CourseRegError extends Error
  code: CourseRegErrorCode
  messageKey: string
  retryable: boolean
  detail: string        // 已剥离 HTML、控制字符并截断；不含 token/Cookie/学号/密码
```

### i18n 键目录

| key | 中文 | English |
|---|---|---|
| `courseReg.error.notLoggedIn` | 需要登录后才能访问选课系统 | Please sign in to access course registration |
| `courseReg.error.sessionExpired` | 选课系统会话已失效，请重新登录 | Your course registration session has expired |
| `courseReg.error.network` | 网络请求失败，请检查网络后重试 | Network request failed. Please try again |
| `courseReg.error.http` | 选课系统返回异常状态 | The course registration service returned an error |
| `courseReg.error.parse` | 选课系统响应格式异常 | Unexpected course registration response |
| `courseReg.error.noSemester` | 未找到可用学期 | No available semester was found |
| `courseReg.error.noFormToken` | 选课表单缺少令牌，请重新登录后重试 | The form token is missing. Please sign in again |
| `courseReg.error.rejected` | 选课系统拒绝了本次操作 | The course registration request was rejected |
| `courseReg.error.unconfirmed` | 选课系统未返回明确结果，请回查已选课程 | The result is unconfirmed. Please check your selected courses |
| `courseReg.error.unsupportedPriority` | 不支持的选课类型 | Unsupported course selection type |
| `courseReg.error.invalidParam` | 请求参数不完整或不合法 | Invalid request parameters |
| `courseReg.error.server` | 选课系统暂时不可用 | The course registration service is unavailable |

### HTML 解析契约（`CourseRegHtml.ets`）

| 函数 | 输入 | 输出 | 规则 |
|---|---|---|---|
| `parseSemesters(mainHtml, treeHtml)` | 主页面 + 学期树页面 | `CrSemester[]` | 主页面提取基础学期；树页面提取 `<option value>`；空 ID 或空名称丢弃 |
| `parseRemainingPage(html)` | 搜索结果页 | `RemainingParseResult { result, skipped, recognized }` | `p.yeM` 分页；`.trr2` 行；`<td>` ≥ 6；≥8 列时插队列列；6 列行 `time` 安全回退空串；坏行计入 `skipped`；未命中预期结构时 `recognized=false` |
| `parseSelectedPage(html)` | 已选课程页 | `SelectedParseResult { courses, skipped, recognized }` | `.trr2` / `.tdd2` 行；<9 列跳过并计入 `skipped`；`will` 文本映射；`secondary` 按“是”；未命中预期结构时 `recognized=false` |
| `parseRemaining(html)` / `parseSelected(html)` | 同上 | `CrRemainingSearchResult` / `SelectedCourse[]` | 兼容薄包装，供不关心 `recognized`/`skipped` 的调用方使用 |
| `isSelectedPage(html)` / `isRemainingPage(html)` | 任意响应 | `boolean` | 强标记：已选页要求 `trr2` / `yxSearchTab` / `tokenPriFlag`；搜索页要求 `yeM` / `trr2`；`pathContent`、`课余量`、`name=token` 仅作辅助 |
| `extractFormToken(html)` | 表单页 | `string` | 查找 `input[name=token]` 的 `value`，属性顺序无关 |
| `extractShowMsg(html)` | 写操作响应 | `string` | 匹配 `showMsg("…")`；缺失返回空串 |
| `isLoginPage(html)` | 任意响应 | `boolean` | 命中 WebVPN 标题、`sm2publicKey`（宽松）或“用户登陆超时或访问内容不存在” |
| `redactSensitive(text)` | 任意文本 | `string` | URL → `<url>`；token/XSRF → `<redacted>`；32+ hex → `<token>`；10 位数字 → `<id>`（安全优先） |
| `stripHtml` / `decodeHtmlEntities` | HTML 片段 | 纯文本 | 去标签、解码常见实体、压缩空白 |

### 外部端点常量

- 选课系统端点、WebVPN token、信息门户 token 均从 RN `src/services/campus/courseRegistration.ts` 与 `src/services/webvpn/transport.ts` 原样移植，不在本计划中新增或猜测 URL。
- 默认漫游复用 RN `webvpnTransport.roamDefault('')` 的流程；门户兜底使用 `INFO_PORTAL_YYFWID`。
- 所有业务 URL 必须包含 `cr_xk` token，确保 `HttpClient` 的 GBK 判定生效。

### 验证契约

1. **静态**：`arkts_check` 0 error；`devecocli build` 成功。
2. **解析自测**：`CourseRegSelfTest` 覆盖学期选项、分页脚注、剩余课程行（含/不含队列列、6 列边界）、已选课程行、token 提取（两种属性顺序）、`showMsg`、登录页判定、页面识别（错误页 vs 合法空页）、坏行计数、优先级/表单字段映射、URL 包装与脱敏；由 `Phase4SelfTest` 启动时调用。
3. **真实只读**：登录后依次验证学期列表、已选课程（含空学期）、按学期搜索、按课程号搜索、分页；记录响应耗时与错误码。
4. **写操作**：当前非选课开放时段，不执行真实选课/退课；记录为“实现完成、待开放时段验证”，并保留受控步骤：指定可安全退选的课程 → 选课 → 回查已选 → 退课 → 再回查。
5. **日志**：抽查 `CourseReg` 日志，确认无 token/Cookie/学号/密码/完整 URL。
6. **高危文件回归**：修改 `SessionManager` 后按 `tsinghua-auth` 技能清单检查冷启动自动登录、重登录后 learn 数据、退出复位。
