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
| `fetchSemesterInfo` | `getCurrentAndNextSemester result.kssj` | 学期首日（周数计算），有缓存 |
| `fetchGrades` | `cj.cjCjbAll.do?m=bks_cjdcx` HTML 表格 | 漫游 yyfwid 与课表不同；GPA 跳过 P/F（point=NaN） |
| `fetchNewsList` | info 门户 `/b/info/xxfb_fg/xnzx/template/more` JSON | `object.dataList`；webvpn csrf；置顶= `yxzd` 含 `1-` |

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

### 课表（zhjw 教务域）激活 403 —— 已定位根因，待验证（2026-09-19 修复）

**现象**：课表 `fetchScheduleEvents` 返回 HTML 登录页（`idxBracket=-1`，非 JSONP），`events=0`。

**已排查**：
- 主登录 + learn 激活均成功（`LEARN_CSRF ok`）
- 教务漫游 `ROAMING_URL` 返回 403；`cookieSync` 返回空（无 XSRF-TOKEN）；`infoUserData` 也返回 403

**根因（对比原项目逐行核对确认，共 3 处差异）**：
1. **`wrapWebVPNUrl` 过度编码**：HarmonyOS 版对 `uri` 做了 `encodeURIComponent`，而原项目（`tsinghuaAuth.ts:903`，照搬 thu-info-lib `getWebVPNUrl`）刻意**不编码**且对 `oauth.tsinghua.edu.cn` URL 早返回。编码后 lbredirect 转发的 URI 被破坏 → `roamIdPolicy(INFO_PORTAL_YYFWID)` 建立的 info 门户会话无效 → infoUserData / cookieSync / 教务漫游全 403。
2. **XSRF-TOKEN 提取源错误**：原项目从 cookieSync **响应体**正则提取（`/XSRF-TOKEN=([^;]+);/`，`transport.ts:294`），HarmonyOS 版误从 Set-Cookie 头/cookie 管理器提取 → 拿不到。
3. **infoUserData 探针缺 `_csrf`**：原项目 `verifyInfoSession` 带 `?_csrf=`，HarmonyOS 版不带 → 必然 403（假阴性）。

**修复**（2026-09-19）：
- `WebvpnConstants.ets wrapWebVPNUrl`：去掉 `encodeURIComponent`，加 oauth 早返回
- `CampusDataService.getWebvpnCsrf`：改为解析 cookieSync 响应体（cookie 管理器作回退）；新增 `verifyInfoSession`（带 `_csrf`，校验 `object.ryh === 学号`）
- `HttpClient`：增加 `GBK_URL_MARKERS` 按 URL 强制 GBK 解码（对齐原项目 `GBK_WEBVPN_TOKENS`，zhjw 不声明 charset）
- `fetchScheduleEvents`：JSONP 无 `[` 时重置 `registrarRoamEnsured`（会话自愈）

**验证（已通过，2026-09-19）**：用户实测同步消息"已同步 7 门课程 · 待办 1 · 未读 1"无课表警告（周六空课表正确显示"今日无课程安排"），统计 pill 显示 0/1/1 —— zhjw 教务域链路已打通。
- 顺带修复：`MetricPill.value` 未加 `@Prop` 装饰器，父组件 `@State` 更新不传导（子组件普通成员只初始化一次）——统计恒为 0 的根因。
- `scheduleStatus`（ok/error）区分"课表拉取失败"与"今日真的无课"。

### 课表页/成绩/资讯真实数据接入（2026-09-19）

- **SchedulePage**：真实周课表 —— `fetchSemesterInfo()`（learn `getCurrentAndNextSemester result.kssj` 学期首日）算学期周数；`fetchScheduleEvents(周一, 周日)` 拉整周；事件按 `kssj` 起始时间映射 6 大节（08:00/09:50/13:30/15:20/17:05/19:20，`periodIndexFor` 分桶）；‹ › ±12 周导航，点中间回本周；演示模式保留内置示例。
- **GradesPage**：`fetchGrades()` —— 漫游 yyfwid `B7EF0ADF9406335AD7905B30CD7B49B1`（与课表不同）→ GET `cj.cjCjbAll.do?m=bks_cjdcx&cjdlx=zw&flag=di1`（zhjw token URL 自动 GBK 解码）→ 正则解析 `<table cellspacing=1>`（bks 列序 3/5/7/9/11 = 课名/学分/等级/绩点/学期）→ GPA 计算：point 为 NaN（P/F）不计学分绩，`allCredit` 含 P/F（对齐原项目 `grades.ts computeGpa`）。失败可重试。
- **NewsPage**：`fetchNewsList(page, length)` —— info 门户 `/b/info/xxfb_fg/xnzx/template/more?oType=xs&lydw=&_csrf=..&lmid=all`，解析 `object.dataList`（bt/time/dwmc_show/lmid/yxzd），置顶（yxzd 含 `1-`）显示"置顶"标签，栏目标签取 `NEWS_CHANNEL_LABELS`。失败可重试。
- 漫游重构：`roamByYyfwid(yyfwid)` 通用化，`ensureRegistrarRoam`/`ensureGradesRoam` 分别缓存。

### 首页天气 + 快捷操作真实跳转（2026-09-19）

- **WeatherService**（`services/campus/WeatherService.ets`）：Open-Meteo 公共 API（免登录免 key，坐标清华园 39.9593,116.2985），`fetchHomeWeather()` 带 30 分钟模块级缓存；`describeWeatherCode` WMO 码→中文；`buildWeatherSubtitle` 生成"海淀 23° · 晴 · 今日 18/30°（· 建议带伞）"。rcp 直连，与 webvpn 无关。
- **ScreenHeader.subtitle 加 `@Prop`**：与 MetricPill 同款问题（未装饰成员不随父 @State 更新）——首页天气与课表页周导航副标题由此跟随刷新。
- **快捷操作跨页导航**（`state/UiEvents.ets`，emitter 总线 `EVT_NAVIGATE`）：NavTarget{tab, campusSub, learningTab}；Index（切底部 Tab）/CampusPage（开子页）/LearningPage（切子标签）各自订阅，aboutToDisappear 反订阅。"查空教室"→校园·空闲教室子页，"添加 DDL"→学习·作业标签；"图书馆座位"未接入保留 toast。
- HomePage 两处弃用 `promptAction.showToast` 改为 `getUIContext().getPromptAction()`（SettingsPage/LoginPage/LearningPage 的同类 WARN 暂未处理）。

### 真实数据三缺陷修复：课表乱码 / GPA 0.00 / 资讯实体（2026-09-19 第三轮验证反馈）

- **课表课程名乱码**（HttpClient.ets）：旧逻辑 `isGbkUrl(url)` 命中即强制 GBK，一票否决响应头 charset；而 webvpn 会把部分 zhjw 响应（如课表 `jxmh_out.do` JSONP）重编码为 UTF-8 → 中文全乱。改为对齐原项目 `transport.inferResponseCharset` 优先级：**响应头 charset 优先**（`charsetFromContentType` + `isGBKContentType`）；头无声明才按 URL 标记回退 GBK，且加严格 UTF-8 字节校验嗅探（`hasNonAsciiByte && !isValidUtf8` 才 GBK）——GBK 中文响应体几乎不可能整段通过校验。GBK 路径打 hilog（tag `HttpClient`）。
- **GPA 0.00**（CampusDataService.ets）：原项目 `htmlSelect.childText(tr, N)` 按 cheerio **子节点序**取值——children 含标签间换行缩进**文本节点**，`childText(tr,3/5/7/9/11)` 实为第 2/3/4/5/6 个 td。我们旧版只数 td 且 `cells.length < 12` guard 把所有行滤光 → 空报表 GPA 0.00。重写 `parseGradeTableChildren/parseGradeRowChildren`（文本节点与 td 各占一席），守卫改 `children.length < 12`，并打 row0/row1 诊断日志（tag `LearnAct` `GRADES row0=[..]`）。顺带修 `Number('')=0` bug：绩点空列 → NaN（P/F 课不计学分绩）。
- **资讯 `&ldquo;` 未解码**：`decodeHtmlEntities` 补 NAMED_HTML_ENTITIES 映射（ldquo/rdquo/mdash/ndash/hellip/middot/bull/times/copy/deg 等 20 项）；解码顺序=数值 → 命名（不含 amp）→ `&amp;` 最后（防 `&amp;ldquo;` 二次解码）；fetchNewsList 调用点去掉冗余外层 decodeNumericEntities。

### 资讯详情视觉打磨 + 会话失效修复（2026-10-11）

- **视觉打磨**（NewsPage）：标题/元信息（栏目徽标/来源/日期）加载中立即可见（列表标题兜底，对齐原项目 `detail?.title || news.name`）；加载完成由 HTML 文档内同款样式接管，标题随正文一起滚动（对齐原项目 ScrollView 结构）；正文白卡（radius 20 + hairline 边框）浮灰底；加载/错误态内联；注入文本 `escapeHtml` 转义；演示正文 `\n→<br>` 同卡渲染。
- **会话失效连锁修复**（校园卡使用后资讯全挂 403 的根因链）：
  1. `getWebvpnCsrf` **去缓存每次现取**（对齐原项目 `transport.getCsrfToken`）——旧缓存在完整重登录后持有过期 XSRF-TOKEN，导致所有 info 门户请求 403 且无法自愈；
  2. `fetchNewsList` 包 `withSessionRecovery` + 非 JSON 响应给可读错误（此前 403 HTML 直接抛 `Unexpected Text in JSON` 给用户）；
  3. `doFetchNewsDetail` 401/403 抛错触发恢复（此前错误页会被 `adaptNewsHtml` 当正文渲染）；
  4. `CampusCardService.withCardRetry` 快照只比对 `accountUser`（**有意偏离参考实现**：`getCampusCardInfo` 在 operation 内合法写入 `accountCardId`，参考连 cardId 一并比对导致首调必误判"登录态被并发修改"、空跑 3 次登录 + 1 次完整重登录，连锁触发上述过期 csrf 问题）。
- **按钮边距**：校园财务/宿舍电费"去充值"按钮 `width('90%')` 在 `alignItems(Start)` 父容器下贴左——改卡片同款 `width('100%') + constraintSize({maxWidth:'100%'}) + 左右 margin 16`。

### 校园网接入（2026-10-11）

- **CampusNetworkService**（`services/campus/CampusNetworkService.ets`）：WebVPN 校园网自助服务（token `7772647…`，与 info 门户同一 WebVPN 会话，无需独立漫游）。
  - **快照**：`getNetworkSnapshot()` = 探测登录入口页（WebVPN 登录页标记=会话失效；`loginform-verifycode`=需验证码）→ 首页（`#w3-container` 余额表、`#w1-container` 设备表、状态图标父文本）→ `users`（`#w0` 账户表，按序 0/1/2/3/5/6/7）→ `user/online-num`（允许设备数取图标父文本首个数字）；整体 `withNetworkRetry`（探测 + `withSessionRecovery(…, 'campus-network')` 两层恢复，对齐原项目 `withNetworkRetry`）。
  - **注销**：`logoutNetworkDevice(key, mac)` —— 首页提取 `input[name=_csrf-8800]` → `postForm` 携带 CSRF 至 `home/delete?id=&user_mac=`（查询参数百分号编码）→ `w5-success-0` 判成功 / `w5-danger-0` 取失败文本。
  - **正则解析**：复刻参考 DOM 选择语义，无三方依赖；`tableInnerById` 兼容 id 在 table 上（`#w0` DetailView）与外层容器上（`#w1-container`/`#w3-container` GridView）两种形态；`iconParentText` 向前栈式扫描取图标父元素文本。
  - **验证码**：命中标记抛 `NetworkCaptchaRequiredError`（稳定 code + `isNetworkCaptchaRequiredError` 判别），页面进验证码登录态——图片验证码登录见下方「校园网图片验证码登录」增量。
- **NetworkPage 重写**：余额/用量 hero（产品名/已用流量/已用时长/余额/结算日期）→ 账户信息 9 字段（空值"—"）→ 在线设备列表（IPv4/IPv6/登录时间/权限/MAC + 空态）；注销 `AlertDialog.show` 二次确认（文案含权限、掩码 IP/MAC 与断网提示）+ 行内 busy + toast + 重载；右上角刷新加载中转圈；错误/验证码引导态可重试。演示模式内置示例，零网络请求。
- `SessionManager.getNetworkService()` 单例接线（与 `getCampusCardService()` 同构）。

### 图书馆座位（只读）接入（2026-10-11）

- **LibrarySeatService**（`services/campus/LibrarySeatService.ets`，对齐原项目 `library.ts`）：
  - 子系统会话：id 漫游 `roamIdSubsystem`（yyfwid `ef84f6…/0?/api/id_tsinghua_callback`）+ 已激活标记 + 首个 home 请求失败忽略；读取统一包 `withLibRetry`（两层 `withSessionRecovery`，reroam = 重置标记 + 强制重漫游，label `lib`）。
  - 接口（纯 JSON，`api.php/areas|areadays|spaces_old`）：失败标记 `status='false'` → 抛服务端 msg；`data.list` 缺失 → 可读错误。
  - 楼层使用率：楼层自身无总数，由其开放子区域聚合（可用 = max(0, TotalCount − UnavailableSpace)）；并发拉取（任务数组发起后逐个 await，规避 `Promise.all`）、单层失败容错为 0、未开放层不发请求。
  - 座位查询：先 `areadays/{sectionId}` 命中目标日拿时段 id 与起止（今天起始时间钳制"当前时刻或更晚"），再 `spaces_old` 查座位状态（1 可用/6 已预约/7 已被占用，其余不可用）。
  - 我的预约：`user/index/book` HTML 表格正则解析（复刻 cheerio children 语义，childText 索引 3/5/7/11）；无 tbody 且无记录抛可读错误。
- **LibrarySeatPage**（`pages/campus/LibrarySeatPage.ets`）：页内多级浏览（馆 chips + 今天/明天切换 + 楼层使用率 → 区域（可用/总数/已预约）→ 座位状态 + 我的预约/空态）；标题随层级变化（自绘 HeaderBar——自定义组件普通成员只初始化一次，动态标题不能经 `DetailHeader` 传入）；系统返回经 `BackDispatcher` 逐级 pop；右上角刷新/错误重试按层级重拉；演示模式内置示例零网络请求；只读引导（"预约请前往官方小程序完成"）各层就位。
- **ReservationPage 改造**：图书馆座位卡片 → 内联渲染 `LibrarySeatPage`（返回回到入口卡片）；研读间/体育场馆 → toast"即将支持"（不发起请求）。
- `SessionManager.getLibrarySeatService()` 单例接线（与 `getCampusCardService()` 同构）。

### 校园网图片验证码登录（2026-10-11 第二轮增量）

- **共享能力**（跨模块新增，既有方法零改动）：
  - `HttpClient.getBytes(url)`：GET 响应体**原始字节**（`resp.body` ArrayBuffer → `Uint8Array`，不走文本解码——图片二进制经 charset 解码必损坏；同款 Cookie 注入 + 手动重定向跟随 Location）。
  - `HttpClient.postFormWithHeaders(url, form, extraHeaders)`：urlencoded POST + 自定义请求头（`X-CSRF-Token`/`X-Requested-With`/带 charset 的 Content-Type）；`extraHeaders` 后合并，可覆盖默认 Content-Type；既有 `postForm` 签名未动。
  - `CryptoUtils.rsaEncryptPkcs1(text, pem)`：PEM 体 Base64 → DER → PKCS#1 裸公钥先 ASN.1 包装为 X.509 SPKI（手写 `readAsn1Length/encodeAsn1Length/wrapPkcs1ToSpki`）→ 密钥位数按模数长度推断（256B→RSA2048，向上取整到 1024 倍数）→ `convertKeySync` + `createCipher('RSA2048|PKCS1')`（**PKCS#1 v1.5**，对齐参考 JSEncrypt 默认填充）→ Base64。
  - `CampusDataService.roamByYyfwidHtml(yyfwid)`：既有 `roamByYyfwid` 的 HTML 变体（webvpn csrf → onlineAppRedirect → roamingurl → 落点页），返回落点页 HTML；失败返回空串不抛；既有 `roamByYyfwid` 未动。
- **验证码登录**（CampusNetworkService，对齐原项目 `network.ts` fetchNetworkCaptchaBase64 / loginNetworkWithCaptcha）：
  - `fetchCaptchaImage()`：`site/captcha?refresh=1` 预热（触发新验证码并落 Cookie）→ `?_=<Date.now()>` 一次性取图规避缓存 → Base64 data URI（`data:image/png;base64,…`）。
  - `loginNetworkWithCaptcha(code)`：① 空输入拦截 → ② 登录页提取 `meta[name=csrf-token]` / `input[name=_csrf-8800]` / `#public`（RSA 公钥 PEM；属性值内 `&#10;` 等实体先 `decodeEntities`）→ ③ `roamByYyfwidHtml(USER_INFO_YYFWID)` 从 `'addr':'…@mails.tsinghua.edu.cn'` 提取邮箱前缀为账号名 → ④ `rsaEncryptPkcs1` 加密 WebVPN 密码 → ⑤ `postFormWithHeaders` 调 `site/validate-user`（JSON `success` 必须为 true，否则透出服务端 message）→ ⑥ `postForm` 提交登录表单（`LoginForm[username/password/verifyCode/smsCode]` + `_csrf-8800`）→ ⑦ 复探测确认（仍见验证码表单 = 登录未生效）。
  - **有意偏离**：单发**不套 withNetworkRetry**——探测在验证码态必抛 `NetworkCaptchaRequiredError`（等于必失败），且会话恢复重试可能重复提交登录表单（错验证码二次提交）；错误一律可读中文直接抛给页面。
- **NetworkPage 验证码态**：进入自动取图；图片点击或「换一张」手动刷新；输入框回车即提交；提交中按钮禁用（`登录中…`）；成功 toast + 退出验证码态 + 自动 `load()` 重载数据；失败 toast + **自动换图** + 清空输入（验证码一次性，旧图作废）；「重试原查询」保留。演示模式零网络请求，永不进验证码态。

### 研读间（只读 + 子系统登录）接入（2026-10-11）

- **共享能力（跨模块新增，既有方法零改动）**：
  - `HttpClient.resolveFinalUrl(url)`：GET 跟随重定向返回**最终落点地址**（同款 Cookie 注入 + 手动重定向循环，等价 XHR responseURL；研读间 cab 登录解析动态标识用）。
  - `TsinghuaAuthService.cabLogin()`：研读间专用登录——cab 登录链路要点：①请求 `ic-web/auth/address` 取**动态认证地址**（JSON 取 data 地址字段，纯地址文本兼容）→ ②非 WebVPN 域做等价前缀替换（cab.lib 根地址 → WebVPN 前缀）→ ③`resolveFinalUrl` **跟随重定向**取最终地址 → ④正则 `/\/login\/form\/(.+)$/` 解析登录标识（**保留 `?`/`#` 之后完整尾串**，截断会让会话失效）→ ⑤`roamIdSubsystem(标识)` **复用既有 id 漫游** → ⑥`ic-web/auth/userInfo` **账号校验**（业务码 0 且 `data.pid` 与当前学号一致，否则抛可读错误）。
- **LibraryRoomService**（`services/campus/LibraryRoomService.ets`，对齐原项目 `library.ts` cab 部分）：
  - 会话装配：`cabLoginEnsured` 标记 + `cabAccNo` 账号号缓存 + `assureCabSession` **最多两轮复查**（失败强制重登后再读用户信息比对学号，仍失败抛可读错误）+ `withCabRetry`（`withSessionRecovery(op, reroam{标记复位 + 强制 cabLogin}, 'cab')`——**勿用默认 info 门户 reroam**，恢复后访问不到研读间子系统）。
  - 接口（ic-web 纯 JSON，业务码非 0 抛服务端 message；非 JSON 抛可读错误附截断片段）：类型 `roomDevice/roomInfos`、资源 `reserve?sysKind=1&resvDates=yyyyMMdd&kindIds=`、我的预约 `reserve/resvInfo?needStatus=8454&orderKey=gmt_create&orderModel=desc&beginDate=&endDate=`（查询窗口"今天 → +6 天"）。
  - 日期：近 5 天（今天起偏移 0–4）；展示 `YYYY-MM-DD`（`formatLibRoomDateIso`）、请求 `yyyyMMdd`（`formatLibRoomDateYmd`）。
- **LibraryRoomPage**（`pages/campus/LibraryRoomPage.ets`）：页内多级（类型卡（"N 个房间 · 点选查看近 5 天"）点击展开近 5 天日期项 → 当天资源（房间名（`maxUser>1` 附"最少~最多人"）、类型名、开放时间、"可浏览/未开放"徽标（`kindName` 含"暂未开放"视为未开放））+ 我的预约（房间/日期起止/成员文本）/空态）；标题随层级变化（自绘 HeaderBar——动态标题不能经 `DetailHeader` 传入）；系统返回经 `BackDispatcher` 逐级 pop；右上角刷新加载中转进度；各态加载（首次"正在建立研读间会话…"）/错误（可重试）/空态；演示模式内置示例零网络请求。
- **ReservationPage 改造**：研读间卡片 → 内联渲染 `LibraryRoomPage`（返回回到入口卡片）；体育场馆 → toast"即将支持"。
- `SessionManager.getLibraryRoomService()` 单例接线（与 `getLibrarySeatService()` 同构）。

### 体育场馆（只读）接入（2026-10-11）

- **SportsService**（`services/campus/SportsService.ets`，对齐原项目 `sports.ts`）：
  - 子系统会话：**通用漫游** `CampusDataService.roamByYyfwidHtml(SPORTS_ROAM_PAYLOAD)`（yyfwid `5539ECF8…`）+ `sportsSessionEnsured` 已激活标记；读取统一包 `withSportsRetry`（`withSessionRecovery(op, reroam{标记复位 + 强制重漫游}, 'sports')`）。
  - **落点地址映射**：webvpn roamingurl 为**原始主机** `50.tsinghua.edu.cn`（非 WebVPN 域）——`CampusDataService.parseToWebVPN` **加法式**补充体育场馆主机映射（包装为 gymbook webvpn token 前缀，不改既有 zhjw 分支）；`roamByYyfwidHtml` 落点日志补 `finalUrl` 便于核对。
  - **GBK 解析**：gymbook 子系统 token 已在 `HttpClient.GBK_URL_MARKERS`（响应头无 charset 时按 URL 标记回退 GBK + 严格 UTF-8 嗅探），中文零乱码。
  - 资源页为**脚本驱动 HTML（非 JSON）**：四类脚本调用按资源标识合并——`resourceArray.push({…});…resourcesm.put(id,hash)`（push.id 与 put 键一致才收录）、`addCost`（费用）、`markResStatus`（预约标识/锁定）、`markStatusColor`（用户类型/支付状态）。
  - 限额：资源首页脚本变量**多形态匹配**（`var x='n'` / `"n"` / 裸数字 / 不带 var），缺失抛可读错误。
  - `getSportsResources`：并发取"限额 + 联系电话 + 资源列表"（联系电话约定值 `do_not`/接口失败 → 空，**不阻塞资源加载**）。
  - 记录：未支付订单按 **td 计数列序 1/3/5/7/9** 取名称/场地/时间/价格/支付方式（参考本地 `cellText` 按 td 计数，**与 cheerio 子节点序不同，勿混用**）；行内脚本 `payNow`/`unsubscribeOnline`/`unsubscribe` 提取支付/预约标识；已支付订单 `tr[display:none]` 内嵌行（列序 2/3/4/5）合并；逐行容错 + 首行诊断日志核对列序。
  - **只读边界**：下单/支付/退订不迁移（`makeSportsReservation` 等不移植）。
- **SportsBookingPage**（`pages/campus/SportsBookingPage.ets`）：页内两视图（RESOURCES：固定 8 场馆 chips（默认第一个）+ 近 7 天日期行（默认今天）+ 限额/联系电话卡（仅服务端返回时展示）+ 资源列表（时段/场地/费用/可预约/已锁定/不可预约徽标）+ 我的预约记录入口 → RECORDS：未支付 + 已支付合并列表（可支付/可取消标注）/空态）；标题随视图变化（自绘 HeaderBar——动态标题不能经 `DetailHeader` 传入）；系统返回经 `BackDispatcher` 逐级 pop；右上角刷新加载中转进度；演示模式内置示例零网络请求；只读引导（"下单与支付请通过官方渠道完成"）就位。
- **ReservationPage 改造**：体育场馆卡片 → 内联渲染 `SportsBookingPage`（返回回到入口卡片）；至此场馆预约三卡片（图书馆座位/研读间/体育场馆）全部接入只读查询。
- `SessionManager.getSportsService()` 单例接线（与 `getLibrarySeatService()` 同构）。

### 清华邮件（Coremail 读写）接入（2026-10-11）

- **MailService**（`services/campus/MailService.ets`，对齐原项目 `src/services/campus/mail.ts`）：
  - 会话（`ensureMailSession`）：①`auth.hydrateCredentials()` 校验登录 → ②`campus.roamByYyfwidHtml(INFO_PORTAL_YYFWID)` 建立信息门户会话（失败返回空串不阻断）→ ③对 [邮箱门户地址（webvpn info 门户 `roamingToApp?yyfwid=清华邮箱yyfwid`）, `mails.tsinghua.edu.cn/coremail/XT/index.jsp`] **双路径**依次 `HttpClient.resolveFinalUrl` 取最终地址并解析 sid（URL 参数优先 → 落地页正文 → Cookie 池兜底）→ ④再取一次完成落地（刷新 Cookie）→ ⑤内存缓存约 20 分钟。
  - 会话自愈：响应错误码 `FA_INVALID_SESSION`/`FA_SECURITY` → 清缓存强制重建**一次**后重试；`result=error` 或 `FA_*` 码 → `coremailErrorMessage` 转可读中文（messages 摘要拼接）。
  - 接口：JSON POST 走 `HttpClient.postJsonRaw`（**加法式新增**：`/coremail/s/json?sid=..&func=..`）；urlencoded 走既有 `postFormWithHeaders`（`/coremail/s?sid=..&func=..`）；公共头 `X-Requested-With: XMLHttpRequest` + `Accept`。
  - 列表多形态回退：`[mbox:listThreads×date, listThreads×receivedDate, mbox:listMessages×date, listMessages×receivedDate]` 全空再试兼容 XML（RPC url + `{var: xml}`）；"总数>0 但解析 0 条"抛可读错误。解析容错：递归寻找邮件数组/总数（深度 6/5）、逐条失败跳过、联系人三形态（字符串/对象/数组）。
  - 读信 `readMessage`（修复轮 R1）：form/RPC 端点优先（`/coremail/s?sid=..&func=!readMessage` + urlencoded 体 `mid/mboxa` + `Content-Type: application/x-www-form-urlencoded; charset=UTF-8`），失败回退 `func=readMessage`（同端点同体）；载荷映射 `payload.mail|message|payload` 与 `payload.mailInfo|info` 双取源，正文 `content|html|text`，附件 `attachments|attachInfos`（字段 `id|attachId`、`name|fileName|displayName`、`size`、`part`）。搜索 `mail:searchMessages` 同改 form/RPC 优先（`!` 前缀 → 无前缀），JSON 端点仅作最后回退（体 `start/limit/pattern/summaryWindowSize/mboxa`）。写操作 `mbox:updateMessageInfos`（标记已读/移动）、`mbox:deleteMessages`、`mbox:compose`（compose 初始化 → `action=deliver` 发送）。
  - 列表附件标记（修复轮 R1 结论）：`parseMessage` 派生链对齐参考（`attached|hasAttachment|attach|attr.attached|attr.hasAttachment|envelope.hasAttachment ?? attachments.length`）；实测上游列表接口不返回任何附件线索 → 列表附件标记退化为"未知"（不显示标记、不伪造），附件以详情页元信息展示为准（日志 `LIST ... attFlag=` 可观察）。
  - `syncCoremailCookiesForWebView()`：Coremail 域会话 Cookie → `webview.WebCookieManager.configCookieSync`（受控 Web 内嵌图片鉴权，对齐 NewsPage 的 webvpn Cookie 同步做法）。
- **页面三件套**（`pages/campus/MailPage.ets` / `MailDetailView.ets` / `MailComposeView.ets`）：
  - **MailPage**：页内多级 LIST/DETAIL/COMPOSE（详情/撰写整页切换，自带 DetailHeader）；文件夹 chips（收件箱/草稿箱/已发送/已删除/垃圾邮件）+ 未读计数 + 列表（发件人/主题/摘要/时间/未读圆点/附件标记）+ 加载更多（id 去重追加）；搜索框（空关键词=清除恢复文件夹视图，结果复用列表渲染）；列表长按 ActionSheet（删除/移动）；演示模式内置示例**零网络请求**。
  - **MailDetailView**：纯文本原生直显；富文本受控 Web（CSP 禁脚本/图片放行 + 禁缩放 + 禁文件访问 + 关暗色 + `loadData` 五参 baseUrl=mails.tsinghua.edu.cn，配合父级同步的 Coremail Cookie）；附件元信息（名称/大小）；底部删除/移动操作条（确认流程由父组件执行）。
  - **MailComposeView**：收件人/抄送/主题/正文输入 + 必填校验（收件人、主题，缺失 toast 不发请求）+ AlertDialog 发送前二次确认；失败保留已填内容并展示服务端消息。
  - **写操作确认**：删除 `AlertDialog.show` 二次确认；移动 ActionSheet 选目标文件夹 → AlertDialog 确认；打开未读邮件自动标记已读（失败不阻塞阅读，仅日志 + 轻提示）；成功 toast + 刷新当前列表（搜索模式重搜索）。
- `SessionManager.getMailService()` 单例接线（与 `getLibrarySeatService()` 同构）。

### 校园卡余额/信息/流水（2026-10-10）

- **CampusCardService**（`services/campus/CampusCardService.ets`）：card.tsinghua.edu.cn 直连域（不走 webvpn 包装）。
  - **登录**：`TsinghuaAuthService.roamCardPolicy` —— 与 `roamIdPolicy` 同款 ID 两循环登录，但 callback 直连获取（card 域 Cookie 必须落在 card.tsinghua.edu.cn）；payload `eea30c…/0?/userindex`。
  - **会话**：`ensureCampusCardLogin`（getUserInfoFromToken 取 loginuser，空则抛错）+ `assureCampusCardSession`（探针比对 loginuser）+ `withCardRetry`（两层 `withSessionRecovery`，含登录态快照校验防误判）。
  - **响应解密**：`business/getCardUserinfo`/`querySelfTradeList` 返回 `success` + `data`（AES-128-ECB-PKCS7，Base64）：key=前 16 字符明文，其余 Base64 解密（`CryptoUtils.aesEcbDecryptBase64`，`convertKeySync` 需 `DataBlob` 包装）。
  - **postJson**：`HttpClient` 新增 `JsonBodyValue`（string|number|boolean）联合类型 + `postJson`（ArkTS 禁原始类型装箱进 `Record<string, Object>`）。
- **FinancePage 重写**：余额 hero（最近交易 footer）→ 校园卡信息（姓名/院系/卡号打码/状态/单笔/日限额）→ 近 7 天流水（30 条封顶，充值/圈存等入账绿色 +，消费原色 -；标题 name→summary→txName 链）；信息与流水同一 try（信息成功即渲染，流水失败不抹掉信息）；充值链不迁移（支付宝），按钮 toast。演示模式内置示例。
- 卡号打码 mask（空→`—`，≤4→`****`，否则 `ab***yz`）；交易时间 `MM-DD HH:mm`。

### 校园服务真实数据接入（2026-09-20，六项分步推进）

- **资讯详情**：info 门户 `/b/info/xxfb_fg/xnzx/template/detail?_csrf=..&xxid=..`，正文 HTML 经 `stripScriptBlocks/fixNewsAssets` 清洗后 ArkWeb `loadData` 渲染（raw + utf-8 + baseUrl + 第 5 参 historyUrl，缺省 401）；附件列表可复制链接。
- **成绩学期分组**（GradesPage）：按学期分组渲染，分组头显示该组 GPA（Σcredit×point/Σcredit，P/F 计学分不计绩点），整体 GPA 沿用服务器 `report.gpa`。
- **空闲教室**（ClassroomPage）：zhjw `jxmh_out.do` 教室状态查询，超时标记（`time out用户登陆超时…`）检测 + `withSessionRecovery` 会话自愈；楼名搜索 `gb2312PercentEncode`（`util.TextDecoder.create('gbk')` 运行时暴力构建反查表）；固定 6 大节/天。
- **体测成绩**（PETestPage）：zhjw `tyjx.tyjx_tc_xscjb.do?m=jsonCj` 解析 27 项 + 参考成绩加权公式。⚠️ 已知问题：该端点实测返回 JSONP 括号包裹 `({'success':'false'})`，原 RN 版行为一致（同样失败），暂按上游行为保留，页面错误态可重试。
- **宿舍电费**（DormitoryPage）：id-roam 电费子系统（yyfwid `0a993…/1`，`TsinghuaAuthService.roamIdSubsystem` 复用登录链 `roamIdPolicy`）→ webvpn 只读页 `Netweb_Home_electricity_Detail.aspx`：剩余电量（lblele）+ 房间信息（input value 提取）+ 缴费记录（myTable 正则）。登录页检测会话失效自动重漫游；余额核心 await，房间/记录失败不阻塞（对齐原项目 allSettled）。充值链不迁移，按钮 toast 提示走网页。用户实测余额/房间/记录正常。
- **UI 边界修复**：宿舍页卡片 `width('100%')` + 左右 margin 导致右缘溢出，补 `constraintSize({ maxWidth: '100%' })`（对齐 HomePage 模式）。

### 设置页功能对接（含 i18n 框架）（2026-10-11）

- **偏好持久化（修复"假设置"根因）**：`state/SettingsManager.ets` 三个 setter（`setDemoMode`/`setTrustDevice`/`setLocale`）改为**写内存后立即异步持久化**（`StateManager.saveSettings`，失败记日志不抛；新增 `flush(): Promise<boolean>` 供页面可读提示），签名与语义不变。新增 `ensureLoaded()`（幂等一次性加载 `StateManager.init`），由 `EntryAbility` 在**装载首页之前**调用——此前 `StateManager.init` 从未被调用、设置从不回读，持久化无从谈起。演示模式写内存即全应用生效（既有判定读同一设置对象，无需广播）。
- **i18n 分期**：本轮交付**框架 + 设置页双语化**；其余页面**后续批次**迁移（未迁移页面保持中文）。
  - `utils/I18n.ets`：词典 `key → {zh, en}` 成对（`SETTINGS_DICTIONARY`）；`t(key)` 回退链=当前语言 → 中文 → 可读占位 `—`（禁止空白/键名外泄）；`setLocale` 仅接受 `zh`/`en`（非法回退 `zh`）→ 写 **AppStorage 键 `'locale'`** → 经 `SettingsManager.setLocale` 持久化（单一写入路径）；`init()` 启动时把持久化 locale 灌入 AppStorage（EntryAbility 调用，先于任何 `@StorageLink('locale')` 绑定）。
  - 设置页全部文案走 `I18n.t('settings.xxx')`，以 `@StorageLink('locale')` 订阅语言变化**即时重渲染**；后续页面迁移只需扩词典 + 同款 StorageLink。
- **退出登录**：`AlertDialog.show` 二次确认 → `SessionManager.logout()`（注销会话）→ `SecureStorage.clearCredentials()`（清除本地凭证）→ 成功 toast；异常可读提示。凭证与会话标记双清后**冷启动不再自动登录**。
- **数据清理**：`storage/LocalDataCleaner.ets` 集中管理清理项（键名不散落页面）——`clearAiConversations()`/`clearLearningCache()` 基于既有 `StorageKeys`（AI 会话/学习缓存两个占位键，当前无模块写入，正常返回 0）；返回清理条数（JSON 数组按元素数计、非数组按 1 计、空为 0），失败不抛返回 0。设置页入口 + 二次确认 + 结果提示（含清理项与条数，无数据亦提示"未发现可清理的本地数据"）。
- **版本号**：设置页改读**自身应用包信息** `bundleManager.getBundleInfoForSelf(GET_BUNDLE_INFO_DEFAULT).versionName`（来源 `AppScope/app.json5` 的 `versionName`，禁止硬编码）；读取失败回退可读占位（"版本未知"）。
- **"暂不支持"三项**：AI 记忆 / 操作记录 / 智能监控 → 新 `UnsupportedRow` 禁用态行（muted + 无 › 无点击），移除"已保存偏好/查看最近操作/管理提醒监控项"等误导文案与"开发中"toast。
- **账号信息（只读）**：学号取自本地凭证（`SecureStorage.getCredentials`）；姓名/邮箱无既有获取能力，**省略该行**（不臆造）；未登录/演示模式展示对应状态文案。
- **弃用 API 清理**：SettingsPage 弃用 `promptAction.showToast` 全部移除，统一 `getUIContext().getPromptAction().showToast`（LoginPage/LearningPage 同类 WARN 仍保留，待后续批次）。

### i18n 核心骨架 + 高频页迁移（2026-10-13，第一批）

- **范围与键前缀**：底部导航 + 六个高频页全部静态文案迁移完成——`Index.ets`（`nav.*` 底部导航 + `common.exitHint` 退出提示 + `login.restoring` 自动登录等待）、`HomePage.ets`（+`HomeData.ets`，`home.*` 含问候/日期/同步/快捷操作）、`LearningPage.ets`（`learning.*`）、`SchedulePage.ets`（`schedule.*` 含周选择器/星期列/日期区间/状态提示）、`CampusPage.ets`（`campus.*` 入口卡）、`ai/AIChatPage.ets`（`ai.*` 含推荐提问与 mock 回复）、`LoginPage.ets`（`login.*` 含 2FA/错误/演示入口）；通用态用 `status.*`（loading/empty/failed/retry/demo），通用操作用 `common.*`。词典 zh/en 成对，回退链不变（当前语言 → 中文 → `—`）。
- **页面范式**：`@StorageLink('locale') locale` + 页面私有 `tr(key)`/`trp(key, args)`（内部 `I18n.t/tp(key, …, this.locale)`，显式读 `this.locale` 建立渲染依赖）——语言切换即时重渲染。
- **参数化 `tp()` 用法**：模板 `{name}` 占位安全替换（缺参保留占位符原文）。示例：`trp('schedule.week', { 'n': String(weekNumber) })` → "第 3 周 / Week 3"；`trp('home.date', { 'm': '10', 'd': '13', 'w': '一' })` → "10月13日 周一 / Mon, 10/13"。
- **课表页细节**：周提示 `hint` 状态存**词典键**、渲染时 `tr(this.hint)` 翻译（切换即时生效且不改状态逻辑）；日期区间经 `schedule.dateMd`（zh `{m}月{d}日` / en `{m}/{d}`）格式化。
- **弃用 API 清理**：LoginPage/LearningPage 残留 `promptAction.showToast` 全部改 `getUIContext().getPromptAction().showToast`（首批页面 grep 无弃用提示 API）。
- **未迁移页面（回退中文，无键名外泄）**：`pages/campus/*`（10 个子页）、`pages/learning/*`（4 个详情页 + WebViewer）、`ClassroomPage`/`GradesPage`/`PlaceholderPage`/`common/components/MarkdownText` 均**未引入** `t()/tr()/I18n` 调用（硬编码中文即回退态）。
- **下批清单**：①校园子页 10 个（邮箱/网课/图书馆座位/研读间/体育/宿舍/财务/资讯/程序/校园网）；②学习子页 4 个（课程/作业/通知/文件详情）；③其它页（Classroom/Grades/Placeholder/MarkdownText）——扩词典 + 同款 `@StorageLink('locale')` + `tr()/trp()` 范式；业务数据（课程名/邮件主题/机构名）不翻译。

### 课表页块状视觉重构（2026-10-13）

参照原项目 `src/features/schedule/`（ScheduleWeekGrid/ScheduleEventBlock/gridProjection）把课表页从"6 节 × 7 天固定单格表格"重构为**块状课表**：跨节课程块高度对应节次数、按课程名稳定配色、地点完整多行展示。

- **新组件 `components/ScheduleGrid.ets`（纯展示）**：输入 `blocks: ScheduleBlock[]` + `axisLabels`（大节"起-止"）+ `dayLabels`（星期，i18n）+ `dateLabels`（MM-DD）+ `cellHeight`/`leftWidth`；不发起请求、不读写存储、不硬编码文案（静态字样全由页面传入）；时间轴"08:00-09:35"按 `-` 拆两行渲染。
- **节次区间换算（`SchedulePage.mapEventsToBlocks`）**：起始索引沿用既有 `periodIndexFor` 阈值分桶（<585/780/910/1020/1140 分钟）；结束索引按各大节**结束时间**判定（结束时间 ≤ 哪节结束时间即为该节，`PERIOD_END_MINUTES` = 09:35/12:15/15:05/16:55/18:40/21:45，与时间轴同源）；起始时间无法解析 → 跳过并记日志（tag `SchedAct`，`MAP_SKIP*`）；结束时间缺失/非法/不晚于开始 → 兜底单节并记日志（`MAP_FALLBACK_SINGLE`，课程保留可见）。
- **配色散列**：课程名确定性散列（`h = h*31 + charCode >>> 0`，对齐原项目 `hashTitle`）→ 8 组固定调色板下标，同名恒同色（跨周/跨会话一致）；调色板为柔和底色 + 深色前景 + 同系描边（浅色主题对比度安全），页面算好 `colorIndex` 传入组件。
- **堆叠/跳过策略（无绝对定位）**：每日列为纵向堆叠容器；按起始节升序遍历——起始节处渲染高 = `跨度×cellHeight` 的块，被跨节块覆盖的节次跳过，其余渲染空占位单元；**同日起始节相同的多个块同槽并列**（`layoutWeight(1)` 均分列宽，各自高度按自身跨度，槽高取最大跨度）；与前面跨节块**部分重叠**的块顺延至下一空节位堆叠（节位游标可越过末节，极端重叠时列高自然增长，不破版）。
- **空地点与裁剪规则**：地点为空/纯空白 → 不渲染地点行（块布局不塌陷）；块内自上而下"课程名（maxLines 4，优先保证）→ 地点（maxLines 5，多行折行）"，超长文本 `textOverflow` 省略 + 容器 `clip(true)` 安全裁剪（不溢出、不遮挡相邻块）。
- **演示模式复用**：`getMockBlocks()` 直接产出同构 `ScheduleBlock[]`（含跨两节/空地点/长地点边界样例），与真实数据走同一 `ScheduleGrid` 渲染，视觉一致。
- **既有行为保持**：周导航 ‹ ›（±12 周钳制）/点中间回本周、加载/空态/错误（可重试）分支、`hint` 存词典键渲染处翻译、`@StorageLink('locale')` 语言订阅全部不变；i18n 既有 `schedule.*` 键足够（时间轴/日期标签为纯数字），本轮**未新增词典键**。

### AI 真实对话（流式，多 provider）（2026-10-13）

AI 页从本地 mock 应答升级为**真实 OpenAI 兼容 LLM 流式对话**。设计文档见 `entry/src/main/ets/pages/ai-chat/`（spec/plan/tasks）。

- **LLM 客户端**（`services/ai/LLMService.ets`）：
  - **Provider 预设**：openai（`api.openai.com/v1` / gpt-4o-mini）/ deepseek（`api.deepseek.com/v1` / deepseek-v4-flash）/ dashscope（通义千问兼容模式）/ moonshot（kimi）/ custom（用户自填 baseUrl/model，仅 OpenAI 兼容）；预设表对齐参考实现 `src/services/ai/agentService.ts` 的 `AI_PRESETS`。`resolveBaseUrl/resolveModel` 解析实际请求目标（custom 用填写值，其余预设固定 baseUrl；model 填写优先、缺省回退预设默认）。
  - **流式实现（无降级）**：系统网络能力 `@ohos.net.http` 的 `requestInStream`（`@kit.NetworkKit`）——响应码经 Promise 返回，响应体经 `on('dataReceive')` 逐块回调；SSE 增量解析（跨块行缓冲 → `data:` 行 → JSON `choices[0].delta.content`，`[DONE]` 收尾）；兼容服务端忽略 `stream:true` 返回整体 JSON 的回退（dataEnd 无任何增量时整体解析 `choices[0].message.content`）。**T001 已用 `devecocli docs search` 查证接口可用，自定义 HTTPS baseUrl 直接可用，未降级非流式**。
  - **防御性状态机**：`LLMStreamSession` 同步返回取消句柄（`streamChat` 非 Promise，保证"停止"立即可用）；dataEnd 早于响应码时兜底等待 2s 按成功收尾；请求仅携带最近 24 轮历史（载荷上界）。
  - **取消与错误语义**：`cancel()` 立即 `destroy()` 请求并停止消费流（中断后不再回调，页面保留已生成内容并自行标注）；错误以结构化 `LLMErrorKind` 回调（401/403→AUTH、429→RATE_LIMIT、5xx/4xx→SERVER、2300028 或 timeout 字样→TIMEOUT、传输层其余→NETWORK、成功但空回复→EMPTY），页面经 i18n 映射可读文案；连接超时 15s、读取超时 300s。**日志与错误信息不含 API Key 与鉴权头**。
- **API Key 安全存储**（`services/ai/ApiKeyStore.ets`）：复用 `SecureStorage` 的 **ASSET 范式**——别名 `campusos.ai.apikey`，Key 仅存加密字段 `SECRET`；保存幂等（DUPLICATED→update）、读取失败/未配置返回空串、清除幂等；`save` 返回 `Promise<boolean>` 供设置页提示保存失败。**禁止写入偏好设置明文**；`SettingsManager.ensureLoaded` 发现历史 `AppSettings.apiKey` 明文残留会立即清除（scrub）。
- **设置页"AI 模型"配置区**（SettingsPage）：预设弹层选择（bindSheet）、custom baseUrl/model 输入（保存时校验 `http(s)://` 形态）、API Key 掩码输入 + 显隐切换 + "留空保持不变"（已配置时占位提示）、保存/清除（清除 AlertDialog 二次确认）、已配置/未配置状态。provider 配置（preset/baseUrl/model）持久化于独立偏好键 `@campusos/ai_provider_config`（`SettingsManager.get/setAIProviderSettings`）；`getApiProvider/getApiKey/setApiConfig` 保留签名但已弃用（Key 恒不落偏好）。
- **AI 页**（`pages/ai/AIChatPage.ets`）：
  - **发送前判定（零请求硬约束）**：①演示模式 → 本地示例应答（关键词命中 `ai.mock*`，零网络请求）；②Key 未配置（ASSET 读空）→ 内联引导卡（可跳设置页 tab=5，经 `emitNavigate`），**不构造请求、不清空输入**；③custom baseUrl 缺失 → 可读提示，不构造请求。
  - **流式渲染**：增量经页面级 `@State streamingText` 驱动独立"生成中"气泡实时渲染 + 自动滚动跟随；完成/中断/失败后一次性落入会话消息（**消息入列后不变更**，规避 V1 ForEach 同 key 不刷新的限制——气泡用 `@Prop` 基本类型，无 @Observed 依赖）。
  - **中断**："停止"按钮 / 切换会话 / 离开页面（`aboutToDisappear`）统一走 `cancelGeneration()`：取消句柄、保留已生成内容、消息标注"已停止生成"（aborted）；无悬挂请求。
  - **错误处理**：`LLMErrorKind` → i18n 可读文案横幅（`ai.error*`）；保留已生成内容（标注"生成失败"）与用户输入（输入框为空时回填上次发送内容便于重试）。
  - **多会话**：新建/切换/删除（AlertDialog 二次确认）经既有 `AIChatManager`（create/delete 签名不变，`Phase4SelfTest` 兼容）；会话列表 bindSheet；`aboutToAppear` 调 `loadConversations()` 启动恢复；状态胶囊显示 演示模式提示 / provider·model。
- **会话持久化**（`state/AIChatManager.ets`）：沿用 `StorageKeys.AI_CONVERSATIONS`（偏好 JSON，每次增删改后异步落盘）；消息扩展 `AIChatMessage extends ChatMessage` 带 `status`（ok/streaming/aborted/error），读取旧数据（无 status）归一 'ok'——结构向后兼容；会话标题取首条用户消息摘要（≤20 字符截断）。
- **启动落盘守卫（验证期修复 2026-10-13）**：`EntryAbility` 冷启动会先跑 `Phase4SelfTest`，其 `createConversation/deleteConversation` 在页面 `loadConversations()` 之前触发，会以"临时空列表"覆盖既有会话（旧实现重启后会话丢失）。现于 `AIChatManager` 增加 `loaded` 标志：`loadConversations()` 完成前 `saveConversations()` 跳过写入，恢复后再正常落盘——用户既有会话不再被启动自检清空（Phase 2 复验：会话+消息重启后恢复、删除持久生效）。

### 其他待办

- 体测上游缺陷跟进（JSONP 括号包裹响应，待上游修复后复验）
- 清华邮件（Coremail）逐用户故事 UI 验证（构建 + 模拟器部署后按 US1–US6 校验：列表/未读计数/分页、详情与附件、搜索、已读标记、删除/移动确认、撰写校验/确认/发送反馈）
- i18n 其余页面双语化（下一批次：校园子页/学习子页/其它页——见上方"i18n 核心骨架 + 高频页迁移"节的下批清单）
- "信任此设备"后续是否与指纹复用/2FA 策略真正联动（本轮仅持久化，UI 文案已准确表述）
- SettingsPage 退出登录后整应用回登录页需 Index 门控联动（本轮受"不改导航装配"约束，仅清会话+凭证+页内状态刷新；冷启动正确回登录页）

### 已修复待办

- ~~修复 #3 密码明文存储~~ **已修复（2026-10-11，凭证安全存储特性）**：`storage/SecureStorage.ets` 内部改为**系统关键资产存储**（Asset Store Kit）——单条关键资产：固定别名 `campusos.credentials` + 凭证三项（学号/密码/指纹）沿用既有格式序列化进唯一加密字段 `SECRET`（严禁放入别名或 DATA_LABEL 类明文字段）；访问条件"设备开机后可用"（不设"需用户认证"，保证静默自动登录）；保存幂等（新增命中"已存在"错误码则更新）。读取路径**惰性自动迁移**：关键资产未命中 → 读偏好设置旧明文键 `@secure:credentials` → 写入新存储**成功后**才清除旧明文（失败保留、不丢数据、下次读取重试）；注销双清（关键资产 + 旧明文键，各自容错、幂等）。保存失败只记日志不阻断登录；读取失败/ASSET 不可用返回空值，**绝不回退明文写入**。日志不含明文（tag `SecureStore`：`CRED_SAVE`/`CRED_QUERY`/`CRED_MIGRATE`/`CRED_CLEAR`，仅步骤/命中布尔/长度/错误码）。对外三方法（保存/读取/清除）签名与语义不变，调用方零改动。
- 备注：`turbomodules/SecureStorageTurboModule.ets` 为 HUKS 桥接**桩**（`getGenericPassword` 恒返回 `null`），未接入凭证链路；本特性未改动它，保持现状、不在凭证安全存储范围内。

---

## 8. 参考

- 原项目认证文档：`docs/login-to-thu.md`
- 设计系统：`docs/CAMPUS_OS_DESIGN_SYSTEM_V1.md`
- 原项目实现：`src/services/auth/tsinghuaAuth.ts`、`src/services/campus/learningAdapter.ts`、`src/services/webvpn/transport.ts`
