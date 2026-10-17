# 上游同步记录

**上游** = `upstream` remote → <https://github.com/yf-w23/campus-os.git>（RN 版 Campus OS）
**本项目** = 移植分支：`harmony/` 是新增目录，上游不存在 → 上游的改动不会与 `harmony/` 冲突。

---

## 当前状态（2026-10-17 22:40 实测）

| 项 | 值 |
|---|---|
| `upstream/main` | `a2dbb9f`（2026-07-11，*Merge pull request #1 from yf-w23/agent/publish-v2-1-1*） |
| 本地 `HEAD` | `b84edb5`（2026-10-17） |
| 落后 / 领先 | **0 / 106** —— upstream/main 已全部包含在 `dev/harmony` 中 |
| merge-base | `a2dbb9f` = `upstream/main` 本身 → **完全同步** |
| 上游分支 | `main`、`agent/publish-v2-1-1`（无 tag） |
| 上游自 2026-07-11 起 | **无新提交**（远程 `ls-remote` 实测与本地 ref 一致） |
| 最后一次上游合并提交 | `f949b37`（2026-07-23，冲突在 `learningScheduleStorage.ts`） |
| 非 harmony 文件改动面 | **30 个文件**；最后一次**真改 RN 代码** = `70b1a54`（2026-07-09） |

**结论：当前无需同步动作。** 风险不在"落后"，而在下面这 30 个文件构成的**未来冲突面**。

---

## 冲突面清单（上游一旦有更新，优先检查这些）

| 类别 | 文件 |
|---|---|
| 存储层 | `src/storage/asyncStorage.ts` · `secureStorage.ts` · `secureStorageBridge.ts` · `cookieManager.ts` · `learningScheduleStorage.ts` · `preferencesStorage.ts` · `conversationsStorage.ts` · `aiMemoryStorage.ts` · `actionAuditStorage.ts` · `manualDeadlinesStorage.ts` · `personalEventsStorage.ts` · `workflowStorage.ts` |
| 服务层 | `src/services/webvpn/transport.ts` · `src/services/campus/mail.ts` · `src/services/campus/networkCompat.ts` |
| 平台适配 | `src/app/platform.ts` · `src/app/navigation/navigationCompat.ts` · `src/polyfills.ts` |
| 兼容组件 | `src/features/common/components/{SafeAreaView,AnimatedCompat,Gradient,MarkdownCompat}.tsx` · `src/features/learning/InAppViewerScreen.tsx` · `src/features/campus/CampusMailViewerScreen.tsx` · `src/utils/filesystemCompat.ts` |
| 根配置 | `.gitignore` · `__mocks__/jest.setup.ts` · `docs/harmonyos-dependency-matrix.md` |

**处理原则**：能不改就不改；必须改时**单独提交**，并在 commit message 加 `[shared]` 标记，
方便下次合并时用 `git log --grep="\[shared\]"` 快速定位冲突面。

> 这 30 个改动主要是 2026-07-09 那次"为鸿蒙移植在 RN 侧加兼容层"（`*Compat` / `platform.ts` /
> 存储双平台 fallback）带来的**一次性**改动，之后 RN 侧基本冻结 —— 所以冲突面虽广但稳定。

---

## RN 侧改动的性质与回退方案（2026-10-17 逐文件核实）

> 精确差异：**26 个 `src/` 文件 + `__mocks__/jest.setup.ts` + `.gitignore`**。
> 之前统计的 30 还包含 2 个 `.deveco/plans/*.md`（已不入库）与 1 个已不存在的 `docs/harmonyos-dependency-matrix.md`。

### A 类：本分支新增的"OpenHarmony RN 兼容层"（11 个文件，上游没有）

| 文件 | 新增行 | 被引用 | 备注 |
|---|---|---|---|
| `src/storage/cookieManager.ts` | 121 | 4（transport / mail / 2 个 Screen） | 手动 cookie jar |
| `src/app/platform.ts` | 72 | 仅 compat 文件 | 平台判断 |
| `src/storage/secureStorageBridge.ts` | 76 | 1（secureStorage.ts） | Keychain 桥 |
| `src/storage/asyncStorage.ts` | 64 | 7（各 storage） | 存储桥 |
| `src/app/navigation/navigationCompat.ts` | 88 | **0** | 死代码 |
| `src/features/common/components/AnimatedCompat.tsx` | 97 | **0** | 死代码 |
| `src/features/common/components/SafeAreaView.tsx` | 70 | **0** | 死代码 |
| `src/features/common/components/MarkdownCompat.tsx` | 50 | **0** | 死代码 |
| `src/services/campus/networkCompat.ts` | 57 | **0** | 死代码 |
| `src/features/common/components/Gradient.tsx` | 57 | **0** | 死代码 |
| `src/utils/filesystemCompat.ts` | 45 | **0** | 死代码 |

**合计 797 行新增；其中 7 个文件 464 行是零引用死代码。**
（注：业务屏里的 `LinearGradient` 来自 `react-native-linear-gradient`，与本文件的 `Gradient.tsx` 无关 —— 已核实。）

### B 类：上游已有文件被改（13 个文件，+57 / −45 行）

全部是把 `@react-native-cookies/cookies`、RN 存储包等**替换成 A 类的桥**，或把 import 包进 `try/catch`：

| 文件 | 差异 | 性质 |
|---|---|---|
| `src/services/webvpn/transport.ts` | 1/1 | `CookieManager` 换成自建桥 |
| `src/services/campus/mail.ts` | 1/1 | 同上 |
| `src/features/campus/CampusMailViewerScreen.tsx` | 1/1 | 同上 |
| `src/features/learning/InAppViewerScreen.tsx` | 1/1 | 同上 |
| `src/polyfills.ts` | 6/2 | `try { import 'react-native-get-random-values' }` |
| `src/storage/asyncStorage.ts` 等 7 个 | 3–12 行 | import 路径切换 |
| `src/storage/preferencesStorage.ts` | 12/12 | import 路径切换 |
| `src/storage/secureStorage.ts` | 1/1 | 改用 secureStorageBridge |
| `__mocks__/jest.setup.ts` | 11/0 | 新增 ohos mock |

**B 类不含任何业务协议逻辑** —— 纯 plumbing。

### 对当前重写方案的价值：**0**

- `harmony/` 对 `src/` 的**跨端 import 次数 = 0**（ArkTS 不消费 TS/TSX）
- 业务协议知识本来就在**上游原版**里（`transport.ts` / `mail.ts` 的原始实现），已提取进
  `.deveco/skills/{tsinghua-auth,campus-endpoints}/SKILL.md`
- 唯一可参考的是 `cookieManager.ts` 的手动 jar 思路，但鸿蒙侧 `CookieManager.ets` 已独立实现

### 回退方案（闭合、可逆；需产品决策后执行）

A + B **必须一起回退**，否则 RN 版会因缺少 compat 模块而编译失败：

```powershell
# 1) 删除 11 个纯新增文件
git rm src/app/navigation/navigationCompat.ts src/app/platform.ts `
       src/features/common/components/AnimatedCompat.tsx src/features/common/components/Gradient.tsx `
       src/features/common/components/MarkdownCompat.tsx src/features/common/components/SafeAreaView.tsx `
       src/services/campus/networkCompat.ts src/storage/asyncStorage.ts src/storage/cookieManager.ts `
       src/storage/secureStorageBridge.ts src/utils/filesystemCompat.ts
# 2) 14 个文件回退到上游内容
git checkout upstream/main -- src __mocks__/jest.setup.ts
# 保留：.gitignore（项目级，与兼容层无关）
```

回退后冲突面从 **27 → 1**（只剩 `.gitignore`）。

⚠️ **前置条件与风险**
1. 本机 `node_modules` 不存在 → **无法本地跑 `npm run typecheck` 验证**（需先 `npm ci`，RN 依赖较重）
2. 回退即放弃"RN 应用跑在 OpenHarmony 上"这条备用路线
3. 回退是可逆的（这些文件都在 git 历史里；备份分支 `backup/pre-improve-20261017-2238`）

---

## 同步流程（建议每两周一次，或上游有 release 时）

```powershell
git fetch upstream --prune
git log --oneline HEAD..upstream/main                    # ① 先看上游多了什么
git log --oneline --stat HEAD..upstream/main -- src      # ② 是否动了冲突面
git merge upstream/main                                  # ③ 保留 merge commit 作为同步标记
git rev-list --left-right --count upstream/main...HEAD   # ④ 应回到 0  X
```

**三条纪律**

1. **禁止在 `dev/harmony` 上随意改 RN 侧文件**（`src/`、`android/`、根配置）。
   必须改时开 `shared/<主题>` 分支单独立项，合并后记入下方日志。
2. 同步前先看上游动了什么，把"上游新增的 RN 功能"登记进 `harmony/specs/INDEX.md`，
   否则永远不知道漏了什么没移植。
3. 每次同步在下方追加一行日志。

---

## 同步日志

| 日期 | from → to | 新增上游提交 | 冲突 | 需移植 |
|---|---|---|---|---|
| 2026-07-23 | — → `f949b37` | — | `learningScheduleStorage.ts`（保留上游多学期缓存） | — |
| 2026-10-17 | `a2dbb9f` → `a2dbb9f` | 0（上游无新提交） | 无 | 无 |

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
