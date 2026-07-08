# CampusOS → HarmonyOS 依赖兼容性审计矩阵

> 生成日期: 2026-07-09
> 基于 CampusOS v2.1.1 (React Native 0.76.9)

---

## 1. 🔴 高风险：含原生代码，必须桥接/替代 (10 个包)

| npm 包 | 使用文件数 | 核心 API | 鸿蒙替代方案 | 工作量 |
|--------|----------|---------|-------------|-------|
| `react-native-keychain` | 1 | `Keychain.getGenericPassword`, `setGenericPassword`, `resetGenericPassword` | ArkTS HUKS (`@ohos.security.huks`) TurboModule | 3天 |
| `react-native-webview` | 4 | `<WebView>`, `WebViewMessageEvent`, `WebViewNavigation` | ArkUI `Web` 组件 (`@ohos.web.webview`) | 1天 |
| `react-native-reanimated` | 2 | `useSharedValue`, `useAnimatedStyle`, `withRepeat`, `FadeInDown` | RN 内置 `Animated` API 降级 | 1天 |
| `react-native-safe-area-context` | 31 | `<SafeAreaView>` | ArkUI `expandSafeArea()` + Column padding | 1天 |
| `react-native-linear-gradient` | 4 | `<LinearGradient>` | ArkUI `.linearGradient()` 装饰器 | 0.5天 |
| `@react-native-async-storage/async-storage` | 8 | `AsyncStorage.getItem/setItem/removeItem` | `@react-native-oh-tpl/async-storage` 或 `@ohos.data.preferences` | 1天 |
| `@react-native-cookies/cookies` | 4 | `CookieManager.get/set/clearAll` | 纯 JS fetch cookie 手动管理 | 1天 |
| `react-native-gesture-handler` | 1 (side-effect) | `PanGestureHandler`, `TapGestureHandler` | ArkUI `gesture()` API | 1天 |
| `react-native-screens` | 隐式 (React Nav) | 原生屏幕容器 | RN-OH 移植版 或 自定义 | 1天 |
| `react-native-markdown-display` | 1 | `<Markdown>` 组件 | 纯 JS Markdown 渲染替代 | 1天 |

---

## 2. 🟡 中风险：纯 JS 但依赖 JSI/Bridge/Fabric (3 个模块组)

| 模块组 | 使用文件数 | 核心 API | 鸿蒙兼容策略 | 风险 |
|--------|----------|---------|-------------|------|
| `@react-navigation/native` | 5 | `NavigationContainer`, `useFocusEffect`, `useNavigation` | RN-OH 移植版 或 自建轻量 Router | RN-OH 可能尚未完全支持 React Navigation v7 |
| `@react-navigation/native-stack` | 28 | `createNativeStackNavigator`, `NativeStackScreenProps` | 同上 | 页面间导航类型需重定义 |
| `@react-navigation/bottom-tabs` | 5 | `createBottomTabNavigator`, `BottomTabScreenProps` | 同上 或 ArkUI `Tabs` 组件 | Tab 图标渲染需适配 |

**降级方案**：若 RN-OH 不支持 React Navigation v7，则降级为自建 stack navigator（基于 Redux screen state + 简单的 `<View>` 层级）。

---

## 3. 🟢 低风险：纯 JavaScript，直接复用 (14 个包)

### 状态管理 (2个)
| npm 包 | 使用文件数 | 兼容性 |
|--------|----------|--------|
| `@reduxjs/toolkit` | 9 | 🟢 零原生依赖，直接复用 |
| `react-redux` | 广泛使用 | 🟢 零原生依赖，直接复用 |

### 加密 (3个)
| npm 包 | 使用文件数 | 兼容性 |
|--------|----------|--------|
| `crypto-js` | 间接 (加密流程) | 🟢 纯 JS，直接复用 |
| `jsencrypt` | 1 (`network.ts`) | 🟡 依赖 `window.crypto.subtle`（RSA），鸿蒙用 `cryptoFramework` 备选 |
| `sm-crypto` | 1 (`sm2.ts`) | 🟢 纯 JS SM2/SM3/SM4，直接复用 |

### HTML 解析 (3个)
| npm 包 | 使用文件数 | 兼容性 |
|--------|----------|--------|
| `cheerio` | 间接 (HTML 解析) | 🟢 纯 JS，直接复用 |
| `node-html-parser` | 4 (`htmlSelect.ts`, `network.ts`, `mail.ts`, `grades.ts`) | 🟢 纯 JS，直接复用 |
| `entities` | 间接 (HTML 实体解码) | 🟢 纯 JS，直接复用 |

### 工具库 (4个)
| npm 包 | 使用文件数 | 兼容性 |
|--------|----------|--------|
| `uuid` | 1 (`tsinghuaAuth.ts`) | 🟢 纯 JS，直接复用 |
| `base-64` | 1 (`polyfills.ts`) | 🟡 可用 ArkTS `util.Base64Helper` 替代 |
| `react-native-get-random-values` | 1 (`polyfills.ts`) | 🟡 可用 `@ohos.cryptoFramework` Random 替代 |
| `react-native-markdown-display` | 1 | 🔴 含 RN 原生渲染，需替代（见上表） |

### React 核心 (2个)
| npm 包 | 兼容性 |
|--------|--------|
| `react` (18.3.1) | 🟢 RN-OH 内置提供 |
| `react-native` (0.76.9) | 🟡 替换为 RN-OH 对应版本 |

---

## 4. 📊 统计汇总

| 风险等级 | 包数量 | 百分比 |
|---------|--------|--------|
| 🔴 高风险（需桥接/替代） | 10 | 33% |
| 🟡 中风险（需适配） | 3 模块组 | 10% |
| 🟢 低风险（直接复用） | 14 | 47% |
| 🟡 中低风险（需 polyfill） | 3 | 10% |

**总计**: 30 个 npm 包中，17 个可复用或容易适配，13 个需要较大工作量。

---

## 5. 📁 影响范围热力图

### 文件受影响最严重的前 10 个文件

| 文件 | 需要改动的原生依赖 | 迁移复杂度 |
|------|------------------|----------|
| `src/app/navigation/AppNavigator.tsx` | React Navigation (全部 3 包) + screens + gesture-handler | 🔴 极高 |
| `src/storage/secureStorage.ts` | react-native-keychain | 🔴 高 |
| `src/features/common/components/HtmlContent.tsx` | react-native-webview | 🟡 中 |
| `src/features/learning/InAppViewerScreen.tsx` | react-native-webview + cookies | 🟡 中 |
| `src/features/campus/CampusMailViewerScreen.tsx` | react-native-webview + cookies | 🟡 中 |
| `src/services/webvpn/transport.ts` | @react-native-cookies/cookies | 🟡 中 |
| `src/features/common/components/Skeleton.tsx` | react-native-reanimated | 🟡 中 |
| `src/features/common/components/Animated.tsx` | react-native-reanimated | 🟡 中 |
| `src/features/common/components/MarkdownText.tsx` | react-native-markdown-display | 🟡 中 |
| `src/polyfills.ts` | base-64 + get-random-values | 🟢 低 |

### 受 SafeAreaView 影响的 31 个文件（批量替换）

全部仅使用 `<SafeAreaView>` 单一组件，可统一替换为带 padding 的 `<View>`。

---

## 6. 🔑 关键决策点

| 决策 | 建议 | 理由 |
|------|------|------|
| React Navigation 是否保留 | **保留，等待 RN-OH 移植** | 28 个文件依赖，自建成本过高 |
| Reanimated → Animated 降级 | **降级** | 仅 2 个文件使用，动画效果简单 |
| WebView 策略 | **ArkUI Web 组件** | 4 个文件，鸿蒙原生 WebView 更稳定 |
| Keychain → HUKS | **TurboModule 桥接** | 安全存储是核心功能，不可降级 |
| @react-native-cookies | **纯 JS 替代** | fetch API 可手动管理 Cookie 头 |
| Markdown 渲染 | **纯 JS 渲染替代** | 1 个文件，可用 marked + 自建渲染 |

---

## 7. 📋 迁移顺序（依赖拓扑排序）

按依赖关系排序，确保每个阶段的可验证性：

```
Phase 2: 项目骨架
├── 创建 harmony/ 目录
├── 配置 hvigor + oh-package.json5
└── EntryAbility.ets（加载 RN Bundle）

Phase 3: 纯 JS 层迁移
├── polyfills.ts → ArkTS util 适配
├── domain/ → 全部复用
├── services/ (除 campus/mail.ts 的 cookie 依赖)
├── state/ → 全部复用
└── utils/ → 全部复用

Phase 4: 原生桥接
├── (1) AsyncStorage → RN-OH 移植版（8 个文件）
├── (2) Keychain → HUKS TurboModule（1 个文件）
├── (3) WebView → ArkUI Web（4 个文件）
├── (4) Cookie → 纯 JS（4 个文件）
├── (5) SafeArea → expandSafeArea（31 个文件）
├── (6) LinearGradient → .linearGradient()（4 个文件）
├── (7) Reanimated → Animated 降级（2 个文件）
└── (8) Markdown → 纯 JS 替代（1 个文件）

Phase 5: UI 层迁移
├── AppNavigator + React Navigation 适配
└── 47 个页面组件逐一适配

Phase 6: 平台差异适配
Phase 7: 测试验证
```
