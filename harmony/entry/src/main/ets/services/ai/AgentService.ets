/**
 * ============================================================================
 * AgentService — Agent 循环（对话 → 工具调用 → 回灌 → 最终回答）
 * ============================================================================
 *
 * 【对齐参考实现】src/services/ai/agentService.ts（runAgent/buildAgentContext/
 *   buildSystemPrompt/createMockAgentReply 语义逐条移植）：
 *   - 流式 ≤ MAX_AGENT_ROUNDS 轮循环（FR-015/D1）：每轮以 SSE 流式请求模型
 *     （携带 tools + tool_choice:'auto'），从流式增量中【同时累积 content 与
 *     tool_calls】→ 执行 tool_calls → 结果以 role:tool 回灌 → 直到出现不含
 *     工具调用的轮次，其累积 content 即最终回答（经 onDelta 逐字流式输出，
 *     onAnswer 为结束信号；中间工具轮正文不展示，SC-009）。
 *   - 未知工具：回灌可读错误 {error: '未知工具：…'}，不中断循环；同时派发
 *     onToolStart/onToolEnd 使页面收起中间轮已流出正文并复位过程态。
 *   - 写工具治理链（D4）：dryRun（预览）→ requestConfirmation（二次确认，
 *     拒绝即不执行）→ run → verify（执行后验证）→ 审计留痕（内存会话级，D7）。
 *   - 缺少确认通道：requiresConfirmation 工具直接被阻止（confirmation=
 *     unavailable，status=cancelled），绝不静默执行。
 *
 * 【与参考实现的差异】
 *   - apiKey 独立入参（沿用 LLMService 的 config/key 分离约定）。
 *   - LLM 失败抛 AgentRunError（携带 LLMErrorKind），页面映射 i18n 文案。
 *   - 回调增加可选 isCancelled（停止按钮/离开页面时循环在轮次/工具边界退出）。
 *   - 不可逆写工具（选课/退课）不注册（见 AgentTools/AgentWriteTools）。
 * ============================================================================
 */
import { AgentContext, AgentToolDef, AIMemory, ChatMessage, ToolTrace } from '../../domain/AIAgentTypes';
import { ActionExecutionStatus, ActionPreview, AuditRecord, ConfirmationStatus, ToolRisk, VerificationResult } from '../../domain/ActionTypes';
import { LLMErrorKind, LLMProviderConfig, LLMService, LLMToolCall, LLMToolsOutcome, LLMRoundStreamOptions } from './LLMService';
import { AgentTools } from './AgentTools';
import { AgentWriteTools } from './AgentWriteTools';
import { AIMemoryStore } from '../../state/AIMemoryStore';
import { SettingsManager } from '../../state/SettingsManager';
import { SessionManager } from '../auth/SessionManager';
import { CampusDataService, CampusCourse, CampusHomework, ScheduleEvent } from '../campus/CampusDataService';
import { fetchHomeWeather, HomeWeather } from '../campus/WeatherService';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';
import { ActionAuditStore } from '../../storage/ActionAuditStore';
import { AIPermissionStore } from '../../storage/AIPermissionStore';
import { I18n } from '../../utils/I18n';
import { generateUUID } from '../../utils/CryptoUtils';
import { Log } from '../../utils/Logger';

const LOG_TAG: string = 'AgentService';
/** 最大工具调用轮数（每轮可含多个 tool_calls；超出给出可读兜底） */
const MAX_AGENT_ROUNDS: number = 6;
/** 会话内审计记录上界（超出淘汰最旧；与持久化上限 200 对齐） */
const MAX_AUDIT_RECORDS: number = 200;
/** 轨迹参数兜底截断长度（无 summarize 的工具） */
const TRACE_PARAMS_CLIP: number = 120;

/** LLM 请求失败（携带错误类别；页面经既有 errorTextFor 映射 i18n 文案） */
export class AgentRunError extends Error {
  readonly kind: LLMErrorKind;

  constructor(kind: LLMErrorKind) {
    super('agent failed: ' + kind);
    this.kind = kind;
  }
}

/** onToolEnd 附加上下文（轨迹 + 治理链留痕，供页面渲染/审计展示） */
export class AgentToolEndMeta {
  trace: ToolTrace = new ToolTrace();
  preview: ActionPreview | undefined = undefined;
  verification: VerificationResult | undefined = undefined;
  confirmation: string = '';
  resultJson: string = '';
}

/** Agent 回调契约（对齐 RN AgentCallbacks + 流式增量 + 可选取消信号） */
export class AgentCallbacks {
  /** 最终回答增量（最终轮流式逐字回调；中间工具轮正文不回调，FR-015/SC-009） */
  onDelta: (text: string) => void = (text: string): void => {};
  /** 最终回答结束信号（完整文本；正文已经由 onDelta 流式输出） */
  onAnswer: (text: string) => void = (text: string): void => {};
  /** 工具开始执行（过程可视化；argsJson 为模型原始参数 JSON） */
  onToolStart: (tool: AgentToolDef, argsJson: string) => void =
    (tool: AgentToolDef, argsJson: string): void => {};
  /** 工具执行结束（status=ActionExecutionStatus；meta 含轨迹与治理留痕） */
  onToolEnd: (tool: AgentToolDef, status: string, detail: string, meta: AgentToolEndMeta) => void =
    (tool: AgentToolDef, status: string, detail: string, meta: AgentToolEndMeta): void => {};
  /** 写操作二次确认；返回 true 才执行（缺省视为无确认通道，写工具被阻止） */
  requestConfirmation: ((tool: AgentToolDef, argsJson: string, preview: ActionPreview | undefined) => Promise<boolean>) | undefined =
    undefined;
  /** 取消信号（停止按钮/离开页面）：轮次与工具边界检查，取消后静默退出 */
  isCancelled: (() => boolean) | undefined = undefined;
}

/** 会话轮次（序列化为原始 JSON 文本；tool_calls/tool 消息无法用强类型类表达） */
class AgentTurn {
  role: string = '';
  content: string = '';
  toolCallId: string = '';
  toolCalls: AgentTurnToolCall[] = [];
}

class AgentTurnToolCall {
  id: string = '';
  name: string = '';
  arguments: string = '{}';
}

// ============================================================
// 日期辅助（本地时区；与 SchedulePage 同语义）
// ============================================================

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

/** 本地时区当前日期：YYYY-MM-DD（不是 UTC，避免凌晨偏到昨天/明天） */
function todayLocalISO(): string {
  const d: Date = new Date();
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

function weekdayCN(): string {
  const names: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  return names[new Date().getDay()];
}

function mondayOf(date: Date): Date {
  const d: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const wd: number = d.getDay();
  d.setDate(d.getDate() + (wd === 0 ? -6 : 1 - wd));
  return d;
}

function addDays(date: Date, days: number): Date {
  const d: Date = new Date(date.getTime());
  d.setDate(d.getDate() + days);
  return d;
}

function ymdCompact(d: Date): string {
  return '' + d.getFullYear() + pad2(d.getMonth() + 1) + pad2(d.getDate());
}

/** 本地时间戳：YYYY-MM-DD HH:mm:ss */
function localTimestamp(): string {
  const d: Date = new Date();
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()) +
    ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

export class AgentService {
  /** 会话内审计记录（内存；D7 会话级审计列表） */
  private static auditRecords: AuditRecord[] = [];

  // ============================================================
  // 上下文构建（对齐 RN buildAgentContext + US4 记忆/天气注入）
  // ============================================================

  /**
   * 构建上下文（US4）：日期/星期、学期与教学周、今日与近期课表、待办 DDL
   * （课程作业 + 自建 DDL）、课程列表、个性化记忆、海淀天气快照、学号、
   * 演示模式标记。真实数据逐项 best-effort：单项失败保留占位文案，
   * 不阻断对话（演示模式零真实校园请求）。
   */
  static async buildContext(): Promise<AgentContext> {
    const context: AgentContext = new AgentContext();
    const now: Date = new Date();
    const today: string = todayLocalISO();
    context.todayDate = today + ' ' + weekdayCN();
    context.demoMode = SettingsManager.isDemoMode();
    // 占位文案（失败/演示模式兜底；成功后被真实数据覆盖）
    context.todaySummary = '今天暂无课表数据（尚未同步或同步失败）';
    context.scheduleSummary = '暂无课表数据（尚未同步或同步失败）';
    context.ddlSummary = '暂无待办作业';
    context.courseSummary = '暂无课程数据';
    context.memorySummary = '（暂无个性化记忆）';

    // 学号（未登录/未信任设备时为空；仅进入系统提示，不进日志/轨迹）
    try {
      const creds: SecureCredentials | undefined = await SecureStorage.getCredentials();
      if (creds !== undefined) {
        context.studentId = creds.studentId;
      }
    } catch (e) {
      // 无凭证：留空，系统提示展示"未获取到学号"
    }

    // 个性化记忆（本地持久化，US4）
    try {
      const items: AIMemory[] = await AIMemoryStore.load();
      context.memorySummary = AIMemoryStore.summarizeText(items);
    } catch (e) {
      // 记忆读取失败：保留占位
    }

    // 演示模式：不发起任何真实网络/校园请求（FR-009/FR-010/SC-006 零请求约束）
    if (context.demoMode) {
      context.todaySummary = '演示模式：课表数据不可用';
      context.scheduleSummary = '演示模式：课表数据不可用';
      return context;
    }

    // 海淀天气（公开 API；30 分钟缓存。仅登录态获取，演示路径保持零网络请求）
    try {
      const w: HomeWeather = await fetchHomeWeather(false);
      context.weatherSummary = AgentService.weatherSummaryText(w);
    } catch (e) {
      // 天气失败：系统提示提示模型按需调用 get_campus_weather
    }

    const service: CampusDataService = SessionManager.getCampusDataService();

    // 学期与教学周
    try {
      const firstDay: string = await service.fetchSemesterInfo();
      context.semesterName = service.currentSemester;
      if (firstDay.length >= 10) {
        const start: Date = new Date(firstDay.substring(0, 10) + 'T00:00:00');
        const weeks: number = Math.floor((mondayOf(now).getTime() - start.getTime()) / 604800000) + 1;
        context.currentWeek = weeks > 0 ? weeks : 0;
      }
    } catch (e) {
      // 学期信息失败：周次保持 0
    }

    // 本周课表（今日 + 近期摘要）
    try {
      const monday: Date = mondayOf(now);
      const sunday: Date = addDays(monday, 6);
      const events: ScheduleEvent[] = await service.fetchScheduleEvents(ymdCompact(monday), ymdCompact(sunday));
      const todayEvents: ScheduleEvent[] = [];
      for (let i: number = 0; i < events.length; i++) {
        if (events[i].date === today) {
          todayEvents.push(events[i]);
        }
      }
      todayEvents.sort((a: ScheduleEvent, b: ScheduleEvent): number => a.startTime.localeCompare(b.startTime));
      const todayLines: string[] = [];
      for (let i: number = 0; i < todayEvents.length; i++) {
        todayLines.push('- ' + todayEvents[i].startTime + '-' + todayEvents[i].endTime + ' ' +
          todayEvents[i].title + ' @ ' + todayEvents[i].location);
      }
      context.todaySummary = todayLines.length > 0 ? todayLines.join('\n') : '今天没有课程安排';
      const recentLines: string[] = [];
      const recentCount: number = events.length < 14 ? events.length : 14;
      for (let i: number = 0; i < recentCount; i++) {
        recentLines.push('- ' + events[i].date + ' ' + events[i].startTime + '-' + events[i].endTime + ' ' +
          events[i].title + ' @ ' + events[i].location);
      }
      context.scheduleSummary = recentLines.length > 0 ? recentLines.join('\n') : '暂无课表数据';
    } catch (e) {
      // 课表失败：保留占位
    }

    // 课程列表 + 待办 DDL（作业 + 自建 DDL 合并）
    try {
      const courses: CampusCourse[] = await service.fetchCourses();
      const courseLines: string[] = [];
      for (let i: number = 0; i < courses.length; i++) {
        courseLines.push('- ' + courses[i].name + ' (' + courses[i].teacher + ')');
      }
      context.courseSummary = courseLines.length > 0 ? courseLines.join('\n') : '暂无课程数据';

      const homework: CampusHomework[] = await service.fetchHomework(courses);
      const pending: CampusHomework[] = [];
      for (let i: number = 0; i < homework.length; i++) {
        if (!homework[i].submitted) {
          pending.push(homework[i]);
        }
      }
      const ddlLines: string[] = [];
      const hwCount: number = pending.length < 8 ? pending.length : 8;
      for (let i: number = 0; i < hwCount; i++) {
        ddlLines.push('- [' + pending[i].courseName + '] ' + pending[i].title + ' · 截止 ' + pending[i].deadline);
      }
      const manualDeadlines = await AgentWriteTools.listManualDeadlines();
      const mdCount: number = manualDeadlines.length < 8 ? manualDeadlines.length : 8;
      for (let i: number = 0; i < mdCount; i++) {
        const item = manualDeadlines[i];
        const courseTag: string = item.course.length > 0 ? '自建/' + item.course : '自建';
        ddlLines.push('- [' + courseTag + '] ' + item.title + ' · 截止 ' +
          (item.time.length > 0 ? item.date + ' ' + item.time : item.date));
      }
      context.ddlSummary = ddlLines.length > 0 ? ddlLines.join('\n') : '暂无待办作业';
    } catch (e) {
      // 作业/课程失败：保留占位
    }
    return context;
  }

  /** 天气快照 → 系统提示文本（对齐 RN buildCampusWeatherSummary 可用字段） */
  private static weatherSummaryText(w: HomeWeather): string {
    const parts: string[] = [];
    if (!Number.isNaN(w.temperature)) {
      const apparent: string = !Number.isNaN(w.apparent) ? '，体感 ' + Math.round(w.apparent) + '℃' : '';
      parts.push('当前 ' + Math.round(w.temperature) + '℃' + apparent);
    }
    if (w.condition.length > 0) {
      parts.push(w.condition);
    }
    if (!Number.isNaN(w.minTemp) && !Number.isNaN(w.maxTemp)) {
      parts.push('今日 ' + Math.round(w.minTemp) + '/' + Math.round(w.maxTemp) + '℃');
    }
    if (!Number.isNaN(w.precipProbability)) {
      parts.push('未来 3 小时最大降水概率 ' + Math.round(w.precipProbability) + '%');
      if (w.precipProbability >= 45) {
        parts.push('建议带伞');
      }
    }
    return parts.join(' · ');
  }

  // ============================================================
  // 系统提示（对齐 RN buildSystemPrompt；字段名适配 Harmony 服务）
  // ============================================================

  static buildSystemPrompt(context: AgentContext): string {
    const lines: string[] = [
      '你是 Campus OS 的校园智能体（agent），不只是问答助手——你可以通过“工具”实时查询校园数据，并在用户授权下替用户完成低风险、可撤销操作。',
      `今天是 ${context.todayDate}。当用户问“今天/明天/本周”等相对时间时，一律以这个日期为准，不要臆造日期。`,
    ];
    if (context.semesterName.length > 0 && context.currentWeek > 0) {
      lines.push(`当前学期：${context.semesterName}，第 ${context.currentWeek} 教学周。`);
    }
    lines.push(
      '',
      '## 工具使用原则',
      '- 需要实时/精确数据（成绩、电费余额、校园卡/校园网余额、图书馆空位、体育预约、作业详情）时，调用相应工具获取，不要凭注入摘要臆测。',
      '- 预约/取消图书馆座位、预约/取消研读间、注销校园网设备、添加/删除个人备忘日程、添加/删除自建 DDL 属于写操作，会触发 dry-run、用户二次确认和执行后验证。',
      '- 选课、退课、支付、校园卡挂失/充值/改密码、教学评价提交、邮件发送等高风险事务当前不自动执行；只能给出方案或提醒用户到官方页面手动处理。',
      '- 问「这周/某天有什么安排」时优先用 get_week_schedule；仅查用户自建备忘用 list_personal_events。不能删除或修改教务课表，只能增删个人备忘。',
      '- 问 DDL/作业/待办时优先用 list_homework，它会合并老师布置的作业与用户自建 DDL。用户要求新增 DDL 时用 add_manual_deadline；要求删除 DDL 时只能用 remove_manual_deadline 删除自建 DDL，老师布置的作业不能删除。',
      '- 问天气、是否带伞、防晒、通勤路线、户外活动或受天气影响的学习安排时，优先使用 get_campus_weather 刷新海淀天气；下方天气上下文只是进入对话时的快照。',
      '- 问空教室、自习地点、某教学楼空闲情况时，先用 list_classroom_buildings 或 find_available_classrooms 获取真实教室状态。',
      '- 预约图书馆座位按"列馆→列楼层→列分区→找座位→预约"的顺序逐步推进，不要反复试探。',
      '- 用户问图书馆当前预约记录或取消座位预约时，先用 list_library_booking_records 获取真实记录，再用其中 cancelId 调 cancel_library_seat_booking。',
      '- 用户问研读间时，先用 list_library_room_types / find_library_rooms 查可用资源；预约前必须有明确日期、开始/结束时间和 devId/kindId。',
      '- 用户问校园网余额/在线设备时使用 get_network_balance / list_network_devices；注销设备前只使用 key，工具会自行查 mac。',
      '- 用户问校园卡时只查询余额和流水，不要承诺充值、挂失或修改密码。',
      '- 用户问邮件、收件箱、最近邮件、某封邮件内容或附件时，使用 list_mail_folders / search_mail_messages / read_mail_message 只读查询；不要发送、删除或移动邮件。',
      '- 用户问校园新闻、通知、公告、最近动态、某关键词相关新闻时，使用 get_news_list / search_news 只读查询；需要正文摘要时，用结果里的 url 调 get_news_detail。不要承诺收藏、订阅或修改新闻偏好。',
      '- 用户问宿舍洗衣机状态、哪里有空闲洗衣机、某楼洗衣机剩余时间时，先用 list_laundry_buildings 找楼宇；有明确楼宇后用 get_laundry_status 获取真实状态。',
      '- 预约座位前若用户没指定地点，优先使用其常用图书馆（见下方记忆）；仍不确定时先询问。',
      '- 用户表达明确长期偏好（常去哪、默认充值多少、关注哪些课）时，用 remember_preference 记住。',
      '- 当用户在同一会话中连续 2 次以上对同一资源做同类操作（如连续查同一图书馆、同一分区、同一场馆），可主动建议：「我注意到你好像经常用 xxx，要不要我记住这个偏好？」如果用户同意，再调用 remember_preference 写入。',
      '- 操作完成后用简洁中文向用户复述结果（成功/失败/下一步）。',
      '- 【重要】展示工具返回的具体数据（座位号 name、成绩、电量、金额、日期等）时，必须逐字原样引用工具结果，严禁编造、改写、推测或用"范围/区间"概括座位号；项目较多时可只列前若干个真实值并注明"等"，但绝不能虚构编号。预约座位时必须使用工具返回的真实 seatId/seatType，不能凭座位号猜测。',
    );
    if (context.demoMode) {
      lines.push('- 当前为演示模式：实时查询与写操作不可用，请提示用户退出演示模式并登录。');
    }
    lines.push(
      '',
      '## 关于用户',
      context.studentId.length > 0 ? `学号：${context.studentId}` : '（未获取到学号）',
      '',
      '## 个性化记忆',
      context.memorySummary.length > 0 ? context.memorySummary : '（暂无个性化记忆）',
      '',
      '## 海淀天气（进入对话时的快照）',
      context.weatherSummary.length > 0 ? context.weatherSummary : '天气暂未获取；如用户询问天气，请调用 get_campus_weather。',
      '',
      '## 今日课表（已按今天的真实日期筛选）',
      context.todaySummary,
      '',
      '## 近期课表（含日期）',
      context.scheduleSummary,
      '',
      '## 待办 DDL',
      context.ddlSummary,
      '',
      '## 课程列表',
      context.courseSummary,
    );
    return lines.join('\n');
  }

  // ============================================================
  // Agent 循环（对齐 RN runAgent）
  // ============================================================

  /**
   * 运行一轮"对话→（按需调用工具）→…→最终回答"的 agent 循环。
   *
   * @param config provider 运行配置（preset/baseUrl/model）
   * @param apiKey API Key（仅进入请求，不进入日志）
   * @param messages 对话历史（user/assistant；空内容自动跳过）
   * @param context 系统提示上下文（buildContext 产物）
   * @param callbacks 回调（onDelta/onAnswer/onToolStart/onToolEnd/requestConfirmation/isCancelled）
   * @returns 最终回答文本；取消时返回空串
   * @throws AgentRunError LLM 请求失败（kind 映射可读提示）
   */
  static async runAgent(config: LLMProviderConfig, apiKey: string, messages: ChatMessage[],
    context: AgentContext, callbacks: AgentCallbacks): Promise<string> {
    const convo: AgentTurn[] = [];
    const sysTurn: AgentTurn = new AgentTurn();
    sysTurn.role = 'system';
    sysTurn.content = AgentService.buildSystemPrompt(context);
    convo.push(sysTurn);
    for (let i: number = 0; i < messages.length; i++) {
      const m: ChatMessage = messages[i];
      if (m.role !== 'user' && m.role !== 'assistant') {
        continue;
      }
      if (m.content.trim().length === 0) {
        continue;
      }
      const turn: AgentTurn = new AgentTurn();
      turn.role = m.role;
      turn.content = m.content;
      convo.push(turn);
    }

    // 权限开关就绪后按禁用清单过滤工具（ai-governance US2）：
    // 关闭的能力不下发给模型（请求 tools 不含该权限的工具）。
    // 读取失败时降级为全工具可见（fail-open）并告警，不阻断会话；
    // executeToolCall 的门禁兜底仍按内存态生效
    await AIPermissionStore.ensureLoaded().catch((): void => {
      Log.w(LOG_TAG, 'permission store load failed; agent runs with all tools visible');
    });
    const disabledPermissions: string[] = AIPermissionStore.disabledKeys();
    const tools: AgentToolDef[] = AgentTools.all(disabledPermissions);
    const toolsJson: string = AgentService.buildToolsJson(tools);
    Log.i(LOG_TAG, 'AGENT start turns=%{public}d tools=%{public}d disabledPerms=%{public}d',
      convo.length, tools.length, disabledPermissions.length);

    for (let round: number = 0; round < MAX_AGENT_ROUNDS; round++) {
      if (AgentService.isCancelled(callbacks)) {
        Log.i(LOG_TAG, 'AGENT cancelled round=%{public}d', round);
        return '';
      }
      const messagesJson: string = AgentService.serializeTurns(convo);
      // 每轮流式请求（携带 tools）：content 增量直通 onDelta（最终轮逐字输出；
      // 中间工具轮正文由流式会话在 tool_calls 片段出现后截断，不外发）
      const roundOptions: LLMRoundStreamOptions = new LLMRoundStreamOptions();
      roundOptions.onContentDelta = (chunk: string): void => {
        callbacks.onDelta(chunk);
      };
      roundOptions.isCancelled = (): boolean => AgentService.isCancelled(callbacks);
      const outcome: LLMToolsOutcome =
        await LLMService.streamRoundWithTools(config, apiKey, messagesJson, toolsJson, roundOptions);
      if (outcome.cancelled || AgentService.isCancelled(callbacks)) {
        Log.i(LOG_TAG, 'AGENT cancelled round=%{public}d', round);
        return '';
      }
      if (!outcome.ok) {
        Log.e(LOG_TAG, 'AGENT llm failed kind=%{public}s', outcome.kind);
        throw new AgentRunError(outcome.kind);
      }
      if (outcome.toolCalls.length === 0) {
        const answer: string = outcome.content.trim().length > 0 ? outcome.content.trim() : '（模型未返回内容）';
        callbacks.onAnswer(answer);
        Log.i(LOG_TAG, 'AGENT answer len=%{public}d', answer.length);
        return answer;
      }

      // 模型的工具调用意图压回对话
      const assistantTurn: AgentTurn = new AgentTurn();
      assistantTurn.role = 'assistant';
      assistantTurn.content = outcome.content;
      for (let i: number = 0; i < outcome.toolCalls.length; i++) {
        const call: LLMToolCall = outcome.toolCalls[i];
        const atc: AgentTurnToolCall = new AgentTurnToolCall();
        atc.id = call.id;
        atc.name = call.name;
        atc.arguments = call.arguments;
        assistantTurn.toolCalls.push(atc);
      }
      convo.push(assistantTurn);

      for (let ci: number = 0; ci < outcome.toolCalls.length; ci++) {
        if (AgentService.isCancelled(callbacks)) {
          Log.i(LOG_TAG, 'AGENT cancelled in tools round=%{public}d', round);
          return '';
        }
        const call: LLMToolCall = outcome.toolCalls[ci];
        const tool: AgentToolDef | undefined = AgentTools.byName(call.name);
        let result: Record<string, Object> = {};
        if (tool === undefined) {
          // 未知工具：回灌可读错误（不中断循环）；派发 onToolStart/onToolEnd
          // 使页面收起中间轮已流出正文并复位过程态（SC-009：工具轮不产出可见正文）
          const unknownDef: AgentToolDef = new AgentToolDef();
          unknownDef.name = call.name;
          unknownDef.title = call.name;
          callbacks.onToolStart(unknownDef, call.arguments);
          result = { 'error': '未知工具：' + call.name };
          AgentService.emitToolEnd(callbacks, unknownDef, call, ActionExecutionStatus.ERROR,
            '未知工具：' + call.name, undefined, ConfirmationStatus.NOT_REQUIRED, undefined, result);
        } else {
          result = await AgentService.executeToolCall(tool, call, callbacks);
        }
        const toolTurn: AgentTurn = new AgentTurn();
        toolTurn.role = 'tool';
        toolTurn.toolCallId = call.id;
        toolTurn.content = JSON.stringify(result);
        convo.push(toolTurn);
      }
    }

    const fallback: string = '（已达到工具调用上限，请补充信息或拆分需求后再试）';
    callbacks.onAnswer(fallback);
    Log.i(LOG_TAG, 'AGENT hit round limit');
    return fallback;
  }

  /**
   * 单个工具调用执行（治理链：dryRun → 确认 → run → verify；对齐 RN runAgent 内循环）。
   * 返回回灌给模型的结果（始终有值；错误以 {error} 形态返回）。
   */
  private static async executeToolCall(tool: AgentToolDef, call: LLMToolCall,
    callbacks: AgentCallbacks): Promise<Record<string, Object>> {
    const args: Record<string, Object> = AgentService.parseToolArgs(call.arguments);
    callbacks.onToolStart(tool, call.arguments);

    let cancelled: boolean = false;
    let confirmation: string = tool.requiresConfirmation ? ConfirmationStatus.UNAVAILABLE : ConfirmationStatus.NOT_REQUIRED;
    let status: string = ActionExecutionStatus.SUCCESS;
    let errorMessage: string = '';
    let preview: ActionPreview | undefined = undefined;
    let verification: VerificationResult | undefined = undefined;
    let result: Record<string, Object> = {};

    // 权限门禁（ai-governance US2）：命中用户禁用 → 返回可读拒绝（含权限键与
    // 文案），派发 onToolStart/onToolEnd 并写审计；不进入 dryRun/确认/run/verify。
    // 正常路径下该工具不会随请求下发，此门禁兜底"点名调用"与并发改开关的场景。
    if (tool.permission.length > 0 && AIPermissionStore.isDisabled(tool.permission)) {
      const denied: string = I18n.t('ai.permissionDisabled');
      confirmation = ConfirmationStatus.NOT_REQUIRED;
      status = ActionExecutionStatus.ERROR;
      errorMessage = denied;
      result = { 'ok': false, 'error': 'permission_disabled', 'permission': tool.permission, 'message': denied };
      AgentService.emitToolEnd(callbacks, tool, call, ActionExecutionStatus.ERROR, denied,
        undefined, confirmation, undefined, result);
      AgentService.appendAuditRecord(tool, call, args, undefined, confirmation, status, result, errorMessage, undefined);
      return result;
    }

    if (tool.requiresConfirmation) {
      if (tool.dryRun !== undefined) {
        try {
          preview = await tool.dryRun(args);
        } catch (e) {
          cancelled = true;
          status = ActionExecutionStatus.ERROR;
          errorMessage = AgentService.errorText(e);
          result = { 'error': errorMessage };
          AgentService.emitToolEnd(callbacks, tool, call, ActionExecutionStatus.ERROR, errorMessage,
            preview, confirmation, undefined, result);
        }
      }
      const confirmFn: ((tool: AgentToolDef, argsJson: string, preview: ActionPreview | undefined) => Promise<boolean>) | undefined =
        callbacks.requestConfirmation;
      if (!cancelled && confirmFn === undefined) {
        // 缺少确认通道：阻止执行（绝不静默执行写操作）
        cancelled = true;
        confirmation = ConfirmationStatus.UNAVAILABLE;
        status = ActionExecutionStatus.CANCELLED;
        result = { 'ok': false, 'cancelled': true, 'message': '缺少确认通道，已阻止执行' };
        AgentService.emitToolEnd(callbacks, tool, call, ActionExecutionStatus.CANCELLED, '缺少确认通道',
          preview, confirmation, undefined, result);
      } else if (!cancelled && confirmFn !== undefined) {
        const approved: boolean = await confirmFn(tool, call.arguments, preview);
        confirmation = approved ? ConfirmationStatus.APPROVED : ConfirmationStatus.DENIED;
        if (!approved) {
          // 用户拒绝：不执行
          cancelled = true;
          status = ActionExecutionStatus.CANCELLED;
          result = { 'ok': false, 'cancelled': true, 'message': '用户取消了该操作' };
          AgentService.emitToolEnd(callbacks, tool, call, ActionExecutionStatus.CANCELLED, '已取消',
            preview, confirmation, undefined, result);
        }
      }
    }

    if (!cancelled) {
      try {
        result = await tool.run(args);
        status = AgentService.isToolResultFailure(result) ? ActionExecutionStatus.ERROR : ActionExecutionStatus.SUCCESS;
        if (tool.verify !== undefined && status === ActionExecutionStatus.SUCCESS) {
          verification = await tool.verify(args, result);
          if (!verification.ok) {
            status = ActionExecutionStatus.ERROR;
            errorMessage = verification.message.length > 0 ? verification.message : '执行后验证失败';
          }
        }
        const detail: string = errorMessage.length > 0 ? errorMessage : AgentService.summarizeToolResult(result);
        AgentService.emitToolEnd(callbacks, tool, call, status, detail, preview, confirmation, verification, result);
      } catch (e) {
        const detail: string = AgentService.errorText(e);
        result = { 'error': detail };
        status = ActionExecutionStatus.ERROR;
        errorMessage = detail;
        AgentService.emitToolEnd(callbacks, tool, call, ActionExecutionStatus.ERROR, detail,
          preview, confirmation, undefined, result);
      }
    }

    AgentService.appendAuditRecord(tool, call, args, preview, confirmation, status, result, errorMessage, verification);
    return result;
  }

  // ============================================================
  // 序列化与解析
  // ============================================================

  /** 会话轮次 → messages 原始 JSON 文本（system/user/assistant/tool 四形态） */
  private static serializeTurns(turns: AgentTurn[]): string {
    const parts: string[] = [];
    for (let i: number = 0; i < turns.length; i++) {
      const t: AgentTurn = turns[i];
      if (t.role === 'tool') {
        parts.push('{"role":"tool","tool_call_id":' + JSON.stringify(t.toolCallId) +
          ',"content":' + JSON.stringify(t.content) + '}');
      } else if (t.toolCalls.length > 0) {
        const calls: string[] = [];
        for (let j: number = 0; j < t.toolCalls.length; j++) {
          const c: AgentTurnToolCall = t.toolCalls[j];
          calls.push('{"id":' + JSON.stringify(c.id) +
            ',"type":"function","function":{"name":' + JSON.stringify(c.name) +
            ',"arguments":' + JSON.stringify(c.arguments) + '}}');
        }
        parts.push('{"role":"assistant","content":' + JSON.stringify(t.content) +
          ',"tool_calls":[' + calls.join(',') + ']}');
      } else {
        parts.push('{"role":' + JSON.stringify(t.role) + ',"content":' + JSON.stringify(t.content) + '}');
      }
    }
    return '[' + parts.join(',') + ']';
  }

  /** 注册表 → OpenAI tools 数组 JSON 文本（空注册表返回空串，请求不带 tools） */
  private static buildToolsJson(tools: AgentToolDef[]): string {
    const parts: string[] = [];
    for (let i: number = 0; i < tools.length; i++) {
      const t: AgentToolDef = tools[i];
      parts.push('{"type":"function","function":{"name":' + JSON.stringify(t.name) +
        ',"description":' + JSON.stringify(t.description) +
        ',"parameters":' + t.parametersJson + '}}');
    }
    return parts.length > 0 ? '[' + parts.join(',') + ']' : '';
  }

  /** 模型工具参数 JSON → Record（非法/空返回空 Record，不抛） */
  static parseToolArgs(argsJson: string): Record<string, Object> {
    try {
      const trimmed: string = argsJson.trim();
      if (trimmed.length === 0) {
        const empty: Record<string, Object> = {};
        return empty;
      }
      const parsed: Object = JSON.parse(trimmed);
      if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
        return parsed as Record<string, Object>;
      }
    } catch (e) {
      // 半包/非法 JSON：按空参数执行（工具自行校验必填项）
    }
    const empty: Record<string, Object> = {};
    return empty;
  }

  // ============================================================
  // 结果摘要 / 失败判定（对齐 RN summarizeToolResult / isToolResultFailure）
  // ============================================================

  static summarizeToolResult(result: Record<string, Object>): string {
    const msg: Object | undefined = result['message'];
    if (typeof msg === 'string' && msg.length > 0) {
      return msg;
    }
    const err: Object | undefined = result['error'];
    if (typeof err === 'string' && err.length > 0) {
      return err;
    }
    const ok: Object | undefined = result['ok'];
    if (ok === true) {
      return '成功';
    }
    if (ok === false) {
      return '失败';
    }
    return '';
  }

  static isToolResultFailure(result: Record<string, Object>): boolean {
    const err: Object | undefined = result['error'];
    if (typeof err === 'string' && err.length > 0) {
      return true;
    }
    const ok: Object | undefined = result['ok'];
    return ok === false;
  }

  private static errorText(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  private static isCancelled(callbacks: AgentCallbacks): boolean {
    const fn: (() => boolean) | undefined = callbacks.isCancelled;
    return fn !== undefined && fn();
  }

  // ============================================================
  // 回调派发（onToolEnd 轨迹构建）
  // ============================================================

  private static emitToolEnd(callbacks: AgentCallbacks, tool: AgentToolDef, call: LLMToolCall,
    status: string, detail: string, preview: ActionPreview | undefined, confirmation: string,
    verification: VerificationResult | undefined, result: Record<string, Object>): void {
    const trace: ToolTrace = new ToolTrace();
    trace.callId = call.id;
    trace.name = tool.name;
    trace.title = tool.title;
    trace.status = status;
    trace.detail = detail;
    trace.timestamp = localTimestamp();
    trace.success = status === ActionExecutionStatus.SUCCESS;
    if (tool.summarize !== undefined) {
      try {
        trace.params = tool.summarize(AgentService.parseToolArgs(call.arguments));
      } catch (e) {
        trace.params = '';
      }
    } else {
      const raw: string = call.arguments.trim();
      trace.params = raw.length > TRACE_PARAMS_CLIP ? raw.substring(0, TRACE_PARAMS_CLIP) + '…' : raw;
    }
    trace.result = AgentService.summarizeToolResult(result);

    const meta: AgentToolEndMeta = new AgentToolEndMeta();
    meta.trace = trace;
    meta.preview = preview;
    meta.confirmation = confirmation;
    meta.verification = verification;
    meta.resultJson = JSON.stringify(result);
    callbacks.onToolEnd(tool, status, detail, meta);
  }

  // ============================================================
  // 审计（会话级内存列表；D7）
  // ============================================================

  private static appendAuditRecord(tool: AgentToolDef, call: LLMToolCall, args: Record<string, Object>,
    preview: ActionPreview | undefined, confirmation: string, status: string,
    result: Record<string, Object>, errorMessage: string,
    verification: VerificationResult | undefined): void {
    const rec: AuditRecord = new AuditRecord();
    rec.id = generateUUID();
    rec.timestamp = new Date().toISOString();
    rec.toolName = tool.name;
    rec.toolTitle = tool.title;
    rec.risk = String(tool.risk);
    rec.status = status;
    rec.confirmation = confirmation;
    rec.success = status === ActionExecutionStatus.SUCCESS;
    rec.confirmed = confirmation === ConfirmationStatus.APPROVED;
    rec.parameters = AgentService.paramsSummaryFor(tool, call);
    const resultJson: string = JSON.stringify(result);
    // 先对完整 JSON 脱敏（敏感键遮蔽 + 邮箱/手机号文本兜底）再写入内存；
    // sanitizeResultJson 内含 2000 上限截断。store 落盘时二次脱敏（幂等，
    // 已打码文本不会被二次误伤）——杜绝长结果截断后解析失败导致的明文漏路
    rec.result = ActionAuditStore.sanitizeResultJson(resultJson);
    rec.resultSummary = AgentService.summarizeToolResult(result);
    rec.errorMessage = errorMessage;
    rec.permission = tool.permission;
    rec.paramsJson = call.arguments;
    rec.previewAffectedResource = preview !== undefined ? preview.affectedResource : '';
    rec.verificationOk = verification !== undefined && verification.ok;
    rec.verificationMessage = verification !== undefined ? verification.message : '';
    AgentService.auditRecords.push(rec);
    while (AgentService.auditRecords.length > MAX_AUDIT_RECORDS) {
      AgentService.auditRecords.shift();
    }
    // 持久化双写（ai-governance）：store 内部复制并脱敏后落盘；失败吞掉不打断循环
    ActionAuditStore.append(rec).catch((): void => {
      Log.w(LOG_TAG, 'audit persist append failed tool=%{public}s', tool.name);
    });
    // 日志治理（US3）：仅工具名/状态/记录条数，不含参数与结果正文
    Log.i(LOG_TAG, 'AUDIT append tool=%{public}s status=%{public}s records=%{public}d',
      tool.name, status, AgentService.auditRecords.length);
  }

  private static paramsSummaryFor(tool: AgentToolDef, call: LLMToolCall): string {
    if (tool.summarize !== undefined) {
      try {
        return tool.summarize(AgentService.parseToolArgs(call.arguments));
      } catch (e) {
        return '';
      }
    }
    const raw: string = call.arguments.trim();
    return raw.length > TRACE_PARAMS_CLIP ? raw.substring(0, TRACE_PARAMS_CLIP) + '…' : raw;
  }

  /** 会话内审计记录（副本；含时间/工具/参数概要/状态/确认/验证摘要） */
  static getAuditRecords(): AuditRecord[] {
    return AgentService.auditRecords.slice();
  }

  static clearAuditRecords(): Promise<void> {
    AgentService.auditRecords = [];
    // 持久化清空结果上抛给面板提示；store 的 tick（成功/失败均发）驱动列表刷新
    return ActionAuditStore.clear();
  }

  // ============================================================
  // 演示模式本地应答（对齐 RN createMockAgentReply）
  // ============================================================

  static createMockReply(question: string, context: AgentContext): string {
    const lines: string[] = [
      `【演示模式】今天是 ${context.todayDate}。我已读取你的本地校园数据上下文：`,
      '',
      `你问：${question}`,
      '',
      '今日课表：',
      context.todaySummary,
      '',
      '海淀天气：',
      context.weatherSummary.length > 0 ? context.weatherSummary : '天气暂未获取',
      '',
      '待办 DDL：',
      context.ddlSummary,
      '',
      '提示：退出演示模式并登录后，可获得真实模型回答与实时校园数据查询。',
    ];
    return lines.join('\n');
  }
}
