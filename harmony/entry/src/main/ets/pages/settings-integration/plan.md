# Implementation Plan: 设置页功能对接（含 i18n 框架）

**Input**: Feature specification: `entry/src/main/ets/pages/settings-integration/spec.md`

**Note**: 本特性产物按项目约定与所属源码同区域放置（`entry/src/main/ets/pages/settings-integration/`），不创建 `spec/` 目录。

## Summary

让设置页各项真正生效并持久化：偏好项（演示模式/信任设备/语言）经状态层**写入即持久化**且演示模式**当次运行立即生效**；新增轻量 **i18n 框架**（词典 + 翻译函数 + 运行时切换，locale 存于 AppStorage 以便后续页面扩展）并完成**设置页双语化**；补齐账号信息展示、退出登录（二次确认 + 清会话与本地凭证）、数据清理（AI 会话/学习缓存）、真实版本号；三个未实现功能标注"暂不支持"。全部改动为**加法式**（不破坏既有调用语义）。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `StateManager`/`SettingsManager`（设置持久化）、`PreferencesStorage` + `StorageKeys`（本地键）、`SessionManager`/`SecureStorage`（会话与凭证）、`AuthManager`（登录态）、`@kit.AbilityKit`（读取自身版本信息）；无新增三方依赖
**State Management**: 沿用 **State Management V1**；跨页语言状态使用 **AppStorage**（`@StorageLink`）以便后续页面接入
**Storage**: 设置沿用既有设置存储；清理仅作用于既有本地键（AI 会话 / 学习缓存）
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（含重启验证持久化）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 语言切换 1 秒内完成（SC-003）；设置类操作反馈即时
**Constraints**: 版本号不得硬编码；未迁移页面回退中文且不泄露键名；提示用非弃用 API；写设置失败须可读提示且状态一致；ArkTS 严格模式
**Scale/Scope**: 新增 2 个工具/存储模块（i18n、数据清理）；改造 1 个页面与 1 个状态管理器；实体 5 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/settings-integration/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── utils/
│   └── I18n.ets                               # 新增：词典（zh/en）+ t() + locale（AppStorage）
├── storage/
│   ├── StorageKeys.ets                        # 复用（清理项键名）
│   ├── LocalDataCleaner.ets                   # 新增：清理 AI 会话 / 学习缓存（返回清理条数）
│   └── SecureStorage.ets                      # 复用：clearCredentials（退出登录）
├── state/
│   ├── StateManager.ets                       # 复用：saveSettings（持久化入口）
│   ├── SettingsManager.ets                    # 改造：setter 内持久化（setDemoMode/setTrustDevice/setLocale）
│   └── AuthManager.ets                        # 复用：登录态/演示模式判定
├── services/auth/SessionManager.ets           # 复用：logout（注销会话）
└── pages/
    └── SettingsPage.ets                       # 改造：七项对接 + i18n + 确认弹窗 + 版本 + 暂不支持
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。设置页保持"单页面 + 既有状态层"结构：新增能力放在最小合理位置（i18n 工具置于 `utils/`，本地数据清理置于 `storage/`），偏好持久化下沉到既有 `SettingsManager`（页面只调用，避免页内散落存储逻辑）。**不新增目录、不新增依赖、不改动 `CampusPage` 等导航装配**。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 偏好持久化位置**
- **Decision**: 在既有 `SettingsManager` 的 setter（`setDemoMode` / `setTrustDevice` / `setLocale`）内部**写入并持久化**（更新内存 + 调用 `StateManager.saveSettings()`）；设置页只调用 setter，不再直接写 `StateManager.settings`。
- **Rationale**: 修复"开关只改内存不保存"的根因（FR-001/FR-002/FR-003）；集中持久化点，避免页面各处散落保存逻辑。
- **Alternatives considered**: 由页面在每次切换后手动调用 `saveSettings`（易漏、且新增设置项需重复样板）。

**Decision 2 — 演示模式"当次运行即时生效"**
- **Decision**: 持久化后立即更新内存中的设置对象；全应用既有判定（`AuthManager`/`StateManager`）直接读取该对象，因此**无需额外广播**即可生效；演示模式相关的页面在下次进入/刷新时按新值表现（本轮不引入全局重载）。
- **Rationale**: 现有架构已以状态对象为单一事实源，写内存即生效（SC-002）。
- **Alternatives considered**: 事件广播强制全应用刷新（超出需要，且可能打断用户当前操作）。

**Decision 3 — i18n 框架形态与回退**
- **Decision**: 新增 `utils/I18n.ets`：①词典为 `key → {zh, en}` 的结构；②`t(key)` 按当前 locale 返回文案，**未命中则回退中文**，中文亦缺则返回 key 的可读占位（避免空白/键名外泄）；③`setLocale(locale)` 校验（仅 `zh`/`en`，非法回退 `zh`）并写入 **AppStorage**（键如 `locale`），同时持久化；④后续页面可用 `@StorageLink('locale')` 自动重渲染。
- **Rationale**: 轻量、可扩展（新增语言只需扩词典）；回退策略满足 FR-005/边界要求；AppStorage 让后续批次迁移无需改框架。
- **Alternatives considered**: 引入三方 i18n 库（与项目"无新增依赖"约束冲突）；编译期资源多语言（需重构页面文案体系，成本更高）。

**Decision 4 — 设置页双语化方式**
- **Decision**: 设置页所有文案改为 `I18n.t('settings.xxx')`；页面用 `@StorageLink('locale')` 订阅语言变化以**即时重渲染**（满足 SC-003 ≤1s）。
- **Rationale**: 最小改动实现"切换即生效"；为后续页面迁移提供范式。
- **Alternatives considered**: 语言切换后重建页面（闪烁、丢失滚动位置）。

**Decision 5 — 真实版本信息来源**
- **Decision**: 通过系统能力读取**自身应用的包信息**（版本名/版本号）来展示；读取失败时回退为可读占位（如"—"），**不得硬编码**版本字符串。
- **Rationale**: 满足 FR-012/SC-006；避免版本漂移。
- **Alternatives considered**: 编译期常量（需与构建配置同步维护，易漂移）；写死字符串（违反 FR-012）。

**Decision 6 — 账号信息来源与降级**
- **Decision**: 学号取自**本地凭证/会话**（无凭证或演示模式 → 展示"演示模式/未登录"状态文案）；姓名/邮箱**仅在既有能力可直接获取时**展示，否则**省略该行**（不显示错误占位、不臆造）。
- **Rationale**: 满足 FR-006/FR-007 且避免引入新的服务端耦合；数据可得性不明确时不阻塞交付。
- **Alternatives considered**: 为姓名/邮箱新增服务端请求（扩大范围、增加失败面）。

**Decision 7 — 退出登录（清会话 + 清凭证）**
- **Decision**: `AlertDialog.show` 二次确认 → 调用既有会话注销（`SessionManager.logout()`）→ 清除本地凭证（安全存储）→ 回到未登录态并提示成功；异常时给出可读提示（不静默失败）。
- **Rationale**: 满足 FR-008/FR-009 与用户确认的"清会话+清凭证"；复用既有能力。
- **Alternatives considered**: 仅清会话保留凭证（用户已否决）；无确认直接退出（误触风险）。

**Decision 8 — 数据清理范围与实现**
- **Decision**: 新增 `storage/LocalDataCleaner.ets`，通过既有 `StorageKeys` 清理 **AI 会话**与**学习缓存**两项本地数据，返回清理条数；设置页提供入口 + `AlertDialog` 二次确认 + 结果提示（无数据也给出可读结果）。
- **Rationale**: 满足 FR-010/FR-011；集中管理清理项，键名不散落页面。
- **Alternatives considered**: 页面内直接删除键（键名散落、易错）；"清除全部数据"一键项（超出本轮，列入 Open Questions）。

**Decision 9 — "暂不支持"三项与提示 API**
- **Decision**: "AI 记忆 / 操作记录 / 智能监控"三行文案改为"暂不支持"并呈现禁用态（不可点击/无跳转、无"开发中"以外误导）；所有提示统一改用 `getUIContext().getPromptAction().showToast`（去除页面内弃用 API 调用）。
- **Rationale**: 满足 FR-013/FR-018 与 SC-007；同时消除既有弃用告警。
- **Alternatives considered**: 保留"开发中"toast（仍属误导）；移除三项（用户已选择"改为暂不支持"）。

## Data Model

**AppSettings（既有，持久化结构）**: `locale: string`（zh/en）· `demoMode: boolean` · `trustDevice: boolean` · `apiProvider: string` · `apiKey: string`

**翻译词条**: `key: string` → `{ zh: string, en: string }`（本轮覆盖设置页全部文案）

**本地数据清理项**: `AI 会话`（既有 AI 会话键）· `学习缓存`（既有学习缓存键）；清理结果 = `{ item: string, cleared: boolean, remaining: number }`

**版本信息**: `versionName: string` · `platform: string`（如 "HarmonyOS ArkTS"）

**账号信息（只读展示）**: `studentId: string`（本地可得）· `name/email: string`（可获取时）

## Contracts & Interfaces

**状态层契约（`SettingsManager`，改造后）**
- `static setDemoMode(enabled: boolean): void` / `getDemoMode(): boolean`
- `static setTrustDevice(enabled: boolean): void` / `getTrustDevice(): boolean`
- `static setLocale(locale: string): void` / `getLocale(): string`
- 三个 setter **均持久化**（内存 + 设置存储）；语义与返回类型不变（调用方兼容）。

**i18n 契约（新增 `I18n`）**
- `static t(key: string): string` —— 按当前 locale 返回文案；未命中回退中文；再缺返回可读占位
- `static setLocale(locale: string): void` —— 校验 + 写 AppStorage + 持久化
- `static getLocale(): string`
- 约束：词典条目**成对**（zh/en 同键）；新增语言只需扩列

**数据清理契约（新增 `LocalDataCleaner`）**
- `static async clearAiConversations(): Promise<number>` —— 返回清理条数（无数据返回 0）
- `static async clearLearningCache(): Promise<number>`
- 约束：仅本地；不触达服务端；失败不抛（返回可读结果由页面提示）

**页面契约（`SettingsPage`，改造）**
- 分区：账号信息（只读）→ 偏好设置（演示模式/信任设备/语言）→ 功能（AI 记忆/操作记录/智能监控＝暂不支持、数据清理）→ 退出登录 → 版本信息
- 语言行：点击弹选择（中文/English）→ 选择后**页面文案即时切换**并持久化
- 退出登录/数据清理：`AlertDialog` 二次确认；结果 toast（非弃用 API）
- 布局遵循既有约定（分区标题 + 白卡行组；全宽元素配 `constraintSize({ maxWidth: '100%' })` 防右缘溢出）

**依赖契约（复用，不改）**
- `StateManager.saveSettings(): Promise<void>`（持久化入口）
- `AuthManager`（登录态/演示模式判定）、`SessionManager.logout()`、`SecureStorage.clearCredentials()`
- `PreferencesStorage` + `StorageKeys`（清理项键名）
- 系统能力：读取自身应用包信息（版本）；统一 toast（`getUIContext().getPromptAction()`）
