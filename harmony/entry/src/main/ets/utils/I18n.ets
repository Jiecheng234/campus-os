/**
 * ============================================================================
 * I18n — 轻量国际化框架（词典 + 翻译查找 + 运行时切换）
 * ============================================================================
 *
 * 【分期】本轮交付框架 + 设置页双语化；其余页面后续批次迁移。
 *
 * 【词典】key → { zh, en } 成对条目（SETTINGS_DICTIONARY）；新增语言只需扩列。
 *
 * 【回退链】t(key)：当前 locale 未命中/空串 → 回退中文 → 仍缺返回可读占位
 *   （PLACEHOLDER），禁止空白或键名外泄。
 *
 * 【参数化】tp(key, args)：在 t(key) 文案上把 {name} 占位符按 args 安全替换
 *   （未提供的参数保留占位符原文，不抛错）。
 *
 * 【locale 运行时状态】AppStorage 键 'locale'（LOCALE_STORAGE_KEY）：
 *   - 页面用 @StorageLink('locale') 订阅即可随切换即时重渲染；
 *   - setLocale() 校验（仅 zh/en，非法回退 zh）→ 写 AppStorage → 经
 *     SettingsManager.setLocale 持久化（单一写入路径，保证两者一致）；
 *   - init() 由 EntryAbility 在页面装载前调用，把持久化 locale 灌入 AppStorage。
 * ============================================================================
 */
import { SettingsManager } from '../state/SettingsManager';
import { Log } from './Logger';

/** AppStorage 中的语言键（后续页面 @StorageLink('locale') 直接复用） */
const LOCALE_STORAGE_KEY: string = 'locale';
const LOCALE_ZH: string = 'zh';
const LOCALE_EN: string = 'en';
/** 词典完全未命中时的可读占位（非空白、非键名） */
const PLACEHOLDER: string = '—';
const LOG_TAG: string = 'I18n';

/** 翻译词条：zh/en 成对（新增语言在此扩列） */
interface I18nEntry {
  zh: string;
  en: string;
}

/** 设置页全部文案词典（后续页面迁移时按前缀扩列） */
const SETTINGS_DICTIONARY: Record<string, I18nEntry> = {
  // ── 通用操作（common.*）──
  'common.cancel': { zh: '取消', en: 'Cancel' },
  'common.confirm': { zh: '确定', en: 'Confirm' },
  'common.ok': { zh: '好的', en: 'OK' },
  'common.more': { zh: '更多', en: 'More' },
  'common.exitHint': { zh: '再按一次退出应用', en: 'Press back again to exit' },

  // ── 底部导航（nav.*，对应 Index.tabTitles 6 项）──
  'nav.home': { zh: '首页', en: 'Home' },
  'nav.learning': { zh: '学习', en: 'Learning' },
  'nav.schedule': { zh: '课表', en: 'Schedule' },
  'nav.campus': { zh: '校园', en: 'Campus' },
  'nav.ai': { zh: 'AI', en: 'AI' },
  'nav.settings': { zh: '设置', en: 'Settings' },

  // ── 页面标题（*.title；副标题仅静态文案建词条，动态数据由页面拼接）──
  'home.title': { zh: 'CampusOS', en: 'CampusOS' },
  'learning.title': { zh: '学习', en: 'Learning' },
  'schedule.title': { zh: '课表', en: 'Schedule' },
  'schedule.subtitle': { zh: '每周课程安排', en: 'Your weekly classes' },
  'campus.title': { zh: '校园', en: 'Campus' },
  'campus.services': { zh: '{n} 项校园服务', en: '{n} campus services' },
  'ai.title': { zh: 'AI 助手', en: 'AI Assistant' },
  'ai.subtitle': { zh: '你的清华校园智能助手', en: 'Your smart campus assistant' },

  // ── 通用状态（status.*）──
  'status.loading': { zh: '加载中…', en: 'Loading…' },
  'status.empty': { zh: '暂无数据', en: 'No data yet' },
  'status.failed': { zh: '加载失败', en: 'Failed to load' },
  'status.retry': { zh: '重试', en: 'Retry' },
  'status.demo': { zh: '演示模式', en: 'Demo mode' },

  // ── 课表（schedule.*，供课表特性复用；week 用 tp 的 {n} 占位符）──
  'schedule.week': { zh: '第 {n} 周', en: 'Week {n}' },
  'schedule.today': { zh: '今天', en: 'Today' },
  'schedule.location': { zh: '地点', en: 'Location' },

  // ── 首页（home.*）──
  'home.greetNight': { zh: '夜深了', en: 'Up late' },
  'home.greetMorning': { zh: '早上好', en: 'Good morning' },
  'home.greetNoon': { zh: '中午好', en: 'Good afternoon' },
  'home.greetAfternoon': { zh: '下午好', en: 'Good afternoon' },
  'home.greetEvening': { zh: '晚上好', en: 'Good evening' },
  'home.date': { zh: '{m}月{d}日 周{w}', en: '{w}, {m}/{d}' },
  'home.weekday0': { zh: '日', en: 'Sun' },
  'home.weekday1': { zh: '一', en: 'Mon' },
  'home.weekday2': { zh: '二', en: 'Tue' },
  'home.weekday3': { zh: '三', en: 'Wed' },
  'home.weekday4': { zh: '四', en: 'Thu' },
  'home.weekday5': { zh: '五', en: 'Fri' },
  'home.weekday6': { zh: '六', en: 'Sat' },
  'home.weatherUnavailable': { zh: '海淀 · 天气暂不可用', en: 'Haidian · Weather unavailable' },
  'home.syncAction': { zh: '同步校园数据', en: 'Sync campus data' },
  'home.syncing': { zh: '同步中...', en: 'Syncing…' },
  'home.syncDone': { zh: '已同步 {n} 门课程', en: 'Synced {n} courses' },
  'home.syncPending': { zh: '待办 {n}', en: '{n} pending' },
  'home.syncUnread': { zh: '未读 {n}', en: '{n} unread' },
  'home.syncScheduleUnavailable': { zh: '课表暂不可用', en: 'Schedule unavailable' },
  'home.demoToast': { zh: '演示模式下使用本地数据', en: 'Demo mode uses local data' },
  'home.todayFocus': { zh: '今日重点', en: 'Today\'s focus' },
  'home.metricClasses': { zh: '今日课程', en: 'Classes today' },
  'home.metricTasks': { zh: '待处理任务', en: 'Pending tasks' },
  'home.metricUnread': { zh: '未读通知', en: 'Unread notices' },
  'home.sectionTodayCourses': { zh: '今日课程', en: 'Today\'s classes' },
  'home.noClassesToday': { zh: '今日无课程安排', en: 'No classes scheduled today' },
  'home.scheduleDebugging': {
    zh: '课表暂不可用（教务会话调试中）',
    en: 'Schedule unavailable (academic system session in progress)'
  },
  'home.quickActions': { zh: '快捷操作', en: 'Quick actions' },
  'home.qa.emptyClassroom': { zh: '查空教室', en: 'Free classrooms' },
  'home.qa.librarySeat': { zh: '图书馆座位', en: 'Library seats' },
  'home.qa.addDdl': { zh: '添加 DDL', en: 'Add deadline' },
  'home.comingSoon': { zh: '即将接入', en: 'Coming soon' },

  // ── 学习页（learning.*；tabs 中文名为跨页逻辑标识，仅展示层翻译）──
  'learning.eyebrow': { zh: 'LEARNING', en: 'LEARNING' },
  'learning.tabCourses': { zh: '课程', en: 'Courses' },
  'learning.tabHomework': { zh: '作业', en: 'Homework' },
  'learning.tabNotifications': { zh: '通知', en: 'Notices' },
  'learning.tabFiles': { zh: '文件', en: 'Files' },
  'learning.countsSnippet': {
    zh: '{a} 门课程 · {b} 项作业 · {c} 通知 · {d} 文件',
    en: '{a} courses · {b} assignments · {c} notices · {d} files'
  },
  'learning.emptyHomework': { zh: '暂无作业', en: 'No assignments yet' },
  'learning.emptyNotifications': { zh: '暂无通知', en: 'No notices yet' },
  'learning.emptyFiles': { zh: '暂无文件', en: 'No files yet' },
  'learning.addDdl': { zh: '添加 DDL', en: 'Add deadline' },
  'learning.formTitle': { zh: '标题（必填）', en: 'Title (required)' },
  'learning.formDate': { zh: '日期', en: 'Date' },
  'learning.formTime': { zh: '时间', en: 'Time' },
  'learning.formCourse': { zh: '课程（选填）', en: 'Course (optional)' },
  'learning.formNote': { zh: '备注（选填）', en: 'Note (optional)' },
  'learning.save': { zh: '保存', en: 'Save' },
  'learning.titleRequired': { zh: '请输入标题', en: 'Please enter a title' },
  'learning.customCourse': { zh: '自定义', en: 'Custom' },
  'learning.badgeNew': { zh: 'NEW', en: 'NEW' },

  // ── 校园页入口（campus.*）──
  'campus.eyebrow': { zh: 'CAMPUS', en: 'CAMPUS' },
  'campus.news.title': { zh: '校园资讯', en: 'Campus news' },
  'campus.news.subtitle': { zh: '清华快讯 · 公告', en: 'Tsinghua updates · notices' },
  'campus.classroom.title': { zh: '空闲教室', en: 'Free classrooms' },
  'campus.classroom.subtitle': { zh: '查询空闲教室', en: 'Find free classrooms' },
  'campus.grades.title': { zh: '成绩查询', en: 'Grades' },
  'campus.grades.subtitle': { zh: '查看成绩绩点', en: 'Check grades and GPA' },
  'campus.petest.title': { zh: '体测成绩', en: 'Fitness test' },
  'campus.petest.subtitle': { zh: '查看体测结果', en: 'View fitness results' },
  'campus.dormitory.title': { zh: '宿舍服务', en: 'Dormitory' },
  'campus.dormitory.subtitle': { zh: '电费 · 洗衣机', en: 'Power · laundry' },
  'campus.finance.title': { zh: '财务缴费', en: 'Payments' },
  'campus.finance.subtitle': { zh: '校园卡 · 消费记录', en: 'Campus card · spending' },
  'campus.network.title': { zh: '校园网', en: 'Campus network' },
  'campus.network.subtitle': { zh: '余额 · 在线设备', en: 'Balance · devices' },
  'campus.reservation.title': { zh: '场馆预约', en: 'Book venues' },
  'campus.reservation.subtitle': { zh: '研读间 · 体育场馆', en: 'Study rooms · gyms' },
  'campus.mail.title': { zh: '校园邮箱', en: 'Campus mail' },
  'campus.mail.subtitle': { zh: '清华邮箱', en: 'Tsinghua email' },
  'campus.program.title': { zh: '培养方案', en: 'Degree program' },
  'campus.program.subtitle': { zh: '学分完成度', en: 'Credit progress' },

  // ── AI 助手（ai.*）──
  'ai.eyebrow': { zh: 'AI ASSISTANT', en: 'AI ASSISTANT' },
  'ai.newChat': { zh: '新建对话', en: 'New chat' },
  'ai.brandName': { zh: 'CampusOS AI', en: 'CampusOS AI' },
  'ai.tryAsking': { zh: '试试问我：', en: 'Try asking:' },
  'ai.inputPlaceholder': { zh: '问我关于校园的任何问题...', en: 'Ask me anything about campus...' },
  'ai.send': { zh: '发送', en: 'Send' },
  'ai.suggest.schedule': { zh: '今天有什么课？', en: 'What is my schedule today?' },
  'ai.suggest.classroom': { zh: '查一下空教室', en: 'Find a free classroom' },
  'ai.suggest.ddl': { zh: '帮我添加一个DDL', en: 'Help me add a deadline' },
  'ai.suggest.grades': { zh: '最近的成绩怎么样？', en: 'How are my grades?' },
  'ai.suggest.card': { zh: '校园卡还有多少钱？', en: 'How much is left on my card?' },
  'ai.mockCourses': {
    zh: '根据你的课表，今天有以下课程：\n\n🔹 8:00-9:35 高等数学(1) — 六教6A201\n🔹 10:10-11:45 大学物理B(2) — 四教4301\n🔹 13:30-15:05 线性代数 — 六教6B101\n\n需要我帮你查看课程详情或作业吗？',
    en: 'Based on your schedule, today\'s classes:\n\n🔹 8:00-9:35 Advanced Math I — Bldg 6, 6A201\n🔹 10:10-11:45 Physics II — Bldg 4, 4301\n🔹 13:30-15:05 Linear Algebra — Bldg 6, 6B101\n\nWant to see course details or homework?'
  },
  'ai.mockClassroom': {
    zh: '查询到当前时段以下教室空闲：\n\n🏫 六教：6A301, 6A302, 6A401, 6A402, 6B203\n🏫 四教：4303, 4304, 4402\n🏫 五教：5102, 5201, 5303\n\n共 11 间教室可用。需要预约吗？',
    en: 'These classrooms are free right now:\n\n🏫 Building 6: 6A301, 6A302, 6A401, 6A402, 6B203\n🏫 Building 4: 4303, 4304, 4402\n🏫 Building 5: 5102, 5201, 5303\n\n11 rooms available. Want to book one?'
  },
  'ai.mockDdl': {
    zh: '你当前有 2 项待完成的作业：\n\n📝 高等数学(1) — 习题集第5章 — 截止：7月25日\n📝 大学物理B(2) — 实验报告2 — 截止：7月28日\n\n需要我帮你添加新的DDL吗？',
    en: 'You have 2 pending assignments:\n\n📝 Advanced Math I — Problem set Ch.5 — due Jul 25\n📝 Physics II — Lab report 2 — due Jul 28\n\nWant me to add a new deadline?'
  },
  'ai.mockGrades': {
    zh: '你的学业成绩概览：\n\n📊 本学期 GPA：3.72\n🏆 等级分布：A=3门, A-=2门, B+=1门, B=1门\n\n详细成绩可在「校园」→「成绩查询」中查看。',
    en: 'Your academic overview:\n\n📊 This term GPA: 3.72\n🏆 Grade distribution: A=3, A-=2, B+=1, B=1\n\nSee full grades in Campus → Grades.'
  },
  'ai.mockCard': {
    zh: '你的校园卡信息：\n\n💰 当前余额：¥285.30\n💳 卡号：**** **** **** 6821\n📋 最近消费：紫荆园餐厅 -¥15.50\n\n余额充足，无需充值。',
    en: 'Your campus card:\n\n💰 Balance: ¥285.30\n💳 Card no.: **** **** **** 6821\n📋 Latest purchase: Zijing Dining Hall -¥15.50\n\nBalance looks good, no top-up needed.'
  },
  'ai.mockDefault': {
    zh: '我是 CampusOS AI 助手，可以帮你：\n\n📚 查询课表和学习任务\n🏫 查找空教室\n📊 查看成绩和 GPA\n💰 查询校园卡余额\n📝 管理 DDL 待办\n🌐 查询校园网状态\n\n有什么我可以帮你的吗？',
    en: 'I\'m your CampusOS AI assistant. I can help you:\n\n📚 Check classes and tasks\n🏫 Find free classrooms\n📊 View grades and GPA\n💰 Check campus card balance\n📝 Manage deadlines\n🌐 Check campus network status\n\nWhat can I do for you?'
  },

  // ── AI 真实对话（ai-chat 特性追加：流式/停止/错误/引导/会话）──
  'ai.stop': { zh: '停止', en: 'Stop' },
  'ai.generating': { zh: '正在生成…', en: 'Generating…' },
  'ai.msgAborted': { zh: '已停止生成', en: 'Stopped' },
  'ai.msgFailed': { zh: '生成失败', en: 'Failed' },
  'ai.demoNotice': { zh: '演示模式 · 回复来自本地示例', en: 'Demo mode · replies are local samples' },
  'ai.notConfiguredTitle': { zh: '尚未配置 AI 模型', en: 'AI model not configured' },
  'ai.notConfiguredHint': {
    zh: '请先在设置中配置 AI 模型与 API Key',
    en: 'Set up an AI model and API key in Settings first'
  },
  'ai.goSettings': { zh: '去设置', en: 'Go to Settings' },
  'ai.chats': { zh: '会话', en: 'Chats' },

  'ai.chatListTitle': { zh: '选择会话', en: 'Select a chat' },
  'ai.deleteChatTitle': { zh: '删除会话', en: 'Delete chat' },
  'ai.deleteChatMessage': {
    zh: '将删除该会话及全部消息，不可恢复。',
    en: 'This deletes the chat and all its messages. This cannot be undone.'
  },
  'ai.deleteChatOk': { zh: '删除', en: 'Delete' },
  'ai.errorAuth': { zh: '密钥无效或已过期，请在设置中重新配置', en: 'Invalid or expired API key. Please reconfigure in Settings.' },
  'ai.errorRateLimit': { zh: '请求过于频繁，请稍后再试', en: 'Too many requests. Please try again later.' },
  'ai.errorServer': { zh: 'AI 服务暂时不可用，请稍后再试', en: 'AI service is temporarily unavailable. Please try again later.' },
  'ai.errorNetwork': { zh: '网络不可用，请检查网络后重试', en: 'Network unavailable. Please check your connection and retry.' },
  'ai.errorTimeout': { zh: '请求超时，请重试', en: 'Request timed out. Please retry.' },
  'ai.errorEmpty': { zh: '模型未返回内容，请重试', en: 'The model returned no content. Please retry.' },
  'ai.errorGeneric': { zh: '请求失败，请重试', en: 'Request failed. Please retry.' },
  'ai.errorBadBaseUrl': { zh: '接口地址无效，请在设置中检查', en: 'Invalid base URL. Please check Settings.' },

  // ── 登录页（login.*）──
  'login.subtitle': { zh: '清华校园 AI 操作系统', en: 'Tsinghua campus AI OS' },
  'login.restoring': { zh: '正在恢复登录…', en: 'Restoring sign-in…' },
  'login.twoFactorTitle': { zh: '二次认证', en: 'Two-factor authentication' },
  'login.sendCode': { zh: '发送验证码', en: 'Send code' },
  'login.codePlaceholder': { zh: '输入验证码', en: 'Enter verification code' },
  'login.verify': { zh: '验证', en: 'Verify' },
  'login.studentIdPlaceholder': { zh: '学号', en: 'Student ID' },
  'login.passwordPlaceholder': { zh: '密码', en: 'Password' },
  'login.loggingIn': { zh: '登录中...', en: 'Signing in…' },
  'login.loginButton': { zh: '登  录', en: 'Sign in' },
  'login.demoButton': { zh: '演示模式（无需账号）', en: 'Demo mode (no account needed)' },
  'login.footerNote': { zh: '部分功能需清华大学校园网', en: 'Some features require the Tsinghua campus network' },
  'login.errorEmptyFields': { zh: '请输入学号和密码', en: 'Please enter your student ID and password' },
  'login.errorServerResponse': {
    zh: '认证服务器返回错误：{msg}\n\n请使用「演示模式」进入（无需账号）',
    en: 'Authentication server error: {msg}\n\nUse "Demo mode" to continue (no account needed)'
  },
  'login.errorNetwork': {
    zh: '网络不可达\n\n真实登录需要清华校园网或 WebVPN。\n请使用「演示模式」进入（无需账号）',
    en: 'Network unreachable\n\nSigning in requires the Tsinghua campus network or WebVPN.\nUse "Demo mode" to continue (no account needed)'
  },
  'login.codeSent': { zh: '验证码已发送', en: 'Verification code sent' },
  'login.codeSendFailed': { zh: '发送验证码失败', en: 'Failed to send verification code' },
  'login.errorEmptyCode': { zh: '请输入验证码', en: 'Please enter the verification code' },
  'login.verifyFailed': { zh: '验证失败', en: 'Verification failed' },
  'login.errorRetry': { zh: '网络错误，请重试', en: 'Network error. Please try again.' },

  // ── 登录页（login.*，trust-device 特性追加：信任开关 + 需二次认证提示）──
  'login.trustDevice': { zh: '信任此设备', en: 'Trust this device' },
  'login.trustDeviceHint': {
    zh: '勾选后将在本设备安全保存登录凭证，下次启动自动登录；不勾选则仅本次运行内保持登录',
    en: 'Checked, credentials are kept on this device for automatic sign-in next time; unchecked, you stay signed in only for this run'
  },
  'login.twoFactorRequired': {
    zh: '需要二次认证，请完成验证后继续',
    en: 'Two-factor authentication is required. Please verify to continue.'
  },
  'login.savedCredentialsHint': {
    zh: '已填入本设备保存的凭证，点击「登录」即可继续',
    en: 'Saved credentials are filled in. Tap Sign in to continue.'
  },

  // ── 课表页正文（schedule.*，第二批追加；day0=周一 … day6=周日，对应页内 WEEKDAYS 下标）──
  'schedule.thisWeek': { zh: '本周', en: 'This week' },
  'schedule.offSemester': { zh: '非本学期周次', en: 'Outside semester' },
  'schedule.demoHint': { zh: '演示数据 · 登录后显示真实课表', en: 'Demo data · Sign in for your real schedule' },
  'schedule.fetchFailed': { zh: '课表拉取失败', en: 'Failed to load schedule' },
  'schedule.fetchFailedSession': {
    zh: '课表拉取失败（教务会话未打通）',
    en: 'Failed to load schedule (registrar session unavailable)'
  },
  'schedule.emptyWeek': { zh: '本周无课程安排', en: 'No classes this week' },
  'schedule.dateMd': { zh: '{m}月{d}日', en: '{m}/{d}' },
  'schedule.day0': { zh: '一', en: 'Mon' },
  'schedule.day1': { zh: '二', en: 'Tue' },
  'schedule.day2': { zh: '三', en: 'Wed' },
  'schedule.day3': { zh: '四', en: 'Thu' },
  'schedule.day4': { zh: '五', en: 'Fri' },
  'schedule.day5': { zh: '六', en: 'Sat' },
  'schedule.day6': { zh: '日', en: 'Sun' },

  'settings.eyebrow': { zh: 'SETTINGS', en: 'SETTINGS' },
  'settings.title': { zh: '设置', en: 'Settings' },
  'settings.statusDemo': { zh: '演示模式', en: 'Demo mode' },
  'settings.statusLoggedIn': { zh: '已登录', en: 'Signed in' },
  'settings.statusLoggedOut': { zh: '未登录', en: 'Not signed in' },

  'settings.sectionAccount': { zh: '账号', en: 'Account' },
  'settings.accountStatus': { zh: '状态', en: 'Status' },
  'settings.accountStudentId': { zh: '学号', en: 'Student ID' },

  'settings.sectionPreferences': { zh: '偏好设置', en: 'Preferences' },
  'settings.demoMode': { zh: '演示模式', en: 'Demo mode' },
  'settings.trustDevice': { zh: '信任此设备', en: 'Trust this device' },
  'settings.language': { zh: '语言', en: 'Language' },
  'settings.langZh': { zh: '中文', en: '中文' },
  'settings.langEn': { zh: 'English', en: 'English' },
  'settings.selectLanguage': { zh: '选择语言', en: 'Select language' },

  // ── AI 模型配置区（ai-chat 特性追加；API Key 不落明文，入 ASSET）──
  'settings.sectionAI': { zh: 'AI 模型', en: 'AI model' },
  'settings.aiConfigured': { zh: '已配置', en: 'Configured' },
  'settings.aiNotConfigured': { zh: '未配置', en: 'Not configured' },
  'settings.aiPreset': { zh: '预设服务', en: 'Provider' },
  'settings.aiSelectPreset': { zh: '选择预设服务', en: 'Select a provider' },
  'settings.aiPresetOpenai': { zh: 'OpenAI', en: 'OpenAI' },
  'settings.aiPresetDeepseek': { zh: 'DeepSeek', en: 'DeepSeek' },
  'settings.aiPresetDashscope': { zh: '通义千问', en: 'Qwen' },
  'settings.aiPresetMoonshot': { zh: 'Moonshot', en: 'Moonshot' },
  'settings.aiPresetCustom': { zh: '自定义', en: 'Custom' },
  'settings.aiBaseUrl': { zh: '接口地址', en: 'Base URL' },
  'settings.aiBaseUrlPlaceholder': { zh: 'https://api.example.com/v1', en: 'https://api.example.com/v1' },
  'settings.aiModel': { zh: '模型', en: 'Model' },
  'settings.aiModelPlaceholder': { zh: '模型名，如 gpt-4o-mini', en: 'Model name, e.g. gpt-4o-mini' },
  'settings.aiApiKey': { zh: 'API Key', en: 'API Key' },
  'settings.aiApiKeyPlaceholder': { zh: '输入 API Key', en: 'Enter API key' },
  'settings.aiApiKeyKeep': {
    zh: '已配置 · 留空保持不变',
    en: 'Configured — leave blank to keep'
  },
  'settings.aiShowKey': { zh: '显示', en: 'Show' },
  'settings.aiHideKey': { zh: '隐藏', en: 'Hide' },
  'settings.aiCustomHint': {
    zh: '自定义仅支持 OpenAI 兼容接口（/chat/completions）',
    en: 'Custom endpoints must be OpenAI-compatible (/chat/completions)'
  },
  'settings.aiSave': { zh: '保存配置', en: 'Save' },
  'settings.aiClear': { zh: '清除配置', en: 'Clear' },
  'settings.aiClearTitle': { zh: '清除 AI 配置', en: 'Clear AI config' },
  'settings.aiClearMessage': {
    zh: '将清除 provider 配置与 API Key，AI 对话将回到未配置引导状态。',
    en: 'This clears the provider config and API key. AI chat will return to the unconfigured guide.'
  },
  'settings.aiClearOk': { zh: '清除', en: 'Clear' },
  'settings.aiSaveSuccess': { zh: 'AI 配置已保存', en: 'AI config saved' },
  'settings.aiClearSuccess': { zh: '已清除 AI 配置', en: 'AI config cleared' },
  'settings.aiSaveFailed': { zh: 'AI 配置保存失败，请重试', en: 'Failed to save AI config. Please try again.' },
  'settings.aiBaseUrlInvalid': {
    zh: '接口地址需以 http:// 或 https:// 开头',
    en: 'Base URL must start with http:// or https://'
  },
  'settings.aiModelRequired': { zh: '请填写模型名', en: 'Model name is required' },
  'settings.aiKeyRequired': { zh: '请输入 API Key', en: 'Enter an API key' },

  'settings.sectionFeatures': { zh: '功能', en: 'Features' },
  'settings.aiMemory': { zh: 'AI 记忆', en: 'AI memory' },
  'settings.actionHistory': { zh: '操作记录', en: 'Action history' },
  'settings.smartMonitor': { zh: '智能监控', en: 'Smart monitor' },
  'settings.notSupported': { zh: '暂不支持', en: 'Not available yet' },

  'settings.clearLocalData': { zh: '清理本地数据', en: 'Clear local data' },
  'settings.clearDataTitle': { zh: '清理本地数据', en: 'Clear local data' },
  'settings.clearDataConfirm': { zh: '确认清理', en: 'Clear' },
  'settings.clearDataMessage': {
    zh: '将清除 AI 会话与学习缓存等本地数据，不影响账号与云端数据。',
    en: 'This will clear local AI chats and learning cache. Your account and cloud data are not affected.'
  },
  'settings.clearItemAi': { zh: 'AI 会话', en: 'AI chats' },
  'settings.clearItemLearning': { zh: '学习缓存', en: 'Learning cache' },
  'settings.countUnit': { zh: '条', en: 'items' },
  'settings.clearListSep': { zh: '、', en: ', ' },
  'settings.clearResultDone': { zh: '已清理：', en: 'Cleared: ' },
  'settings.clearResultNone': { zh: '未发现可清理的本地数据', en: 'No local data to clear' },

  'settings.logout': { zh: '退出登录', en: 'Sign out' },
  'settings.logoutConfirmTitle': { zh: '退出登录', en: 'Sign out' },
  'settings.logoutConfirmMessage': {
    zh: '退出后将清除本机会话与登录凭证，下次使用需重新登录。',
    en: 'This will sign out and clear saved credentials on this device. You will need to sign in again.'
  },
  'settings.logoutConfirmKeepMessage': {
    zh: '退出后将结束本次登录并返回登录页；已信任此设备，登录凭证将保留，可直接一键登录。',
    en: 'This ends the current session and returns to the sign-in page. This device is trusted, so your saved credentials remain for one-tap sign-in.'
  },
  'settings.logoutConfirmOk': { zh: '确认退出', en: 'Sign out' },
  'settings.logoutSuccess': { zh: '已退出登录', en: 'Signed out' },
  'settings.logoutFailed': { zh: '退出登录失败，请重试', en: 'Failed to sign out. Please try again.' },

  'settings.saveFailed': { zh: '设置保存失败，请重试', en: 'Failed to save settings. Please try again.' },

  // ── 信任此设备（trust-device 特性：设置页切换信任的明示提示）──
  'settings.trustOnNotice': {
    zh: '已信任此设备：登录时勾选"信任此设备"将保存登录凭证，下次可自动登录',
    en: 'Trusted: with "Trust this device" checked at sign-in, credentials are kept for automatic sign-in'
  },
  'settings.trustOffNotice': {
    zh: '已取消信任此设备：本次使用不受影响，退出应用后将清除已保存的登录凭证，下次需重新登录',
    en: 'Trust removed: you can keep using the app. Saved credentials will be cleared when the app exits and you will need to sign in again'
  },

  'settings.appName': { zh: 'CampusOS', en: 'CampusOS' },
  'settings.platformLine': { zh: 'HarmonyOS ArkTS', en: 'HarmonyOS ArkTS' },
  'settings.versionUnknown': { zh: '版本未知', en: 'Version unknown' },
};

export class I18n {
  /**
   * 启动初始化：把持久化设置中的 locale 灌入 AppStorage。
   * 由 EntryAbility 在页面装载前调用（须在 SettingsManager.ensureLoaded 之后）。
   */
  static init(): void {
    const locale: string = I18n.normalizeLocale(SettingsManager.getLocale());
    AppStorage.setOrCreate<string>(LOCALE_STORAGE_KEY, locale);
  }

  /**
   * 翻译查找：按当前 locale 取词。
   * 回退链：当前语言缺 → 中文 → 可读占位（禁止空白/键名外泄）。
   *
   * 【locale 参数】可选。页面若传入 `@StorageLink('locale')` 的当前值，
   * 可在渲染期建立状态依赖，使语言切换即时刷新该元素（ArkUI 局部更新）。
   */
  static t(key: string, locale?: string): string {
    const entry: I18nEntry | undefined = SETTINGS_DICTIONARY[key];
    if (entry === undefined) {
      return PLACEHOLDER;
    }
    const current: string = locale !== undefined ? I18n.normalizeLocale(locale) : I18n.getLocale();
    if (current === LOCALE_EN && entry.en.length > 0) {
      return entry.en;
    }
    if (entry.zh.length > 0) {
      return entry.zh;
    }
    return PLACEHOLDER;
  }

  /**
   * 参数化翻译：取 t(key) 文案后，将其中 {name} 形式占位符按 args 安全替换。
   *
   * 【安全策略】args 未提供的参数保留占位符原文（不抛错、不吞占位符）；
   * t(key) 未命中时返回的 PLACEHOLDER 不含 {name}，replace 自然透传。
   *
   * 【locale 参数】可选，语义同 t()：传入 @StorageLink('locale') 当前值
   * 可在渲染期建立状态依赖，语言切换即时刷新。
   */
  static tp(key: string, args: Record<string, string>, locale?: string): string {
    const text: string = I18n.t(key, locale);
    const placeholderPattern: RegExp = /\{([a-zA-Z0-9_]+)\}/g;
    return text.replace(placeholderPattern, (match: string, name: string): string => {
      const value: string | undefined = args[name];
      return value !== undefined ? value : match;
    });
  }

  /**
   * 切换语言：仅接受 zh/en（非法回退 zh）→ 写 AppStorage（页面即时重渲染）
   * → 经 SettingsManager.setLocale 持久化。
   */
  static setLocale(locale: string): void {
    const valid: string = I18n.normalizeLocale(locale);
    AppStorage.setOrCreate<string>(LOCALE_STORAGE_KEY, valid);
    SettingsManager.setLocale(valid);
    Log.i(LOG_TAG, 'locale set %{public}s', valid);
  }

  /** 当前 locale（AppStorage 缺失/非法时回退 zh） */
  static getLocale(): string {
    const stored: string | undefined = AppStorage.get<string>(LOCALE_STORAGE_KEY);
    if (stored !== undefined) {
      return I18n.normalizeLocale(stored);
    }
    return LOCALE_ZH;
  }

  /** 校验：仅 zh/en，其余一律回退 zh */
  private static normalizeLocale(locale: string): string {
    return locale === LOCALE_EN ? LOCALE_EN : LOCALE_ZH;
  }
}
