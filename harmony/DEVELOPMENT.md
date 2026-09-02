# CampusOS HarmonyOS 迁移项目 — 开发文档

> 本文档记录 HarmonyOS（ArkTS）版本 CampusOS 的项目进展、架构设计、各模块职责与开发注意事项，供后续开发者快速上手。
>
> **适用基线**：HarmonyOS API 24（DevEco Studio 6.1.1）· 最后更新：2026-09-02

---

## 1. 项目概述

CampusOS 是清华校园 AI 操作系统。本项目将其从 React Native 版本（仓库根目录 `src/`）迁移到 **HarmonyOS 纯 ArkTS 原生方案**（`harmony/` 目录），并对接**清华大学统一身份认证**与**校园真实数据**。

### 当前进展（截至 2026-09-02）

| 模块 | 状态 | 说明 |
|------|------|------|
| 六标签导航框架 | ✅ 完成 | 首页/学习/课表/校园/AI/设置，真实 PNG 瓷砖图标 |
| 设计系统 | ✅ 完成 | 对齐 `docs/CAMPUS_OS_DESIGN_SYSTEM_V1.md`，完整 token + 共享组件库 |
| 统一身份认证 | ✅ 完成 | SM2 加密 + 主登录 + 2FA + 设备信任 + 静默登录 |
| 自动登录 | ✅ 完成 | 凭证 + 指纹持久化，启动时静默重建 WebVPN 会话 |
| learn 域数据 | ✅ 完成 | 课程/作业/通知/文件列表 + 详情（含作业要求/附件解析） |
| 首页真实数据 | ✅ 完成 | 今日课程（课表）+ 指标统计（待办/未读） |
| 课表（zhjw 教务域） | ⚠️ 调试中 | 教务域激活遇到 info 门户会话 403 问题（见 §7 已知问题） |
| 调试日志编译开关 | ✅ 完成 | `BuildProfile.DEBUG` 控制，release 构建自动屏蔽 |

---

## 2. 技术栈与架构

### 技术栈

- **语言**：ArkTS（严格模式，禁 `any`/`as`/动态属性）
- **UI**：ArkUI 声明式（`@Component`/`@State`/`@BuilderParam`）
- **网络**：`@kit.RemoteCommunicationKit`（RCP），手动 Cookie 管理 + 手动重定向
- **加密**：`@kit.CryptoArchitectureKit`（SM2/SHA256/MD5）
- **存储**：`@kit.ArkData` preferences（凭证/设置持久化）

### 分层架构

```
pages/            UI 层（页面 + 共享组件）
  ├─ Index.ets           入口：登录门控 + 自动登录 loading + 底部 6 标签
  ├─ HomePage/LearningPage/SchedulePage/CampusPage/SettingsPage/LoginPage
  ├─ ai/AIChatPage       AI 助手
  ├─ learning/           学习详情页 ×4 + WebViewer
  └─ campus/             校园子页面 ×10
components/Ui.ets        共享组件库（ScreenHeader/DetailHeader/ListCard/…）
services/         服务层（认证 + 数据 + 网络）
  ├─ auth/               TsinghuaAuthService（认证链路）+ SessionManager（协调）
  ├─ campus/             CampusDataService（校园数据接入）
  ├─ HttpClient.ets      RCP 封装（手动重定向 + GBK 解码 + Cookie 同步）
  ├─ CookieManager.ets   手动 Cookie 存储/域匹配
  └─ WebvpnConstants.ets 端点常量
state/            状态层（AuthManager/StateManager/各 Manager）
storage/          存储层（SecureStorage 凭证 + PreferencesStorage 设置）
domain/           领域模型（AuthTypes 等）
utils/            工具（SM2Crypto/EncodingUtils/CryptoUtils/Logger）
```

**数据流**：`页面 → SessionManager/CampusDataService → TsinghuaAuthService/HttpClient → 清华服务器`。UI 不直接碰网络，全部经服务层。

---

## 3. 核心链路详解

### 3.1 统一身份认证链路（`TsinghuaAuthService.ets`）

这是整个项目最核心、最易出错的部分。**顺序不可调整**，每步依赖前一步写入的 Cookie。

```
login(credentials)
 ├─ clearSession()                        清旧 Cookie，避免污染
 ├─ GET WEBVPN_OAUTH_LOGIN_URL ×2        预热：让 WebVPN→OAuth→ID 链落到登录表单
 ├─ 提取 sm2publicKey（#sm2publicKey 元素文本）
 ├─ SM2 加密密码（encryptPassword，输出需 DER→裸格式 04||C1x||C1y||C3||C2）
 ├─ POST ID_LOGIN_URL                    i_user/i_pass/fingerPrint/fingerGenPrint/fingerGenPrint3/i_captcha
 │    ├─ 含「二次认证」→ 返回 TWO_FACTOR，UI 走 verify2FACode 续链
 │    └─ 含「登录成功。正在重定向到」→ 成功（设备被信任时跳过 2FA）
 ├─ follow callback href                 建立 WebVPN 会话（仅用一次，重复消费会清会话）
 ├─ roamIdPolicy(INFO_PORTAL_YYFWID)     建立 info 门户会话（校园通用门户漫游）
 └─ activateLearnSession                 learn 域激活（见下）
```

**learn 域激活**（`activateLearnSession`）：

```
GET  ID_BASE_URL + LEARN_LOGIN_YYFWID   取 learn 登录表单 + SM2 公钥
POST ID_LOGIN_URL                       learn yyfwid 的 ID 登录
提取 callback → ticket（callbackUrl 末段 = 号后部分）
GET  learnAuthRoam?ticket=…             建立 learn.tsinghua.edu.cn 域会话（关键！）
GET  learnStudentHome                   学生首页
提取 _csrf（正则 &_csrf=(\S+?)["'&]）    后续 learn API 的 CSRF token
```

**2FA 二次认证**（`verify2FACode`）：`DOUBLE_AUTH_URL` 端点，`action=SEND_CODE/VERITY_CODE`，`type=mobile/wechat/totp`。验证成功后先 `saveFinger`（信任设备，**必须在 redirectUrl 之前**），再 follow redirect → 续主链。

### 3.2 判定标记（极易错，务必用对）

| 标记 | 值 | 说明 |
|------|----|----|
| `LOGIN_SUCCESS_MARK` | `登录成功。正在重定向到` | 登录成功页（带后缀，不是裸「登录成功」） |
| `TWO_FACTOR_MARK` | `二次认证` | 中文文本，**不是** URL 路径 `/b/doubleAuth/login` |

> **教训**：曾把 learn 激活返回的「登录成功页」误判为 2FA 页（因其内嵌 `/v2/dist/doubleauth/` JS）。用错判定标记会导致完全错误的流程分支。

### 3.3 自动登录（`SessionManager.tryAutoLogin` + `Index.ets`）

- `SecureStorage` 持久化 `studentId:password:fingerprint`（**fingerprint 复用**，避免设备信任数超限）。
- 启动时 `Index.aboutToAppear` → `tryAutoLogin`：读凭证 → 执行完整 `login()`（设备被信任则跳过 2FA）→ 静默重建会话。
- Cookie **不持久化**（内存态），所以每次冷启动都要重新 `login()`；fingerprint 持久化使 2FA 可跳过。
- **注意**：`aa start` 热启动不触发 `aboutToAppear`，自动登录只在冷启动（`force-stop` 后）执行。

### 3.4 校园数据接入（`CampusDataService.ets`）

| 方法 | 端点/方式 | 说明 |
|------|-----------|------|
| `fetchCourses` | `getCurrentAndNextSemester` → `loadCourseBySemesterId/{id}/zh` | 先取真实学期 ID，再取课程（URL 含 `/wlxt/` 段，易漏） |
| `fetchHomework` | POST `zyList{Wj/Yjwg/Ypg}` + `aoData` | 按课程遍历 3 状态端点（未交/已交未批改/已批改） |
| `fetchNotifications` | POST `pageListXsby{Wgq/Ygq}` + `aoData` | 内容 `ggnr` 是 Base64 编码 HTML |
| `fetchFiles` | GET `kjxxbByWlkcidAndSizeForStudent` | `object` 可能是数组或 `{resultsList}`，需兼容 |
| `fetchHomeworkDetail` | GET `viewCj` 页 HTML 解析 | 作业要求（`div.c55`）+ 附件（`div.list.fujian`），平衡 div 提取 |
| `fetchScheduleEvents` | `jxmh_out.do?m=bks_jxrl_all` JSONP | 教务 zhjw 域，需先教务激活（见 §7 问题） |

**learn API 通用规则**：URL 用 `withCsrf(url, csrf)` 拼 `_csrf`；`aoData` 是 `[{"name":"wlkcid","value":"课程id"}]` 的 JSON 字符串，POST urlencoded 提交。

---

## 4. 设计系统（`pages/Theme.ets` + `components/Ui.ets`）

对齐 `docs/CAMPUS_OS_DESIGN_SYSTEM_V1.md` 与原项目 `src/app/theme`：

- **Theme**：完整色板（含各 Muted 变体）；`Space`（4/8/16/24/32/48）、`Radius`（10/14/20/28/999）、`FontSize`（display34→micro11）
- **视觉语言**：浅灰底 `#FAFAFB` + 白卡 `#FFF` + 1px hairline 描边 `borderSubtle` + 大圆角，**无阴影**
- **共享组件**：`ScreenHeader`（Tab 根页头部）、`DetailHeader`（详情页 ‹ 返回 + 居中标题）、`SectionHeader`、`ListCard`（左 2px accent 条）、`StatusBadge`、`MetricPill`、`InfoRow`、`EmptyHint`、`StateBlock`
- **美术资源**：`resources/base/media/` 下 18 张 PNG（从原项目 `campusOS_ui/` 迁移，重命名为小写合规名）

---

## 5. 调试与日志（`utils/Logger.ets`）

- **编译开关**：`Log.d/i/w` 由 `BuildProfile.DEBUG` 控制——debug 构建输出，release 构建屏蔽；`Log.e` 始终输出。
- **误报说明**：`arkts_check` 会对 `import BuildProfile from 'BuildProfile'` 报 "Cannot find module"（它不含编译期生成目录），但 `build_project` 编译正常。**这是已知误报，可忽略。**
- **真机日志**：`hdc shell "hilog -x -T LearnAct"`（`LearnAct` 是认证/数据诊断标签）。
- **常用调试序列**：`aa force-stop com.campusos.app` → 清日志 → `aa start` → 等自动登录 → 收集日志。

---

## 6. 开发注意事项（常见坑）

1. **POST 必须带 Content-Type**：RCP 默认不带 `application/x-www-form-urlencoded`，缺了会导致登录失败（响应异常短）。
2. **GBK 解码**：教务/电费等老系统是 GBK 编码。`HttpClient` 按 content-type 检测，但 zhjw 可能未标记——必要时按 URL 强制 GBK。
3. **SM2 密文格式**：`cryptoFramework` 输出 ASN.1 DER，必须 `derToRawSM2()` 转裸格式 `04||C1x||C1y||C3||C2` 才能被清华 ID 接受。
4. **fingerprint 持久化**：重新生成会导致设备信任数超限（「信任浏览器数量已达上限」）。务必复用 `SecureStorage` 中的值，格式为 32 位无横线 UUID。
5. **callback 只 follow 一次**：含一次性 SSO ticket，重复消费会让 WebVPN 后端清掉刚建立的会话。
6. **learn csrf ≠ WebVPN csrf**：learn API 用 learn 学生首页提取的 `_csrf`；WebVPN 漫游（教务等）用 cookieSync 接口提取的 `XSRF-TOKEN`，两者不同。
7. **ArkTS 严格模式**：对象字面量需类型上下文；JSON 字段用 `Record<string, Object>` + `?? ''` 兜底；`JSON.parse` 后立即 `as` 具体类型。

---

## 7. 已知问题与待办

### 课表（zhjw 教务域）激活 403 —— 调查中

**现象**：课表 `fetchScheduleEvents` 返回 HTML 登录页（`idxBracket=-1`，非 JSONP），`events=0`。

**已排查**：
- 主登录 + learn 激活均成功（`LEARN_CSRF ok`）
- 教务漫游 `ROAMING_URL` 返回 403；`cookieSync` 返回空（无 XSRF-TOKEN）；`infoUserData` 也返回 403

**根因判断**：**info 门户后端会话未真正建立**。尽管 `roamIdPolicy(INFO_PORTAL_YYFWID)` 的 lbredirect 返回 200（`ROAM_LB len=1467 has_sm2=false`），但 `infoUserData` 403 表明 info 会话无效。教务漫游（`roamDefault`）与 cookieSync 都依赖 info 门户会话。

**下一步**：
1. 检查 `roamIdPolicy` 的 lbredirect 响应完整内容（`ROAM_LB_FULL`，已加日志）——1467 字节可能是 meta refresh 跳转页，需进一步 follow。
2. 对比原项目 `verifyInfoSession`（`infoUserData` 校验 `object.ryh === 学号`）确认 info 会话建立的确切步骤。
3. 确认 WebVPN cookie 是否正确写入（`syncCookiesViaXhr` 与 RCP 的 cookie 处理差异）。

### 其他待办

- 课表页 SchedulePage 接入真实课表（当前 Mock，待教务域打通）
- 成绩（GradesPage）真实数据
- 修复 #3 密码明文存储（`SecureStorage` 当前仅 URL-encode，应改用 Asset Store Kit 或加密）
- 课表详情/周视图网格完善

---

## 8. 参考

- 原项目认证文档：`docs/login-to-thu.md`
- 设计系统：`docs/CAMPUS_OS_DESIGN_SYSTEM_V1.md`
- 原项目实现：`src/services/auth/tsinghuaAuth.ts`、`src/services/campus/learningAdapter.ts`、`src/services/webvpn/transport.ts`
