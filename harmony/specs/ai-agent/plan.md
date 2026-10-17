# Implementation Plan: AI Agent（校园智能助手·工具调用）

**Input**: Feature specification: `entry/src/main/ets/pages/ai/ai-agent/spec.md`

**Note**: 本特性产物按项目约定与其余 AI 源码同区域放置（`entry/src/main/ets/pages/ai/ai-agent/`），不创建 `spec/` 目录。

## Summary

在既有 AI 聊天（provider 配置 + 流式对话）之上接入 **agent 循环 + 工具调用**：

1. **工具注册表**：只读 38 + 可逆写 11（不可逆写 2 不注册），每工具含名称/标题/描述/参数 schema/权限/风险/执行实现（对照原项目语义）。
2. **agent 循环**：把工具 spec 发给模型（OpenAI 兼容 tools）→ 执行 `tool_calls` → 结果回灌 → 直至最终回答（**≤6 轮**）。
3. **写操作治理**：dry-run 预览 → 用户二次确认 → 执行 → 执行后验证 → 审计；未确认不执行。
4. **上下文与记忆**：构建 `AgentContext`（学期/周次/日期）+ 记忆项读写。
5. **UI**：对话内工具轨迹（脱敏）+ 写操作确认弹窗。

技术路径：扩展 `LLMService` 支持**非流式**带 tools 补全；新增 `AgentService`（循环/上下文/审计）；新增工具注册表（读/写分文件）；扩展 `ActionTypes`/`AIAgentTypes`；`AIChatPage` 接入 agent 路径与确认交互。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `LLMService`（OpenAI 兼容预设/传输）、`ApiKeyStore`、`AIChatManager`、各校园服务（`SessionManager.get*Service()`）；无新增三方依赖
**State Management**: 沿用 **V1**（`@Component` + `@State`）；新增数据以静态存储类（偏好/内存）
**Storage**: 会话复用既有 `StorageKeys.AI_CONVERSATIONS`；**记忆项**与**审计**按决策 D6/D7（偏好或内存）
**Testing**: `arkts_check` + `devecocli build` + 模拟器验证（项目既有流程）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Performance Goals**: 只读工具问答在数秒内出结果（受模型响应时间主导）；agent 轮数上限 6（收敛保障）
**Constraints**: 写操作 100% 经确认（SC-002）；不可逆写执行数 0（SC-004）；演示零真实请求（SC-006）；无敏感明文（SC-007）；ArkTS 严格模式
**Scale/Scope**: 新增 ~4 个文件（AgentService / 工具注册表 ×2 / 审计或记忆存储）+ 扩展 ~4 个（LLMService / AIAgentTypes / ActionTypes / AIChatPage）+ i18n；工具 49 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/ai/ai-agent/
├── feature.json         # 特性目录记录
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── domain/
│   ├── AIAgentTypes.ets                  # 扩展：工具定义/上下文/轨迹相关类型
│   └── ActionTypes.ets                   # 扩展：执行状态/确认状态/验证结果等
├── services/ai/
│   ├── LLMService.ets                    # 扩展：非流式带 tools 的补全
│   ├── AgentTools.ets                    # 新增：只读工具注册表（38）
│   ├── AgentWriteTools.ets               # 新增：可逆写工具注册表（11）
│   └── AgentService.ets                  # 新增：agent 循环 + 上下文 + 记忆 + 审计
├── state/
│   ├── AIChatManager.ets                 # 扩展：消息携带工具轨迹/审计关联
│   └── AIMemoryStore.ets                 # 新增：记忆项存取（remember_preference）
└── pages/ai/
    └── AIChatPage.ets                    # 改造：接入 agent 路径 + 工具轨迹 + 确认弹窗
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。工具注册表按"读/写"拆两个文件以控制单文件规模（49 工具）；agent 循环/上下文/记忆/审计集中在 `AgentService`（单一编排点）；类型沿用既有 `domain/`；UI 在既有 `AIChatPage` 内扩展。不新增目录（除本特性产物）、不新增依赖/资源。

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 工具注册表拆两文件（`AgentTools`/`AgentWriteTools`） | 49 个工具定义体量大，单文件难维护 | 单文件（>2500 行，ArkTS 编译/维护成本高） |
| 新增 `AgentService`（而非并入 `AIChatManager`） | agent 循环含网络/工具/确认/审计，与"会话状态管理"职责不同 | 并入会话管理器（职责混杂、难测） |

## Research & Decisions

**Decision 1 — agent 循环（流式，≤6 轮）**
- **Decision**: 循环调用**流式** chat/completions（SSE），携带 `tools` 与 `tool_choice:'auto'`；每轮**累积 content 增量与 `tool_calls` 增量**；`MAX_AGENT_ROUNDS = 6`；无 `tool_calls` 的轮次其累积 content 即为最终回答（边收边流式渲染）。
- **Rationale**: 用户要求最终回答**流式**；OpenAI 兼容 SSE 亦支持 `tool_calls` 增量，故流式与工具调用可并存。
- **Alternatives considered**: 非流式一次性呈现（**原方案，已按用户变更废弃**：无法流式呈现最终回答）。

**Decision 2 — 工具定义形态（ArkTS 严格模式下）**
- **Decision**: 新增 `AgentToolDef`：`name`/`title`/`description`/`parametersJson`（**JSON Schema 原文串**）/`risk`/`permission`/`requiresConfirmation` + 可选 `dryRun`/`verify`/`summarize`/`confirmPrompt` + 必选 `run`。工具 spec 发给模型时以 `parametersJson` 注入（请求体经原始 JSON 文本构造）。
- **Rationale**: ArkTS 禁止 `Record<string, unknown>`/深层匿名类型；以 JSON 文本承载 schema 最稳妥，且请求体本就需要原始 JSON（含嵌套数组）。
- **Alternatives considered**: 结构化 `Record<string, Object>` 递归建 schema（类型体操、易错）。

**Decision 3 — LLM 工具调用传输**
- **Decision**: 扩展 `LLMService` 增加非流式补全（`stream:false` + `tools`），沿用其既有传输/鉴权装配（OpenAI 兼容 `{baseUrl}/chat/completions` + `Authorization: Bearer`）；请求体以原始 JSON 文本提交（含 tools 数组）。
- **Rationale**: 复用既有 provider 预设与 key 管理（`ApiKeyStore`）；避免新造传输层。
- **Alternatives considered**: 直接在页面用 `fetch`（与既有传输重复、鉴权/错误处理不一致）。

**Decision 4 — 写操作治理（预览→确认→执行→验证→审计）**
- **Decision**: 对 `requiresConfirmation` 工具：先 `dryRun` 得 `ActionPreview` → 经 `AgentCallbacks.requestConfirmation` 交 UI 二次确认（Promise<boolean>）→ 仅 `true` 时 `run` → `verify` → 写审计；拒绝/无确认通道则**不执行**并回灌"已取消/已阻止"结果。
- **Rationale**: 对齐原项目 `runAgent` 的治理链；确保"未确认不执行"（SC-002）。
- **Alternatives considered**: 写操作直接执行（不可接受）。

**Decision 5 — 不可逆写不注册**
- **Decision**: `select_course`/`drop_course` **不进入注册表**；模型若臆造该工具名 → 返回"未知工具"并可读提示。
- **Rationale**: 安全边界（FR-005/SC-004）。
- **Alternatives considered**: 注册但拒绝执行（易被绕过，不如不注册干净）。

**Decision 6 — 记忆（remember_preference）**
- **Decision**: 新增 `AIMemoryStore`（静态，基于既有 `PreferencesStorage` + `StorageKeys` 扩展），提供键值存取；`remember_preference` 工具写入；`AgentContext` 构建时注入已有记忆摘要。
- **Rationale**: 支撑"记住偏好"（US4）；持久化以便跨会话生效。
- **Alternatives considered**: 仅内存（重启丢失，价值有限）。

**Decision 7 — 审计（会话内为主）**
- **Decision**: 新增会话内审计存储（`ActionAuditRecord` 列表，进程内）；`AgentService` 每次工具调用后追加记录（工具/风险/参数概要/结果/时间/是否确认）。
- **Rationale**: 满足 FR-011 与可诊断性；跨会话持久化列为 Open Question（默认不做）。
- **Alternatives considered**: 立即持久化（写放大、隐私面扩大）。

**Decision 8 — UI 集成（agent 路径 + 流式回答 + 轨迹 + 确认）**
- **Decision**: `AIChatPage` 发送消息时走 agent 路径（携带工具）；**最终回答逐字流式渲染**（复用既有 `streamingText`）；中间工具调用轮次显示"工具执行中"过程态且**不产生可见正文**；对话内展示工具轨迹卡片（脱敏）；写操作以确认弹窗拦截。
- **Rationale**: 对齐用户"输出改为流式"的要求；每轮流式 + 累积 `tool_calls` 使流式与工具调用并存。
- **Alternatives considered**: 非流式一次性呈现（**原方案，已废弃**）。

**Decision 9 — 演示模式**
- **Decision**: 演示模式下 agent 不发起真实网络/写操作，返回模拟结果（`createMockAgentReply` 语义）。
- **Rationale**: SC-006。
- **Alternatives considered**: 照常请求（演示模式会因鉴权失败而不稳定）。

**Decision 10 — 敏感信息脱敏**
- **Decision**: 轨迹/审计中参数与结果里的学号/卡号/令牌/API Key 一律脱敏（复用既有 `maskId` 类思路）；日志不含密钥。
- **Rationale**: FR-014/SC-007。

**Decision 11 — 上下文构建**
- **Decision**: `AgentContext` 由既有能力构建（登录学号、`CampusDataService` 学期/周次/日期语义）——对齐原项目 `buildAgentContext`/`buildSystemPrompt`。
- **Rationale**: US4；复用既有学期解析，避免重复。

## Data Model

**AgentToolDef（新增）**: `name` · `title` · `description` · `parametersJson`（JSON Schema 原文）· `risk: ToolRisk` · `permission` · `requiresConfirmation: boolean` · 可选 `dryRun`/`verify`/`summarize`/`confirmPrompt` · `run`

**AgentContext（既有，按需扩展）**: `studentId` · `semesterName` · `todayDate` · `currentWeek`

**AIMemory（既有）**: `key` · `value` · `updatedAt`

**ToolTrace（既有）**: `callId` · `name` · `params` · `result` · `timestamp` · `success`

**ActionPreview / ConfirmationSpec / AuditRecord（既有，按需扩展）**: 预览（工具/描述/参数）· 确认（工具/摘要/风险/明细/可取消）· 审计（id/时间/工具/参数/结果/成功/是否确认）

**新增扩展**：执行状态（success/error/cancelled）与确认状态（not_required/approved/denied/unavailable）、验证结果（ok/message）——以 `ActionTypes` 常量类或枚举表达。

**工具清单（49）**
- 只读 38：天气、今日概览、作业（列表/详情）、成绩、电费、洗衣机（楼宇/状态）、校园卡（余额/流水）、校园网（余额/账号/设备）、体育（场馆/时段/记录）、空教室（楼宇/查找）、图书馆座位（馆/楼层/区域/座位/记录）、研读间（类型/资源/成员/记录）、个人日程（列表/周课表）、培养方案（完成度/全量）、资讯（列表/搜索/详情）、邮件（文件夹/搜索/读取）。
- 可逆写 11：`add_manual_deadline`/`remove_manual_deadline`/`recharge_campus_card`/`book_library_seat`/`cancel_library_seat_booking`/`logout_network_device`/`book_library_room`/`cancel_library_room_booking`/`add_personal_event`/`remove_personal_event`/`remember_preference`。
- 不接入 2：`select_course`/`drop_course`。

## Contracts & Interfaces

**`AgentService`（新增）**
- `buildContext(): Promise<AgentContext>` —— 学期/周次/日期/学号。
- `buildSystemPrompt(context: AgentContext, memory: AIMemory[]): string` —— 系统提示（含工具使用与安全约束）。
- `runAgent(config, messages, context, callbacks): Promise<string>` —— agent 循环（≤6 轮），携带工具、处理 `tool_calls`、确认/验证/审计、回灌结果。
- `createMockReply(messages): string` —— 演示模式模拟回答。
- `getAuditRecords(): AuditRecord[]` —— 会话内审计查询。

**`AgentCallbacks`（新增）**: `onAnswer(text)` · `onToolStart(tool, args)` · `onToolEnd(tool, status, detail?, meta?)` · `requestConfirmation(tool, args, preview?): Promise<boolean>`

**`AIMemoryStore`（新增）**: `load(): Promise<AIMemory[]>` · `remember(key, value): Promise<void>` · `forget(key): Promise<void>`

**工具注册表（新增）**: `AgentTools.all(): AgentToolDef[]`（读 + 写）· `AgentTools.byName(name): AgentToolDef | undefined`

**`LLMService`（扩展）**: `chatCompleteWithTools(config, apiKey, messages, toolsJson: string): Promise<AgentCompletionResult>`（非流式；返回 content + toolCalls）

**`AIChatPage`（改造）**: 发送 → `AgentService.runAgent`（携回调）；`onToolEnd` 追加 `ToolTrace` 展示；`requestConfirmation` 弹确认框并解析 Promise；写操作拒绝即不执行；演示模式走 `createMockReply`。

**依赖契约（复用，不改）**: `ApiKeyStore`、`AIChatManager`（会话/消息，扩展字段向后兼容）、各 `SessionManager.get*Service()`、`PreferencesStorage`/`StorageKeys`。

**安全契约**: 未确认写操作执行数 = 0；不可逆写不注册；日志/轨迹无敏感明文。

## Changelog

- 2026-10-16：初版计划（AI Agent：工具注册表 49 + agent 循环 + 确认/验证/审计 + 上下文/记忆 + UI 集成）。
- 2026-10-16（变更）：按用户要求将 agent 最终回答由**非流式**改为**流式增量渲染**；D1/D8 相应修订，新增"流式 `tool_calls` 增量解析"。
