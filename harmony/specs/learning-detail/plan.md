# Implementation Plan: 学习详情深链

**Input**: Feature specification from `harmony/specs/learning-detail/spec.md`

## Summary

在既有 Harmony 分层（pages → state/services → storage）内补齐学习模块的下钻能力：

1. 扩展学习数据模型，让通知/资料携带课程归属，从而支持课程详情在内存中聚合三类数据；本地缺失时按课程补拉一次。
2. 通知详情优先使用同步时已解码的正文，空正文时按课程重拉通知列表并按 id 匹配，补拉失败保留元信息并可重试。
3. 资料详情接入两条真实链路：内嵌 WebView 预览（先同步 learn 域 Cookie + 桌面 UA）、下载到应用私有目录并用系统预览能力打开；下载态与已下载态可跨重启识别（按确定性路径判断）。
4. 把手动 DDL 的持久化从 `AgentWriteTools` 私有实现抽成共享 `ManualDeadlineStore`，学习页新增/删除、首页最近 DDL、AI 写工具统一读写同一份数据，变更通过订阅即时广播。
5. 演示模式补齐课程/作业/通知/资料的原始样例，详情页在演示模式下只读本地数据、零网络请求。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS 6.1.1 / API 24，`compatibleSdkVersion` 24）  
**Primary Dependencies**: 既有 `HttpClient` / `CookieManager` / `SessionManager` / `CampusDataService` / `PreferencesStorage`；系统能力 `@kit.ArkWeb`（Web、WebCookieManager）、`@kit.CoreFileKit`（fileIo、fileUri）、`@kit.PreviewKit`（filePreview）、`@kit.ArkData`（preferences）  
**State Management**: 沿用项目现有 ArkUI 状态管理 V1（`@State` / `@Prop` / `@StorageLink` / `@Watch`），不引入 V2、不做 MVVM 迁移  
**Storage**: Preferences（`@campusos/manual_deadlines`，JSON 数组）；应用私有目录 `filesDir/learn_downloads/`（下载文件）  
**Testing**: `devecocli build` + `arkts_check` + `check lint`；模拟器按 user story 做 UI 验证；无单元测试框架  
**Target Platform**: HarmonyOS 手机（竖屏为主，兼容平板）  
**Project Type**: 移动应用（单 entry 模块）  
**Performance Goals**: 本地已有数据时详情首屏 < 1s；课程详情补拉并发执行且不阻塞基础信息渲染；下载 50MB 内文件可接受一次性读入内存  
**Constraints**: 演示模式学习链路零网络请求；下载不申请外部存储权限；新增可见文案必须中英双语；不记录 Cookie/学号明文  
**Scale/Scope**: 单学期约 10–20 门课；每课最多 200 个资料；4 个学习标签 + 4 个详情页

## Project Structure

### Documentation (this feature)

```text
D:\Develop\campus_os\campus-os\harmony\specs\learning-detail\
├── spec.md              # 需求规格（已确认）
├── plan.md              # 本文件
├── tasks.md             # Phase 3 产出
└── feature.json         # feature 目录记录
```

### Source Code (repository root)

项目根：`D:\Develop\campus_os\campus-os\harmony`

```text
entry/src/main/ets/
├── pages/
│   ├── LearningPage.ets                  # 修改：手动 DDL 合并/增删、嵌套详情返回、详情入参
│   ├── HomePage.ets                      # 修改：最近 DDL 合并手动项、订阅变更
│   ├── LearningData.ets                  # 修改：HomeworkItem 增 id/manual/note；补齐演示原始数据
│   └── learning/
│       ├── CourseDetailPage.ets          # 修改：三类聚合 + 补拉 + 嵌套下钻
│       ├── NotificationDetailPage.ets    # 修改：正文补拉/失败重试/课程上下文
│       ├── FileDetailPage.ets            # 修改：预览、下载、已下载、打开
│       └── WebViewerPage.ets             # 修改：Cookie 同步、UA、进度与错误态
├── state/
│   └── ManualDeadlineStore.ets           # 新增：手动 DDL 共享读写 + 变更订阅
├── services/
│   ├── campus/
│   │   └── CampusDataService.ets         # 修改：通知/资料课程归属、learn Cookie 同步、下载字节
│   ├── ai/
│   │   └── AgentWriteTools.ets           # 修改：DDL 存储委托给 ManualDeadlineStore
│   └── learning/
│       └── LearningFileStore.ets         # 新增：下载路径/落盘/已下载判断/系统打开
└── utils/
    ├── I18n.ets                          # 修改：新增详情/下载/DDL 文案
    └── DeadlineFormat.ets                # 新增：DDL 时间拼装/解析/排序（从 HomePage 抽出）
```

**Structure Decision**: 沿用项目现有架构（`pages` / `state` / `services` / `storage` / `components`），继续使用 ArkUI 状态管理 V1；不新建 MVVM 目录、不改动既有目录职责。新增文件只有 3 个（共享 DDL store、文件落盘服务、DDL 时间工具），其余均为在既有文件内扩展，符合“最小可行拆分”。

## Complexity Tracking

无架构违规项。本特性不改变分层，不新增依赖框架，不引入第二套状态管理。

## Research & Decisions

### R1. 课程详情的三类数据来源

- **Decision**: 优先使用 `LearningPage` 已加载的作业/通知/资料，按 `courseId` 过滤后传入 `CourseDetailPage`；当三类同时为空且处于真实模式时，详情页按该课程补拉一次（作业/通知/资料并发）。
- **Rationale**: 与 RN 的“纯快照聚合”一致，正常情况下零额外请求；同时解决冷启动/外部入口进入时快照为空导致详情永久空白的问题。
- **Alternatives considered**: 仅内存过滤（快照失败时详情不可用）；每次进入都实时拉取（首屏等待、请求量翻倍）。

### R2. 通知正文的获取

- **Decision**: `CampusNotification.content` 继续在 `fetchNotifications` 阶段由 `ggnr` Base64 解码 + `stripHtml` 得到；详情页直接展示。仅当正文为空时，用该通知的 `courseId` 构造课程上下文重拉一次通知列表并按 `id` 匹配。失败展示可重试提示，不回写已读。
- **Rationale**: 不新增服务端契约；正文在列表接口中已完整返回；补拉只在异常路径发生。
- **Alternatives considered**: 每次进详情必拉（多余请求）；只读内联正文（正文缺失时无法恢复）。

### R3. 文件下载

- **Decision**: 通过 `CampusDataService` 暴露 `downloadFileBytes(url)`，内部复用 `HttpClient.getBytes`（自动带 Cookie、手动跟随重定向）；字节写入应用私有目录 `filesDir/learn_downloads/`。文件名使用确定性规则（文件标识 + 清洗后的标题），据此判断“已下载”，无需额外索引。
- **Rationale**: 复用已验证的会话与重定向逻辑；私有目录免权限、跨重启稳定；确定性路径避免维护下载索引与迁移。
- **Alternatives considered**: 系统下载管理器（无法注入 Cookie，易落到登录页）；用户选择目录（引入 picker 与权限/失败分支）；内存缓存（重启丢失）。

### R4. 文件预览

- **Decision**: 在 `WebViewerPage` 中加载 `CampusFile.previewUrl`；加载前把 learn 域与 id 域 Cookie 同步到 ArkWeb，并设置桌面 Chrome UA；增加进度条与加载失败提示。演示模式不打开该页。
- **Rationale**: 与 RN 的 `InAppViewer` 行为对齐；服务端预览页对 UA 与 Cookie 敏感，必须先注入再加载。
- **Alternatives considered**: 直接把预览 URL 交给系统浏览器（会话不保证）；在应用内自行解析 Office/PDF（成本与风险过高）。

### R5. 下载文件的再次打开

- **Decision**: 优先调用系统文件预览能力（`@kit.PreviewKit` 的 `filePreview.openPreview`，URI 由 `@kit.CoreFileKit` 的 `fileUri.getUriFromPath` 生成）；能力不可用或预览失败时回退到 `startAbility` 的 `viewData` 动作。演示/失败场景给出可读提示。
- **Rationale**: 系统预览覆盖 PDF/Office/图片等常见课程资料；回退路径保证非 HMS 环境仍可尝试打开。
- **Alternatives considered**: 仅 `startAbility`（部分设备无默认处理应用）；仅应用内 WebView（无法读本地 Office 文件）。

### R6. 手动 DDL 的存储与共享

- **Decision**: 新建 `state/ManualDeadlineStore.ets`，承接 `AgentWriteTools` 现有的读写、缓存、排序与 id 定位逻辑；`AgentWriteTools` 改为委托调用，保留其对外 `listManualDeadlines()`。学习页与首页通过 store 读取，并订阅变更（监听器列表）以在 AI 写入/页面增删后即时刷新。
- **Rationale**: 消除两套数据源；沿用既有 `ManualDeadline` 字段与 `@campusos/manual_deadlines` JSON 格式，无迁移；订阅机制不依赖页面重新挂载，适配 Tabs 常驻页面。
- **Alternatives considered**: 保留 `AgentWriteTools` 私有实现并让页面直接调用（服务层职责倒置、缓存分裂）；AppStorage 版本号轮询（隐式且难追踪）。

### R7. 详情页导航与返回

- **Decision**: 继续使用 `LearningPage.subScreen` 的组件内切换；新增 `detailParent` 记录来源页。课程详情内点击条目时设置 `detailParent='course'` 并切到对应详情，返回时回到课程详情；系统返回键复用 `BackDispatcher`。
- **Rationale**: 与现有学习子页模式一致，不引入路由框架；嵌套返回语义明确。
- **Alternatives considered**: 引入 `Navigation`/`NavPathStack`（大范围重构，超出本特性）；退回列表再进入课程（体验断裂）。

### R8. 演示模式数据

- **Decision**: 在 `LearningData.ets` 中补齐演示用的原始对象（课程/作业/通知/资料），学习页在演示模式下同时填充 UI 列表与原始对象数组，保证按索引下钻可用；演示文件提供标题/类型/大小/说明，但不提供可请求的预览/下载地址。
- **Rationale**: 复用现有按索引传对象的机制，改动面最小；资料详情可完整展示，按钮走演示态提示。
- **Alternatives considered**: 详情页内各自硬编码演示数据（重复且不一致）；保持文件列表为空（验收链路不完整）。

### R9. 富文本与安全

- **Decision**: 通知正文继续以纯文本展示（服务层已 `stripHtml`），不引入 HTML 渲染；下载内容若首字节呈 HTML 文档特征（登录页/错误页）则判定为失败，不落盘；文件名按文件系统非法字符清洗并限长。
- **Rationale**: 满足“正文不执行脚本、不加载外部资源”；避免把登录页当成资料保存；避免非法文件名导致写入失败。
- **Alternatives considered**: WebView 渲染通知 HTML（脚本/外链风险与高度适配成本）；不校验内容类型（产生损坏文件）。

### R10. 下载态与失败语义

- **Decision**: 资料详情维护 `idle / downloading / done / failed` 四态；`done` 在进入页面时通过确定性路径探测；失败保留错误文案与重试按钮；重新下载先写临时文件再原子替换，避免半截文件。
- **Rationale**: 明确的状态机便于 UI 与验证；临时文件 + 替换避免损坏已有文件。
- **Alternatives considered**: 直接覆盖目标文件（中断即损坏）；仅内存标记已下载（重启丢失）。

## Data Model

### 既有模型扩展

| 模型 | 位置 | 变更 | 说明 |
|---|---|---|---|
| `CampusNotification` | `services/campus/CampusDataService.ets` | 新增 `courseId: string`、`courseName: string` | 课程详情聚合与正文补拉的必要外键；由 `fetchNotifications` 的课程循环写入 |
| `CampusFile` | `services/campus/CampusDataService.ets` | 新增 `courseId: string` | 课程详情聚合外键；`courseName` 已存在 |
| `HomeworkItem` | `pages/LearningData.ets` | 新增 `id: string`、`manual: boolean`、`note: string` | 作业列表合并手动 DDL 后区分来源、定位删除；远程项 `manual=false` |

### 复用模型

| 模型 | 位置 | 用途 |
|---|---|---|
| `CampusCourse` | `CampusDataService.ets` | 课程详情基础信息与补拉上下文 |
| `CampusHomework` | `CampusDataService.ets` | 作业分组与作业详情入口 |
| `ManualDeadline` | `domain/DeadlineTypes.ets` | 手动 DDL 持久化模型（`id/title/date/time/course/note/createdAt`） |

### 新增状态模型

| 名称 | 位置 | 字段/取值 | 说明 |
|---|---|---|---|
| `ManualDeadlineStore` | `state/ManualDeadlineStore.ets` | 静态缓存 + 监听器表 | 对外提供加载、列表、追加、删除、查找、订阅 |
| 下载状态 | `FileDetailPage.ets` | `idle` / `downloading` / `done` / `failed` | 仅页面内状态，不持久化 |
| 详情来源 | `LearningPage.ets` | `detailParent: '' \| 'course'` | 控制嵌套详情的返回目标 |

### 持久化格式（不迁移）

- Key：`@campusos/manual_deadlines`（`StorageKeys.MANUAL_DEADLINES`）
- 值：`ManualDeadline[]` 的 JSON 字符串；字段与顺序保持现状。
- 下载文件：`filesDir/learn_downloads/learn_dl_<fileId|id>_<清洗标题>`；临时文件同目录 `*.part`，成功后替换。
- 不新增 Preferences key；下载索引由文件系统探测替代。

### 校验与排序规则

- 手动 DDL：标题 `trim` 后非空；日期 `YYYY-MM-DD`；时间 `HH:mm`（1–2 位小时归一为 2 位）；允许过期时间。
- 合并排序：远程未提交作业与手动 DDL 统一转毫秒后升序；无法解析的时间排最后。
- 课程详情分组：按 `courseId` 精确匹配；作业保留原顺序，通知按发布时间倒序，资料保留接口顺序，均不截断。

## Contracts & Interfaces

### 服务层

| 接口 | 签名 | 约束 |
|---|---|---|
| `CampusDataService.syncLearnCookiesForWebView` | `(): void` | 读取 learn 域 Cookie header，按 `name=value` 逐条写入 ArkWeb；异常仅记录日志，不抛出 |
| `CampusDataService.downloadFileBytes` | `(url: string): Promise<Uint8Array>` | 复用 `HttpClient.getBytes`；空 URL / 网络异常抛出可读错误 |
| `ManualDeadlineStore.load` | `(): Promise<void>` | 幂等；解析失败回退空数组 |
| `ManualDeadlineStore.list` | `(): ManualDeadline[]` | 返回副本，按 `date + time` 升序 |
| `ManualDeadlineStore.append` | `(title, date, time, course, note): Promise<ManualDeadline \| undefined>` | 生成 `md-` 前缀 id 与 `createdAt`；写后广播；失败返回 `undefined` |
| `ManualDeadlineStore.remove` | `(id: string): Promise<boolean>` | 不存在返回 `false`；成功写后广播 |
| `ManualDeadlineStore.find` | `(key: string): ManualDeadline \| undefined` | id 精确 → 标题全等 → 标题包含 |
| `ManualDeadlineStore.subscribe` | `(listener: () => void): number` | 返回订阅 id；页面在 `aboutToDisappear` 取消 |
| `LearningFileStore.localPath` | `(context, file): string` | 确定性路径；清洗非法字符；限长 80 |

### 页面契约（ArkUI V1）

| 组件 | 入参 | 行为 |
|---|---|---|
| `CourseDetailPage` | `course`、`semester`、`homework[]`、`notifications[]`、`files[]`、`demoMode`、`onOpenHomework/onOpenNotification/onOpenFile`、`onBack` | 本地优先渲染；三类全空且非演示时补拉；分组空态；嵌套下钻 |
| `NotificationDetailPage` | `item`、`demoMode`、`onBack` | 正文非空直接渲染；空则补拉并匹配；失败可重试 |
| `FileDetailPage` | `item`、`demoMode`、`onPreview(url, title)`、`onBack` | 预览走 WebViewer；下载四态；已下载可打开 |
| `WebViewerPage` | `url`、`title`、`onBack` | 加载前同步 Cookie + 桌面 UA；进度与失败态 |
| `LearningPage` | 无外部入参 | 合并手动 DDL；新增/删除；嵌套详情返回；订阅 store 变更 |
| `HomePage` | 无外部入参 | 最近 DDL 合并手动项；订阅 store 变更；演示模式同样合并 |

### 文案（i18n）

新增 key 统一放 `utils/I18n.ets` 的既有字典，zh/en 成对：

- 课程详情：分组标题（作业/通知/资料）、分组空态、课程不存在、补拉失败与重试。
- 通知详情：发布人、发布时间、加载中、失败与重试。
- 资料详情：预览、下载中、已下载、打开、下载成功（含文件名）、下载失败、预览失败、演示模式不可用。
- 手动 DDL：来源徽标、删除、删除确认（含标题参数）、已过期。

### 复用而非新增的外部接口

- 课程/作业/通知/资料列表端点、作业详情端点均复用 `CampusDataService` 现有实现，不新增服务端接口。
- 文件预览使用 `CampusFile.previewUrl`，下载使用 `CampusFile.downloadUrl`；不拼接新地址。
- 会话与编码：learn 域为 UTF-8；通知正文按 UTF-8 解码；不套用教务/电费类 GBK 分支。
