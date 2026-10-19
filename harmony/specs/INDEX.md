# SDD 规范产物索引

> **约定**：每个 feature 的 `feature.json / spec.md / plan.md / tasks.md` 统一放在
> `harmony/specs/<feature>/`，**不要**写回 `entry/src/main/ets/` 源码树。
> 新增 feature 后请在下面的总览表补一行。
>
> **迁移记录**：2026-10-17 由 `entry/src/main/ets/**` 下迁出
> （17 个目录 / 68 个文件，用 `git mv` 保留历史）；2026-10-19 新增
> `schedule-interaction`（新建，无迁移前目录）。

## 进度总览

> **统计口径（2026-10-19 按源码与 tasks.md 重算）**：任务完成度按各 `tasks.md` 中实际任务行
> `- [X]` / `- [ ]` 计数，不含 Notes/Summary 中的示例文本。`✅ 完成` 仅表示该 feature
> 规格内任务闭环，**不代表与原 RN v2.1.1 功能完全等价**；实际能力边界见下方“已知边界”。

| # | feature | specs 目录 | 任务完成度 | 状态 | 实现边界 / 备注 |
|---|---|---|---|---|---|
| 1 | ai-agent | `specs/ai-agent/` | 21/21 | ✅ 完成 | 35 只读 + 10 可逆写；培养方案/已选课程/校园卡充值/选课退课未注册 |
| 2 | ai-chat | `specs/ai-chat/` | 17/17 | ✅ 完成 | OpenAI 兼容流式；多 provider/多会话 |
| 3 | campus-laundry | `specs/campus-laundry/` | 13/13 | ✅ 完成 | 只读：楼宇/楼层/机台状态 |
| 4 | campus-mail | `specs/campus-mail/` | 29/29 | ✅ 完成 | Coremail HTTP；附件仅元信息，无下载/草稿 |
| 5 | campus-network | `specs/campus-network/` | 23/23 | ✅ 完成 | 余额/账号/设备/验证码登录/注销；无充值/套餐变更 |
| 6 | campus-session-nav | `specs/campus-session-nav/` | 16/16 | ✅ 完成 | 会话自愈 + 冷启动跨页导航 |
| 7 | i18n-batch2 | `specs/i18n-batch2/` | 25/25 | ✅ 完成 | 校园/学习子页 + 顶层页 |
| 8 | i18n-migration | `specs/i18n-migration/` | 18/18 | ✅ 完成 | 清单按源码回填；T011 状态键按页面实际实现，T012 由 batch2 接管 |
| 9 | library-room | `specs/library-room/` | 19/19 | ✅ 完成 | 只读；预约/取消见 library-room-booking |
| 10 | library-room-booking | `specs/library-room-booking/` | 12/12 | ✅ 完成 | 预约/取消/成员搜索 |
| 11 | library-seat | `specs/library-seat/` | 24/24 | ✅ 完成 | 查询/预约/取消/首页直达；T014–T016 并入 T013 |
| 12 | schedule-interaction | `specs/schedule-interaction/` | 26/26 | ✅ 完成 | 课程详情/时间线/16 色 |
| 13 | schedule-visual | `specs/schedule-visual/` | 12/12 | ✅ 完成 | 块状课表/跨节/配色 |
| 14 | secure-credential-store | `specs/secure-credential-store/` | 10/10 | ✅ 完成 | Asset Store Kit + 懒迁移 |
| 15 | session-reset-unification | `specs/session-reset-unification/` | 13/13 | ✅ 完成 | 校园服务瞬态态统一复位 |
| 16 | settings-integration | `specs/settings-integration/` | 16/16 | ✅ 完成 | 偏好/语言/退出/清理/版本；AI 记忆/审计/监控入口仍为禁用态 |
| 17 | sports-booking | `specs/sports-booking/` | 17/17 | ✅ 完成 | 只读；下单/支付/退订未开放（RN 服务层有写能力） |
| 18 | trust-device | `specs/trust-device/` | 17/17 | ✅ 完成 | US5 UI 验证受限；US3 服务端 2FA 场景未构造 |
| — | **合计** | 18 个 feature | **328 / 328** | **100%** | 任务闭环；功能边界见下节 |

> 旧口径（`376/385`、各 feature 的 `30/30` 等）与当前 `tasks.md` 不一致，已废弃。
> `schedule-interaction` 已于 2026-10-19 提交（`11af855`），其任务计数已纳入本表。

## 已知边界（与 RN v2.1.1 基线对照）

> 以下为“任务已完成、但功能未完全对齐”的实际边界；不等同于任务未完成。

### 1. 鸿蒙侧未迁移、RN 用户可见

- **支付/充值**：电费充值、校园卡充值（含支付宝外跳）未迁移；查询与流水已接。
- **选课/退课**：鸿蒙未实现；RN 通过 AI 工具提供（无独立页面）。
- **邮件附件**：仅展示附件元信息，无下载/预览（RN Android 原生 IMAP 支持下载）。
- **后台监控/通知**：无 WorkManager/Headless 等价链路；`WorkflowEngine` 仅预设、`NotificationService` 无调用方。
- **AI 治理 UI**：AI 权限页、操作记录页、智能监控页、记忆管理入口未交付；AI 记忆/审计仅后端/会话级实现。
- **学习详情**：课程详情无聚合、通知正文不单独抓取、资料下载按钮无动作、手动 DDL 不持久化。
- **个人日程**：无新增/编辑 UI；`ScheduleManager` 仅内存，AI 写工具直写 Preferences。
- **其他**：天气详情页、成绩研究生切换、健康打卡/报修入口、缓存新鲜度页、本地通知接入未迁移。

### 2. RN 服务层已有、但 UI/AI 未暴露（鸿蒙未跟进）

- 体育预约/支付/退订、新闻收藏/订阅（RN 服务层有写能力，但 UI/AI 未暴露）。

### 3. 双方均未完成

- 培养方案（RN 为占位，鸿蒙为 mock 且入口隐藏）、课程评估、邮件附件发送、邮件门户 WebView。

> 逐项实现位置见 `harmony/DEVELOPMENT.md` 与对应 feature 的 `spec.md` / 源码。

## 原始位置对照（仅追溯用）

`feature.json` 里的 `feature_directory` 是**迁移前的历史记录**，尚未回改：

| feature | 原 feature_directory |
|---|---|
| ai-agent | `entry/src/main/ets/pages/ai/ai-agent` |
| ai-chat | `entry/src/main/ets/pages/ai-chat` |
| campus-laundry | `entry/src/main/ets/pages/campus/campus-laundry` |
| campus-mail | `entry/src/main/ets/pages/campus/campus-mail` |
| campus-network | `entry/src/main/ets/pages/campus/campus-network` |
| campus-session-nav | `entry/src/main/ets/pages/campus/campus-session-nav` |
| i18n-batch2 | `entry/src/main/ets/utils/i18n-batch2` |
| i18n-migration | `entry/src/main/ets/utils/i18n-migration` |
| library-room | `entry/src/main/ets/pages/campus/library-room` |
| library-room-booking | `entry/src/main/ets/pages/campus/library-room-booking` |
| library-seat | `entry/src/main/ets/pages/campus/library-seat` |
| schedule-visual | `entry/src/main/ets/pages/schedule-visual` |
| schedule-interaction | —（2026-10-19 新增，无迁移前目录） |
| secure-credential-store | `entry/src/main/ets/storage/secure-credential-store` |
| session-reset-unification | `entry/src/main/ets/services/auth/session-reset-unification` |
| settings-integration | `entry/src/main/ets/pages/settings-integration` |
| sports-booking | `entry/src/main/ets/pages/campus/sports-booking` |
| trust-device | `entry/src/main/ets/pages/trust-device` |

## 相关文档

- 项目契约（工作纪律 / 工具踩坑 / i18n / verify_ui 边界）：`harmony/AGENTS.md`
- 开发进展与已知限制：`harmony/DEVELOPMENT.md`
- RN → HarmonyOS 功能同步进度：`docs/RN-FEATURE-SYNC.md`
- 移植方案与实测数据：`harmony/docs/MULTI_MODEL_PLAYBOOK.md`（本地，未入库）
- 开发手册与回滚：`harmony/docs/DEVECO-USAGE.md`（本地，未入库）
- 上游同步记录：`docs/UPSTREAM-SYNC.md`
- 上游代码参考与许可证：`docs/SOURCE-REUSE-LOG.md`
