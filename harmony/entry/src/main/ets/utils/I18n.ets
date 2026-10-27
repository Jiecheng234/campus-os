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
  'campus.dormitory.tabPower': { zh: '电费', en: 'Power' },
  'campus.dormitory.tabLaundry': { zh: '洗衣机', en: 'Laundry' },
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

  // ── AI Agent 工具调用（ai-agent 特性追加：过程态/确认/轨迹）──
  'ai.agentThinking': { zh: '正在思考…', en: 'Thinking…' },
  'ai.agentToolRunning': { zh: '正在调用工具：', en: 'Running tool: ' },
  'ai.traceOk': { zh: '成功', en: 'OK' },
  'ai.traceError': { zh: '失败', en: 'Failed' },
  'ai.traceCancelled': { zh: '已取消', en: 'Cancelled' },
  'ai.traceParams': { zh: '参数', en: 'Params' },
  'ai.confirmTitle': { zh: '确认执行', en: 'Confirm action' },
  'ai.confirmExecute': { zh: '确认执行', en: 'Execute' },
  'ai.confirmRisk': { zh: '低风险 · 可撤销操作', en: 'Low risk · reversible' },
  'ai.confirmFallback': {
    zh: '该操作将在你确认后执行，执行后可通过对应工具撤销。确认继续吗？',
    en: 'This action runs after your approval and can be undone afterwards. Continue?'
  },

  // ── AI Agent 治理（ai-governance 特性追加：权限门禁 / 风险标签 / 审计）──
  'ai.permissionDisabled': {
    zh: '该工具已被禁用，可在 设置 › AI 工具权限 中开启',
    en: 'This tool is disabled. Enable it in Settings › AI tool permissions.'
  },
  'ai.riskNone': { zh: '只读', en: 'Read-only' },
  'ai.riskLow': { zh: '可写', en: 'Write' },
  'ai.riskMedium': { zh: '中风险', en: 'Medium risk' },
  'ai.riskHigh': { zh: '高风险', en: 'High risk' },
  'ai.confirmRequired': { zh: '需确认', en: 'Confirm first' },
  'ai.confirmNotRequired': { zh: '无需确认', en: 'No confirmation' },
  'ai.confirmApproved': { zh: '已确认', en: 'Approved' },
  'ai.confirmDenied': { zh: '已拒绝', en: 'Denied' },
  'ai.confirmUnavailable': { zh: '缺少确认通道', en: 'No channel' },
  'ai.auditPermission': { zh: '权限', en: 'Permission' },
  'ai.auditConfirmation': { zh: '确认', en: 'Confirmation' },
  'ai.auditAffected': { zh: '影响资源', en: 'Affected' },
  'ai.auditParams': { zh: '参数', en: 'Params' },
  'ai.auditResult': { zh: '结果', en: 'Result' },
  'ai.auditError': { zh: '错误', en: 'Error' },
  'ai.auditVerification': { zh: '验证', en: 'Verification' },
  'ai.verifyOk': { zh: '验证通过', en: 'Verified' },
  'ai.verifyFailed': { zh: '验证未通过', en: 'Verification failed' },

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

  // ── 课表交互增强（schedule.detail.*，第三批追加；periodRange 用 tp 的 {start}/{end} 占位符，1 基节次）──
  'schedule.detail.title': { zh: '课程详情', en: 'Class details' },
  'schedule.detail.date': { zh: '日期', en: 'Date' },
  'schedule.detail.weekday': { zh: '星期', en: 'Weekday' },
  'schedule.detail.periods': { zh: '节次', en: 'Periods' },
  'schedule.detail.time': { zh: '时间', en: 'Time' },
  'schedule.detail.periodRange': { zh: '第 {start}–{end} 节', en: 'Periods {start}–{end}' },
  'schedule.detail.noLocation': { zh: '未填写', en: 'Not set' },

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

  // ── AI 治理区（ai-governance 特性追加：行为审计面板 + 工具权限页）──
  'settings.sectionGovernance': { zh: 'AI 治理', en: 'AI governance' },
  'settings.aiPermissions': { zh: 'AI 工具权限', en: 'AI tool permissions' },
  'settings.aiPermDesc': { zh: '管理 AI 可使用的工具范围', en: 'Manage which tools the AI may use' },
  'settings.aiPermSummary': { zh: '已启用 {enabled}/{total}', en: '{enabled}/{total} enabled' },
  'settings.aiPermReadonlyGroup': { zh: '只读工具', en: 'Read-only tools' },
  'settings.aiPermWriteGroup': { zh: '可写工具', en: 'Write tools' },
  'settings.aiPermToolCount': { zh: '{n} 个工具', en: '{n} tools' },
  'settings.aiPermTools': { zh: '包含工具：{tools}', en: 'Tools: {tools}' },
  'settings.aiPermRestoreAll': { zh: '恢复全部权限', en: 'Restore all permissions' },
  'settings.aiPermRestored': { zh: '已恢复全部权限', en: 'All permissions restored' },
  'settings.aiPermToggleFailed': { zh: '保存失败，已恢复原状态', en: 'Save failed; the switch was reverted' },
  'settings.aiPermRestoreFailed': { zh: '恢复失败，请重试', en: 'Restore failed. Please retry.' },
  'settings.aiPermLoadFailed': {
    zh: '权限设置读取失败，开关暂不可用，请稍后重试',
    en: 'Failed to load permission settings; toggles are unavailable. Please retry later.'
  },
  'settings.aiAuditTitle': { zh: 'AI 行为审计', en: 'Action audit' },
  'settings.aiAuditDesc': { zh: 'AI 工具调用记录（本地保存 200 条）', en: 'AI tool call history (200 kept locally)' },
  'settings.aiAuditEmpty': { zh: '暂无审计记录', en: 'No audit records yet' },
  'settings.aiAuditLoadFailed': {
    zh: '审计记录读取失败，请稍后重试',
    en: 'Failed to load audit records. Please retry later.'
  },
  'settings.aiAuditClearWithCount': { zh: '清空审计记录（{n} 条）', en: 'Clear records ({n})' },
  'settings.aiAuditClearTitle': { zh: '清空审计记录', en: 'Clear audit records' },
  'settings.aiAuditClearMessage': {
    zh: '将删除本机保存的全部 AI 工具调用记录，不可恢复。',
    en: 'This deletes all locally stored AI tool call records. This cannot be undone.'
  },
  'settings.aiAuditClearOk': { zh: '清空', en: 'Clear' },
  'settings.aiAuditClearFailed': { zh: '清空失败，请重试', en: 'Failed to clear. Please retry.' },
  'settings.aiPermDomain.campus.weather.read': { zh: '天气查询', en: 'Weather' },
  'settings.aiPermDomain.learning.overview.read': { zh: '学业概览', en: 'Learning overview' },
  'settings.aiPermDomain.learning.homework.read': { zh: '作业查询', en: 'Homework' },
  'settings.aiPermDomain.campus.grades.read': { zh: '成绩查询', en: 'Grades' },
  'settings.aiPermDomain.campus.electricity.read': { zh: '宿舍电费', en: 'Dorm electricity' },
  'settings.aiPermDomain.campus.laundry.read': { zh: '洗衣房', en: 'Laundry' },
  'settings.aiPermDomain.campus.card.read': { zh: '校园卡', en: 'Campus card' },
  'settings.aiPermDomain.campus.card.transactions.read': { zh: '校园卡流水', en: 'Card transactions' },
  'settings.aiPermDomain.campus.network.read': { zh: '校园网', en: 'Campus network' },
  'settings.aiPermDomain.campus.network.devices.read': { zh: '联网设备', en: 'Network devices' },
  'settings.aiPermDomain.campus.sports.read': { zh: '体育场馆', en: 'Sports venues' },
  'settings.aiPermDomain.campus.sports.reservation.read': { zh: '体育场馆预约', en: 'Sports reservations' },
  'settings.aiPermDomain.campus.classroom.read': { zh: '空闲教室', en: 'Classrooms' },
  'settings.aiPermDomain.campus.library.read': { zh: '图书馆', en: 'Library' },
  'settings.aiPermDomain.campus.library.booking.read': { zh: '图书馆预约', en: 'Library bookings' },
  'settings.aiPermDomain.campus.library.room.read': { zh: '研读间', en: 'Study rooms' },
  'settings.aiPermDomain.campus.library.room.member.read': { zh: '研读间成员', en: 'Study room members' },
  'settings.aiPermDomain.campus.library.room.booking.read': { zh: '研读间预约', en: 'Study room bookings' },
  'settings.aiPermDomain.campus.news.read': { zh: '新闻资讯', en: 'News' },
  'settings.aiPermDomain.campus.mail.read': { zh: '清华邮箱', en: 'Mail' },
  'settings.aiPermDomain.schedule.personal.read': { zh: '个人日程', en: 'Personal schedule' },
  'settings.aiPermDomain.schedule.read': { zh: '课表日程', en: 'Class schedule' },
  'settings.aiPermDomain.learning.deadline.write': { zh: '截止日期写入', en: 'Deadline write' },
  'settings.aiPermDomain.campus.library.booking.write': { zh: '图书馆预约写入', en: 'Library booking write' },
  'settings.aiPermDomain.campus.network.devices.write': { zh: '联网设备写入', en: 'Network device write' },
  'settings.aiPermDomain.campus.library.room.booking.write': { zh: '研读间预约写入', en: 'Study room booking write' },
  'settings.aiPermDomain.schedule.personal.write': { zh: '个人日程写入', en: 'Personal schedule write' },
  'settings.aiPermDomain.ai.memory.write': { zh: 'AI 记忆写入', en: 'AI memory write' },

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

  // ── 体测页（pe.*，PETestPage 视觉改版追加；数据 label/value 来自教务原样不翻译）──
  'pe.title': { zh: '体测成绩', en: 'Fitness test' },
  'pe.refresh': { zh: '刷新', en: 'Refresh' },
  'pe.demoHint': { zh: '演示数据 · 登录后显示真实成绩', en: 'Demo data · Sign in to see real results' },
  'pe.loading': { zh: '正在加载体测成绩...', en: 'Loading fitness results…' },
  'pe.errorTitle': { zh: '体测成绩加载失败', en: 'Failed to load fitness results' },
  'pe.retry': { zh: '重试', en: 'Retry' },
  'pe.emptyTitle': { zh: '暂无体测数据', en: 'No fitness data yet' },
  'pe.emptyMessage': {
    zh: '教务系统暂未返回体测记录，可以稍后刷新。',
    en: 'The registrar has not returned fitness records yet. Try refreshing later.'
  },
  'pe.groupSummary': { zh: '总览', en: 'Overview' },
  'pe.groupDetails': { zh: '单项成绩', en: 'Individual events' },

  // ── 首页建议操作（home.suggest.*，对齐原项目 homeWorkbench task_plan 语义）──
  'home.suggest.title': { zh: '建议操作', en: 'Suggested actions' },
  'home.suggest.subtitle': { zh: '按紧急度和上下文排序', en: 'Sorted by urgency and context' },
  'home.suggest.nextClass': { zh: '下一节：{title}', en: 'Next: {title}' },
  'home.suggest.openSchedule': { zh: '看日程', en: 'Schedule' },
  'home.suggest.nextDdl': { zh: '优先处理：{title}', en: 'Prioritize: {title}' },
  'home.suggest.open': { zh: '查看', en: 'Open' },
  'home.suggest.unread': { zh: '{n} 条未读课程通知', en: '{n} unread course notices' },
  'home.suggest.unreadDetail': {
    zh: '先看课程通知，再决定是否添加 DDL 或日程。',
    en: 'Review notices first, then add deadlines or events if needed.'
  },
  'home.suggest.openNotices': { zh: '看通知', en: 'Open' },
  'home.suggest.quietTitle': { zh: '今天节奏比较轻', en: 'A lighter day' },
  'home.suggest.quietDetail': {
    zh: '可以安排复习、整理资料，或让 AI 帮你规划下一阶段。',
    en: 'Good time to review, organize files, or plan the next block.'
  },
  'home.suggest.overdue': { zh: '已经逾期', en: 'Overdue' },
  'home.suggest.dueToday': { zh: '今天截止', en: 'Due today' },
  'home.suggest.dueTomorrow': { zh: '明天截止', en: 'Due tomorrow' },
  'home.suggest.dueInDays': { zh: '{n} 天后截止', en: 'Due in {n} days' },
  'home.suggest.noDeadline': { zh: '未设置截止时间', en: 'No deadline' },

  // ── 图书馆座位（libseat.*，预约/取消/首页直达增量；既有层级文案沿用页内硬编码中文）──
  'libseat.libraryHint': {
    zh: '浏览楼层与区域，对可用座位可直接预约',
    en: 'Browse floors and sections; available seats can be booked directly'
  },
  'libseat.sectionHint': {
    zh: '选择区域查看座位，可用座位支持在线预约',
    en: 'Pick a section to view seats; available ones can be booked'
  },
  'libseat.seatHint': {
    zh: '对"可用"座位点击"预约"，二次确认后提交',
    en: 'Tap "Book" on an available seat and confirm to submit'
  },
  'libseat.bookingsHint': {
    zh: '可取消的记录提供"取消预约"操作',
    en: 'Cancellable bookings offer a cancel action'
  },
  'libseat.bookingsEmptyMessage': {
    zh: '在座位列表中对可用座位点击"预约"',
    en: 'Book an available seat from the seat list'
  },
  'libseat.book': { zh: '预约', en: 'Book' },
  'libseat.cancelBooking': { zh: '取消预约', en: 'Cancel booking' },
  'libseat.submitting': { zh: '提交中…', en: 'Submitting…' },
  'libseat.bookTitle': { zh: '预约此座位？', en: 'Book this seat?' },
  'libseat.cancelTitle': { zh: '取消此预约？', en: 'Cancel this booking?' },
  'libseat.confirmSeat': { zh: '座位：{name}', en: 'Seat: {name}' },
  'libseat.confirmDate': { zh: '日期：{name}', en: 'Date: {name}' },
  'libseat.confirmSegment': { zh: '时段：{name}', en: 'Time: {name}' },
  'libseat.confirmTime': { zh: '时间：{name}', en: 'Time: {name}' },
  'libseat.confirmStatus': { zh: '状态：{name}', en: 'Status: {name}' },
  'libseat.today': { zh: '今天', en: 'Today' },
  'libseat.tomorrow': { zh: '明天', en: 'Tomorrow' },
  'libseat.segmentFallback': {
    zh: '以区域当日时段为准',
    en: 'Per the section\'s daily schedule'
  },
  'libseat.confirmBook': { zh: '确认预约', en: 'Confirm' },
  'libseat.confirmCancel': { zh: '确认取消', en: 'Confirm' },
  'libseat.demoWriteBlocked': {
    zh: '演示模式下不可提交，登录后可预约/取消座位',
    en: 'Demo mode: sign in to book or cancel a seat'
  },
  'libseat.bookSuccess': { zh: '预约成功', en: 'Booked' },
  'libseat.bookFailed': { zh: '预约失败：{msg}', en: 'Failed to book: {msg}' },
  'libseat.cancelSuccess': { zh: '已取消预约', en: 'Booking cancelled' },
  'libseat.cancelFailed': { zh: '取消失败：{msg}', en: 'Failed to cancel: {msg}' },
  'libseat.unknownError': { zh: '未知错误', en: 'Unknown error' },

  // ── 研读间（libroom.*，预约/取消/成员邀请增量；既有层级文案沿用页内硬编码中文）──
  'libroom.kindHint': {
    zh: '浏览研读间类型，选择日期即可查看资源并在线预约',
    en: 'Browse room types, pick a date to view and book rooms'
  },
  'libroom.resourceHint': {
    zh: '对房间点击"预约"，按房间规则选择时段与成员',
    en: 'Tap "Book" on a room, then pick a time slot and members per its rules'
  },
  'libroom.bookingsHint': {
    zh: '我的预约记录支持在线取消（已开始的记录不可取消）',
    en: 'Bookings can be cancelled online (started ones cannot)'
  },
  'libroom.bookingsEmptyMessage': {
    zh: '在资源列表中对房间点击"预约"',
    en: 'Book a room from the resource list'
  },
  'libroom.book': { zh: '预约', en: 'Book' },
  'libroom.cancelBooking': { zh: '取消预约', en: 'Cancel booking' },
  'libroom.submit': { zh: '提交预约', en: 'Submit booking' },
  'libroom.submitting': { zh: '提交中…', en: 'Submitting…' },
  'libroom.bookTitle': { zh: '确认预约研读间？', en: 'Book this room?' },
  'libroom.cancelTitle': { zh: '取消此预约？', en: 'Cancel this booking?' },
  'libroom.confirmRoom': { zh: '房间：{name}', en: 'Room: {name}' },
  'libroom.confirmDate': { zh: '日期：{name}', en: 'Date: {name}' },
  'libroom.confirmTime': { zh: '时段：{name}', en: 'Time: {name}' },
  'libroom.confirmMembers': { zh: '人数：{name}', en: 'People: {name}' },
  'libroom.confirmMembersMulti': {
    zh: '{n} 人（本人 + {m} 名成员）',
    en: '{n} people (you + {m} members)'
  },
  'libroom.confirmMembersSolo': { zh: '1 人（本人）', en: '1 person (you)' },
  'libroom.confirmBook': { zh: '确认预约', en: 'Confirm' },
  'libroom.confirmCancel': { zh: '确认取消', en: 'Confirm' },
  'libroom.formDate': { zh: '日期：{name}', en: 'Date: {name}' },
  'libroom.formStartTime': { zh: '开始时间（HH:mm，分钟为 5 的倍数）', en: 'Start time (HH:mm, 5-min steps)' },
  'libroom.formEndTime': { zh: '结束时间（HH:mm，分钟为 5 的倍数）', en: 'End time (HH:mm, 5-min steps)' },
  'libroom.memberSection': { zh: '邀请成员', en: 'Invite members' },
  'libroom.memberSearchPlaceholder': { zh: '姓名或学号', en: 'Name or student ID' },
  'libroom.search': { zh: '搜索', en: 'Search' },
  'libroom.searching': { zh: '搜索中…', en: 'Searching…' },
  'libroom.noCandidates': { zh: '未找到匹配成员', en: 'No matching members' },
  'libroom.memberSearchFailed': { zh: '成员搜索失败：{msg}', en: 'Member search failed: {msg}' },
  'libroom.add': { zh: '添加', en: 'Add' },
  'libroom.remove': { zh: '移除', en: 'Remove' },
  'libroom.memberCount': {
    zh: '当前 {n} 人（含本人）· 需 {min}~{max} 人',
    en: '{n} people (incl. you) · requires {min}–{max}'
  },
  'libroom.memberCountMin': {
    zh: '当前 {n} 人（含本人）· 至少 {min} 人',
    en: '{n} people (incl. you) · at least {min}'
  },
  'libroom.memberCountNoLimit': {
    zh: '当前 {n} 人（含本人）',
    en: '{n} people (incl. you)'
  },
  'libroom.ruleOpen': { zh: '开放 {start}–{end}', en: 'Open {start}–{end}' },
  'libroom.ruleDuration': { zh: '时长 {min}–{max} 分钟', en: '{min}–{max} minutes' },
  'libroom.ruleDurationMin': { zh: '时长不少于 {min} 分钟', en: 'At least {min} minutes' },
  'libroom.ruleDurationMax': { zh: '时长不超过 {max} 分钟', en: 'At most {max} minutes' },
  'libroom.ruleUsers': { zh: '{min}~{max} 人（含本人）', en: '{min}–{max} people (incl. you)' },
  'libroom.ruleUsersMin': { zh: '至少 {min} 人（含本人）', en: 'At least {min} people (incl. you)' },
  'libroom.ruleUsersMax': { zh: '最多 {max} 人（含本人）', en: 'At most {max} people (incl. you)' },
  'libroom.ruleHintFallback': {
    zh: '以房间当日开放规则为准',
    en: 'Per the room\'s daily rules'
  },
  'libroom.errTimeFormat': {
    zh: '请输入有效的 HH:mm 时间（分钟须为 5 的倍数）',
    en: 'Enter a valid HH:mm time (minutes in 5-min steps)'
  },
  'libroom.errEndAfterStart': {
    zh: '结束时间需晚于开始时间',
    en: 'End time must be after start time'
  },
  'libroom.errOpenTime': {
    zh: '时段须在开放时间 {start}–{end} 内',
    en: 'The slot must be within opening hours {start}–{end}'
  },
  'libroom.errDurationShort': {
    zh: '预约时长不能少于 {min} 分钟',
    en: 'Booking must be at least {min} minutes'
  },
  'libroom.errDurationLong': {
    zh: '预约时长不能超过 {max} 分钟',
    en: 'Booking must be at most {max} minutes'
  },
  'libroom.errUserMin': {
    zh: '该研读间至少需要 {n} 人（含本人），请在成员区邀请成员',
    en: 'This room needs at least {n} people (incl. you); invite members above'
  },
  'libroom.errUserMax': {
    zh: '该研读间最多 {n} 人（含本人），请移除部分成员',
    en: 'This room allows at most {n} people (incl. you); remove some members'
  },
  'libroom.errOverlap': {
    zh: '所选时段已被占用，请更换时段',
    en: 'That slot is already taken; pick another time'
  },
  'libroom.bookSuccess': { zh: '预约成功', en: 'Booked' },
  'libroom.bookFailed': { zh: '预约失败：{msg}', en: 'Failed to book: {msg}' },
  'libroom.cancelSuccess': { zh: '已取消预约', en: 'Booking cancelled' },
  'libroom.cancelFailed': { zh: '取消失败：{msg}', en: 'Failed to cancel: {msg}' },
  'libroom.demoWriteBlocked': {
    zh: '演示模式下不可提交，登录后可预约/取消研读间',
    en: 'Demo mode: sign in to book or cancel a room'
  },
  'libroom.unknownError': { zh: '未知错误', en: 'Unknown error' },

  // ── 宿舍洗衣机（campus-laundry 特性追加：楼宇分组/楼层机台/状态/容错）──
  'laundry.title': { zh: '洗衣机', en: 'Laundry' },
  'laundry.platformJieli': { zh: '洁力', en: 'Jieli' },
  'laundry.platformHaile': { zh: '海乐生活', en: 'Haile Life' },
  'laundry.demoHint': { zh: '演示数据 · 登录后显示真实洗衣机状态', en: 'Demo data · Sign in for live machine status' },
  'laundry.hintBuildings': {
    zh: '选择楼宇查看楼层与洗衣机、洗鞋机、烘干机的实时状态',
    en: 'Pick a building to see live washer, shoe-washer and dryer status by floor'
  },
  'laundry.errorBuildings': { zh: '楼宇列表加载失败', en: 'Failed to load buildings' },
  'laundry.emptyBuildings': { zh: '暂无洗衣机楼宇', en: 'No laundry buildings' },
  'laundry.emptyBuildingsHint': {
    zh: '两个平台均未返回楼宇数据，可稍后重试',
    en: 'Neither platform returned buildings; try again later'
  },
  'laundry.errorFloors': { zh: '机台状态加载失败', en: 'Failed to load machine status' },
  'laundry.emptyFloors': { zh: '暂无机台状态', en: 'No machine status' },
  'laundry.emptyFloorsHint': {
    zh: '该楼宇暂未返回机台数据，可稍后重试',
    en: 'This building returned no machine data; try again later'
  },
  'laundry.statIdle': { zh: '空闲', en: 'Idle' },
  'laundry.statWorking': { zh: '使用中', en: 'In use' },
  'laundry.statError': { zh: '异常', en: 'Error' },
  'laundry.remaining': { zh: '剩余 {n} 分钟', en: '{n} min left' },
  'laundry.updatedAt': { zh: '更新于 {name}', en: 'Updated {name}' },
  'laundry.floorFallback': { zh: '楼层', en: 'Floor' },
  'laundry.thirdPartyNote': {
    zh: '状态由第三方洗衣平台提供，仅供参考',
    en: 'Status is provided by third-party laundry platforms, for reference only'
  },

  // ══════════════════════════════════════════════════════════════════
  // i18n 批次二（校园子页 / 顶层页 / 学习详情页文案迁移）
  // ══════════════════════════════════════════════════════════════════

  // ── 通用（common.*，批次二追加）──
  'common.refresh': { zh: '刷新', en: 'Refresh' },

  // ── 校园财务（campus.finance.*，FinancePage）──
  'campus.finance.pageTitle': { zh: '校园财务', en: 'Campus finance' },
  'campus.finance.demoHint': {
    zh: '演示数据 · 登录后显示真实校园卡信息',
    en: 'Demo data · Sign in for your real card info'
  },
  'campus.finance.balanceTitle': { zh: '校园卡余额', en: 'Card balance' },
  'campus.finance.yuan': { zh: '元', en: 'CNY' },
  'campus.finance.lastTx': { zh: '最近交易 {name}', en: 'Last transaction {name}' },
  'campus.finance.errorTitle': { zh: '校园财务加载失败', en: 'Failed to load finance' },
  'campus.finance.cardInfo': { zh: '校园卡信息', en: 'Card information' },
  'campus.finance.name': { zh: '姓名', en: 'Name' },
  'campus.finance.department': { zh: '院系', en: 'Department' },
  'campus.finance.cardId': { zh: '卡号', en: 'Card no.' },
  'campus.finance.status': { zh: '状态', en: 'Status' },
  'campus.finance.perTxLimit': { zh: '单笔限额', en: 'Per-transaction limit' },
  'campus.finance.dailyLimit': { zh: '日限额', en: 'Daily limit' },
  'campus.finance.yuanAmount': { zh: '{n} 元', en: '¥{n}' },
  'campus.finance.recentTx': { zh: '近 7 天流水', en: 'Last 7 days' },
  'campus.finance.loadingTx': { zh: '正在读取近期流水', en: 'Loading recent transactions' },
  'campus.finance.emptyTxTitle': { zh: '暂无近期流水', en: 'No recent transactions' },
  'campus.finance.emptyTxMessage': {
    zh: '近 7 天没有查询到校园卡交易记录。',
    en: 'No card transactions in the last 7 days.'
  },
  'campus.finance.txFallback': { zh: '校园卡交易', en: 'Card transaction' },
  'campus.finance.balanceLabel': { zh: '余额 {n}', en: 'Balance {n}' },
  'campus.finance.topUp': { zh: '去充值', en: 'Top up' },
  'campus.finance.topUpToast': {
    zh: '充值请通过支付宝或网页版校园卡系统操作',
    en: 'Top up via Alipay or the web campus card system'
  },

  // ── 通用（common.*，批次二追加）──
  'common.search': { zh: '搜索', en: 'Search' },
  'common.clear': { zh: '清除', en: 'Clear' },

  // ── 校园邮件（mail.*，MailPage / MailComposeView / MailDetailView）──
  'mail.title': { zh: '校园邮件', en: 'Campus mail' },
  'mail.unknownSender': { zh: '未知发件人', en: 'Unknown sender' },
  // 系统文件夹（服务层 MAIL_FOLDERS 的 system 标识 → 展示名）
  'mail.folder.inbox': { zh: '收件箱', en: 'Inbox' },
  'mail.folder.drafts': { zh: '草稿箱', en: 'Drafts' },
  'mail.folder.sent': { zh: '已发送', en: 'Sent' },
  'mail.folder.deleted': { zh: '已删除', en: 'Deleted' },
  'mail.folder.junk': { zh: '垃圾邮件', en: 'Junk' },
  'mail.demoHint': {
    zh: '演示数据 · 登录后查看真实邮箱',
    en: 'Demo data · Sign in for your real mailbox'
  },
  'mail.searchPlaceholder': { zh: '搜索邮件', en: 'Search mail' },
  'mail.searchEmptyTitle': { zh: '未找到相关邮件', en: 'No matching messages' },
  'mail.searchEmptyMessage': { zh: '换个关键词试试', en: 'Try another keyword' },
  'mail.emptyTitle': { zh: '暂无邮件', en: 'No messages' },
  'mail.emptyMessage': { zh: '该文件夹暂时没有邮件', en: 'This folder is empty' },
  'mail.unreadCount': { zh: '{n} 封未读', en: '{n} unread' },
  'mail.noUnread': { zh: '无未读邮件', en: 'No unread mail' },
  'mail.totalCount': { zh: '共 {n} 封', en: '{n} in total' },
  'mail.searchResult': { zh: '关键词“{k}” · 找到 {n} 封', en: '“{k}” · {n} found' },
  'mail.loadMore': { zh: '加载更多', en: 'Load more' },
  'mail.loadMoreFailed': { zh: '加载更多失败：{msg}', en: 'Failed to load more: {msg}' },
  'mail.delete': { zh: '删除邮件', en: 'Delete message' },
  'mail.move': { zh: '移动邮件', en: 'Move message' },
  'mail.rowActionsMessage': { zh: '选择对该邮件的操作', en: 'Choose an action for this message' },
  'mail.deleteConfirmMessage': {
    zh: '确认删除所选邮件？删除的邮件可在“已删除”文件夹中找到。',
    en: 'Delete the selected messages? Deleted messages can be found in Trash.'
  },
  'mail.deleteConfirmOk': { zh: '确认删除', en: 'Delete' },
  'mail.deletedToast': { zh: '已删除', en: 'Deleted' },
  'mail.deleteFailed': { zh: '删除失败：{msg}', en: 'Failed to delete: {msg}' },
  'mail.markReadFailed': {
    zh: '已读状态同步失败，可稍后刷新',
    en: 'Failed to sync read state; try refreshing later'
  },
  'mail.pickFolderMessage': { zh: '选择目标文件夹', en: 'Choose a target folder' },
  'mail.moveConfirmMessage': {
    zh: '确认将所选邮件移动到“{name}”？',
    en: 'Move the selected messages to “{name}”?'
  },
  'mail.moveConfirmOk': { zh: '确认移动', en: 'Move' },
  'mail.movedToast': { zh: '已移动到{name}', en: 'Moved to {name}' },
  'mail.moveFailed': { zh: '移动失败：{msg}', en: 'Failed to move: {msg}' },
  'mail.sentToast': { zh: '发送成功', en: 'Sent' },

  // ── 撰写邮件（mail.compose.*，MailComposeView）──
  'mail.compose.title': { zh: '写邮件', en: 'Compose' },
  'mail.compose.to': { zh: '收件人 *', en: 'To *' },
  'mail.compose.toPlaceholder': {
    zh: '收件人邮箱，多人用分号分隔',
    en: 'Recipient addresses, separated by semicolons'
  },
  'mail.compose.toRequired': { zh: '请填写收件人', en: 'Please enter a recipient' },
  'mail.compose.cc': { zh: '抄送', en: 'Cc' },
  'mail.compose.ccPlaceholder': {
    zh: '抄送邮箱（可选），多人用分号分隔',
    en: 'Cc addresses (optional), separated by semicolons'
  },
  'mail.compose.subject': { zh: '主题 *', en: 'Subject *' },
  'mail.compose.subjectPlaceholder': { zh: '邮件主题', en: 'Email subject' },
  'mail.compose.subjectRequired': { zh: '请填写主题', en: 'Please enter a subject' },
  'mail.compose.content': { zh: '正文', en: 'Body' },
  'mail.compose.contentPlaceholder': { zh: '输入正文…', en: 'Write your message…' },
  'mail.compose.sendTitle': { zh: '发送邮件', en: 'Send email' },
  'mail.compose.sendConfirmMessage': { zh: '确认发送这封邮件？', en: 'Send this email?' },
  'mail.compose.sendConfirmOk': { zh: '确认发送', en: 'Send' },
  'mail.compose.sending': { zh: '发送中…', en: 'Sending…' },
  'mail.compose.send': { zh: '发送', en: 'Send' },

  // ── 邮件详情（mail.detail.*，MailDetailView）──
  'mail.detail.title': { zh: '邮件详情', en: 'Message detail' },
  'mail.detail.loading': { zh: '正在加载邮件…', en: 'Loading message…' },
  'mail.detail.from': { zh: '发件人', en: 'From' },
  'mail.detail.to': { zh: '收件人', en: 'To' },
  'mail.detail.cc': { zh: '抄送', en: 'Cc' },
  'mail.detail.time': { zh: '时间', en: 'Date' },
  'mail.detail.folder': { zh: '文件夹', en: 'Folder' },
  'mail.detail.emptyBody': { zh: '暂无正文', en: 'No body' },
  'mail.detail.attachments': { zh: '附件（{n}）', en: 'Attachments ({n})' },

  // ── 校园网络（campus.network.*，NetworkPage）──
  'campus.network.pageTitle': { zh: '校园网络', en: 'Campus network' },
  'campus.network.demoHint': {
    zh: '演示数据 · 登录后显示真实校园网信息',
    en: 'Demo data · Sign in for your real network info'
  },
  'campus.network.balance': { zh: '账户余额', en: 'Account balance' },
  'campus.network.yuan': { zh: '元', en: 'CNY' },
  'campus.network.usedBytes': { zh: '已用流量', en: 'Data used' },
  'campus.network.usedTime': { zh: '已用时长', en: 'Time used' },
  'campus.network.settlementDate': { zh: '结算日期 {name}', en: 'Billing date {name}' },
  'campus.network.errorTitle': { zh: '校园网信息加载失败', en: 'Failed to load network info' },
  'campus.network.captchaTitle': { zh: '校园网需要验证码', en: 'Captcha required' },
  'campus.network.captchaHint': {
    zh: '输入图片中的字符完成校园网登录',
    en: 'Enter the characters in the image to sign in'
  },
  'campus.network.getCaptcha': { zh: '点击获取验证码', en: 'Tap to get captcha' },
  'campus.network.captchaPlaceholder': { zh: '请输入验证码', en: 'Enter captcha' },
  'campus.network.refreshCaptcha': { zh: '换一张', en: 'New image' },
  'campus.network.loggingIn': { zh: '登录中…', en: 'Signing in…' },
  'campus.network.loginButton': { zh: '登录校园网', en: 'Sign in' },
  'campus.network.retryQuery': { zh: '重试原查询', en: 'Retry the original query' },
  'campus.network.captchaFailed': { zh: '验证码获取失败：{msg}', en: 'Failed to get captcha: {msg}' },
  'campus.network.captchaEmpty': { zh: '请输入验证码', en: 'Please enter the captcha' },
  'campus.network.loginSuccess': { zh: '校园网登录成功', en: 'Signed in to the campus network' },
  'campus.network.accountInfo': { zh: '账户信息', en: 'Account information' },
  'campus.network.username': { zh: '用户名', en: 'Username' },
  'campus.network.contactEmail': { zh: '联系邮箱', en: 'Email' },
  'campus.network.contactPhone': { zh: '联系电话', en: 'Phone' },
  'campus.network.contactLandline': { zh: '固定电话', en: 'Landline' },
  'campus.network.realName': { zh: '真实姓名', en: 'Real name' },
  'campus.network.userGroup': { zh: '用户组', en: 'User group' },
  'campus.network.status': { zh: '状态', en: 'Status' },
  'campus.network.location': { zh: '所在位置', en: 'Location' },
  'campus.network.allowedDevices': { zh: '允许在线设备数', en: 'Allowed online devices' },
  'campus.network.devices': { zh: '在线设备', en: 'Online devices' },
  'campus.network.loadingDevices': { zh: '正在读取在线设备', en: 'Loading online devices' },
  'campus.network.emptyDevicesTitle': { zh: '暂无在线设备', en: 'No online devices' },
  'campus.network.emptyDevicesMessage': {
    zh: '当前账号没有查询到在线设备。',
    en: 'No online devices found for this account.'
  },
  'campus.network.deviceFallback': { zh: '在线设备', en: 'Device' },
  'campus.network.ip4': { zh: 'IPv4 {name}', en: 'IPv4 {name}' },
  'campus.network.ip6': { zh: 'IPv6 {name}', en: 'IPv6 {name}' },
  'campus.network.loginTime': { zh: '登录时间 {name}', en: 'Signed in {name}' },
  'campus.network.mac': { zh: 'MAC {name}', en: 'MAC {name}' },
  'campus.network.processing': { zh: '处理中', en: 'Working…' },
  'campus.network.logout': { zh: '注销', en: 'Log out' },
  'campus.network.logoutTitle': { zh: '注销校园网设备', en: 'Log out device' },
  'campus.network.logoutWarning': {
    zh: '设备可能立刻断网，需要重新认证后才能联网。',
    en: 'The device may go offline immediately and need re-authentication to reconnect.'
  },
  'campus.network.logoutOk': { zh: '确认注销', en: 'Log out' },
  'campus.network.loggedOutToast': { zh: '设备已注销', en: 'Device logged out' },
  'campus.network.logoutFailed': { zh: '注销失败：{msg}', en: 'Failed to log out: {msg}' },

  // ── 校园资讯（campus.news.*，NewsPage）──
  'campus.news.pageTitle': { zh: '校园新闻', en: 'Campus news' },
  'campus.news.detailTitle': { zh: '新闻详情', en: 'News detail' },
  'campus.news.demoHint': {
    zh: '演示数据 · 登录后显示真实资讯',
    en: 'Demo data · Sign in for real news'
  },
  'campus.news.loadingDetail': { zh: '正在加载正文...', en: 'Loading content…' },
  'campus.news.noDetailUrl': { zh: '该资讯缺少详情链接', en: 'This item has no detail link' },
  'campus.news.emptyContent': { zh: '暂无内容', en: 'No content' },
  'campus.news.sourceFallback': { zh: '清华信息门户', en: 'Tsinghua info portal' },
  'campus.news.topped': { zh: '置顶', en: 'Pinned' },

  // ── 培养方案（campus.program.*，ProgramPage）──
  'campus.program.progress': {
    zh: '已完成 {earned} / {required} 学分',
    en: 'Earned {earned} / {required} credits'
  },
  'campus.program.creditsShort': { zh: '{earned}/{required} 学分', en: '{earned}/{required} cr' },
  'campus.program.credits': { zh: '{n} 学分', en: '{n} cr' },

  // ── 场馆预约入口（campus.reservation.*，ReservationPage）──
  'campus.reservation.libSeat': { zh: '图书馆座位预约', en: 'Library seat booking' },
  'campus.reservation.libSeatHint': { zh: '已预约 0 个座位', en: '0 seats booked' },
  'campus.reservation.libRoom': { zh: '研读间预约', en: 'Study room booking' },
  'campus.reservation.libRoomHint': { zh: '已预约 0 间', en: '0 rooms booked' },
  'campus.reservation.sports': { zh: '体育场馆预约', en: 'Sports venue booking' },
  'campus.reservation.sportsHint': {
    zh: '羽毛球 · 乒乓球 · 游泳馆',
    en: 'Badminton · Table tennis · Pool'
  },

  // ── 通用（common.*，批次二补充）──
  'common.today': { zh: '今天', en: 'Today' },
  'common.tomorrow': { zh: '明天', en: 'Tomorrow' },

  // ── 体育场馆（campus.sports.*，SportsBookingPage）──
  'campus.sports.title': { zh: '体育场馆', en: 'Sports venues' },
  // 服务层错误文案的本地化映射（页面展示，避免英文模式泄露中文）
  'campus.sports.errorLimit': {
    zh: '无法获取体育场馆预约限额',
    en: 'Could not load sports venue booking quotas'
  },
  'campus.sports.errorSession': {
    zh: '体育场馆会话未登录，请刷新重试',
    en: 'Sports venue session is not signed in. Please refresh and try again.'
  },
  'campus.sports.errorSessionBuild': {
    zh: '体育场馆会话建立失败，请稍后重试',
    en: 'Could not establish the sports venue session. Please try again later.'
  },
  'campus.sports.errorOrders': {
    zh: '无法加载体育场馆预约订单',
    en: 'Could not load sports booking records'
  },
  'campus.sports.errorGeneric': {
    zh: '操作失败，请稍后重试',
    en: 'Something went wrong. Please try again later.'
  },
  'campus.sports.recordsTitle': { zh: '我的预约记录', en: 'My bookings' },
  'campus.sports.locked': { zh: '已锁定', en: 'Locked' },
  'campus.sports.notBookable': { zh: '不可预约', en: 'Not bookable' },
  'campus.sports.bookable': { zh: '可预约', en: 'Bookable' },
  'campus.sports.limitTitle': { zh: '今日限额', en: 'Daily limit' },
  'campus.sports.limitUsed': { zh: '已用 {used} / 上限 {max}', en: 'Used {used} / Limit {max}' },
  'campus.sports.phone': { zh: '联系电话', en: 'Phone' },
  'campus.sports.timeTbd': { zh: '时段待发布', en: 'Time to be announced' },
  'campus.sports.fieldTbd': { zh: '场地待发布', en: 'Field to be announced' },
  'campus.sports.fieldFallback': { zh: '场地', en: 'Field' },
  'campus.sports.timeFallback': { zh: '时间待定', en: 'Time TBC' },
  'campus.sports.methodFallback': { zh: '支付方式待定', en: 'Payment method TBC' },
  'campus.sports.payable': { zh: '可支付', en: 'Payable' },
  'campus.sports.cancellable': { zh: '可取消', en: 'Cancellable' },
  'campus.sports.priceLine': { zh: '{price} 元 · {method}', en: '¥{price} · {method}' },
  'campus.sports.readonlyHint': {
    zh: '资源信息仅供查询，下单与支付请通过官方渠道完成',
    en: 'For reference only. Book and pay via official channels.'
  },
  'campus.sports.recordsHint': {
    zh: '记录仅供查询，下单与支付请通过官方渠道完成',
    en: 'Records are for reference only. Book and pay via official channels.'
  },
  'campus.sports.emptyResourcesTitle': { zh: '暂无可预约资源', en: 'No bookable resources' },
  'campus.sports.emptyResourcesMessage': {
    zh: '该场馆当日暂无发布资源',
    en: 'No resources published for this venue today.'
  },
  'campus.sports.emptyRecordsTitle': { zh: '暂无预约记录', en: 'No bookings yet' },
  'campus.sports.emptyRecordsMessage': {
    zh: '预约场馆请通过官方渠道完成',
    en: 'Book venues via official channels.'
  },

  // ── 空教室查询（classroom.*，ClassroomPage）──
  'classroom.title': { zh: '空教室查询', en: 'Free classrooms' },
  'classroom.loadingList': { zh: '正在加载教学楼列表...', en: 'Loading buildings…' },
  'classroom.errorList': { zh: '教学楼列表加载失败', en: 'Failed to load buildings' },
  'classroom.loadingState': { zh: '加载教室状态...', en: 'Loading room status…' },
  'classroom.errorState': { zh: '教室状态加载失败', en: 'Failed to load room status' },
  'classroom.day0': { zh: '周一', en: 'Mon' },
  'classroom.day1': { zh: '周二', en: 'Tue' },
  'classroom.day2': { zh: '周三', en: 'Wed' },
  'classroom.day3': { zh: '周四', en: 'Thu' },
  'classroom.day4': { zh: '周五', en: 'Fri' },
  'classroom.day5': { zh: '周六', en: 'Sat' },
  'classroom.day6': { zh: '周日', en: 'Sun' },
  'classroom.todayMark': { zh: '·今', en: ' · Today' },
  'classroom.periodsFree': { zh: '{n}/{total} 节空', en: '{n}/{total} free' },
  'classroom.freeAllDay': { zh: '{n}/{total} 间全天空闲', en: '{n}/{total} free all day' },
  'classroom.emptyTitle': { zh: '该教学楼无教室数据', en: 'No room data for this building' },
  'classroom.emptyMessage': {
    zh: '可以切换其它教学楼、周次或稍后刷新',
    en: 'Try another building or week, or refresh later'
  },
  'classroom.statusAvailable': { zh: '空闲', en: 'Free' },
  'classroom.statusTeaching': { zh: '上课', en: 'Class' },
  'classroom.statusExam': { zh: '考试', en: 'Exam' },
  'classroom.statusBorrowed': { zh: '借用', en: 'Borrowed' },
  'classroom.statusDisabled': { zh: '停用', en: 'Closed' },
  'classroom.statusReserved': { zh: '保留', en: 'Reserved' },
  'classroom.colRoom': { zh: '教室', en: 'Room' },
  'classroom.colCapacity': { zh: '容量', en: 'Capacity' },
  'classroom.colPeriods': { zh: '1  2  3  4  5  6', en: '1  2  3  4  5  6' },

  // ── 成绩查询（campus.grades.*，GradesPage）──
  'campus.grades.demoHint': {
    zh: '演示数据 · 登录后显示真实成绩',
    en: 'Demo data · Sign in for real grades'
  },
  'campus.grades.subtitleStats': {
    zh: '已修 {all} 学分（计入绩点 {total}）· 共 {n} 门',
    en: '{all} credits earned ({total} in GPA) · {n} courses'
  },
  'campus.grades.noSemester': { zh: '未分学期', en: 'No semester' },
  'campus.grades.gpaShort': { zh: '绩点 {n}', en: 'GPA {n}' },
  'campus.grades.credits': { zh: '{n} 学分', en: '{n} cr' },
  'campus.grades.courseMeta': { zh: '{c} 学分 · 绩点 {p}', en: '{c} cr · GPA {p}' },

  // ── 占位页（common.placeholder.*，PlaceholderPage）──
  'common.placeholder.defaultTitle': { zh: '页面', en: 'Page' },
  'common.placeholder.wip': { zh: '功能开发中', en: 'Work in progress' },

  // ── 网络学习详情页（learning.*，pages/learning/*）──
  'learning.course.code': { zh: '课程代码', en: 'Course code' },
  'learning.course.teacher': { zh: '授课教师', en: 'Instructor' },
  'learning.course.semester': { zh: '学期', en: 'Semester' },
  'learning.file.title': { zh: '文件详情', en: 'File details' },
  'learning.file.course': { zh: '所属课程', en: 'Course' },
  'learning.file.size': { zh: '文件大小', en: 'Size' },
  'learning.file.type': { zh: '文件类型', en: 'Type' },
  'learning.file.uploadTime': { zh: '上传时间', en: 'Uploaded' },
  'learning.file.descriptionTitle': { zh: '文件说明', en: 'Description' },
  'learning.file.emptyDescription': { zh: '暂无说明', en: 'No description' },
  'learning.file.download': { zh: '下载文件', en: 'Download' },
  'learning.file.downloadWithSize': { zh: '下载文件 ({size})', en: 'Download ({size})' },
  'learning.homework.title': { zh: '作业详情', en: 'Homework details' },
  'learning.homework.course': { zh: '课程', en: 'Course' },
  'learning.homework.deadline': { zh: '截止时间', en: 'Deadline' },
  'learning.homework.requirements': { zh: '作业要求', en: 'Requirements' },
  'learning.homework.emptyRequirements': { zh: '暂无作业要求', en: 'No requirements' },
  'learning.homework.attachments': { zh: '附件材料 ({n})', en: 'Attachments ({n})' },
  'learning.homework.download': { zh: '下载', en: 'Download' },
  'learning.homework.feedback': { zh: '成绩反馈', en: 'Feedback' },
  'learning.homework.grade': { zh: '成绩：{grade}', en: 'Grade: {grade}' },
  'learning.homework.graded': { zh: '已批改', en: 'Graded' },
  'learning.homework.notGraded': {
    zh: '作业尚未批改，请耐心等待。',
    en: 'Not graded yet. Please wait.'
  },
  'learning.notification.title': { zh: '通知详情', en: 'Notification details' },
  'learning.notification.empty': { zh: '暂无内容', en: 'No content' },
  'webviewer.defaultTitle': { zh: '浏览器', en: 'Browser' },

  // ── US4 复核补齐：图书馆座位（libseat.*，LibrarySeatPage）──
  'libseat.title': { zh: '图书馆座位', en: 'Library seats' },
  'libseat.bookingsTitle': { zh: '我的预约', en: 'My bookings' },
  'libseat.errorNoLibrary': { zh: '未获取到图书馆列表', en: 'No libraries found' },
  'libseat.libraryFallback': { zh: '图书馆', en: 'Library' },
  'libseat.floorN': { zh: '楼层 {n}', en: 'Floor {n}' },
  'libseat.floorAvailability': { zh: '可用 {n} / 共 {total} 座位', en: '{n} of {total} seats free' },
  'libseat.sectionN': { zh: '区域 {n}', en: 'Section {n}' },
  'libseat.sectionAvailability': {
    zh: '可用 {n} / 共 {total} · 已预约 {r}',
    en: '{n} of {total} free · {r} booked'
  },
  'libseat.notOpen': { zh: '暂不开放', en: 'Not open' },
  'libseat.closedBadge': { zh: '未开放', en: 'Closed' },
  'libseat.emptyFloorsTitle': { zh: '暂无楼层信息', en: 'No floor info' },
  'libseat.emptyFloorsMessage': {
    zh: '该图书馆暂无可用楼层',
    en: 'No floors available in this library'
  },
  'libseat.emptySectionsTitle': { zh: '暂无区域信息', en: 'No section info' },
  'libseat.emptySectionsMessage': {
    zh: '该楼层暂无开放区域',
    en: 'No open sections on this floor'
  },
  'libseat.emptySeatsTitle': { zh: '暂无座位信息', en: 'No seat info' },
  'libseat.emptySeatsMessage': {
    zh: '该区域暂无可查询座位',
    en: 'No seats to show in this section'
  },
  'libseat.emptyBookingsTitle': { zh: '暂无预约记录', en: 'No bookings yet' },
  'libseat.bookingFallback': { zh: '预约 {id}', en: 'Booking {id}' },
  'libseat.unknownStatus': { zh: '未知', en: 'Unknown' },
  'libseat.seatAvailable': { zh: '可用', en: 'Available' },
  'libseat.seatBooked': { zh: '已预约', en: 'Booked' },
  'libseat.seatOccupied': { zh: '已被占用', en: 'Occupied' },
  'libseat.seatUnavailable': { zh: '不可用', en: 'Unavailable' },

  // ── US4 复核补齐：研读间（libroom.*，LibraryRoomPage）──
  'libroom.title': { zh: '研读间', en: 'Study rooms' },
  'libroom.bookingsTitle': { zh: '我的预约', en: 'My bookings' },
  'libroom.loadingSession': { zh: '正在建立研读间会话…', en: 'Starting study room session…' },
  'libroom.loadingKinds': { zh: '正在刷新研读间类型…', en: 'Refreshing room types…' },
  'libroom.loadingResources': { zh: '正在读取研读间资源…', en: 'Loading rooms…' },
  'libroom.loadingBookings': { zh: '正在读取我的预约…', en: 'Loading my bookings…' },
  'libroom.resourcesFallback': { zh: '研读间资源', en: 'Rooms' },
  'libroom.roomFallback': { zh: '研读间 {id}', en: 'Room {id}' },
  'libroom.kindFallback': { zh: '类型 {id}', en: 'Type {id}' },
  'libroom.kindCardHint': {
    zh: '{rooms} 个房间 · 点选查看近 {days} 天',
    en: '{rooms} rooms · Tap to view the next {days} days'
  },
  'libroom.emptyKindsTitle': { zh: '无研读间类型', en: 'No room types' },
  'libroom.emptyKindsMessage': {
    zh: '接口未返回研读间类型数据，可稍后刷新',
    en: 'No room types returned. Try refreshing later.'
  },
  'libroom.userRange': { zh: '（{min}~{max}人）', en: ' ({min}–{max} people)' },
  'libroom.closedBadge': { zh: '未开放', en: 'Closed' },
  'libroom.bookableBadge': { zh: '可预约', en: 'Bookable' },
  'libroom.emptyResourcesTitle': { zh: '暂无可预约资源', en: 'No bookable rooms' },
  'libroom.emptyResourcesMessage': {
    zh: '该类型当天暂无可预约研读间',
    en: 'No bookable rooms of this type today'
  },
  'libroom.emptyBookingsTitle': { zh: '暂无预约记录', en: 'No bookings yet' },
  'libroom.membersLine': { zh: '成员：{names}', en: 'Members: {names}' },

  // ── US4 复核补齐：宿舍服务（campus.dormitory.*，DormitoryPage）──
  'campus.dormitory.demoHint': {
    zh: '演示数据 · 登录后显示真实电费',
    en: 'Demo data · Sign in for real power info'
  },
  'campus.dormitory.powerTitle': { zh: '当前剩余电量', en: 'Remaining power' },
  'campus.dormitory.kwh': { zh: '度', en: 'kWh' },
  'campus.dormitory.updatedAt': { zh: '更新于 {name}', en: 'Updated {name}' },
  'campus.dormitory.powerError': { zh: '电费余额加载失败', en: 'Failed to load power balance' },
  'campus.dormitory.roomInfo': { zh: '房间信息', en: 'Room info' },
  'campus.dormitory.owner': { zh: '户名', en: 'Owner' },
  'campus.dormitory.building': { zh: '楼号', en: 'Building' },
  'campus.dormitory.room': { zh: '房间', en: 'Room' },
  'campus.dormitory.studentId': { zh: '学号', en: 'Student ID' },
  'campus.dormitory.records': { zh: '缴费记录', en: 'Payment records' },
  'campus.dormitory.topUp': { zh: '去充值', en: 'Top up' },
  'campus.dormitory.topUpToast': {
    zh: '充值请通过网页版电费系统操作',
    en: 'Top up via the web power system'
  },
  'campus.dormitory.colTime': { zh: '充值时间', en: 'Time' },
  'campus.dormitory.colAmount': { zh: '充值', en: 'Amount' },
  'campus.dormitory.colBefore': { zh: '充值前', en: 'Before' },
  'campus.dormitory.colAfter': { zh: '充值后', en: 'After' },
  'campus.dormitory.colOperator': { zh: '操作员', en: 'Operator' },
  'campus.dormitory.colNote': { zh: '备注', en: 'Note' },

  // ── 支付基础设施（payment.*，T02）──
  'payment.error.invalidCode': { zh: '支付码无效，请重试', en: 'Payment code is invalid. Please try again.' },
  'payment.error.alipayNotInstalled': {
    zh: '未检测到支付宝，请先安装支付宝后重试',
    en: 'Alipay was not found. Install Alipay and try again.'
  },
  'payment.error.launchFailed': { zh: '打开支付宝失败，请重试', en: 'Could not open Alipay. Please try again.' },
  'payment.error.unsupported': {
    zh: '当前设备不支持外部支付链接',
    en: 'This device does not support external payment links.'
  },
  'payment.link.ready': { zh: '支付链接已生成', en: 'Payment link is ready.' },
  'payment.launch.opened': { zh: '已请求打开支付宝，请完成支付', en: 'Alipay was opened. Complete payment there.' },
  'payment.return.refreshing': {
    zh: '已返回 CampusOS，正在刷新余额与记录…',
    en: 'Back in CampusOS. Refreshing balance and records…'
  },
  'payment.return.unconfirmed': {
    zh: '未确认支付结果。若已完成支付，请刷新查看；若未支付，可重试。',
    en: 'Payment is not confirmed. Refresh if you paid; retry if you did not.'
  },
  'payment.diag.section': { zh: '支付通道自检（仅调试）', en: 'Payment channel diagnostics (debug)' },
  'payment.diag.probe': { zh: '探测支付宝', en: 'Check Alipay' },
  'payment.diag.openTest': { zh: '打开支付宝测试链接', en: 'Open Alipay test link' },
  'payment.diag.available': { zh: '支付宝可用', en: 'Alipay is available' },
  'payment.diag.notInstalled': { zh: '未检测到支付宝', en: 'Alipay was not found' },
  'payment.diag.noPayment': { zh: '此操作不会发起支付', en: 'This does not start a payment' },
  'payment.diag.returned': { zh: '已收到支付回读事件', en: 'Payment return event received' },

  // ── 选课系统错误（courseReg.error.*，T03 CourseRegService）──
  'courseReg.error.notLoggedIn': { zh: '需要登录后才能访问选课系统', en: 'Please sign in to access course registration' },
  'courseReg.error.sessionExpired': { zh: '选课系统会话已失效，请重新登录', en: 'Your course registration session has expired' },
  'courseReg.error.network': { zh: '网络请求失败，请检查网络后重试', en: 'Network request failed. Please try again' },
  'courseReg.error.http': { zh: '选课系统返回异常状态', en: 'The course registration service returned an error' },
  'courseReg.error.parse': { zh: '选课系统响应格式异常', en: 'Unexpected course registration response' },
  'courseReg.error.noSemester': { zh: '未找到可用学期', en: 'No available semester was found' },
  'courseReg.error.noFormToken': { zh: '选课表单缺少令牌，请重新登录后重试', en: 'The form token is missing. Please sign in again' },
  'courseReg.error.rejected': { zh: '选课系统拒绝了本次操作', en: 'The course registration request was rejected' },
  'courseReg.error.unconfirmed': {
    zh: '选课系统未返回明确结果，请回查已选课程',
    en: 'The result is unconfirmed. Please check your selected courses'
  },
  'courseReg.error.unsupportedPriority': { zh: '不支持的选课类型', en: 'Unsupported course selection type' },
  'courseReg.error.invalidParam': { zh: '请求参数不完整或不合法', en: 'Invalid request parameters' },
  'courseReg.error.server': { zh: '选课系统暂时不可用', en: 'The course registration service is unavailable' },

  // ── 学习详情深链：课程详情聚合（learning.detail.*，CourseDetailPage）──
  'learning.detail.groupHomework': { zh: '作业', en: 'Homework' },
  'learning.detail.groupNotifications': { zh: '通知', en: 'Notices' },
  'learning.detail.groupFiles': { zh: '资料', en: 'Files' },
  'learning.detail.emptyHomework': { zh: '该课程暂无作业', en: 'No assignments in this course' },
  'learning.detail.emptyNotifications': { zh: '该课程暂无通知', en: 'No notices in this course' },
  'learning.detail.emptyFiles': { zh: '该课程暂无资料', en: 'No files in this course' },
  'learning.detail.courseMissingTitle': { zh: '课程不存在或已不可用', en: 'Course not found or unavailable' },
  'learning.detail.courseMissingMessage': {
    zh: '该课程可能已被删除或学期已切换',
    en: 'This course may have been removed or the semester changed'
  },
  'learning.detail.back': { zh: '返回列表', en: 'Back to list' },
  'learning.detail.loading': { zh: '正在加载…', en: 'Loading…' },
  'learning.detail.syncFailed': {
    zh: '部分数据加载失败，可稍后重试',
    en: 'Some data failed to load. Try again later'
  },
  'common.retry': { zh: '重试', en: 'Retry' },

  // ── 学习详情深链：通知详情（learning.notification.*，NotificationDetailPage）──
  'learning.notification.course': { zh: '所属课程', en: 'Course' },
  'learning.notification.publisher': { zh: '发布人', en: 'Publisher' },
  'learning.notification.publishTime': { zh: '发布时间', en: 'Published' },
  'learning.notification.loadingBody': { zh: '正在获取正文…', en: 'Loading content…' },
  'learning.notification.loadFailed': { zh: '正文获取失败', en: 'Failed to load content' },

  // ── 学习详情深链：资料详情（learning.file.*，FileDetailPage / LearningFileStore）──
  'learning.file.preview': { zh: '预览', en: 'Preview' },
  'learning.file.downloading': { zh: '下载中…', en: 'Downloading…' },
  'learning.file.downloaded': { zh: '已下载', en: 'Downloaded' },
  'learning.file.open': { zh: '打开', en: 'Open' },
  'learning.file.downloadSuccess': { zh: '已保存：{name}', en: 'Saved: {name}' },
  'learning.file.downloadFailed': { zh: '下载失败，请重试', en: 'Download failed. Please retry' },
  'learning.file.invalidResponse': {
    zh: '服务端返回了页面而非文件，可能是会话已失效',
    en: 'The server returned a page instead of the file. Your session may have expired'
  },
  'learning.file.previewFailed': { zh: '预览加载失败', en: 'Preview failed to load' },
  'learning.file.demoUnavailable': {
    zh: '演示模式下不可用，登录后可预览与下载真实资料',
    en: 'Not available in demo mode. Sign in to preview and download real files'
  },
  'learning.file.openFailed': { zh: '无法打开该文件', en: 'Could not open this file' },
  'learning.file.nameFallback': { zh: '文件', en: 'File' },

  // ── 学习详情深链：内嵌浏览器（webviewer.*，WebViewerPage）──
  'webviewer.loading': { zh: '正在加载…', en: 'Loading…' },
  'webviewer.loadFailed': { zh: '页面加载失败', en: 'Failed to load the page' },

  // ── 学习详情深链：手动 DDL（learning.ddl.*，LearningPage / HomePage）──
  'learning.ddl.manualBadge': { zh: '手动', en: 'Manual' },
  'learning.ddl.delete': { zh: '删除', en: 'Delete' },
  'learning.ddl.deleteTitle': { zh: '删除这条 DDL？', en: 'Delete this deadline?' },
  'learning.ddl.deleteMessage': {
    zh: '将删除「{title}」，该操作不可撤销。',
    en: '"{title}" will be deleted. This cannot be undone.'
  },
  'learning.ddl.deleteOk': { zh: '删除', en: 'Delete' },
  'learning.ddl.overdue': { zh: '已过期', en: 'Overdue' },
  'learning.ddl.savedToast': { zh: '已添加', en: 'Added' },
  'learning.ddl.deletedToast': { zh: '已删除', en: 'Deleted' },
  'learning.ddl.dateInvalid': { zh: '日期格式应为 YYYY-MM-DD', en: 'Date should be YYYY-MM-DD' },
  'learning.ddl.timeInvalid': { zh: '时间格式应为 HH:mm', en: 'Time should be HH:mm' },
  'learning.ddl.saveFailed': { zh: '保存失败，请重试', en: 'Save failed. Please retry' },
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

  /** 词典是否收录该键（权限域标题等场景：缺失时调用方回退原始键名展示） */
  static has(key: string): boolean {
    return SETTINGS_DICTIONARY[key] !== undefined;
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
