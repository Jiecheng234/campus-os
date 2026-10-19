# RN → HarmonyOS 功能同步进度

- **RN 基线**：v2.1.1（`src/` + `android/`），上游 `a2dbb9f`（2026-07-11）后冻结。
- **Harmony 代码基线**：`11af855`（2026-10-19），18 个 SDD feature，任务 **328 / 328**。
- **最后更新**：2026-10-19

> 本文件记录**功能层**同步进度；SDD 任务层进度见 `harmony/specs/INDEX.md`，
> 上游仓库同步见 `docs/UPSTREAM-SYNC.md`，实现细节与已知限制见 `harmony/DEVELOPMENT.md`。

---

## 1. 口径

- 原项目是 **React Native Android-only** 应用。`android/` 是 RN 宿主 + 原生模块
  （通知、WorkManager/Headless、IMAP/SMTP 邮件），不是独立的原生 Android UI 工程。
- 鸿蒙版是**纯 ArkTS 原生重写**，不是 RN 运行时；`harmony/` 对 `src/` 的跨端 import 为 0。
- 状态定义：

| 状态 | 含义 |
|---|---|
| ✅ 已对齐 | 主要用户流程与 RN 等价；允许实现方式不同（如邮箱 HTTP vs IMAP） |
| 🟡 部分对齐 | 主流程可用，但缺少 RN 的某些字段、动作或页面 |
| ⛔ 未迁移 | RN 用户可见，Harmony 无对应实现 |
| ➖ 不适用 | RN 本身未暴露、占位，或双方都未完成 |

> **任务完成 ≠ 功能同步。** `328/328` 表示各 feature 的规格内任务已闭环，
> 不代表与原 RN 功能完全等价。本文件以源码行为为准，不以 `tasks.md` 复选框替代功能验收。

---

## 2. 总览

| 指标 | RN v2.1.1 | Harmony `11af855` |
|---|---:|---:|
| 底部 Tab | 6 | 6 |
| 登录后页面 / 子页面 | 6 Tab + 29 Stack 页面 | 6 Tab + 18 feature 目录 |
| AI function-calling 工具 | 49 已注册 / 51 已定义 | 45（35 只读 + 10 可逆写） |
| 校园子系统 | 9 个入口 | 9 个入口，均有页面 |
| 发布状态 | Android debug keystore | `harmony-v0.1.0`，debug 签名 |

**功能同步粗估：约 80%。**
其中核心只读查询链路约 95%；支付/充值、后台监控、高风险写操作约 30–40%。
该比例是人工估算，仅用于排优先级，不作为验收指标。

---

## 3. 功能矩阵

### 3.1 框架 / 认证 / 设置

| 功能 | RN 基线 | Harmony 现状 | 状态 |
|---|---|---|---|
| 6 Tab + 登录门控 + 跨页导航 | Bottom Tabs + Native Stack | `Index.ets` Tabs + `UiEvents` + `BackDispatcher` | ✅ |
| 统一认证 / 2FA / SM2 | WebVPN→OAuth→ID、短信/微信/TOTP | 同链路，`TsinghuaAuthService` + `SessionManager` | ✅ |
| 自动登录 / 凭证恢复 | Keychain + Preferences | Asset Store Kit + `SettingsManager` | ✅ |
| 信任设备 | 服务端指纹白名单（`saveFinger`） | 本机凭证落盘门控 + 退出/启动清理（Harmony 新增语义） | ✅ |
| Cookie 持久化 | 原生 Cookie Jar + AsyncStorage | 手动 Cookie 池，仅内存态；冷启动靠自动登录恢复 | 🟡 |
| 中英 i18n | 自建 i18n | `I18n.ets` + batch1/batch2，高频页与校园/学习子页已迁移 | ✅ |
| 演示模式 | 有 | 有，零真实请求 | ✅ |
| 设置页 | Provider/语言/信任/监控/审计/缓存/退出 | Provider/语言/信任/清理/退出/版本；AI 记忆/审计/监控入口仍为禁用态 | 🟡 |
| 发布签名 | debug keystore，不可上架 | debug 签名，不可上架 | 🟡 |

### 3.2 首页 / 学习 / 日程

| 功能 | RN 基线 | Harmony 现状 | 状态 |
|---|---|---|---|
| 首页工作台 | 今日课、DDL、未读、天气、同步、AI 建议 | 同结构；`HomePage` + `CampusDataService` + `WeatherService` | ✅ |
| 天气详情 | 独立 `WeatherDetail` 页 | 仅首页天气副标题，无详情页 | ⛔ |
| 课程列表 | 课程/教师/课号 | `LearningPage` 真实列表 | ✅ |
| 课程详情聚合 | 课程下作业/通知/资料 | 仅课程基本信息 | 🟡 |
| 作业列表/详情 | 状态、截止、详情、附件 | 列表 + 详情拉取；附件下载未接 | 🟡 |
| 通知列表/详情 | 未读、发布人、HTML 正文 | 列表 + 列表传入正文；无独立正文抓取/HTML 渲染 | 🟡 |
| 资料列表/详情 | 下载/外部打开/WebView 预览 | 列表 + 元信息；下载按钮无动作 | 🟡 |
| 手动 DDL | 持久化增删 | 新增只改内存，不持久化/不同步 | 🟡 |
| 课表周视图 | 周网格、学期、周切换 | 同能力，真实教务数据 | ✅ |
| 课表交互增强 | 块状课表、课程详情、时间线、配色 | `schedule-visual` + `schedule-interaction` | ✅ |
| 个人日程 | 新增/删除、日程页展示 | `ScheduleManager` 仅内存且无 UI；AI 写工具直写 Preferences | ⛔ |
| App 内 WebView | PDF/Office/图片/文本预览 | 基础 `WebViewerPage` 容器，未接文件下载 | 🟡 |

### 3.3 校园子系统

| 功能 | RN 基线 | Harmony 现状 | 状态 |
|---|---|---|---|
| 新闻列表/搜索/详情 | 7 频道、搜索、分页、HTML 详情 | `NewsPage` 真实列表/详情 | ✅ |
| 新闻收藏/订阅 | 服务层实现，UI 未调用 | 未实现 | ➖ |
| 空教室查询 | 教学楼/周次/节次占用 | `ClassroomPage` 真实查询 | ✅ |
| 成绩/GPA | 本科/研究生切换、学期分组 | 本科路径完整；无研究生切换 | 🟡 |
| 体测 | 汇总/单项/参考分 | 真实接口；上游 JSONP 缺陷待复验 | ✅ |
| 电费查询 | 余额/房间/记录 | `DormitoryPage` 真实查询 | ✅ |
| 电费充值 | 支付宝 payCode + 网页兜底 | 明确不迁移，按钮仅提示 | ⛔ |
| 洗衣房 | 洁力/海乐楼宇/楼层/机台 | `LaundryPage` 只读 | ✅ |
| 校园卡余额/流水 | 卡信息、近 7 天流水 | `FinancePage` 真实查询 + AES-ECB 解密 | ✅ |
| 校园卡充值 | 10–200 元 + 支付宝 | 明确不迁移 | ⛔ |
| 校园网 | 余额/账号/设备/验证码登录/注销 | `NetworkPage` 全链路 | ✅ |
| 图书馆座位 | 馆→层→区→座位、预约/取消 | `LibrarySeatPage` 全链路 | ✅ |
| 研读间 | 类型/资源/成员/预约/取消 | `LibraryRoomPage` 全链路 | ✅ |
| 体育场馆 | 场馆/时段/记录浏览（UI 只读） | `SportsBookingPage` 只读 | ✅ |
| 体育预约/支付/退订 | 服务层有，UI/AI 未暴露 | 未实现 | ➖ |
| 清华邮箱核心 | Android 原生 IMAP/SMTP | Coremail HTTP：列表/搜索/读信/已读/删除/移动/发送 | ✅ |
| 邮件附件下载 | 原生 IMAP 下载到 cacheDir | 仅展示附件元信息 | 🟡 |
| 邮件附件发送 | 未接系统文件选择器 | 未实现 | ➖ |
| 健康打卡/报修入口 | WebView 入口 | 未找到对应入口 | ⛔ |
| 培养方案 | 服务层占位，返回 0/空数组 | mock 页且入口隐藏 | ➖ |
| 课程评估 | README 明确未完整接入 | 未实现 | ➖ |
| 选课/退课 | AI 工具提供（无独立页面） | 未实现，AI 工具未注册 | ⛔ |
| 邮件门户 WebView | 路由已注册，无导航入口 | 未实现 | ➖ |

### 3.4 AI

| 功能 | RN 基线 | Harmony 现状 | 状态 |
|---|---|---|---|
| AI 对话 | 多会话、流式、失败重试 | `AIChatPage` + `AIChatManager` + `LLMService` | ✅ |
| 多 Provider | OpenAI/DeepSeek/Qwen/Moonshot/自定义 | OpenAI 兼容协议 + 预设 | ✅ |
| Agent 工具 | 49 已注册 | 45（35 只读 + 10 可逆写） | 🟡 |
| 写操作治理 | dry-run→确认→执行→验证→审计 | 同链路；审计仅内存会话级 | ✅ |
| AI 长期记忆 | 常用图书馆/默认金额/关注课程/备注 | `AIMemoryStore` 已持久化 | ✅ |
| AI 记忆管理入口 | 设置页可查看/清除 | 设置页仍显示“暂不支持” | ⛔ |
| AI 操作记录 | 按风险/结果展开、可清空 | 仅内存审计，无设置页入口/持久化 | 🟡 |
| AI 权限 | 按能力类别禁用 | 后端支持 `disabledPermissions`，无 UI/调用方 | ⛔ |
| 智能监控 / Workflow | 8 类预设，4 类可执行 | `WorkflowEngine` 仅 3 个预设、无调用方 | ⛔ |
| 后台监控 | WorkManager + Headless JS | 无等价调度链路 | ⛔ |
| Agent UI 简报 | briefing/task_plan/weather 三类块 | 首页有 task plan 风格建议；完整块未确认 | 🟡 |
| 缓存新鲜度 | 独立页面，6h/48h 分级 | 无对应页面 | ⛔ |

### 3.5 平台 / 发布

| 功能 | RN 基线 | Harmony 现状 | 状态 |
|---|---|---|---|
| 安全存储 | react-native-keychain | Asset Store Kit | ✅ |
| 本地通知 | Android 通知渠道 + 权限 | `NotificationService` 存在但无业务调用方 | ⛔ |
| 后台任务 | WorkManager + Headless JS | 未实现 | ⛔ |
| 支付宝外跳 | 财务/电费/体育 | 未迁移（支付链路未接） | ⛔ |
| 文件打开/预览 | Linking + WebView | 基础 WebView 容器 | 🟡 |
| 推送 / Widget / 深链 | 原项目未实现 | 未实现 | ➖ |
| RN TurboModule 运行时 | RN 原生桥 | 仅桩与模块计数，初始化仍是 TODO | ⛔ |

---

## 4. 未同步清单（按优先级）

### P1：用户感知最强 / 主流程缺口

1. **学习详情深链**：课程详情聚合、通知正文抓取、资料下载/预览、手动 DDL 持久化。
2. **邮件附件下载**：详情页已有附件元信息，补下载/保存/打开。
3. **个人日程 UI**：日程页新增/编辑/删除，展示 AI 写入的个人事件。
4. **成绩研究生切换**：`fetchGrades` 支持本科/研究生两套报表。
5. **天气详情页**：对齐 RN `WeatherDetail`。
6. **健康打卡/报修入口**：宿舍页补 WebView 入口。

### P2：平台与 AI 治理

1. **本地通知 + 后台监控**：鸿蒙侧需替代 WorkManager/Headless 的调度方案。
2. **AI 权限 UI**：复用后端 `disabledPermissions`，补设置页。
3. **AI 操作记录页**：审计持久化 + 可按风险/结果查看/清空。
4. **AI 记忆管理页**：查看/清除 `AIMemoryStore`。
5. **智能监控 UI**：Workflow 预设、启停、立即检查、免打扰。
6. **缓存新鲜度页**：学习快照/课表缓存分级展示。

### P3：高风险写操作（需产品决策）

1. **电费充值、校园卡充值**：涉及支付宝外跳与支付回执。
2. **体育预约/支付/退订**：RN 服务层已有，UI/AI 未暴露。
3. **选课/退课**：RN 通过 AI 工具提供；鸿蒙当前明确不注册不可逆工具。
4. **课程评估**：RN 也未完整接入，建议先补服务层再谈 UI。

### 双方均未完成

- 培养方案、课程评估、邮件附件发送、邮件门户 WebView。

---

## 5. 维护流程

> 维护规则同时写入 `harmony/AGENTS.md` 的“RN 功能同步进度”小节；本文件是执行记录。

1. **RN 侧冻结**：`src/`、`android/` 默认不改；确需改动时先按 `docs/UPSTREAM-SYNC.md` 的 `[shared]` 流程处理。
2. **上游新增功能**：先在 `docs/UPSTREAM-SYNC.md` 登记，再在本文件新增/更新对应行，最后在 `harmony/specs/INDEX.md` 建 spec。
3. **Harmony 功能完成**：以源码行为为准更新本文件；不要只凭 `tasks.md` 复选框把状态改成 ✅。
4. **每次更新**：修改顶部“最后更新”，并在第 8 节追加一行变更记录。
5. **证据要求**：每行状态应能指向页面/服务/Manager 路径；无法指向源码的能力按“未迁移/未确认”处理。

---

## 6. 证据索引

| 主题 | 路径 |
|---|---|
| Harmony 导航/门控 | `harmony/entry/src/main/ets/pages/Index.ets` |
| 认证/会话 | `harmony/entry/src/main/ets/services/auth/`、`state/AuthManager.ets` |
| 校园数据总服务 | `harmony/entry/src/main/ets/services/campus/CampusDataService.ets` |
| 校园各子系统 | `harmony/entry/src/main/ets/services/campus/*.ets` |
| AI Agent | `harmony/entry/src/main/ets/services/ai/AgentService.ets`、`AgentTools.ets`、`AgentWriteTools.ets` |
| 设置页未支持项 | `harmony/entry/src/main/ets/pages/SettingsPage.ets` |
| SDD 任务进度 | `harmony/specs/INDEX.md` |
| 开发进展/限制 | `harmony/DEVELOPMENT.md` |
| 维护约定 | `harmony/AGENTS.md`（“RN 功能同步进度”小节） |
| 上游同步 | `docs/UPSTREAM-SYNC.md` |
| RN 基线 | `src/app/navigation/AppNavigator.tsx`、`src/services/ai/tools.ts`、`android/app/src/main/java/com/campusos/` |

---

## 7. 达成功能同步的实施顺序

> 目标：把本文件中的 ⛔/🟡 行清零；确实不做的能力（支付/选课等）由产品决策后标为 ➖，
> 并在本节记录理由。每个阶段完成后更新第 3 节矩阵与第 8 节变更记录。
> 工期为单人粗估，仅用于排期，不含需求评审与真机等待时间。

### Phase 0：范围决策与验收口径（1–2 天）

1. 产品决策：电费/校园卡充值、体育下单、选课/退课、课程评估是否纳入本轮。
2. 对不纳入的能力，在矩阵中标 ➖ 并写明“产品决策不做”，而不是留 ⛔。
3. 定义每个模块的“功能等价”验收项，写入对应 `spec.md`。
4. 建立里程碑 `harmony-v0.2.0`（或按实际版本）。

### Phase 1：低风险只读/详情补齐（约 5–8 人日）

1. 学习详情深链：课程聚合、通知正文、资料下载/预览、手动 DDL 持久化。
2. 个人日程 UI：新增/编辑/删除，展示 AI 写入 Preferences 的个人事件。
3. 天气详情页、成绩研究生切换、健康打卡/报修入口。
4. 邮件附件下载（复用 `MailService` 的 MIME 解析结果）。
5. App 内文件预览/打开补全。

### Phase 2：AI 治理与平台能力（约 8–12 人日）

1. AI 权限 UI（复用 `disabledPermissions`）。
2. AI 操作记录持久化 + 设置页入口。
3. AI 记忆管理页。
4. `WorkflowEngine` 执行器 + 监控 UI（预设/启停/立即检查/免打扰）。
5. 本地通知接入 + 后台调度等价方案（`workScheduler` / `reminderAgent` /
   `backgroundTaskManager`，按系统限制选型）。
6. 缓存新鲜度页。

### Phase 3：高风险写操作（需产品决策，约 8–15 人日）

1. 电费/校园卡充值：支付宝外跳 + 回执/验证 + 失败兜底。
2. 体育预约/支付/退订：先补服务层，再决定 UI/AI 暴露。
3. 选课/退课：先补 `CourseRegService`，再接入 AI 强确认链；不可逆操作必须有 verify。
4. 课程评估：RN 也未完整接入，建议单独立项。

### Phase 4：验证与发布（约 3–5 人日）

1. 每个 feature 走 SDD：spec → plan → tasks → implementation → `spec-verify`。
2. 逐故事 UI 验证；对 `verify_ui` 不可靠的动态行为改用日志 + 人工确认。
3. 全量 `build` + `arkts` + `lint`；必要时 clean build。
4. 更新本文件状态与证据，打 `harmony-v0.2.0` tag（附注 tag）。

### 验收口径

- 本文件第 3 节不再有 ⛔；🟡 要么升级为 ✅，要么有明确的产品决策/上游限制说明。
- 每个 ✅ 行都能指向页面/服务/Manager 路径，并通过至少一次构建 + 对应 UI 验证。
- `harmony/specs/INDEX.md` 的任务计数与 `tasks.md` 一致；本文件与 INDEX 不矛盾。

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-19 | 初版：基于 `11af855` 与源码审计，记录 18 个 feature / 328 任务的同步状态与缺口 |
| 2026-10-19 | 补充“达成功能同步的实施顺序”与 AGENTS.md 维护约定 |
