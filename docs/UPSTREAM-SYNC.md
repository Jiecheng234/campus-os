# 上游同步记录

**上游** = `upstream` remote → <https://github.com/yf-w23/campus-os.git>（RN 版 Campus OS）
**本项目** = 移植分支：`harmony/` 是新增目录，上游不存在 → 上游的改动不会与 `harmony/` 冲突。

---

## 当前状态（2026-10-17 23:00 实测）

| 项 | 值 |
|---|---|
| `upstream/main` | `a2dbb9f`（2026-07-11，*Merge pull request #1 from yf-w23/agent/publish-v2-1-1*） |
| 本地 `HEAD` | `23cd613`（2026-10-17，RN 兼容层回退） |
| 落后 / 领先 | **0 / N**（见下方命令实时查询；上游自 2026-07-11 起零新提交） |
| merge-base | `a2dbb9f` = `upstream/main` 本身 → **完全同步** |
| 上游分支 | `main`、`agent/publish-v2-1-1`（无 tag） |
| 最后一次上游合并 | `f949b37`（2026-07-23，冲突在 `learningScheduleStorage.ts`） |
| **与上游的非 harmony 差异** | **4 个文件**（见下） |

### 非 harmony 差异清单（全部有意为之）

| 文件 | 性质 | 是否冲突风险 |
|---|---|---|
| `.gitignore` | 上游已有，本地追加了 `.deveco/`、`dsh-acl-backup/`、`*.hap/*.hsp/*.app` 等 | ⚠️ **唯一真正的冲突点** |
| `.gitattributes` | 本分支新增（换行治理） | 无（上游没有此文件） |
| `docs/UPSTREAM-SYNC.md` | 本分支新增（本文） | 无 |
| `docs/RN-FEATURE-SYNC.md` | 本分支新增（RN 功能同步进度） | 无 |

**结论：上游合并的冲突面已收敛到 1 个文件（`.gitignore`）。**

> 功能级同步进度（哪些 RN 能力已迁、哪些未迁）见 `docs/RN-FEATURE-SYNC.md`。

---

## RN 侧：已回退到上游纯净状态（2026-10-17）

### 发生了什么

2026-07-09 的提交 `70b1a54`（*"HarmonyOS migration - ArkTS MVP … JS platform abstractions"*）
曾为**「让 RN 应用跑在 OpenHarmony 上」**这条**竞争路线**在 RN 侧加了一整套兼容层。

项目最终选择**原生 ArkTS 重写**，该路线被放弃，兼容层成为遗留：

| 类别 | 数量 | 内容 |
|---|---|---|
| A 类：新增兼容层 | 11 个文件 / 797 行 | `platform.ts`、`navigationCompat.ts`、`*Compat.tsx`、`asyncStorage.ts`、`cookieManager.ts`、`secureStorageBridge.ts`、`networkCompat.ts`、`filesystemCompat.ts`、`Gradient.tsx` |
| — 其中**零引用死代码** | 7 个文件 / 464 行 | `navigationCompat`、`AnimatedCompat`、`MarkdownCompat`、`SafeAreaView`、`networkCompat`、`Gradient`、`filesystemCompat` |
| B 类：上游文件被改 | 13 个 / +57 −45 行 | 全部是 `import` 替换为 A 类的桥，或 `try/catch` 包裹 —— **无业务协议逻辑** |
| 其它 | 2 个 | `.gitignore`、`__mocks__/jest.setup.ts` |

### 为什么回退

- `harmony/` 对 `src/` 的**跨端 import = 0** → 这批代码对重写方案**零依赖、零价值**
- 真正的业务协议知识在上游原版里，且已提取进 `.deveco/skills/{tsinghua-auth,campus-endpoints}/SKILL.md`
- 它把上游合并冲突面从 **1 个文件扩大到 27 个**

### 回退结果（commit `23cd613`）

```
src/           141 个文件 vs 上游 141 个文件 → 逐文件一致，diff = 0
__mocks__/     与上游一致
悬空引用        navigationCompat / AnimatedCompat / MarkdownCompat / SafeAreaView /
                networkCompat / filesystemCompat / secureStorageBridge / cookieManager /
                asyncStorage / platform → 全部 0
```

**回滚点**：`backup/pre-rn-revert-20261017-2249`（回退前）、`backup/pre-improve-20261017-2238`（本轮改进前）

> 如需恢复该兼容层：`git revert 23cd613`（会一并恢复 11 个删除 + 14 个修改）。

---

## 同步流程（建议每两周一次，或上游有 release 时）

```powershell
git fetch upstream --prune
git log --oneline HEAD..upstream/main                    # ① 上游多了什么
git log --oneline --stat HEAD..upstream/main -- src      # ② 是否动了 RN 侧
git merge upstream/main                                  # ③ 保留 merge commit 作为同步标记
git rev-list --left-right --count upstream/main...HEAD   # ④ 应回到 0  X
```

**三条纪律**

1. **默认不改 RN 侧**（`deveco.jsonc` 已对 `../src/**`、`../android/**` 设 `deny`）。
   确实需要改时：临时改回 `ask`，单独提交并在 message 加 `[shared]`，记入下方日志。
2. 同步前先看上游动了什么，把"上游新增的 RN 功能"登记进 `docs/RN-FEATURE-SYNC.md`，
   并在 `harmony/specs/INDEX.md` 建立对应 spec；否则永远不知道漏了什么没移植。
3. 每次同步在下方追加一行日志。

---

## 同步日志

| 日期 | 事件 | 说明 |
|---|---|---|
| 2026-07-23 | 上游合并 `f949b37` | 冲突在 `learningScheduleStorage.ts`（保留上游多学期缓存） |
| 2026-10-17 | 同步检查 | `upstream/main` = `a2dbb9f`，**0 behind**，上游自 07-11 无新提交 |
| 2026-10-17 | **RN 侧兼容层回退** `23cd613` | 删 11 个文件（797 行）+ 回退 14 个修改文件；冲突面 27 → 1 |
| 2026-10-19 | 功能同步进度初版 | 新增 `docs/RN-FEATURE-SYNC.md`；规格状态校正至 328/328 |

---

## 远程与备份

| 远程 | 地址 | 用途 |
|---|---|---|
| `origin` | <https://github.com/Jiecheng234/campus-os.git> | 本仓库（个人） |
| `upstream` | <https://github.com/yf-w23/campus-os.git> | 上游 RN 版（个人） |

⚠️ **两个远程都是个人仓库**，没有组织托管、没有本地镜像。建议每月做一次离线归档：

```powershell
git clone --mirror https://github.com/yf-w23/campus-os.git D:\Backup\campus-os-upstream.git
# 或更轻量
git bundle create D:\Backup\campus-os-$(Get-Date -Format yyyyMM).bundle --all
```
