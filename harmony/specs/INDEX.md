# SDD 规范产物索引

> **约定**：每个 feature 的 `feature.json / spec.md / plan.md / tasks.md` 统一放在
> `harmony/specs/<feature>/`，**不要**写回 `entry/src/main/ets/` 源码树。
> 新增 feature 后请在下面的总览表补一行。
>
> **迁移记录**：2026-10-17 由 `entry/src/main/ets/**` 下迁出
> （17 个目录 / 68 个文件，用 `git mv` 保留历史）。

## 进度总览

| # | feature | specs 目录 | 任务完成度 | 状态 |
|---|---|---|---|---|
| 1 | ai-agent | `specs/ai-agent/` | 30/30 | ✅ 完成 |
| 2 | ai-chat | `specs/ai-chat/` | 24/24 | ✅ 完成 |
| 3 | campus-laundry | `specs/campus-laundry/` | 16/16 | ✅ 完成 |
| 4 | campus-mail | `specs/campus-mail/` | 30/30 | ✅ 完成 |
| 5 | campus-network | `specs/campus-network/` | 24/24 | ✅ 完成 |
| 6 | campus-session-nav | `specs/campus-session-nav/` | 32/33 | 🚧 剩 1 项 |
| 7 | i18n-batch2 | `specs/i18n-batch2/` | 16/16 | ✅ 完成 |
| 8 | i18n-migration | `specs/i18n-migration/` | 4/12 | 🚧 剩 8 项 |
| 9 | library-room | `specs/library-room/` | 18/18 | ✅ 完成 |
| 10 | library-room-booking | `specs/library-room-booking/` | 14/14 | ✅ 完成 |
| 11 | library-seat | `specs/library-seat/` | 24/24 | ✅ 完成 |
| 12 | schedule-interaction | `specs/schedule-interaction/` | 26/26 | ✅ 完成 |
| 13 | schedule-visual | `specs/schedule-visual/` | 20/20 | ✅ 完成 |
| 14 | secure-credential-store | `specs/secure-credential-store/` | 14/14 | ✅ 完成 |
| 15 | session-reset-unification | `specs/session-reset-unification/` | 20/20 | ✅ 完成 |
| 16 | settings-integration | `specs/settings-integration/` | 24/24 | ✅ 完成 |
| 17 | sports-booking | `specs/sports-booking/` | 20/20 | ✅ 完成 |
| 18 | trust-device | `specs/trust-device/` | 20/20 | ✅ 完成 |
| — | **合计** | 18 个 feature | **376 / 385** | 97.7% |

> 完成度来自各 `tasks.md` 的 `- [X]` / `- [ ]` 计数，可随时重算。

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
| secure-credential-store | `entry/src/main/ets/storage/secure-credential-store` |
| session-reset-unification | `entry/src/main/ets/services/auth/session-reset-unification` |
| settings-integration | `entry/src/main/ets/pages/settings-integration` |
| sports-booking | `entry/src/main/ets/pages/campus/sports-booking` |
| trust-device | `entry/src/main/ets/pages/trust-device` |

## 相关文档

- 项目契约（工作纪律 / 工具踩坑 / i18n / verify_ui 边界）：`harmony/AGENTS.md`
- 移植方案与实测数据：`harmony/docs/MULTI_MODEL_PLAYBOOK.md`（本地，未入库）
- 开发手册与回滚：`harmony/docs/DEVECO-USAGE.md`（本地，未入库）
- 上游同步记录：`docs/UPSTREAM-SYNC.md`
- 上游代码参考与许可证：`docs/SOURCE-REUSE-LOG.md`
