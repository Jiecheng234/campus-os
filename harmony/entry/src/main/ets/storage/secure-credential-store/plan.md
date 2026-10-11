# Implementation Plan: 凭证安全存储（系统关键资产存储 + 自动迁移）

**Input**: Feature specification: `entry/src/main/ets/storage/secure-credential-store/spec.md`

**Note**: 本特性产物按项目约定与所属源码同区域放置（`entry/src/main/ets/storage/secure-credential-store/`），不创建 `spec/` 目录。

## Summary

将登录凭证（学号/密码/指纹）的持久化从"偏好设置 + URL 编码"改为**系统关键资产存储**（Asset Store Kit / ASSET）：加解密与访问控制由安全环境完成。实现方式为**替换 `SecureStorage` 的内部实现、保持其对外接口与语义不变**，并在读取路径实现**惰性自动迁移**（旧明文 → 新存储 → 清除旧明文）。调用方（认证服务、会话管理、校园网服务）**零改动**。

## Technical Context

**Language/Version**: ArkTS（HarmonyOS API 24 / DevEco 6.1.1）
**Primary Dependencies**: `@ohos.security.asset`（关键资产存储，ArkTS 接口）；既有 `PreferencesStorage`（仅用于迁移期读取/清除旧明文）；无新增三方依赖
**State Management**: N/A（本特性为存储层，无 UI 状态管理）
**Storage**: 系统关键资产存储（ASSET）承载凭证；偏好设置仅保留旧键以兼容迁移
**Testing**: `arkts_check` + `devecocli build` + 设备验证（日志判定迁移与是否仍有明文；既有链路回归）
**Target Platform**: HarmonyOS 手机（模拟器 Mate 80 Pro Max, API 24）
**Project Type**: mobile-app（既有项目增量特性）
**Performance Goals**: 读取/保存为本地操作，交互路径无明显延迟（与既有偏好设置方案同级）
**Constraints**: 禁止明文回退（FR-008）；迁移失败不得清除旧值（FR-004）；日志不得含密码明文（FR-009）；ArkTS 严格模式
**Scale/Scope**: 修改 1 个存储文件（替换实现）；上层 3 个调用点零改动；实体 2 个（凭证记录、旧明文记录）

## Project Structure

### Documentation (this feature)

```text
entry/src/main/ets/storage/secure-credential-store/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件（/spec-plan 产出）
└── tasks.md             # Phase 3 产出（/spec-tasks 生成）
```

### Source Code (repository root)

```text
entry/src/main/ets/
├── storage/
│   ├── PreferencesStorage.ets                 # 复用（仅迁移期读取/清除旧明文）
│   └── SecureStorage.ets                      # 改造：内部改为 ASSET 实现 + 惰性自动迁移（对外接口不变）
├── services/
│   ├── auth/
│   │   ├── TsinghuaAuthService.ets            # 零改动（调用 SecureStorage 既有接口）
│   │   └── SessionManager.ets                 # 零改动
│   └── campus/
│       └── CampusNetworkService.ets           # 零改动（验证码登录读取凭证）
└── turbomodules/
    └── SecureStorageTurboModule.ets           # 不在本特性范围（未接入链路，保持现状）
```

**Structure Decision**: **沿用既有项目架构**。本特性不是新页面/新服务，而是**存储层实现的替换**：`SecureStorage` 的三个静态方法（保存/读取/清除）签名与语义保持不变，内部改为 ASSET + 迁移逻辑。不新增文件（除非实现时确有必要抽出内部辅助），不新增目录、不引入依赖（`@ohos.security.asset` 为系统能力）、不改动任何调用方——这是达到"零回归"（SC-005）的最小改动路径。

## Complexity Tracking

> 无 Constitution 违背项。

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |

## Research & Decisions

**Decision 1 — 存储形态与字段落位**
- **Decision**: 使用**单条关键资产**：固定别名（如 `campusos.credentials`）+ 将凭证三项序列化为**一个紧凑串**放入关键资产的 `SECRET` 字段；**不得**把学号/密码/指纹放入 `ALIAS` 或任何 `DATA_LABEL` 类字段（这些字段不加密）。
- **Rationale**: 与现有"单键存储"一一对应，迁移与读取均为一次操作；ASSET 中只有 `SECRET` 会被加密，故三项必须全在 `SECRET` 内。
- **Alternatives considered**: (a) 拆分三条关键资产（多别名、多次读写、迁移粒度更碎）；(b) 用 `DATA_LABEL` 存学号/指纹（明文，违背安全目标）。

**Decision 2 — 序列化格式沿用既有格式**
- **Decision**: `SECRET` 内容沿用现有序列化（`encodeURIComponent(学号):encodeURIComponent(密码):指纹`），迁移时**原样搬运**字符串。
- **Rationale**: 迁移=字符串搬运，避免解析/重构带来的边界风险（指纹含特殊字符等）；对上层返回的对象结构与语义完全一致。
- **Alternatives considered**: 迁移时切换为 JSON（需同时改解析与兼容旧值，风险更大）。

**Decision 3 — 访问属性（保证自动登录可用）**
- **Decision**: 关键资产访问条件设为"设备开机后可用"（设备重启后凭证不可读，需重新登录），**不**设置"需用户认证"类属性，以满足自动登录；查询返回类型设为返回全部属性与明文。
- **Rationale**: 与既有语义一致（会话 Cookie 不持久化、冷启动重新登录）；设置需用户认证会破坏"静默自动登录"。
- **Alternatives considered**: 需用户认证（破坏自动登录）；永久不可用/需解锁首次访问（超出需求）。

**Decision 4 — 保存幂等（避免多份残留）**
- **Decision**: 保存采用"新增失败（已存在）则更新"的策略（`add` → 命中"已存在"错误码 → `update`）；保证同别名只有一份。
- **Rationale**: 满足 FR-002；避免"先删后增"在异常时短暂无凭证。
- **Alternatives considered**: 先 `remove` 再 `add`（异常窗口内凭证丢失）；只 `add`（第二次登录失败）。

**Decision 5 — 惰性自动迁移**
- **Decision**: 读取路径实现迁移：①查询 ASSET → 命中则返回（并尝试清除旧明文残留）；②未命中 → 读旧明文字段：存在则写入 ASSET，**写入成功后才清除旧明文**，返回该凭证；写入失败则**保留旧明文**并返回凭证（不丢数据、不阻塞用户）；③两者皆无 → 返回空值。
- **Rationale**: 满足 FR-003/FR-004/FR-010（幂等）；不引入启动期一次性迁移任务，覆盖"升级后首次启动"的自然路径。
- **Alternatives considered**: 启动时批量迁移（需要额外时机与幂等锁，收益低）。

**Decision 6 — 故障与降级边界**
- **Decision**: ①读取失败/ASSET 不可用 → 返回空值（调用方走重新登录），记录可读日志，**绝不**回退为明文写入；②保存失败 → 记录日志并**不向调用方抛出**（登录流程不因存储故障而中断），且不写明文；③清除 → ASSET 与本模块旧键均尝试清除（各自容错）。
- **Rationale**: FR-005/FR-008/SC-004；保持上层行为稳定（保存不阻断登录）。
- **Alternatives considered**: 保存失败即抛错（会让存储问题升级为登录失败，违背既有体验）。

**Decision 7 — 可观测性（不泄露明文）**
- **Decision**: 日志仅输出：步骤名、成功/失败、错误码、旧明文"是否存在"的布尔与长度（可加掩码），**不得**输出密码或完整凭证串。验证阶段以日志判定迁移是否发生、旧明文是否被清除。
- **Rationale**: FR-009 与验证可操作性（SC-001/SC-002/SC-004 的判定依据）。
- **Alternatives considered**: 关闭日志（失去验证手段）；打印明文（违反 FR-009）。

## Data Model

**SecureCredentials（凭证记录，对外结构不变）**: `studentId: string` · `password: string` · `fingerprint: string`

**关键资产（ASSET 条目，逻辑视图）**
| 属性 | 取值 | 说明 |
|---|---|---|
| 别名（ALIAS） | 固定值（如 `campusos.credentials`） | 不加密，可读；不含敏感信息 |
| 密文（SECRET） | `encodeURIComponent(学号):encodeURIComponent(密码):指纹` 的 UTF-8 字节 | **三项凭证全在此字段**（唯一加密字段） |
| 访问条件（ACCESSIBILITY） | 设备开机后可用 | 支持自动登录；重启后需重登 |
| 返回类型（查询时） | 返回属性 + 明文 | 便于一次取回 |

**旧明文记录（迁移期）**: 偏好设置键（沿用既有 `@secure:credentials`），值为上述序列化串；迁移成功后应被清除，之后不再写入。

## Contracts & Interfaces

**对外接口（`SecureStorage`，**签名与语义保持不变**，调用方零改动）**
- `static saveCredentials(studentId: string, password: string, fingerprint: string): Promise<void>` —— 幂等写入关键资产；失败记日志且不抛（见 Decision 6）
- `static getCredentials(): Promise<SecureCredentials | undefined>` —— 优先读关键资产；未命中则尝试惰性迁移；无数据/异常 → `undefined`
- `static clearCredentials(): Promise<void>` —— 清除关键资产与本模块旧明文键（各自容错）

**内部实现契约（新增私有辅助，不外泄）**
- 关键资产读写辅助：新增（含"已存在则更新"）、查询（返回明文）、更新、删除
- 序列化/反序列化辅助：与既有格式一致
- 旧明文读写辅助：`PreferencesStorage.getString` / `remove` / `setString`（仅迁移与清除使用）

**依赖契约（复用）**
- `PreferencesStorage.getString(key, def)` / `setString(key, value)` / `remove(key)`
- 系统关键资产存储能力（`@ohos.security.asset`，ArkTS 接口：新增/查询/更新/删除）

**验证契约（供验证阶段判定，不新增对上层接口）**
- 日志标签统一（如 `SecureStore`），字段示例：`CRED_SAVE ok`、`CRED_QUERY hit=true`、`CRED_MIGRATE old_present=true migrated=true cleared=true`、`CRED_CLEAR ok`
- 迁移/清除判定以日志为准；**不**通过打印明文核验
