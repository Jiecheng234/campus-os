# Implementation Plan: AI 真实对话（流式，多 provider）

**Input**: Feature specification: `entry/src/main/ets/pages/ai-chat/spec.md`

**Note**: 本特性产物按项目约定与所属源码同区域放置（`entry/src/main/ets/pages/ai-chat/`），不创建 `spec/` 目录。

## Summary

把 AI 页从 mock 应答升级为真实 LLM 对话：新增 **LLM 服务**（OpenAI 兼容 `/chat/completions`，**流式解析** + 可取消 + 错误映射）与 **API Key 安全存储**（系统关键资产存储，复用既有 ASSET 范式）；在**设置页**新增"AI 模型"配置区（预设/自定义 baseUrl+model/API Key）；AI 页支持**流式增量渲染、停止、错误与未配置引导、演示模式零请求、多会话持久化**。既有设置/会话/i18n 能力全部复用，不破坏既有契约。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: 既有 `StateManager`/`SettingsManager`（provider 配置持久化）、`storage/SecureStorage` 的 **ASSET** 用法范式（API Key）、`state/AIChatManager` + `StorageKeys.AI_CONVERSATIONS`（会话持久化）、`utils/I18n`（文案）、系统网络能力；**无新增三方依赖**
**State Management**: 沿用 **State Management V1**（`@Component`/`@State`）；语言经 AppStorage `'locale'`
**Storage**: provider 配置→既有设置存储；API Key→**ASSET**；会话/消息→既有 AI 会话存储键
**Testing**: `arkts_check` + `devecocli build` + 模拟器 UI 验证（含真实流式对话、中断、错误、未配置引导、会话恢复）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Performance Goals**: 首段回复 ≤3s；中断 ≤1s 生效（SC-002/003）
**Constraints**: 未配置/演示**零请求**；日志不出 Key；长文本不溢出；ArkTS 严格模式
**Scale/Scope**: 新增 2 个服务文件（LLM、API Key）；改造 3 个既有文件（AI 页、设置页、会话管理器）；实体 4 个

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/pages/ai-chat/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── services/ai/
│   ├── LLMService.ets                        # 新增：provider 预设 + 请求构建 + 流式解析 + 取消 + 错误映射
│   └── ApiKeyStore.ets                       # 新增：API Key 安全存储（复用 ASSET 范式，禁明文）
├── state/
│   ├── AIChatManager.ets                     # 改造：会话/消息 CRUD 与持久化（结构向后兼容）
│   └── SettingsManager.ets                   # 复用/小幅扩展：provider 配置读写（持久化）
├── pages/
│   ├── ai/AIChatPage.ets                     # 改造：真实流式对话、停止、错误、未配置引导、会话切换
│   └── SettingsPage.ets                      # 改造：新增“AI 模型”配置区（预设/自定义/Key）
└── utils/I18n.ets                            # 扩展：ai.* / settings.ai* 文案（zh/en 成对）
```

**Structure Decision**: **沿用既有项目架构，不引入 MVVM 迁移**。网络与密钥为"服务能力"，落 `services/ai/`；会话状态管理沿用既有 `AIChatManager`（扩展而非替换）；UI 改动集中在既有 AI 页与设置页。**不新增目录层级、不新增依赖**（流式所用系统网络能力为系统 API）。

## Complexity Tracking

> 无 Constitution 违背项。仅新增 1 个能力模块（LLM 客户端），理由见 Decision 1。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| 新增 `services/ai/LLMService.ets`（独立网络路径） | 流式（SSE）读取与取消语义需要更细的请求控制，既有 webvpn 客户端面向"请求-响应" | 复用 `HttpClient` 直接做流式：其封装面向 webvpn 会话/手动重定向，缺乏增量读取接口 |

## Research & Decisions

**Decision 1 — 流式实现路径（本特性最大技术不确定性）**
- **Decision**: 优先用**系统网络能力的流式接口**（`@ohos.net.http` 的 `requestInStream`，逐块回调）实现 SSE 增量解析，封装在新 `LLMService` 中；**不改**既有 `HttpClient`。开局先以 `devecocli docs search` 核对接口签名与可用性；若该接口在本 API 版本不可用或与自定义 baseUrl/HTTPS 不兼容，则**降级为非流式**（一次性响应后按块渲染）并在报告中明确标注偏离。
- **Rationale**: LLM 端点为外部 HTTPS，无需 webvpn Cookie；独立路径避免扰动生产链路；流式是用户体验要求（FR-005/SC-002）。
- **Alternatives considered**: (a) 在 `HttpClient` 上强行加流式（耦合会话/重定向逻辑，回归风险高）；(b) 直接非流式（不满足用户选择）。

**Decision 2 — API Key 存储**
- **Decision**: 复用既有 **ASSET** 范式（`storage/SecureStorage` 已实现"关键资产 + 惰性迁移 + 失败不抛"的成熟模式）新增 `ApiKeyStore`：`save(providerId, key)` / `get()` / `clear()`；**禁止**写入偏好设置；日志不输出 Key。
- **Rationale**: 满足 FR-002/SC-008；同一套安全能力已被验证（凭证存储特性）。
- **Alternatives considered**: 存偏好设置（明文，违背安全要求）；自研加密（重复且弱于系统方案）。

**Decision 3 — provider 配置与预设**
- **Decision**: 预设常量（openai / deepseek / dashscope / moonshot / custom，含各自 baseUrl 与默认 model，对齐参考实现）+ 自定义 baseUrl/model 由用户填写；配置存既有设置存储（`AppSettings.apiProvider/apiKey` 中 **apiKey 字段不再使用**，改由 `ApiKeyStore` 承载；新增 `apiModel/apiBaseUrl` 等必要字段或复用现有字段，保持向后兼容）。
- **Rationale**: 满足 FR-001/FR-003；预设降低配置门槛。
- **Alternatives considered**: 仅自定义（门槛高）；把 Key 也塞进设置存储（违背 FR-002）。

**Decision 4 — 会话与消息持久化**
- **Decision**: 沿用既有 `AIChatManager` 与 `StorageKeys.AI_CONVERSATIONS`；**扩展消息结构**（角色/内容/时间/状态）并**向后兼容**旧数据结构（读取时容错，写回时升级）。
- **Rationale**: 满足 FR-007/FR-014；避免破坏既有自检用例（`Phase4SelfTest` 已覆盖会话创建/删除）。
- **Alternatives considered**: 新建独立存储键（数据割裂、迁移成本）。

**Decision 5 — 未配置 / 演示模式零请求**
- **Decision**: 发送前判定：**演示模式** → 本地示例应答（零请求）；**未配置 Key** → 展示引导（可跳转设置页），**不构造请求**；两者均在 UI 明确标注。
- **Rationale**: 满足 FR-008/FR-009/SC-005/SC-006，杜绝"发了没反应"。
- **Alternatives considered**: 统一走请求再由错误提示（会产生真实请求，违背约束）。

**Decision 6 — 取消与超时语义**
- **Decision**: 中断（停止按钮）、离开页面、超时三类事件统一走"取消句柄"（终止请求/停止消费流），并**保留已生成内容**、把消息状态标为"中断"；超时给出可读提示。
- **Rationale**: 满足 FR-006/FR-013/SC-003；避免后台悬挂请求。
- **Alternatives considered**: 仅停止 UI 追加（请求仍在跑，浪费额度）。

**Decision 7 — 文案与布局健壮性**
- **Decision**: 新增/改动文案一律走既有 i18n（`ai.*`/`settings.ai*` 扩展，zh/en 成对）；AI 页消息区可滚动、长词换行、输入区在键盘弹出时可用；胶囊/标签类元素加"缩略+换行"保护（延续本项目既有做法）。
- **Rationale**: 满足 FR-011/FR-012；避免英文变长溢出（近期实际问题）。
- **Alternatives considered**: 硬编码中文（违背既有 i18n 约定）。

## Data Model

**AIProviderConfig**: `preset: string`（openai/deepseek/dashscope/moonshot/custom）· `baseUrl: string`（自定义时）· `model: string`

**ChatMessage（扩展）**: `id: string` · `role: string`（user/assistant）· `content: string` · `ts: number` · `status: string`（ok/streaming/aborted/error）

**Conversation**: `id: string` · `title: string` · `updatedAt: number` · `messages: ChatMessage[]`

**LLM 流式回调契约**: `onDelta(textChunk)` · `onDone(fullText)` · `onError(message)` · `cancel()`

## Contracts & Interfaces

**LLM 服务（新增 `LLMService`）**
- `streamChat(config: AIProviderConfig, apiKey: string, history: ChatMessage[], handlers): Promise<LLMSession>` —— 发起 OpenAI 兼容流式请求；返回可取消句柄
- `resolveBaseUrl(config): string` / `resolveModel(config): string` —— 预设与自定义解析
- 错误映射：401/403 → 密钥无效；429 → 频率限制；5xx/网络 → 可读提示（文案经 i18n，**不含 Key**）

**API Key 存储（新增 `ApiKeyStore`）**
- `save(key: string): Promise<void>` / `get(): Promise<string>` / `clear(): Promise<void>` —— 底层为 ASSET；失败不抛（返回空/记录日志）

**会话管理（改造 `AIChatManager`）**
- 保持既有创建/删除签名；新增/完善：追加消息、更新消息状态、读取恢复、会话标题（首条用户消息摘要）

**设置页（改造 `SettingsPage`）**
- 新增"AI 模型"区：预设选择（选择器/弹层）、自定义 baseUrl/model 输入、API Key 输入（掩码/显隐）、保存与清除；保存时校验 baseUrl 形态；展示"已配置/未配置"状态（文案走 `settings.*`）

**AI 页（改造 `AIChatPage`）**
- 发送流程：演示模式 → 本地示例；未配置 → 引导；否则流式渲染（增量）并可"停止"
- 消息区：滚动列表 + 长文本换行；输入区在键盘弹出时可用；错误以可读提示呈现且保留输入
- 会话入口：新建/切换/删除（删除需确认）

**依赖契约（复用，不改语义）**
- `SettingsManager`（provider 配置持久化）、`storage/SecureStorage` 的 ASSET 使用范式、`StorageKeys.AI_CONVERSATIONS`、`utils/I18n`（`t/tp`）
