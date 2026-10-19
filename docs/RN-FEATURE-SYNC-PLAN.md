# RN 功能同步 · Phase 0 决策与任务拆解

**日期**：2026-10-19  
**范围**：RN v2.1.1 → HarmonyOS `harmony/` 的剩余功能同步  
**状态来源**：`docs/RN-FEATURE-SYNC.md`（功能级）· `harmony/specs/INDEX.md`（任务级）  
**维护规则**：`harmony/AGENTS.md` 的“RN 功能同步进度”小节

---

## 1. Phase 0 决策结果

| 决策 | 结论 | 说明 |
|---|---|---|
| 功能同步口径 | **RN 用户可见对齐** | RN UI + AI 工具用户可触达的流程为目标；RN 服务层未暴露能力默认 ➖ |
| 电费 / 校园卡充值 | **两者都纳入** | Phase 3；支付宝外跳 + 支付后回读余额/记录 |
| 体育预约 / 支付 / 退订 | **全部纳入** | Phase 3；RN 服务层已有，属超出 RN UI 的有意扩展 |
| 选课 / 退课 | **完整 AI 强确认** | Phase 3；前置 CourseRegService + 审计/权限 |
| 课程评估 | **本轮不做** | 标 ➖；RN 也未完整接入 |
| 后台监控 / 通知 | **通知 + 手动检查；后台周期调度后置** | Phase 2；后台调度标 ➖，作为已知限制 |
| 里程碑 | `harmony-v0.2.0` | Phase 4 完成后打附注 tag |
| 发布目标 | 侧载 / debug 签名（默认） | 如需应用市场上架，另行决策 |

> **完成定义**：`docs/RN-FEATURE-SYNC.md` 第 3 节中 in-scope 项不再有 ⛔；
> 🟡 要么升级为 ✅，要么有明确的产品决策/上游限制说明。课程评估与后台周期调度保持 ➖。

---

## 2. 任务总览

| ID | 阶段 | 任务 | 依赖 | 粗估 | 建议 feature 目录 |
|---|---|---|---|---|---|
| T01 | Phase 0 | 决策记录与任务拆解 | — | 1–2 天 | 本文档（已完成） |
| T02 | 基础 | 支付基础设施（支付宝外跳/回读） | — | 2–3 天 | `harmony/specs/payment-alipay/` |
| T03 | 基础 | CourseRegService（选课系统服务） | — | 3–5 天 | `harmony/specs/course-registration-service/` |
| T04 | 基础 | AI 治理：审计持久化 + 权限 UI | — | 3–5 天 | `harmony/specs/ai-governance/` |
| T05 | Phase 1 | 学习详情深链 | — | 3–5 天 | `harmony/specs/learning-detail/` |
| T06 | Phase 1 | 个人日程 UI + 持久化 | — | 2–3 天 | `harmony/specs/schedule-personal-events/` |
| T07 | Phase 1 | 天气详情 / 研究生成绩 / 健康打卡入口 | — | 2–3 天 | `harmony/specs/campus-small-parity/` |
| T08 | Phase 1 | 邮件附件下载 + 文件预览 | — | 2–3 天 | `harmony/specs/mail-attachments/` |
| T09 | Phase 2 | Workflow + 本地通知 + 手动检查 | — | 4–6 天 | `harmony/specs/workflow-notifications/` |
| T10 | Phase 2 | AI 记忆管理 + 缓存新鲜度 | — | 1–2 天 | `harmony/specs/settings-ai-cache/` |
| T11 | Phase 3 | 电费充值 | T02, T04 | 2–3 天 | `harmony/specs/electricity-recharge/` |
| T12 | Phase 3 | 校园卡充值 | T02, T04 | 1–2 天 | `harmony/specs/campus-card-recharge/` |
| T13 | Phase 3 | 体育预约 / 支付 / 退订 | T02, T04 | 3–5 天 | `harmony/specs/sports-booking-write/` |
| T14 | Phase 3 | 选课 / 退课 AI 工具 | T03, T04 | 2–3 天 | `harmony/specs/course-registration-agent/` |
| T15 | Phase 4 | 最终验证与发布 `harmony-v0.2.0` | 全部 in-scope | 3–5 天 | `harmony/specs/release-v0.2.0/` |

**总工期**：约 **34–55 人日**（含 Phase 0；单人粗估，不含需求评审与真机等待）。

---

## 3. 执行顺序

1. **并行启动低风险 Phase 1**：T05–T08 可立即开始，不依赖支付/选课基础。
2. **并行启动基础能力**：T02、T03、T04 三条线互不阻塞。
3. **Phase 2**：T09、T10 可在 Phase 1 进行中并行启动。
4. **Phase 3**：T11/T12 依赖 T02 + T04；T13 依赖 T02 + T04；T14 依赖 T03 + T04。
5. **Phase 4**：T15 在全部 in-scope 任务完成后执行；由验证会话负责。

> 纪律：一个 feature 一个 goal 会话；实现会话只做 Setup→Foundational→User Stories→Polish，
> 不执行 Verification 阶段。正式 `spec-verify` 由独立验证会话执行。

---

## 4. 交接提示词

### 4.1 通用前缀（每条任务提示词前先粘贴）

```text
你是 CampusOS HarmonyOS 移植实现会话。开始前必须：
1) 读 harmony/AGENTS.md（本地契约；缺失时以 docs/RN-FEATURE-SYNC.md 与 README 为准）、
   docs/RN-FEATURE-SYNC.md、docs/RN-FEATURE-SYNC-PLAN.md；
2) 按领域加载技能：tsinghua-auth（认证/会话）、campus-endpoints（校园端点）、
   ai-agent（AI/工具/审计）、hmos-arkui-develop-skill（写 .ets）；
3) 只改 harmony/；../src、../android 只读对照，禁止修改；
4) 先建/更新 harmony/specs/<feature>/ 的 spec→plan→tasks，再按
   Setup→Foundational→User Stories→Polish 实现；
5) 实现会话不执行 Verification 阶段；完成后跑 devecocli build + arkts_check 自检，
   正式 spec-verify 交给验证会话；
6) 汇报前更新 docs/RN-FEATURE-SYNC.md 对应行；不要自行提交/推送。
```

### 4.2 各任务提示词

#### T02 · 支付基础设施

```text
【T02 · 支付基础设施】
Feature dir: harmony/specs/payment-alipay/
目标：提供电费/校园卡/体育共用的支付宝外跳与支付后回读基础设施。
范围：payCode → 支付宝 URL/Deep Link 构建；openLink/startAbility 外跳；返回 App 后刷新
余额/记录；失败可读、可重试；不伪造支付成功。
必读 RN：src/services/campus/electricity.ts、campusCard.ts、sports.ts 中
buildAlipayUrl/payCode 相关段。
必读 Harmony：utils/PlatformBridge.ets、services/campus/*、pages/campus/*、AGENTS.md。
非目标：各子系统的具体充值/下单 UI（T11/T12/T13）。
验收：URL 构建可验证；真实设备能打开支付宝；返回后页面能刷新；异常路径有可读文案；
日志无凭据。
```

#### T03 · CourseRegService

```text
【T03 · CourseRegService】
Feature dir: harmony/specs/course-registration-service/
目标：新建选课系统服务，覆盖学期、已选课程、课余量搜索、选课、退课。
范围：WebVPN/GBK/表单 token；SessionManager 单例；错误归一；日志脱敏。
必读 RN：src/services/campus/courseRegistration.ts、src/services/webvpn/*、src/domain 相关类型。
必读 Harmony：services/HttpClient.ets、services/WebvpnConstants.ets、
services/auth/SessionManager.ets、services/campus/CampusDataService.ets（参考 roam/token 处理）。
非目标：AI 工具注册（T14）、页面 UI。
验收：真实模式下能取学期/已选课程/搜索；选课/退课在受控测试中成功；失败可读；
不记录 token/学号明文。
```

#### T04 · AI 治理

```text
【T04 · AI 治理：审计持久化 + 权限 UI】
Feature dir: harmony/specs/ai-governance/
目标：让高风险写操作可审计、可授权、可关闭。
范围：StorageKeys.ACTION_AUDIT 持久化；设置页查看/清空审计；AI 权限页按能力类别启停；
AgentTools/AgentWriteTools 执行前检查权限；保留现有确认链。
必读 RN：src/features/settings/AIPermissionsScreen.tsx、src/storage/actionAuditStorage.ts、
src/services/ai/agentService.ts。
必读 Harmony：services/ai/AgentService.ets、AgentTools.ets、AgentWriteTools.ets、
pages/SettingsPage.ets、storage/StorageKeys.ets、state/SettingsManager.ets。
非目标：改变现有风险分级；新增工具。
验收：审计跨重启保留；权限关闭后工具不可调用/返回可读拒绝；设置页可查看/清空；
日志无敏感明文。
```

#### T05 · 学习详情深链

```text
【T05 · 学习详情深链】
Feature dir: harmony/specs/learning-detail/
目标：补齐课程详情聚合、通知正文、资料下载/预览、手动 DDL 持久化。
范围：CourseDetailPage 聚合课程下作业/通知/文件；NotificationDetailPage 拉取/展示正文；
FileDetailPage 下载/预览；LearningPage 手动 DDL 持久化到 Preferences 并在首页/学习页共享。
必读 RN：src/features/learning/*、src/services/campus/learningAdapter.ts、
src/services/learning/manualDeadlines.ts。
必读 Harmony：pages/LearningPage.ets、pages/learning/*、
services/campus/CampusDataService.ets、storage/PreferencesStorage.ets、StorageKeys.ets。
非目标：作业提交、讨论区、文件上传。
验收：课程详情能下钻三类数据；通知正文可见；文件可下载/预览；DDL 重启后仍在；
演示模式零请求。
```

#### T06 · 个人日程 UI + 持久化

```text
【T06 · 个人日程 UI + 持久化】
Feature dir: harmony/specs/schedule-personal-events/
目标：把 ScheduleManager 从内存升级为持久化，并在日程页提供新增/编辑/删除入口。
范围：PreferencesStorage 持久化；周视图/今日列表展示；AI 写工具写入的事件可见；
删除确认。
必读 RN：src/features/schedule/ScheduleScreen.tsx、src/services/schedule/personalEvents.ts。
必读 Harmony：state/ScheduleManager.ets、pages/SchedulePage.ets、pages/HomePage.ets、
services/ai/AgentWriteTools.ets（个人日程部分）。
非目标：重复日程/提醒/日历同步。
验收：增删改查跨重启保留；周视图与今日列表一致；AI 新增事件可见；演示模式可用本地数据。
```

#### T07 · 天气详情 / 研究生成绩 / 健康打卡入口

```text
【T07 · 天气详情 / 研究生成绩 / 健康打卡入口】
Feature dir: harmony/specs/campus-small-parity/
目标：补齐三个低风险缺口。
范围：WeatherDetail 页面（当前/逐小时/逐日）；GradesPage 本科/研究生切换 +
fetchGrades(graduate)；DormitoryPage 健康打卡/报修 WebView 入口。
必读 RN：src/features/home/WeatherDetailScreen.tsx、
src/features/campus/GradesScreen.tsx、src/services/campus/grades.ts、
src/features/campus/subscreens.tsx。
必读 Harmony：services/campus/WeatherService.ets、pages/GradesPage.ets、
services/campus/CampusDataService.fetchGrades、pages/campus/DormitoryPage.ets、
pages/learning/WebViewerPage.ets。
非目标：成绩推送、天气预警订阅。
验收：天气详情数据完整；研究生成绩可切换且 GPA 口径正确；健康/报修入口带会话 Cookie
打开；演示模式零请求。
```

#### T08 · 邮件附件下载 + 文件预览

```text
【T08 · 邮件附件下载 + 文件预览】
Feature dir: harmony/specs/mail-attachments/
目标：邮件附件从“元信息”升级为可下载/打开；学习资料复用同一文件预览能力。
范围：MailService 解析附件 part、下载到应用沙箱、打开/预览；MailDetailView 下载动作；
FileDetailPage 复用。
必读 RN：android/app/src/main/java/com/campusos/NativeMailModule.kt（附件下载）、
src/features/campus/CampusMailDetailScreen.tsx。
必读 Harmony：services/campus/MailService.ets（MIME 解析）、
pages/campus/MailDetailView.ets、pages/learning/FileDetailPage.ets、utils/PlatformBridge.ets。
非目标：附件发送（本轮不做）、草稿。
验收：附件名/大小可见；下载成功；可打开/预览；失败可读；无路径穿越/越权写入。
```

#### T09 · Workflow + 本地通知 + 手动检查

```text
【T09 · Workflow + 本地通知 + 手动检查】
Feature dir: harmony/specs/workflow-notifications/
目标：交付本地通知与设置页手动检查；后台周期调度本轮后置。
范围：WorkflowEngine 执行 4 类已有检查（电费/网费/DDL/今日课程）；设置页监控项启停/
立即检查/免打扰；NotificationService 接入；后台调度标 ➖ 并记录限制。
必读 RN：src/services/workflow/WorkflowEngine.ts、
src/services/notification/notificationService.ts、
src/features/settings/MonitorsScreen.tsx。
必读 Harmony：services/workflow/WorkflowEngine.ets、
services/notification/NotificationService.ets、pages/SettingsPage.ets、
entryability/EntryAbility.ets。
非目标：后台周期任务、WorkManager 等价调度。
验收：手动检查可运行并显示结果；通知权限/免打扰生效；设置持久化；后台调度缺失有明确文案。
```

#### T10 · AI 记忆管理 + 缓存新鲜度

```text
【T10 · AI 记忆管理 + 缓存新鲜度】
Feature dir: harmony/specs/settings-ai-cache/
目标：补齐设置页的 AI 记忆查看/清除与缓存新鲜度页。
范围：AIMemoryStore 列表/清除；缓存时间戳展示与刷新；与现有 LocalDataCleaner 对齐。
必读 RN：src/storage/aiMemoryStorage.ts、src/features/settings/CacheFreshnessScreen.tsx。
必读 Harmony：state/AIMemoryStore.ets、pages/SettingsPage.ets、
storage/LocalDataCleaner.ets、storage/StorageKeys.ets。
非目标：AI 权限/审计（T04）。
验收：记忆项可见/可清；缓存状态准确；刷新有反馈；无敏感信息外泄。
```

#### T11 · 电费充值

```text
【T11 · 电费充值】
Feature dir: harmony/specs/electricity-recharge/
目标：在宿舍页补齐电费充值。
范围：金额校验 → 生成支付宝 payCode → 外跳 → 返回后刷新余额/缴费记录；
失败可读/可重试；复用 T02。
必读 RN：src/services/campus/electricity.ts、src/features/campus/EleRechargeScreen.tsx。
必读 Harmony：services/campus/CampusDataService.ets、pages/campus/DormitoryPage.ets、
T02 的支付基础设施。
非目标：校园卡充值（T12）、体育支付（T13）。
验收：真实模式可生成 payCode；支付宝可打开；返回后余额/记录刷新；无假成功；
日志无凭据；演示模式零请求。
```

#### T12 · 校园卡充值

```text
【T12 · 校园卡充值】
Feature dir: harmony/specs/campus-card-recharge/
目标：在财务页补齐校园卡充值。
范围：10–200 元校验 → 支付宝 payCode/URL → 外跳 → 返回后刷新余额/流水；复用 T02。
必读 RN：src/services/campus/campusCard.ts、src/features/campus/CampusFinanceScreen.tsx。
必读 Harmony：services/campus/CampusCardService.ets、pages/campus/FinancePage.ets、
T02 的支付基础设施。
非目标：电费充值（T11）、挂失/改密。
验收：金额范围校验；支付宝可打开；返回后余额/流水刷新；失败可读；日志无凭据。
```

#### T13 · 体育预约 / 支付 / 退订

```text
【T13 · 体育预约/支付/退订】
Feature dir: harmony/specs/sports-booking-write/
目标：把体育从只读升级为预约/支付/退订全流程（Phase 0 有意扩展，超出 RN UI）。
范围：场馆/时段/限额/手机号校验；下单；立即支付/稍后支付；支付状态检查；退订；
二次确认；复用 T02/T04。
必读 RN：src/services/campus/sports.ts。
必读 Harmony：services/campus/SportsService.ets、pages/campus/SportsBookingPage.ets、
AgentWriteTools.ets（如需 AI）。
非目标：场馆收藏、提醒。
验收：受控测试中可预约；支付外跳/回读；退订成功；失败可读；审计完整；无重复下单。
```

#### T14 · 选课 / 退课 AI 工具

```text
【T14 · 选课/退课 AI 工具】
Feature dir: harmony/specs/course-registration-agent/
目标：注册已选课程/选课/退课 AI 工具，走强确认 + verify + 审计。
范围：AgentTools 只读 get_selected_courses；AgentWriteTools select_course/drop_course；
dry-run 预览、强确认、执行后 verify、审计；复用 T03/T04。
必读 RN：src/services/ai/tools.ts（选课相关）、
src/services/campus/courseRegistration.ts。
必读 Harmony：services/ai/AgentTools.ets、AgentWriteTools.ets、AgentService.ets、
T03 的 CourseRegService。
非目标：独立选课页面。
验收：AI 可查已选课程；选课/退课必须二次确认；退课有 verify；失败可读；
不可逆操作未确认不执行。
```

#### T15 · 最终验证与发布

```text
【T15 · 最终验证与发布】
Feature dir: harmony/specs/release-v0.2.0/
目标：对 Phase 1–3 的所有 in-scope feature 做最终验证并发布 harmony-v0.2.0。
范围：逐 feature spec-verify；全量 build/arkts/lint；UI 验证；更新
docs/RN-FEATURE-SYNC.md；打附注 tag；发布说明。
必读：docs/RN-FEATURE-SYNC.md、docs/RN-FEATURE-SYNC-PLAN.md、各 feature tasks.md。
非目标：新增功能。
验收：矩阵中 in-scope ⛔ 清零；🟡 升级或记录；gates 通过；tag 附注；工作树干净。
注意：本条是验证会话，不适用通用前缀第 5 条；由 spec-verify 子 Agent 执行。
```

---

## 5. 验收口径

- `docs/RN-FEATURE-SYNC.md` 第 3 节中 in-scope 项不再有 ⛔。
- 所有 🟡 要么升级为 ✅，要么有明确的产品决策/上游限制说明。
- 每个 ✅ 行都能指向页面/服务/Manager 路径，并通过至少一次构建 + 对应 UI 验证。
- `harmony/specs/INDEX.md` 与各 `tasks.md` 计数一致；本计划与同步文档不矛盾。
- `harmony-v0.2.0` 使用附注 tag，消息包含范围、feature、静态检查、运行验证、已知遗留。

---

## 6. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-10-19 | 初版：Phase 0 决策结果、14 个任务拆解、交接提示词与验收口径 |
