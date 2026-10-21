/**
 * ============================================================================
 * CourseRegService — 清华选课系统服务（学期/已选课程/课余量搜索/选课/退课）
 * ============================================================================
 *
 * 【来源】RN src/services/campus/courseRegistration.ts（端点/表单字段/解析索引
 * 原样移植）；会话激活与错误契约按 T03 spec/plan（RD-01/RD-02/RD-04/RD-08）。
 *
 * 【会话激活】每个进程首次请求前执行"空 yyfwid 默认漫游"（webvpn csrf →
 * onlineAppRedirect → roamingurl → 落点页）；落点命中登录页或漫游失败时，
 * 回退 TsinghuaAuthService.roamIdSubsystem(INFO_PORTAL_YYFWID)。成功后缓存
 * crSessionEnsured；登录/退出复位时由 SessionManager.resetSessionState() 清除。
 *
 * 【读写差异】只读操作的网络请求包 withSessionRecovery；解析与确定性错误
 * （NO_SEMESTER/INVALID_PARAM/PARSE 等）在恢复包装之外判定，不触发
 * reroam/完整重登录。写操作仅对"取表单页 + 取 token"的幂等预检做会话恢复，
 * 真正的 POST 只发一次，禁止自动重试 POST（避免重复选课/退课，RD-02）。
 *
 * 【页面识别】（FR-019）已选/课余量搜索响应先做结构识别（isSelectedPage/
 * isRemainingPage）；未命中预期结构的 200 HTML 抛 PARSE，不得当成空成功。
 *
 * 【写成功判定】showMsg 明确含"成功"且不含否定词 → 成功；明确失败词 →
 * REJECTED；其余 → UNCONFIRMED（不声称成功，RD-08）。
 *
 * 【编码】响应解码依赖 HttpClient（cr_xk token 已在 GBK_URL_MARKERS）；
 * 请求体沿用 postForm 的 UTF-8 percent 编码（与 RN stringifyForm 一致，RD-05）。
 *
 * 【日志红线】tag CourseReg；禁止记录表单 token/Cookie/学号/密码/完整 URL/
 * 完整表单体；detail 先剥离 HTML/控制字符并截断（FR-012/FR-013）。
 * ============================================================================
 */
import { HttpClient, HttpResponse, HttpError } from '../HttpClient';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { INFO_PORTAL_YYFWID } from '../WebvpnConstants';
import { Log } from '../../utils/Logger';
import {
  CR_WEBVPN_TITLE_MARK,
  CR_SM2_MARK,
  CR_TIMEOUT_MARK,
  isLoginPage,
  extractBaseSemester,
  parseSemesters,
  parseSelectedPage,
  parseRemainingPage,
  SelectedParseResult,
  RemainingParseResult,
  extractFormToken,
  extractShowMsg,
  redactSensitive,
} from '../../utils/CourseRegHtml';
import {
  CourseRegError,
  CourseRegErrorCode,
  CourseRegI18n,
  CrSemester,
  SelectedCourse,
  CrRemainingSearchResult,
  CourseSearchParams,
  SelectCourseParams,
  DropCourseParams,
  isSupportedCourseRegPriority,
  courseRegFieldKey,
  courseRegSaveMethod,
} from '../../domain/CourseRegTypes';

const TAG: string = 'CourseReg';
const WEBVPN_BASE: string = 'https://webvpn.tsinghua.edu.cn';
/** 选课系统 webvpn token（RN CR_TOKEN 原样） */
const CR_TOKEN: string = 'eaff4b8b3f3b2653770bc7b88b5c2d320506b1aec738590a49ba';

/** 选课主页面（学期基础信息入口） */
const CR_MAIN_URL: string = `${WEBVPN_BASE}/https/${CR_TOKEN}/xkBks.vxkBksXkbBs.do?m=main`;
/** 学期树（m=showTree&p_xnxq=<学期 ID>） */
const CR_TREE_URL: string = `${WEBVPN_BASE}/https/${CR_TOKEN}/xkBks.vxkBksXkbBs.do?m=showTree&p_xnxq=`;
/** 课余量搜索（注意端点是 JxjhBs，与选课提交的 XkbBs 不同） */
const CR_SEARCH_URL: string = `${WEBVPN_BASE}/https/${CR_TOKEN}/xkBks.vxkBksJxjhBs.do`;
/** 选课/退课提交（含 yxSearchTab / xxxSearch 预检页） */
const CR_SELECT_URL: string = `${WEBVPN_BASE}/https/${CR_TOKEN}/xkBks.vxkBksXkbBs.do`;

/** RN CR_ROAM_PAYLOAD 为空串：默认漫游即"空 yyfwid"（RD-01） */
const CR_ROAM_PAYLOAD: string = '';

/** 信息门户 webvpn token（cookieSync 与 onlineAppRedirect 通道） */
const INFO_TOKEN: string = '77726476706e69737468656265737421f9f9479369247b59700f81b9991b2631506205de';
/** webvpn XSRF-TOKEN 提取接口（响应体回显 info 域 cookies） */
const COOKIE_SYNC_URL: string = 'https://webvpn.tsinghua.edu.cn/wengine-vpn/cookie?method=get'
  + '&host=info.tsinghua.edu.cn&scheme=https&path=/f/info/gxfw_fg/common/index';
/** 信息门户 onlineAppRedirect 漫游端点（RN ROAMING_URL 原样） */
const ONLINE_APP_REDIRECT_URL: string = `${WEBVPN_BASE}/https/${INFO_TOKEN}`
  + '/b/yyfw/vyyfwxx/info/portal_fg/common/onlineAppRedirect';

/** 错误详情最大长度（超长截断；脱敏后仍保持可诊断） */
const DETAIL_MAX_LEN: number = 120;

/**
 * 业务 URL 的 WebVPN 包装表（RN parseUrl.ts HOST_MAP 原样移植；
 * 仅用于漫游 roamingurl 的包装，登录/roam callback 仍走 wrapWebVPNUrl）。
 */
const CR_HOST_MAP: Record<string, string> = {
  'zhjw.cic': '77726476706e69737468656265737421eaff4b8b69336153301c9aa596522b20bc86e6e559a9b290',
  'jxgl.cic': '77726476706e69737468656265737421faef469069336153301c9aa596522b20e33c1eb39606919f',
  'zhjwxk.cic': '77726476706e69737468656265737421faef469069336153301c9aa596522b20e33c1eb39606919f',
  'ecard': '77726476706e69737468656265737421f5f4408e237e7c4377068ea48d546d303341e9882a',
  'learn': '77726476706e69737468656265737421fcf2408e297e7c4377068ea48d546d30ca8cc97bcc',
  'mails': '77726476706e69737468656265737421fdf64890347e7c4377068ea48d546d3011ff591d40',
  '50': '77726476706e69737468656265737421a5a70f8834396657761d88e29d51367b6a00',
  '166.111.14.8': '77726476706e69737468656265737421a1a117d27661391e2f5cc7f4',
  'fa-online': '77726476706e69737468656265737421f6f60c93293c615e7b469dbf915b243daf0f96e17deaf447b4',
  'dzpj': '77726476706e69737468656265737421f4ed519669247b59700f81b9991b2631aee63c51',
  'jjhyhdf': '77726476706e69737468656265737421fafd49852f346e1e6a1b80a29f5d36342bb9c40cf69277',
  'yhdf': '77726476706e69737468656265737421e9ff459a69247b59700f81b9991b26317dbd36ae',
  'usereg': '77726476706e69737468656265737421e5e4448e223726446d0187ab9040227b54b6c80fcd73',
  'thos': '77726476706e69737468656265737421e4ff4e8f69247b59700f81b9991b261ca359dd4',
};

/**
 * 把清华内网 URL 包装为 WebVPN URL（RN parseUrlToWebVPN 原样移植：
 * IP 形式 http://IP:PORT/path 与域名形式 scheme://host.tsinghua.edu.cn(:port)/path；
 * 已是 webvpn 前缀或 host 不在映射表时原样返回）。
 */
export function parseCrUrlToWebVPN(originalUrl: string): string {
  if (originalUrl.startsWith(WEBVPN_BASE)) {
    return originalUrl;
  }
  const ipMatch: RegExpExecArray | null = /http:\/\/(\d+\.\d+\.\d+\.\d+):(\d+)\/(.+)/.exec(originalUrl);
  if (ipMatch !== null && ipMatch.length >= 4) {
    const token: string | undefined = CR_HOST_MAP[ipMatch[1]];
    if (token !== undefined) {
      return `${WEBVPN_BASE}/http-${ipMatch[2]}/${token}/${ipMatch[3]}`;
    }
    return originalUrl;
  }
  const colonIdx: number = originalUrl.indexOf(':');
  if (colonIdx < 0) {
    return originalUrl;
  }
  const protocol: string = originalUrl.substring(0, colonIdx);
  const regRes: RegExpExecArray | null = /:\/\/(.+?)\.tsinghua\.edu\.cn(:(\d+))?\/(.+)/.exec(originalUrl);
  if (regRes === null || regRes.length < 5) {
    return originalUrl;
  }
  const host: string = regRes[1];
  const port: string = regRes[3];
  const protocolFull: string = port !== undefined && port.length > 0 ? `${protocol}-${port}` : protocol;
  const token: string | undefined = CR_HOST_MAP[host];
  if (token === undefined) {
    return originalUrl;
  }
  return `${WEBVPN_BASE}/${protocolFull}/${token}/${regRes[4]}`;
}

/**
 * 错误详情脱敏：剥离 HTML 标签/实体、去控制字符、敏感信息归一（redactSensitive，
 * 见 utils/CourseRegHtml.ets）、压缩空白并截断。
 * 禁止把完整 HTML/URL/表单体/学号/token 放入 detail（FR-012）。
 */
function sanitizeDetail(raw: string): string {
  let text: string = raw.replace(/<[^>]+>/g, ' ');
  text = text.replace(/&nbsp;/g, ' ');
  text = text.replace(/&amp;/g, '&');
  text = text.replace(/[\x00-\x1F\x7F]/g, ' ');
  text = redactSensitive(text);
  text = text.replace(/\s+/g, ' ').trim();
  if (text.length > DETAIL_MAX_LEN) {
    text = text.substring(0, DETAIL_MAX_LEN) + '…';
  }
  return text;
}

/** 写操作结果分类（RD-08）：成功 / 明确拒绝 / 无法确认 */
export enum CourseRegMsgVerdict {
  SUCCESS = 'success',
  REJECTED = 'rejected',
  UNCONFIRMED = 'unconfirmed',
}

/** 服务端失败词表（showMsg 命中即判 REJECTED；与 RN 线上文案对齐） */
const CR_FAIL_WORDS: string[] = [
  '失败', '错误', '不能', '无法', '未开放', '已满', '冲突', '超出', '重复', '不存在', '超时',
];

/**
 * 写操作结果消息分类（纯函数，供 CourseRegSelfTest 直接测试）：
 *   - 含"成功"且无任何失败词 → SUCCESS；
 *   - 命中失败词 → REJECTED（优先级高于"成功"——服务端"成功提交，但…失败"类文案按拒绝处理）；
 *   - 其余 → UNCONFIRMED（不声称成功）。
 */
export function classifyCourseRegMsg(msg: string): CourseRegMsgVerdict {
  let hasFailWord: boolean = false;
  for (let i: number = 0; i < CR_FAIL_WORDS.length; i++) {
    if (msg.indexOf(CR_FAIL_WORDS[i]) >= 0) {
      hasFailWord = true;
      break;
    }
  }
  if (msg.indexOf('成功') >= 0 && !hasFailWord) {
    return CourseRegMsgVerdict.SUCCESS;
  }
  if (hasFailWord) {
    return CourseRegMsgVerdict.REJECTED;
  }
  return CourseRegMsgVerdict.UNCONFIRMED;
}

/** 课余量搜索参数校验（FR-020）：学期必填、page/dayOfWeek/period 为整数且在值域内 */
export function validateCourseSearchParams(params: CourseSearchParams): CourseRegErrorCode | null {
  if (params.semester.trim().length === 0) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  if (!Number.isInteger(params.page) || params.page < 1) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  if (!Number.isInteger(params.dayOfWeek) || !Number.isInteger(params.period)) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  if (params.dayOfWeek !== 0 && (params.dayOfWeek < 1 || params.dayOfWeek > 7)) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  if (params.period !== 0 && (params.period < 1 || params.period > 12)) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  return null;
}

/** 选课参数校验（FR-020）：类型受支持、志愿 ∈ 1/2/3、学期/课程号/课序号必填 */
export function validateSelectCourseParams(params: SelectCourseParams): CourseRegErrorCode | null {
  if (params.semester.trim().length === 0 || params.courseId.trim().length === 0
    || params.courseSeq.trim().length === 0) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  if (!isSupportedCourseRegPriority(params.priority)) {
    return params.priority.length > 0
      ? CourseRegErrorCode.UNSUPPORTED_PRIORITY
      : CourseRegErrorCode.INVALID_PARAM;
  }
  if (params.will !== 1 && params.will !== 2 && params.will !== 3) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  return null;
}

/** 退课参数校验（FR-020）：学期/课程号/课序号必填 */
export function validateDropCourseParams(params: DropCourseParams): CourseRegErrorCode | null {
  if (params.semester.trim().length === 0 || params.courseId.trim().length === 0
    || params.courseSeq.trim().length === 0) {
    return CourseRegErrorCode.INVALID_PARAM;
  }
  return null;
}

export class CourseRegService {
  private http: HttpClient;
  private auth: TsinghuaAuthService;
  /** 选课子系统会话是否已激活（进程内缓存，FR-015） */
  private crSessionEnsured: boolean = false;
  /**
   * 进行中的会话激活 Promise（single-flight：并发调用复用同一 Promise，
   * 失败由各等待者统一承接；FR-015）。
   */
  private crEnsureInFlight: Promise<void> | undefined = undefined;
  /**
   * 会话 epoch：resetSessionState() 时自增，用于作废"复位时仍在进行中"的
   * 激活任务——旧任务完成后不得回写 crSessionEnsured（RD-10，防止
   * "退出→再登录"期间旧激活把新会话误标为已激活）。
   */
  private crEnsureEpoch: number = 0;

  constructor(http: HttpClient, auth: TsinghuaAuthService) {
    this.http = http;
    this.auth = auth;
  }

  /**
   * 会话瞬态复位（SessionManager.resetSessionState() 统一扇出调用）：
   * 清"会话已激活"标志与进行中的激活 Promise，并自增 epoch 作废进行中
   * 激活任务的回写，避免进程内"退出→再登录"复用上一会话标志导致重登后
   * 首次请求跳过会话激活（RD-10）。
   * 契约：无参、同步、幂等、不抛；仅清本服务进程内瞬态态。
   */
  resetSessionState(): void {
    this.crEnsureEpoch++;
    this.crSessionEnsured = false;
    this.crEnsureInFlight = undefined;
  }

  /** 构造统一错误：message=错误码文本，messageKey=i18n 键，detail 脱敏截断 */
  private crError(code: CourseRegErrorCode, detail: string, retryable: boolean): CourseRegError {
    return new CourseRegError(code, CourseRegI18n.keyOf(code), retryable, sanitizeDetail(detail));
  }

  // ==========================================================================
  // T006 会话激活（RD-01：webvpn csrf → onlineAppRedirect 空漫游 → 落点页；
  // 落点命中登录页或漫游失败 → 回退信息门户漫游）
  // ==========================================================================

  /**
   * WebVPN XSRF-TOKEN（每次现取、不缓存——完整重登录会换发新 token，缓存旧值
   * 会导致 info 门户请求 403）。复刻 CampusDataService.getWebvpnCsrf 的提取链
   * （cookieSync 响应体 → info 域 Cookie → webvpn 域 Cookie），但不打印响应体
   * （cookieSync 回显 cookies，日志红线 FR-013）。
   */
  private async getWebvpnCsrf(): Promise<string> {
    try {
      const resp: HttpResponse = await this.http.get(COOKIE_SYNC_URL);
      Log.i(TAG, 'WEBVPN_COOKIESYNC code=%{public}d len=%{public}d', resp.statusCode, resp.body.length);
      const m: RegExpExecArray | null = /XSRF-TOKEN=([^;]+);/.exec(resp.body + ';');
      if (m !== null && m.length >= 2 && m[1].length > 0) {
        return m[1];
      }
      const infoCookies: string = this.http.getCookieManager()
        .getCookieHeader('https://info.tsinghua.edu.cn/');
      const webvpnCookies: string = this.http.getCookieManager()
        .getCookieHeader('https://webvpn.tsinghua.edu.cn/');
      let m2: RegExpExecArray | null = /XSRF-TOKEN=([^;]+)/.exec(infoCookies);
      if (m2 === null || m2.length < 2 || m2[1].length === 0) {
        m2 = /XSRF-TOKEN=([^;]+)/.exec(webvpnCookies);
      }
      if (m2 !== null && m2.length >= 2 && m2[1].length > 0) {
        return m2[1];
      }
      Log.i(TAG, 'WEBVPN_CSRF no_token bodyLen=%{public}d cookieLen=%{public}d',
        resp.body.length, infoCookies.length);
    } catch (e) {
      // 固定文案：异常消息可能透传响应体/URL（FR-013 日志红线），不落盘
      Log.i(TAG, 'WEBVPN_CSRF fetch failed');
    }
    return '';
  }

  /**
   * 默认空 yyfwid 漫游（RN transport.roamDefault('') 原样移植）：
   * csrf → onlineAppRedirect?yyfwid= → object.roamingurl（去 &amp;）→
   * parseCrUrlToWebVPN 包装 → GET 落点页。返回落点页 HTML；
   * 失败抛 CourseRegError（NOT_LOGGED_IN / HTTP / NETWORK）。
   */
  private async roamDefaultCr(): Promise<string> {
    const csrf: string = await this.getWebvpnCsrf();
    if (csrf.length === 0) {
      throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN, 'no webvpn csrf', false);
    }
    let resp: HttpResponse;
    try {
      resp = await this.http.get(ONLINE_APP_REDIRECT_URL + '?yyfwid=' + CR_ROAM_PAYLOAD
        + '&_csrf=' + encodeURIComponent(csrf) + '&machine=p');
    } catch (e) {
      throw this.crError(CourseRegErrorCode.NETWORK, 'roam network error', true);
    }
    Log.i(TAG, 'ROAM code=%{public}d len=%{public}d', resp.statusCode, resp.body.length);
    if (resp.statusCode !== 200 && resp.statusCode !== 201) {
      throw this.crError(CourseRegErrorCode.HTTP, 'roam status=' + resp.statusCode, true);
    }
    // 会话失效时 onlineAppRedirect 返回登录页 HTML 而非 JSON（RN 同款失败路径）
    let json: Record<string, Object>;
    try {
      json = JSON.parse(resp.body) as Record<string, Object>;
    } catch (e) {
      throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN,
        'roam non-json len=' + resp.body.length, false);
    }
    const resultStr: string = String(json['result'] ?? '');
    if (resultStr.length > 0 && resultStr !== 'success') {
      throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN,
        'roam result=' + resultStr + ' msg=' + String(json['msg'] ?? ''), false);
    }
    const objField = json['object'] as Record<string, Object>;
    if (objField === undefined || objField === null) {
      throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN, 'roam no object', false);
    }
    const roamingurl: string = String(objField['roamingurl'] ?? '').replace(/&amp;/g, '&');
    if (roamingurl.length === 0) {
      throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN, 'roam no url', false);
    }
    let landing: HttpResponse;
    try {
      landing = await this.http.get(parseCrUrlToWebVPN(roamingurl));
    } catch (e) {
      throw this.crError(CourseRegErrorCode.NETWORK, 'landing network error', true);
    }
    Log.i(TAG, 'ROAM_LANDING code=%{public}d len=%{public}d',
      landing.statusCode, landing.body.length);
    if (landing.statusCode !== 200 && landing.statusCode !== 201) {
      throw this.crError(CourseRegErrorCode.HTTP, 'landing status=' + landing.statusCode, true);
    }
    return landing.body;
  }

  /**
   * 选课子系统会话激活（每进程一次；FR-015）：
   *   - 进程内缓存命中直接返回（force=true 跳过缓存）；
   *   - single-flight：并发调用等待同一进行中的激活 Promise，其失败由各
   *     等待者统一承接（不再各自重跑激活，避免失败风暴）；force=true 时
   *     先等在途激活结束，再强制重走一次完整激活；
   *   - 激活链：默认空 yyfwid 漫游，落点命中登录页视为未打通 →
   *     回退信息门户漫游 roamIdSubsystem(INFO_PORTAL_YYFWID)（RD-01）。
   * 失败抛 CourseRegError（交由 withCrSession 的恢复层重试）。
   */
  private async ensureCrSession(force: boolean): Promise<void> {
    if (this.crSessionEnsured && !force) {
      return;
    }
    if (this.crEnsureInFlight !== undefined) {
      if (!force) {
        // 等待者：复用在途激活；其失败原样承接（同一失败统一传播）
        await this.crEnsureInFlight;
        return;
      }
      try {
        await this.crEnsureInFlight;
      } catch (e) {
        // 在途激活失败：force 路径仍继续下方的强制重激活
      }
    }
    const epoch: number = this.crEnsureEpoch;
    const task: Promise<void> = this.doEnsureCrSession(epoch);
    this.crEnsureInFlight = task;
    try {
      await task;
    } finally {
      // 仅当在途引用仍是本任务时清空：复位或后续 force 任务已接管时不得误清
      if (this.crEnsureInFlight === task) {
        this.crEnsureInFlight = undefined;
      }
    }
  }

  /** 会话激活实现（由 ensureCrSession 做 single-flight 串行化后调用） */
  private async doEnsureCrSession(epoch: number): Promise<void> {
    let ensured: boolean = false;
    let defaultRoamError: CourseRegError | undefined = undefined;
    try {
      const landing: string = await this.roamDefaultCr();
      if (!isLoginPage(landing)) {
        ensured = true;
        Log.i(TAG, 'SESSION ensured via default roam');
      } else {
        Log.i(TAG, 'SESSION default roam hit login page');
      }
    } catch (e) {
      if (e instanceof CourseRegError) {
        defaultRoamError = e;
        Log.i(TAG, 'SESSION default roam fail code=%{public}s', e.code);
      } else {
        defaultRoamError = this.crError(CourseRegErrorCode.NOT_LOGGED_IN, 'default roam ex', false);
        Log.i(TAG, 'SESSION default roam fail ex');
      }
    }
    if (!ensured) {
      Log.i(TAG, 'SESSION portal fallback');
      try {
        await this.auth.roamIdSubsystem(INFO_PORTAL_YYFWID);
        Log.i(TAG, 'SESSION ensured via portal fallback');
      } catch (e) {
        // HttpClient 网络层错误统一包装为 HttpError → NETWORK（可重试）；
        // 认证/漫游流程错误（roamIdPolicy 等普通 Error）→ NOT_LOGGED_IN
        if (e instanceof HttpError) {
          throw this.crError(CourseRegErrorCode.NETWORK, 'portal fallback network error', true);
        }
        // 默认漫游本身是可重试失败（如 NETWORK）而门户流程也失败时：
        // 保留原可重试分类，不降级为 NOT_LOGGED_IN
        if (defaultRoamError !== undefined && defaultRoamError.retryable) {
          throw defaultRoamError;
        }
        throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN, 'portal fallback fail', false);
      }
    }
    // epoch 校验：激活期间发生复位（退出登录）时，旧任务不得回写激活标志
    if (epoch === this.crEnsureEpoch) {
      this.crSessionEnsured = true;
    } else {
      Log.i(TAG, 'SESSION ensured but session reset during activation');
    }
  }

  // ==========================================================================
  // T007 请求归一（RN crFetch + assertCrHtml 对齐；读写恢复语义见 withCrSession）
  // ==========================================================================

  /**
   * 选课请求归一（RN crFetch + assertCrHtml 移植）：
   *   - 网络异常 → NETWORK；非 200/201 → HTTP（响应体由 HttpClient 按 GBK_URL_MARKERS 解码）；
   *   - WebVPN 登录页（title / sm2publicKey）→ NOT_LOGGED_IN；
   *   - 会话超时页（用户登陆超时或访问内容不存在）→ SESSION_EXPIRED。
   * 日志只记 op/status/len/ms，不记 URL 与表单体（FR-013）。
   */
  private async crRequest(op: string, url: string, form: Record<string, string> | null): Promise<string> {
    const startMs: number = Date.now();
    let resp: HttpResponse;
    try {
      resp = form === null ? await this.http.get(url) : await this.http.postForm(url, form);
    } catch (e) {
      Log.i(TAG, 'REQ op=%{public}s net-fail ms=%{public}d', op, Date.now() - startMs);
      // 固定文案，不透传底层异常消息（可能含 URL/内部细节，FR-012/FR-013）
      throw this.crError(CourseRegErrorCode.NETWORK, 'request network error', true);
    }
    Log.i(TAG, 'REQ op=%{public}s status=%{public}d len=%{public}d ms=%{public}d',
      op, resp.statusCode, resp.body.length, Date.now() - startMs);
    if (resp.statusCode !== 200 && resp.statusCode !== 201) {
      throw this.crError(CourseRegErrorCode.HTTP, 'status=' + resp.statusCode, true);
    }
    const body: string = resp.body;
    if (body.indexOf(CR_WEBVPN_TITLE_MARK) >= 0 || body.indexOf(CR_SM2_MARK) >= 0) {
      throw this.crError(CourseRegErrorCode.NOT_LOGGED_IN, 'webvpn login page', false);
    }
    if (body.indexOf(CR_TIMEOUT_MARK) >= 0) {
      throw this.crError(CourseRegErrorCode.SESSION_EXPIRED, 'cr session timeout page', true);
    }
    return body;
  }

  private async crGet(op: string, url: string): Promise<string> {
    return this.crRequest(op, url, null);
  }

  private async crPostForm(op: string, url: string, form: Record<string, string>): Promise<string> {
    return this.crRequest(op, url, form);
  }

  /**
   * 会话恢复包装（RN withCrSession 对齐）：
   *   1. ensureCrSession（进程内缓存，失败由恢复层兜底）→ operation；
   *   2. 失败 → reroam（复位"已激活"标志 + 强制重漫游）→ operation；
   *   3. 还失败 → 完整重登录 → reroam → operation；
   *   4. 全失败 → 抛第一次的 CourseRegError。
   * 写操作的 POST 必须在 operation 内由调用方保证只发一次（RD-02）。
   */
  private async withCrSession<T>(operation: () => Promise<T>, label: string): Promise<T> {
    const reroam = async (): Promise<void> => {
      this.crSessionEnsured = false;
      await this.ensureCrSession(true);
    };
    return this.auth.withSessionRecovery<T>(async (): Promise<T> => {
      await this.ensureCrSession(false);
      return operation();
    }, reroam, label);
  }

  // ==========================================================================
  // US1 查询可选学期（T011）
  // ==========================================================================

  /**
   * 查询可选学期（RN getCrAvailableSemesters 移植）：
   * 主页面提取基础学期 → 学期树 GET → 解析 option 列表；
   * 空结果映射 NO_SEMESTER（不返回空成功）。
   * 网络请求各自走会话恢复；解析与 NO_SEMESTER 判定在恢复包装之外
   * （确定性错误不触发 reroam/完整重登录）。
   */
  async getAvailableSemesters(): Promise<CrSemester[]> {
    const mainHtml: string = await this.withCrSession<string>(async (): Promise<string> => {
      return this.crGet('cr-main', CR_MAIN_URL);
    }, 'cr-main-page');
    const baseSem: string = extractBaseSemester(mainHtml);
    if (baseSem.length === 0) {
      Log.i(TAG, 'SEMESTER no base semester in main page');
      throw this.crError(CourseRegErrorCode.NO_SEMESTER, 'no base semester', false);
    }
    const treeHtml: string = await this.withCrSession<string>(async (): Promise<string> => {
      return this.crGet('cr-tree', CR_TREE_URL + baseSem);
    }, 'cr-tree-page');
    const semesters: CrSemester[] = parseSemesters(mainHtml, treeHtml);
    if (semesters.length === 0) {
      Log.i(TAG, 'SEMESTER empty tree');
      throw this.crError(CourseRegErrorCode.NO_SEMESTER, 'no semesters in tree', false);
    }
    Log.i(TAG, 'SEMESTER count=%{public}d', semesters.length);
    return semesters;
  }

  // ==========================================================================
  // US2 查看已选课程（T014）
  // ==========================================================================

  /**
   * 查询已选课程（RN getSelectedCourses 移植）：
   * 参数校验（学期必填）→ yxSearchTab GET → 页面结构识别 → 行解析；
   * 空列表是合法结果（学期无已选课程），与"非预期页面"区分：
   * 未命中已选页结构标记的 200 HTML 抛 PARSE（FR-019），不返回空成功。
   */
  async getSelectedCourses(semesterId: string): Promise<SelectedCourse[]> {
    const sem: string = semesterId.trim();
    if (sem.length === 0) {
      throw this.crError(CourseRegErrorCode.INVALID_PARAM, 'semester required', false);
    }
    const url: string = CR_SELECT_URL + '?m=yxSearchTab&p_xnxq='
      + encodeURIComponent(sem) + '&tokenPriFlag=yx';
    // 网络请求走会话恢复；解析与页面识别在恢复包装之外（FR-019）
    const html: string = await this.withCrSession<string>(async (): Promise<string> => {
      return this.crGet('cr-selected', url);
    }, 'cr-selected-courses');
    const parsed: SelectedParseResult = parseSelectedPage(html);
    if (!parsed.recognized) {
      Log.i(TAG, 'SELECTED unrecognized page len=%{public}d', html.length);
      throw this.crError(CourseRegErrorCode.PARSE, 'selected page not recognized', false);
    }
    Log.i(TAG, 'SELECTED count=%{public}d skipped=%{public}d',
      parsed.courses.length, parsed.skipped);
    return parsed.courses;
  }

  // ==========================================================================
  // US3 课余量搜索（T017）
  // ==========================================================================

  /**
   * 课余量搜索（RN searchCrRemaining 移植）。
   * 表单字段与 RN 逐项对齐（m=kylSearch / pathContent=课余量查询 / goPageNumber 等）；
   * dayOfWeek/period 为 0 表示未指定，发送空串（类型模型显式化 RN 的 undefined 分支）。
   * 响应先做页面结构识别（FR-019）：未命中搜索页标记的 200 HTML 抛 PARSE；
   * 合法空结果（p.yeM 脚注"共 0 条记录"）正常返回空列表。
   */
  async searchRemaining(params: CourseSearchParams): Promise<CrRemainingSearchResult> {
    const invalid: CourseRegErrorCode | null = validateCourseSearchParams(params);
    if (invalid !== null) {
      throw this.crError(invalid, 'invalid search params', false);
    }
    // 网络请求走会话恢复；解析与页面识别在恢复包装之外（FR-019）
    const html: string = await this.withCrSession<string>(async (): Promise<string> => {
      const form: Record<string, string> = {
        'm': 'kylSearch',
        'page': String(params.page),
        'p_sort.p1': '',
        'p_sort.p2': '',
        'p_sort.asc1': 'true',
        'p_sort.asc2': 'true',
        'p_xnxq': params.semester,
        'pathContent': '课余量查询',
        'p_kch': params.id,
        'p_kxh': '',
        'p_kcm': params.name,
        'p_skxq': params.dayOfWeek > 0 ? String(params.dayOfWeek) : '',
        'p_skjc': params.period > 0 ? String(params.period) : '',
        'goPageNumber': String(params.page),
      };
      return this.crPostForm('cr-search', CR_SEARCH_URL, form);
    }, 'cr-search-remaining');
    const parsed: RemainingParseResult = parseRemainingPage(html);
    if (!parsed.recognized) {
      Log.i(TAG, 'SEARCH unrecognized page len=%{public}d', html.length);
      throw this.crError(CourseRegErrorCode.PARSE, 'remaining page not recognized', false);
    }
    const result: CrRemainingSearchResult = parsed.result;
    Log.i(TAG, 'SEARCH courses=%{public}d page=%{public}d/%{public}d total=%{public}d skipped=%{public}d',
      result.courses.length, result.currPage, result.totalPage, result.totalCount, parsed.skipped);
    return result;
  }

  // ==========================================================================
  // US4 选课（T019）— 写操作：预检可走会话恢复，POST 仅发一次（RD-02）
  // ==========================================================================

  /**
   * 提交选课（RN selectCourse 移植 + RD-02 写安全约束）：
   *   1. 本地校验（优先级 bx/xx/rx/ty、志愿 1/2/3、学期/课程号/课序号必填）；
   *   2. 预检 GET（`?m=<priority>Search&p_xnxq=…&tokenPriFlag=<priority>`）
   *      取表单 token——幂等，可走会话恢复；缺 token 抛 NO_FORM_TOKEN，不提交；
   *   3. POST 仅发一次（不自动重试，避免重复选课）：m=saveXxKc 形式、
   *      p_<fieldKey>_id=`学期;课程号;课序号;`、p_<fieldKey>_xkzy=志愿；
   *   4. 解析 showMsg：明确成功返回服务端消息；明确失败词 REJECTED；
   *      语义不明 UNCONFIRMED（调用方必须回查已选列表）；缺 showMsg PARSE。
   */
  async selectCourse(params: SelectCourseParams): Promise<string> {
    const invalid: CourseRegErrorCode | null = validateSelectCourseParams(params);
    if (invalid !== null) {
      throw this.crError(invalid, 'invalid select params', false);
    }
    // 预检 GET：幂等，可安全走会话恢复
    const mainHtml: string = await this.withCrSession<string>(async (): Promise<string> => {
      const preUrl: string = CR_SELECT_URL + '?m=' + params.priority + 'Search&p_xnxq='
        + encodeURIComponent(params.semester) + '&tokenPriFlag=' + params.priority;
      return this.crGet('cr-select-pre', preUrl);
    }, 'cr-select-course-pre');

    const token: string = extractFormToken(mainHtml);
    if (token.length === 0) {
      Log.i(TAG, 'SELECT no form token');
      throw this.crError(CourseRegErrorCode.NO_FORM_TOKEN, 'select form missing token', false);
    }

    // POST 仅一次：不包会话恢复（RD-02），网络/会话异常不自动重试
    const fieldKey: string = courseRegFieldKey(params.priority);
    const form: Record<string, string> = {
      'm': courseRegSaveMethod(params.priority),
      'token': token,
      'p_xnxq': params.semester,
      'tokenPriFlag': params.priority,
    };
    form['p_' + fieldKey + '_id'] = params.semester + ';' + params.courseId + ';'
      + params.courseSeq + ';';
    form['p_' + fieldKey + '_xkzy'] = String(params.will);
    const responseHtml: string = await this.crPostForm('cr-select-post', CR_SELECT_URL, form);

    const responseMsg: string = extractShowMsg(responseHtml);
    if (responseMsg.length === 0) {
      Log.i(TAG, 'SELECT response missing showMsg len=%{public}d', responseHtml.length);
      throw this.crError(CourseRegErrorCode.PARSE, 'select response missing showMsg', false);
    }
    const verdict: CourseRegMsgVerdict = classifyCourseRegMsg(responseMsg);
    if (verdict === CourseRegMsgVerdict.REJECTED) {
      Log.i(TAG, 'SELECT rejected');
      throw this.crError(CourseRegErrorCode.REJECTED, responseMsg, false);
    }
    if (verdict === CourseRegMsgVerdict.UNCONFIRMED) {
      Log.i(TAG, 'SELECT unconfirmed');
      throw this.crError(CourseRegErrorCode.UNCONFIRMED, responseMsg, false);
    }
    Log.i(TAG, 'SELECT ok');
    return responseMsg;
  }

  // ==========================================================================
  // US5 退课（T021）— 与 US4 相同的写安全约束（预检可恢复，POST 仅一次）
  // ==========================================================================

  /**
   * 删除已选课程（RN deleteCourse 移植 + RD-02 写安全约束）：
   *   1. 本地校验（学期/课程号/课序号必填）；
   *   2. 预检 GET（已选页 `?m=yxSearchTab&p_xnxq=…&tokenPriFlag=yx`）取
   *      token——幂等，可走会话恢复；缺 token 抛 NO_FORM_TOKEN，不提交；
   *   3. POST 仅发一次：m=deleteYxk、p_del_id=`学期;课程号;课序号;`；
   *   4. 解析 showMsg：明确成功返回服务端消息；明确失败词 REJECTED；
   *      语义不明 UNCONFIRMED（调用方必须回查已选列表）；缺 showMsg PARSE。
   */
  async dropCourse(params: DropCourseParams): Promise<string> {
    const invalid: CourseRegErrorCode | null = validateDropCourseParams(params);
    if (invalid !== null) {
      throw this.crError(invalid, 'invalid drop params', false);
    }
    // 预检 GET：幂等，可安全走会话恢复
    const yxHtml: string = await this.withCrSession<string>(async (): Promise<string> => {
      const preUrl: string = CR_SELECT_URL + '?m=yxSearchTab&p_xnxq='
        + encodeURIComponent(params.semester) + '&tokenPriFlag=yx';
      return this.crGet('cr-drop-pre', preUrl);
    }, 'cr-drop-course-pre');

    const token: string = extractFormToken(yxHtml);
    if (token.length === 0) {
      Log.i(TAG, 'DROP no form token');
      throw this.crError(CourseRegErrorCode.NO_FORM_TOKEN, 'selected page missing token', false);
    }

    // POST 仅一次：不包会话恢复（RD-02），网络/会话异常不自动重试
    const form: Record<string, string> = {
      'm': 'deleteYxk',
      'token': token,
      'p_xnxq': params.semester,
      'tokenPriFlag': 'yx',
    };
    form['p_del_id'] = params.semester + ';' + params.courseId + ';' + params.courseSeq + ';';
    const responseHtml: string = await this.crPostForm('cr-drop-post', CR_SELECT_URL, form);

    const responseMsg: string = extractShowMsg(responseHtml);
    if (responseMsg.length === 0) {
      Log.i(TAG, 'DROP response missing showMsg len=%{public}d', responseHtml.length);
      throw this.crError(CourseRegErrorCode.PARSE, 'drop response missing showMsg', false);
    }
    const verdict: CourseRegMsgVerdict = classifyCourseRegMsg(responseMsg);
    if (verdict === CourseRegMsgVerdict.REJECTED) {
      Log.i(TAG, 'DROP rejected');
      throw this.crError(CourseRegErrorCode.REJECTED, responseMsg, false);
    }
    if (verdict === CourseRegMsgVerdict.UNCONFIRMED) {
      Log.i(TAG, 'DROP unconfirmed');
      throw this.crError(CourseRegErrorCode.UNCONFIRMED, responseMsg, false);
    }
    Log.i(TAG, 'DROP ok');
    return responseMsg;
  }
}
