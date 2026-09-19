/**
 * ============================================================================
 * CampusDataService — 校园真实数据接入服务（learn 域 + 教务 zhjw 域）
 * ============================================================================
 *
 * 【数据接入总览】（均需先经 TsinghuaAuthService 完成 learn 激活拿到 _csrf）：
 *   - fetchCourses          课程列表（先取学期 ID，再取课程；URL 含 /wlxt/ 段）
 *   - fetchHomework         作业（按课程遍历 Wj/Yjwg/Ypg 三状态端点，POST aoData）
 *   - fetchNotifications    通知（POST aoData；内容 ggnr 是 Base64 编码 HTML）
 *   - fetchFiles            课件文件（GET；object 可能是数组或 {resultsList}）
 *   - fetchHomeworkDetail   作业详情（GET viewCj 页 HTML 解析作业要求/附件）
 *   - fetchScheduleEvents   课表（教务 zhjw JSONP，需先 ensureRegistrarRoam 教务激活）
 *   - fetchGrades           成绩（教务 zhjw HTML 表格，漫游 yyfwid 与课表不同）
 *   - fetchNewsList         校园资讯（info 门户 JSON，object.dataList）
 *
 * 【learn API 通用规则】：
 *   - URL 用 withCsrf(url, csrf) 拼 _csrf 参数
 *   - aoData 是 [{"name":"wlkcid","value":"课程id"}] 的 JSON 字符串，POST urlencoded 提交
 *   - 响应数据行通常在 object.aaData 或 object.resultsList
 *
 * 【CSRF 区分】：
 *   - learn csrf（getCsrfToken）     learn 学生首页提取，用于 learn API
 *   - WebVPN csrf（getWebvpnCsrf）   cookieSync 接口提取 XSRF-TOKEN，用于教务等漫游
 *
 * 参考：原项目 src/services/campus/learningAdapter.ts、scheduleService.ts
 * ============================================================================
 */
import { HttpClient, HttpResponse } from '../HttpClient';
import { SessionManager } from '../auth/SessionManager';
import { Log } from '../../utils/Logger';
import { decodeBase64 } from '../../utils/CryptoUtils';

const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
const SCHEDULE_BASE: string = 'https://webvpn.tsinghua.edu.cn/http/77726476706e69737468656265737421eaff4b8b69336153301c9aa596522b20bc86e6e559a9b290';

function pad2(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

/** learn 时间字段统一格式化为 "YYYY-MM-DD HH:mm"（兼容毫秒时间戳/字符串/null） */
function formatDateTime(value: Object | null | undefined): string {
  if (value === null || value === undefined) { return ''; }
  const text: string = String(value);
  if (text.length === 0 || text === 'null') { return ''; }
  let isDigits: boolean = true;
  for (let i: number = 0; i < text.length; i++) {
    const ch: string = text.charAt(i);
    if (ch < '0' || ch > '9') { isDigits = false; break; }
  }
  if (isDigits && text.length >= 10) {
    let num: number = Number(text);
    if (text.length === 10) { num = num * 1000; }
    const d: Date = new Date(num);
    if (!isNaN(d.getTime())) {
      return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
    }
    return text;
  }
  if (text.length >= 10 && text.charAt(4) === '-') {
    return text.replace('T', ' ').substring(0, 16);
  }
  return text;
}

/** 常用命名实体（资讯标题/来源里高频出现 &ldquo; &middot; 等中文排版实体） */
const NAMED_HTML_ENTITIES: Record<string, string> = {
  'nbsp': ' ',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'ldquo': '\u201C',
  'rdquo': '\u201D',
  'lsquo': '\u2018',
  'rsquo': '\u2019',
  'mdash': '\u2014',
  'ndash': '\u2013',
  'hellip': '\u2026',
  'middot': '\u00B7',
  'bull': '\u2022',
  'times': '\u00D7',
  'divide': '\u00F7',
  'copy': '\u00A9',
  'reg': '\u00AE',
  'trade': '\u2122',
  'prime': '\u2032',
  'deg': '\u00B0',
};

/**
 * HTML 实体解码：数值（&#xHH; / &#DD;）→ 命名实体 → &amp; 最后。
 * &amp; 必须放最后，避免 "&amp;ldquo;" 这类已被转义的字面量被二次解码。
 */
function decodeHtmlEntities(value: string): string {
  let out: string = decodeNumericEntities(value);
  out = out.replace(/&([a-zA-Z][a-zA-Z0-9]*);/g, (m: string, name: string): string => {
    const hit: string | undefined = NAMED_HTML_ENTITIES[name.toLowerCase()];
    return hit !== undefined ? hit : m;
  });
  out = out.replace(/&amp;/g, '&');
  return out;
}

/** 去除 HTML 标签，保留文本与换行（用于通知/作业内容纯文本展示） */
function stripHtml(html: string): string {
  let s: string = html;
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n');
  s = s.replace(/<li>/gi, '· ');
  s = s.replace(/<[^>]+>/g, '');
  s = decodeHtmlEntities(s);
  // 压缩多余空行
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

function withCsrf(url: string, csrf: string): string {
  const sep: string = url.indexOf('?') >= 0 ? '&' : '?';
  return url + sep + '_csrf=' + encodeURIComponent(csrf);
}

/** 数值 HTML 实体（&#xHH; / &#DD;）解码（对齐原项目 news.ts decodeText） */
function decodeNumericEntities(value: string): string {
  let out: string = value.replace(/&#x([0-9a-fA-F]+);/g, (m: string, hex: string): string => {
    return String.fromCharCode(parseInt(hex, 16));
  });
  out = out.replace(/&#(\d+);/g, (m: string, dec: string): string => {
    return String.fromCharCode(parseInt(dec, 10));
  });
  return out;
}

/** HTML 片段 → 纯文本（去标签 + 实体解码） */
function htmlCellText(cellHtml: string): string {
  return decodeHtmlEntities(cellHtml.replace(/<[^>]+>/g, '')).trim();
}

/**
 * 解析 <table cellspacing=1> 每个 <tr> 的**子节点序列**——严格对齐原项目
 * htmlSelect.childText / thu-info-lib getCheerioText(element, index) 语义：
 * cheerio 的 children 包含标签之间的文本节点（换行缩进）。
 *
 * 真实成绩表 HTML 的 tr 内容形如 "\n<td>..</td>\n<td>..</td>\n..."，
 * children = [text, td, text, td, ...]，因此原项目取列 childText(tr, 3/5/7/9/11)
 * 实际对应第 2/3/4/5/6 个 td（课程名/学分/等级/绩点/学期）。
 * 之前只数 td 用 3/5/7/9/11 索引导致整列错位（绩点取到空列 → GPA 0.00）。
 */
function parseGradeTableChildren(html: string): string[][] {
  const rows: string[][] = [];
  const tableMatch: RegExpExecArray | null = /<table[^>]*cellspacing="1"[^>]*>([\s\S]*?)<\/table>/i.exec(html);
  const tableHtml: string = tableMatch !== null ? tableMatch[1] : '';
  if (tableHtml.length === 0) {
    return rows;
  }
  const trRe: RegExp = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let trMatch: RegExpExecArray | null = trRe.exec(tableHtml);
  while (trMatch !== null) {
    rows.push(parseGradeRowChildren(trMatch[1]));
    trMatch = trRe.exec(tableHtml);
  }
  return rows;
}

/** 解析 <tr> 内部子节点序列：标签间文本节点与 td/th 单元格文本各占一席（文本节点 trim 后多为空串，仅占位） */
function parseGradeRowChildren(trHtml: string): string[] {
  const children: string[] = [];
  const tagRe: RegExp = /<(t[dh])[^>]*>([\s\S]*?)<\/\1>/gi;
  let lastEnd: number = 0;
  let m: RegExpExecArray | null = tagRe.exec(trHtml);
  while (m !== null) {
    if (m.index > lastEnd) {
      // 相邻标签之间存在文本（换行缩进）→ cheerio 里是一个文本节点子项，占一个下标
      children.push(htmlCellText(trHtml.substring(lastEnd, m.index)));
    }
    children.push(htmlCellText(m[2]));
    lastEnd = m.index + m[0].length;
    m = tagRe.exec(trHtml);
  }
  return children;
}

/** 解析 JSONP（形如 m([...])，取首个 [ 到末个 ]） */
function parseJsonpArray(raw: string): Object[] {
  const start: number = raw.indexOf('[');
  const end: number = raw.lastIndexOf(']');
  if (start < 0 || end < 0 || end <= start) { return []; }
  try {
    return JSON.parse(raw.substring(start, end + 1)) as Object[];
  } catch (e) {
    return [];
  }
}

/** 课表日期归一为 YYYY-MM-DD（兼容 YYYYMMDD） */
function normalizeScheduleDate(value: string): string {
  const s: string = value.trim();
  if (s.length >= 10 && s.charAt(4) === '-') { return s.substring(0, 10); }
  if (s.length === 8) {
    return s.substring(0, 4) + '-' + s.substring(4, 6) + '-' + s.substring(6, 8);
  }
  return s;
}

function formatYmd(d: Date): string {
  return `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
}

function formatDash(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

export class CampusCourse {
  id: string = '';
  name: string = '';
  teacher: string = '';
  code: string = '';
}

export class CampusHomework {
  id: string = '';
  baseId: string = '';
  courseId: string = '';
  title: string = '';
  courseName: string = '';
  deadline: string = '';
  status: string = '';
  submitted: boolean = false;
  graded: boolean = false;
  url: string = '';
  grade: string = '';
  gradeContent: string = '';
}

export class CampusNotification {
  id: string = '';
  title: string = '';
  publisher: string = '';
  publishTime: string = '';
  isNew: boolean = false;
  content: string = '';
}

export class CampusFile {
  id: string = '';
  fileId: string = '';
  title: string = '';
  courseName: string = '';
  size: string = '';
  isNew: boolean = false;
  description: string = '';
  uploadTime: string = '';
  downloadUrl: string = '';
  previewUrl: string = '';
}

/** 作业详情（解析 viewCj 页面 HTML 得到） */
export class HomeworkDetailData {
  description: string = '';
  answerContent: string = '';
  attachments: string[] = [];
}

/** 课表事件（教务 zhjw JSONP） */
export class ScheduleEvent {
  id: string = '';
  date: string = '';
  title: string = '';
  location: string = '';
  startTime: string = '';
  endTime: string = '';
}

/** 成绩课程（教务 zhjw cj.cjCjbAll.do） */
export class CampusGrade {
  name: string = '';
  credit: number = 0;
  grade: string = '';
  point: number = 0;
  semester: string = '';
}

/** 成绩单汇总（GPA 计算对齐原项目 computeGpa：point 为 NaN 的 P/F 课不计学分绩） */
export class GradeReport {
  courses: CampusGrade[] = [];
  gpa: number = 0;
  totalCredit: number = 0;
  allCredit: number = 0;
}

/** 校园资讯条目（info 门户新闻 JSON） */
export class CampusNews {
  id: string = '';
  title: string = '';
  date: string = '';
  source: string = '';
  channel: string = '';
  topped: boolean = false;
}

/** 资讯栏目标签（对齐原项目 CHANNEL_LABELS 子集） */
const NEWS_CHANNEL_LABELS: Record<string, string> = {
  'LM_BGTG': '办公通知',
  'LM_ZYGG': '重要公告',
  'LM_JWGG': '教务通知',
  'LM_KYTZ': '科研通知',
  'LM_XSBGGG': '学生工作通知',
  'LM_TTGGG': '图书馆信息',
  'LM_BYJYXX': '就业通知',
  'LM_JYZPXX': '招聘信息',
};

export class CampusDataService {
  private http: HttpClient;
  private csrfToken: string = '';
  private learnReady: boolean = false;
  public trace: string = '';
  public currentSemester: string = '';
  private registrarRoamEnsured: boolean = false;
  private gradesRoamEnsured: boolean = false;
  private webvpnCsrf: string = '';
  /** 课表拉取状态：'unknown' 未拉过 / 'ok' JSONP 正常（可能为空）/ 'error' 拿到非 JSONP（会话失效等） */
  public scheduleStatus: string = 'unknown';
  /** 当前学期首日（YYYY-MM-DD，learn getCurrentAndNextSemester result.kssj），周数计算用 */
  public semesterFirstDay: string = '';

  constructor(http: HttpClient) {
    this.http = http;
  }

  async getCsrfToken(): Promise<string> {
    if (this.csrfToken.length > 0) {
      return this.csrfToken;
    }
    const authCsrf: string = SessionManager.getAuthService().getCsrfToken();
    if (authCsrf.length > 0) {
      this.csrfToken = authCsrf;
      return authCsrf;
    }
    return '';
  }

  /** WebVPN 的 XSRF-TOKEN（用于 webvpn 漫游，与 learn csrf 不同） */
  async getWebvpnCsrf(): Promise<string> {
    if (this.webvpnCsrf.length > 0) {
      return this.webvpnCsrf;
    }
    try {
      // 与原项目 transport.getCsrfToken 一致：cookieSync 接口在响应体里回显
      // webvpn 后端 jar 中的 info 域 cookies，从 body 提取 XSRF-TOKEN
      const url: string = 'https://webvpn.tsinghua.edu.cn/wengine-vpn/cookie?method=get&host=info.tsinghua.edu.cn&scheme=https&path=/f/info/gxfw_fg/common/index';
      const resp: HttpResponse = await this.http.get(url);
      Log.i('LearnAct', 'WEBVPN_COOKIESYNC code=%{public}d len=%{public}d body=%{public}s',
        resp.statusCode, resp.body.length, resp.body.substring(0, 150));
      const m = /XSRF-TOKEN=([^;]+);/.exec(resp.body + ';');
      if (m !== null && m.length >= 2 && m[1].length > 0) {
        this.webvpnCsrf = m[1];
        Log.i('LearnAct', 'WEBVPN_CSRF ok len=%{public}d', this.webvpnCsrf.length);
        return this.webvpnCsrf;
      }
      // 回退：本地 cookie 管理器（info / webvpn 域）
      const infoCookies: string = this.http.getCookieManager().getCookieHeader('https://info.tsinghua.edu.cn/');
      const webvpnCookies: string = this.http.getCookieManager().getCookieHeader('https://webvpn.tsinghua.edu.cn/');
      let m2 = /XSRF-TOKEN=([^;]+)/.exec(infoCookies);
      if (m2 === null || m2.length < 2 || m2[1].length === 0) {
        m2 = /XSRF-TOKEN=([^;]+)/.exec(webvpnCookies);
      }
      if (m2 !== null && m2.length >= 2 && m2[1].length > 0) {
        this.webvpnCsrf = m2[1];
        Log.i('LearnAct', 'WEBVPN_CSRF fallback ok len=%{public}d', this.webvpnCsrf.length);
      } else {
        Log.i('LearnAct', 'WEBVPN_CSRF no_token bodyLen=%{public}d infoCookieLen=%{public}d',
          resp.body.length, infoCookies.length);
      }
    } catch (e) {
      Log.i('LearnAct', 'WEBVPN_CSRF ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    return this.webvpnCsrf;
  }

  /** 校验 info 门户会话（原项目 verifyInfoSession：infoUserData?_csrf= 检查 object.ryh） */
  async verifyInfoSession(expectedUserId: string): Promise<boolean> {
    const csrf: string = await this.getWebvpnCsrf();
    if (csrf.length === 0) {
      return false;
    }
    try {
      const INFO_TOKEN: string = '77726476706e69737468656265737421f9f9479369247b59700f81b9991b2631506205de';
      const userDataUrl: string = 'https://webvpn.tsinghua.edu.cn/https/' + INFO_TOKEN
        + '/b/info/gxfw_fg/common/grjbxx?_csrf=' + encodeURIComponent(csrf);
      const udResp: HttpResponse = await this.http.get(userDataUrl);
      Log.i('LearnAct', 'INFO_USERDATA code=%{public}d body=%{public}s', udResp.statusCode, udResp.body.substring(0, 150));
      const json: Record<string, Object> = JSON.parse(udResp.body) as Record<string, Object>;
      const objField = json['object'] as Record<string, Object>;
      return objField !== undefined && objField !== null && String(objField['ryh'] ?? '') === expectedUserId;
    } catch (e) {
      Log.i('LearnAct', 'INFO_USERDATA ex=%{public}s', e instanceof Error ? e.message : String(e));
      return false;
    }
  }

  async fetchCourses(): Promise<CampusCourse[]> {
    try {
      const csrf: string = await this.getCsrfToken();
      if (csrf.length === 0) {
        this.trace = 'no_csrf';
        return [];
      }

      // 1. 获取当前学期 ID（原项目 learnCurrentSemester）
      const semesterUrl: string = LEARN_BASE + '/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester?_csrf=' + encodeURIComponent(csrf);
      const semesterResp: HttpResponse = await this.http.get(semesterUrl);
      Log.i('LearnAct',  'SEMESTER code=%{public}d body=%{public}s',
        semesterResp.statusCode, semesterResp.body.substring(0, 200));
      const semesterJson: Record<string, Object> = JSON.parse(semesterResp.body) as Record<string, Object>;
      const message: string = String(semesterJson['message'] ?? '');
      const resultObj = semesterJson['result'] as Record<string, Object>;
      if (message !== 'success' || resultObj === undefined || resultObj === null) {
        this.trace = 'no_semester';
        return [];
      }
      const semesterId: string = String(resultObj['id'] ?? '');
      if (semesterId.length === 0) {
        this.trace = 'no_semester_id';
        return [];
      }
      this.currentSemester = String(resultObj['xnxqmc'] ?? '');
      this.semesterFirstDay = String(resultObj['kssj'] ?? '').substring(0, 10);

      // 2. 用真实学期 ID 获取课程列表（正确路径含 /wlxt/）
      const listUrl: string = LEARN_BASE + '/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/'
        + semesterId + '/zh?_csrf=' + encodeURIComponent(csrf);
      const resp: HttpResponse = await this.http.get(listUrl);
      Log.i('LearnAct',  'FETCH_COURSES code=%{public}d len=%{public}d body=%{public}s',
        resp.statusCode, resp.body.length, resp.body.substring(0, 200));
      const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const resultList = json['resultList'] as Object[];
      if (resultList === undefined || resultList === null) {
        this.trace = 'no_list';
        Log.i('LearnAct',  'FETCH_COURSES no_list keys=%{public}s', Object.keys(json).join(','));
        return [];
      }
      const courses: CampusCourse[] = [];
      for (let i: number = 0; i < resultList.length; i++) {
        const row: Record<string, Object> = resultList[i] as Record<string, Object>;
        const c: CampusCourse = new CampusCourse();
        c.id = String(row['wlkcid'] ?? '');
        // 原项目优先 kcm，回退 zywkcm
        const kcm: string = String(row['kcm'] ?? '');
        c.name = kcm.length > 0 ? kcm : String(row['zywkcm'] ?? '');
        c.teacher = String(row['jsm'] ?? '');
        c.code = String(row['kch'] ?? '');
        courses.push(c);
      }
      this.trace = 'ok:' + courses.length;
      return courses;
    } catch (e) {
      this.trace = 'ex';
      Log.i('LearnAct',  'FETCH_COURSES ex=%{public}s', e instanceof Error ? e.message : String(e));
      return [];
    }
  }

  /** 教务域激活：经信息门户漫游到 zhjw（原项目 roamDefault + ensureRegistrarRoam） */
  private async ensureRegistrarRoam(): Promise<void> {
    if (this.registrarRoamEnsured) {
      return;
    }
    const ok: boolean = await this.roamByYyfwid('287C0C6D90ABB364CD5FDF1495199962');
    if (ok) {
      this.registrarRoamEnsured = true;
    }
  }

  /** 成绩域激活（原项目 BKS_REPORT_YYFWID，与课表漫游是不同 yyfwid） */
  private async ensureGradesRoam(): Promise<void> {
    if (this.gradesRoamEnsured) {
      return;
    }
    const ok: boolean = await this.roamByYyfwid('B7EF0ADF9406335AD7905B30CD7B49B1');
    if (ok) {
      this.gradesRoamEnsured = true;
    }
  }

  /** 信息门户 onlineAppRedirect 漫游到指定 yyfwid 子系统（通用化原项目 roamDefault） */
  private async roamByYyfwid(yyfwid: string): Promise<boolean> {
    const csrf: string = await this.getWebvpnCsrf();
    if (csrf.length === 0) {
      Log.i('LearnAct', 'REG_ROAM skip: no webvpn csrf');
      return false;
    }
    try {
      const INFO_TOKEN: string = '77726476706e69737468656265737421f9f9479369247b59700f81b9991b2631506205de';
      const roamUrl: string = 'https://webvpn.tsinghua.edu.cn/https/' + INFO_TOKEN
        + '/b/yyfw/vyyfwxx/info/portal_fg/common/onlineAppRedirect?yyfwid=' + yyfwid + '&_csrf='
        + encodeURIComponent(csrf) + '&machine=p';
      const resp: HttpResponse = await this.http.get(roamUrl);
      Log.i('LearnAct', 'REG_ROAM code=%{public}d body=%{public}s', resp.statusCode, resp.body.substring(0, 150));
      let json: Record<string, Object>;
      try {
        json = JSON.parse(resp.body) as Record<string, Object>;
      } catch (e) {
        Log.i('LearnAct', 'REG_ROAM non_json head=%{public}s', resp.body.substring(0, 120));
        return false;
      }
      const resultStr: string = String(json['result'] ?? '');
      if (resultStr.length > 0 && resultStr !== 'success') {
        Log.i('LearnAct', 'REG_ROAM fail result=%{public}s msg=%{public}s', resultStr, String(json['msg'] ?? ''));
        return false;
      }
      const objField = json['object'] as Record<string, Object>;
      if (objField === undefined || objField === null) {
        Log.i('LearnAct', 'REG_ROAM no_object keys=%{public}s', Object.keys(json).join(','));
        return false;
      }
      const roamingurl: string = String(objField['roamingurl'] ?? '').replace(/&amp;/g, '&');
      if (roamingurl.length === 0) {
        Log.i('LearnAct', 'REG_ROAM no_roamingurl');
        return false;
      }
      const finalUrl: string = this.parseToWebVPN(roamingurl);
      const authResp: HttpResponse = await this.http.get(finalUrl);
      Log.i('LearnAct', 'REG_AUTH code=%{public}d len=%{public}d head=%{public}s',
        authResp.statusCode, authResp.body.length, authResp.body.substring(0, 80));
      return true;
    } catch (e) {
      Log.i('LearnAct', 'REG_ROAM ex=%{public}s', e instanceof Error ? e.message : String(e));
      return false;
    }
  }

  /** 把 zhjw 内网 URL 包装为 WebVPN URL（简化版 parseUrlToWebVPN） */
  private parseToWebVPN(url: string): string {
    if (url.indexOf('webvpn.tsinghua.edu.cn') >= 0) {
      return url;
    }
    const zhjwMarker: string = 'zhjw.cic.tsinghua.edu.cn';
    const idx: number = url.indexOf(zhjwMarker);
    if (idx >= 0) {
      const afterHost: string = url.substring(idx + zhjwMarker.length);
      const path: string = afterHost.startsWith('/') ? afterHost.substring(1) : afterHost;
      return SCHEDULE_BASE + '/' + path;
    }
    return url;
  }

  /** 拉取今日课表事件（今天 + 明天范围，过滤今天） */
  async fetchTodaySchedule(): Promise<ScheduleEvent[]> {
    const now: Date = new Date();
    const tomorrow: Date = new Date(now.getTime() + 86400000);
    const events: ScheduleEvent[] = await this.fetchScheduleEvents(formatYmd(now), formatYmd(tomorrow));
    const todayDash: string = formatDash(now);
    const result: ScheduleEvent[] = [];
    for (let i: number = 0; i < events.length; i++) {
      if (events[i].date === todayDash) {
        result.push(events[i]);
      }
    }
    return result;
  }

  /** 拉取日期范围内的课表事件（教务 zhjw JSONP） */
  async fetchScheduleEvents(startYmd: string, endYmd: string): Promise<ScheduleEvent[]> {
    try {
      await this.ensureRegistrarRoam();
      const url: string = SCHEDULE_BASE + '/jxmh_out.do?m=bks_jxrl_all&p_start_date=' + startYmd + '&p_end_date=' + endYmd + '&jsoncallback=m';
      const resp: HttpResponse = await this.http.get(url);
      let hexHead: string = '';
      const hexLen: number = resp.body.length < 40 ? resp.body.length : 40;
      for (let i: number = 0; i < hexLen; i++) {
        hexHead = hexHead + resp.body.charCodeAt(i).toString(16) + ' ';
      }
      Log.i('LearnAct', 'SCHEDULE code=%{public}d len=%{public}d idxBracket=%{public}d hex=%{public}s',
        resp.statusCode, resp.body.length, resp.body.indexOf('['), hexHead);
      if (resp.body.indexOf('[') < 0) {
        // 无 JSONP 数据：多半是会话失效拿到登录/错误页，重置漫游缓存下次重新激活
        this.registrarRoamEnsured = false;
        this.scheduleStatus = 'error';
      } else {
        this.scheduleStatus = 'ok';
      }
      const rows: Object[] = parseJsonpArray(resp.body);
      const events: ScheduleEvent[] = [];
      for (let i: number = 0; i < rows.length; i++) {
        const row = rows[i] as Record<string, Object>;
        const ev: ScheduleEvent = new ScheduleEvent();
        ev.date = normalizeScheduleDate(String(row['nq'] ?? ''));
        ev.title = String(row['nr'] ?? '');
        ev.location = String(row['dd'] ?? '');
        ev.startTime = String(row['kssj'] ?? '').replace(/：/g, ':');
        ev.endTime = String(row['jssj'] ?? '').replace(/：/g, ':');
        ev.id = String(row['grrlID'] ?? (ev.date + '-' + ev.title + '-' + ev.startTime));
        events.push(ev);
      }
      Log.i('LearnAct', 'SCHEDULE events=%{public}d', events.length);
      return events;
    } catch (e) {
      Log.i('LearnAct', 'SCHEDULE ex=%{public}s', e instanceof Error ? e.message : String(e));
      this.scheduleStatus = 'error';
      return [];
    }
  }

  /** 获取当前学期首日（YYYY-MM-DD；已缓存直接返回；失败返回空串） */
  async fetchSemesterInfo(): Promise<string> {
    if (this.semesterFirstDay.length > 0) {
      return this.semesterFirstDay;
    }
    try {
      const csrf: string = await this.getCsrfToken();
      if (csrf.length === 0) {
        return '';
      }
      const semesterUrl: string = withCsrf(
        LEARN_BASE + '/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester', csrf);
      const resp: HttpResponse = await this.http.get(semesterUrl);
      const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const resultObj = json['result'] as Record<string, Object>;
      if (resultObj === undefined || resultObj === null) {
        return '';
      }
      this.semesterFirstDay = String(resultObj['kssj'] ?? '').substring(0, 10);
      this.currentSemester = String(resultObj['xnxqmc'] ?? '');
      Log.i('LearnAct', 'SEMESTER_INFO firstDay=%{public}d name=%{public}s',
        this.semesterFirstDay.length, this.currentSemester);
      return this.semesterFirstDay;
    } catch (e) {
      Log.i('LearnAct', 'SEMESTER_INFO ex=%{public}s', e instanceof Error ? e.message : String(e));
      return '';
    }
  }

  /**
   * 成绩单（教务 zhjw HTML 表格，对齐原项目 grades.ts fetchGradeReport）：
   * 漫游 yyfwid=B7EF0ADF... → GET cj.cjCjbAll.do?m=bks_cjdcx&cjdlx=zw&flag=di1 → 解析表格。
   * 列取值按 cheerio 子节点序（含标签间文本节点）：childText(tr, 3/5/7/9/11) =
   * 第 2/3/4/5/6 个 td = 课程名/学分/等级/绩点/学期；首行为表头跳过（slice(1)）。
   */
  async fetchGrades(): Promise<GradeReport> {
    await this.ensureGradesRoam();
    const url: string = SCHEDULE_BASE + '/cj.cjCjbAll.do?m=bks_cjdcx&cjdlx=zw&flag=di1';
    const resp: HttpResponse = await this.http.get(url);
    Log.i('LearnAct', 'GRADES code=%{public}d len=%{public}d head=%{public}s',
      resp.statusCode, resp.body.length, resp.body.substring(0, 80));
    if (resp.body.indexOf('time out用户登陆超时或访问内容不存在') >= 0) {
      throw new Error('教务系统会话超时，请重新同步');
    }
    if (resp.body.indexOf('<title>清华大学WebVPN</title>') >= 0) {
      throw new Error('WebVPN 会话失效，请重新登录');
    }
    const allRows: string[][] = parseGradeTableChildren(resp.body);
    if (allRows.length > 1) {
      // 诊断日志：表头 + 首个数据行的子节点序列，用于核对列位
      Log.i('LearnAct', 'GRADES row0=[%{public}s] row1=[%{public}s]',
        allRows[0].join('|').substring(0, 120), allRows[1].join('|').substring(0, 180));
    }
    const courses: CampusGrade[] = [];
    for (let i: number = 1; i < allRows.length; i++) {
      const children: string[] = allRows[i];
      if (children.length < 12) {
        continue;
      }
      const name: string = children[3];
      if (name.length === 0) {
        continue;
      }
      const g: CampusGrade = new CampusGrade();
      g.name = name;
      g.credit = Number(children[5]) || 0;
      g.grade = children[7];
      // 绩点列为空 → NaN：P/F 课不计入学分绩（对齐原项目 computeGpa 的 isNaN 跳过语义）
      const pointStr: string = children[9];
      g.point = pointStr.trim().length > 0 ? Number(pointStr) : NaN;
      g.semester = children[11];
      courses.push(g);
    }
    if (courses.length === 0 && resp.body.indexOf('table1') < 0) {
      throw new Error('未解析到成绩数据');
    }
    const report: GradeReport = new GradeReport();
    let totalCredit: number = 0;
    let totalPoint: number = 0;
    let allCredit: number = 0;
    for (let i: number = 0; i < courses.length; i++) {
      const c: CampusGrade = courses[i];
      if (c.credit <= 0) {
        continue;
      }
      allCredit += c.credit;
      if (isNaN(c.point)) {
        continue;
      }
      totalCredit += c.credit;
      totalPoint += c.credit * c.point;
    }
    report.courses = courses;
    report.totalCredit = totalCredit;
    report.allCredit = allCredit;
    report.gpa = totalCredit > 0 ? totalPoint / totalCredit : 0;
    Log.i('LearnAct', 'GRADES courses=%{public}d gpa=%{public}f credit=%{public}f',
      courses.length, report.gpa, report.allCredit);
    return report;
  }

  /**
   * 校园资讯列表（info 门户 JSON，对齐原项目 news.ts getNewsList）：
   * GET /b/info/xxfb_fg/xnzx/template/more?oType=xs&lydw=&_csrf=..&lmid=all&currentPage=..&length=..
   */
  async fetchNewsList(page: number, length: number): Promise<CampusNews[]> {
    const csrf: string = await this.getWebvpnCsrf();
    if (csrf.length === 0) {
      throw new Error('info 门户会话未建立');
    }
    const INFO_TOKEN: string = '77726476706e69737468656265737421f9f9479369247b59700f81b9991b2631506205de';
    const base: string = 'https://webvpn.tsinghua.edu.cn/https/' + INFO_TOKEN;
    const url: string = base + '/b/info/xxfb_fg/xnzx/template/more?oType=xs&lydw='
      + '&_csrf=' + encodeURIComponent(csrf)
      + '&lmid=all&currentPage=' + String(page) + '&length=' + String(length);
    const resp: HttpResponse = await this.http.get(url);
    Log.i('LearnAct', 'NEWS code=%{public}d len=%{public}d head=%{public}s',
      resp.statusCode, resp.body.length, resp.body.substring(0, 100));
    const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
    const objField = json['object'] as Record<string, Object>;
    if (objField === undefined || objField === null) {
      throw new Error('资讯响应格式异常');
    }
    const rows = objField['dataList'] as Object[];
    const result: CampusNews[] = [];
    if (rows === undefined || rows === null) {
      return result;
    }
    for (let i: number = 0; i < rows.length; i++) {
      const row: Record<string, Object> = rows[i] as Record<string, Object>;
      const title: string = decodeHtmlEntities(String(row['bt'] ?? '')).trim();
      if (title.length === 0) {
        continue;
      }
      const item: CampusNews = new CampusNews();
      item.id = String(row['xxid'] ?? '');
      item.title = title;
      item.date = String(row['time'] ?? '');
      item.source = decodeHtmlEntities(String(row['dwmc_show'] ?? '')).trim();
      item.channel = NEWS_CHANNEL_LABELS[String(row['lmid'] ?? '')] ?? '通知';
      item.topped = String(row['yxzd'] ?? '').indexOf('1-') >= 0;
      result.push(item);
    }
    Log.i('LearnAct', 'NEWS items=%{public}d', result.length);
    return result;
  }

  /** 作业：对每门课遍历 未交(Wj)/已交未批改(Yjwg)/已批改(Ypg)，POST aoData */
  async fetchHomework(courses: CampusCourse[]): Promise<CampusHomework[]> {
    const csrf: string = await this.getCsrfToken();
    if (csrf.length === 0) { return []; }
    const result: CampusHomework[] = [];
    const suffixes: string[] = ['Wj', 'Yjwg', 'Ypg'];
    const submittedFlags: boolean[] = [false, true, true];
    const gradedFlags: boolean[] = [false, false, true];
    for (let ci: number = 0; ci < courses.length; ci++) {
      const course: CampusCourse = courses[ci];
      for (let si: number = 0; si < suffixes.length; si++) {
        try {
          const path: string = '/b/wlxt/kczy/zy/student/zyList' + suffixes[si];
          const aoData: string = '[{"name":"wlkcid","value":"' + course.id + '"}]';
          const resp: HttpResponse = await this.http.postForm(withCsrf(LEARN_BASE + path, csrf), { 'aoData': aoData });
          const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
          const objField = json['object'] as Record<string, Object>;
          if (objField === undefined || objField === null) { continue; }
          const rows = objField['aaData'] as Object[];
          if (rows === undefined || rows === null) { continue; }
          for (let ri: number = 0; ri < rows.length; ri++) {
            const row = rows[ri] as Record<string, Object>;
            const item: CampusHomework = new CampusHomework();
            item.id = String(row['xszyid'] ?? '');
            item.baseId = String(row['zyid'] ?? '');
            item.courseId = course.id;
            item.title = decodeHtmlEntities(String(row['bt'] ?? ''));
            item.courseName = course.name;
            item.deadline = formatDateTime(row['jzsj']);
            item.submitted = submittedFlags[si];
            item.graded = gradedFlags[si];
            item.status = gradedFlags[si] ? '已批改' : (submittedFlags[si] ? '已提交' : '待提交');
            const wlkcid: string = String(row['wlkcid'] ?? course.id);
            item.url = LEARN_BASE + '/f/wlxt/kczy/zy/student/viewCj?wlkcid=' + wlkcid + '&xszyid=' + item.id;
            const cjVal: Object = row['cj'] as Object;
            item.grade = (cjVal !== undefined && cjVal !== null) ? String(cjVal) : '';
            item.gradeContent = String(row['pynr'] ?? '').trim();
            result.push(item);
          }
        } catch (e) {
          // 单门课某状态失败跳过
        }
      }
    }
    Log.i('LearnAct',  'FETCH_HW courses=%{public}d count=%{public}d', courses.length, result.length);
    return result;
  }

  /** 通知：对每门课遍历 未过期(Wgq)/已过期(Ygq)，POST aoData */
  async fetchNotifications(courses: CampusCourse[]): Promise<CampusNotification[]> {
    const csrf: string = await this.getCsrfToken();
    if (csrf.length === 0) { return []; }
    const result: CampusNotification[] = [];
    const suffixes: string[] = ['Wgq', 'Ygq'];
    for (let ci: number = 0; ci < courses.length; ci++) {
      const course: CampusCourse = courses[ci];
      for (let si: number = 0; si < suffixes.length; si++) {
        try {
          const path: string = '/b/wlxt/kcgg/wlkc_ggb/student/pageListXsby' + suffixes[si];
          const aoData: string = '[{"name":"wlkcid","value":"' + course.id + '"}]';
          const resp: HttpResponse = await this.http.postForm(withCsrf(LEARN_BASE + path, csrf), { 'aoData': aoData });
          Log.i('LearnAct',  'NOTIF_RESP sfx=%{public}s code=%{public}d body=%{public}s',
            suffixes[si], resp.statusCode, resp.body.substring(0, 250));
          const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
          const objField = json['object'] as Record<string, Object>;
          if (objField === undefined || objField === null) { continue; }
          let rows = objField['aaData'] as Object[];
          if (rows === undefined || rows === null) { rows = objField['resultsList'] as Object[]; }
          if (rows === undefined || rows === null) { continue; }
          for (let ri: number = 0; ri < rows.length; ri++) {
            const row = rows[ri] as Record<string, Object>;
            const item: CampusNotification = new CampusNotification();
            item.id = String(row['ggid'] ?? '');
            item.title = decodeHtmlEntities(String(row['bt'] ?? ''));
            item.publisher = String(row['fbrxm'] ?? '');
            item.publishTime = formatDateTime(row['fbsj']);
            const hasRead: boolean = String(row['sfyd'] ?? '') === '是';
            item.isNew = !hasRead;
            // 通知内容 ggnr 是 Base64 编码的 HTML
            const ggnr: string = String(row['ggnr'] ?? '');
            let content: string = '';
            if (ggnr.length > 0) {
              try {
                content = stripHtml(decodeBase64(ggnr));
              } catch (e) {
                content = stripHtml(ggnr);
              }
            }
            item.content = content;
            result.push(item);
          }
        } catch (e) {
          // skip
        }
      }
    }
    Log.i('LearnAct',  'FETCH_NOTIF courses=%{public}d count=%{public}d', courses.length, result.length);
    return result;
  }

  /** 课件文件：对每门课 GET 列表 */
  async fetchFiles(courses: CampusCourse[]): Promise<CampusFile[]> {
    const csrf: string = await this.getCsrfToken();
    if (csrf.length === 0) { return []; }
    const result: CampusFile[] = [];
    for (let ci: number = 0; ci < courses.length; ci++) {
      const course: CampusCourse = courses[ci];
      try {
        const url: string = withCsrf(
          LEARN_BASE + '/b/wlxt/kj/wlkc_kjxxb/student/kjxxbByWlkcidAndSizeForStudent?wlkcid=' + course.id + '&size=200', csrf);
        const resp: HttpResponse = await this.http.get(url);
        Log.i('LearnAct',  'FILE_RESP code=%{public}d body=%{public}s',
          resp.statusCode, resp.body.substring(0, 250));
        const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
        // object 可能是数组（直接是文件列表）或 {resultsList: [...]}
        const objectField: Object = json['object'] as Object;
        let rows: Object[] = [];
        if (Array.isArray(objectField)) {
          rows = objectField as Object[];
        } else if (objectField !== undefined && objectField !== null) {
          const objField = objectField as Record<string, Object>;
          const rl = objField['resultsList'] as Object[];
          if (rl !== undefined && rl !== null) { rows = rl; }
        }
        for (let ri: number = 0; ri < rows.length; ri++) {
          const row = rows[ri] as Record<string, Object>;
          const item: CampusFile = new CampusFile();
          item.id = String(row['kjxxid'] ?? '');
          item.fileId = String(row['wjid'] ?? '');
          item.title = decodeHtmlEntities(String(row['bt'] ?? ''));
          item.courseName = course.name;
          item.size = String(row['fileSize'] ?? row['wjdx'] ?? '');
          item.isNew = String(row['sfqd'] ?? '') === '是';
          item.description = stripHtml(String(row['ms'] ?? ''));
          item.uploadTime = formatDateTime(row['scsj']);
          item.downloadUrl = LEARN_BASE + '/b/wlxt/kj/wlkc_kjxxb/student/downloadFile?sfgk=0&wjid=' + item.fileId;
          item.previewUrl = LEARN_BASE + '/f/wlxt/kc/wj_wjb/student/beforePlay?wjid=' + item.fileId + '&mk=mk_kcwj&browser=-1&sfgk=0&pageType=all';
          result.push(item);
        }
      } catch (e) {
        // skip
      }
    }
    Log.i('LearnAct',  'FETCH_FILES courses=%{public}d count=%{public}d', courses.length, result.length);
    return result;
  }

  /** 抓取并解析单条作业 viewCj 详情页（作业说明 + 附件），对齐 thu-learn-lib parseHomeworkAtUrl */
  async fetchHomeworkDetail(url: string): Promise<HomeworkDetailData> {
    const result: HomeworkDetailData = new HomeworkDetailData();
    try {
      const resp: HttpResponse = await this.http.get(url);
      const html: string = resp.body;
      const c55: string[] = this.extractByMarker(html, 'class="c55"');
      if (c55.length > 0) { result.description = stripHtml(c55[0]); }
      if (c55.length > 1) { result.answerContent = stripHtml(c55[1]); }
      result.attachments = this.extractAttachmentNames(html);
      Log.i('LearnAct',  'HW_DETAIL desc_len=%{public}d attach=%{public}d', result.description.length, result.attachments.length);
    } catch (e) {
      Log.i('LearnAct',  'HW_DETAIL ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    return result;
  }

  /** 提取所有匹配 marker 的 <div> 的平衡内容 */
  private extractByMarker(html: string, marker: string): string[] {
    const results: string[] = [];
    let searchFrom: number = 0;
    while (searchFrom < html.length) {
      const idx: number = html.indexOf(marker, searchFrom);
      if (idx < 0) { break; }
      const divStart: number = html.lastIndexOf('<div', idx);
      if (divStart < 0) { break; }
      const content: string = this.extractDivContent(html, divStart);
      results.push(content);
      searchFrom = idx + marker.length;
    }
    return results;
  }

  /** 从 <div 起始位置提取到平衡 </div> 的内部内容 */
  private extractDivContent(html: string, divStart: number): string {
    let depth: number = 0;
    let i: number = divStart;
    let contentStart: number = -1;
    const len: number = html.length;
    while (i < len) {
      if (html.substring(i, i + 4) === '<div') {
        depth++;
        if (contentStart < 0) {
          const gt: number = html.indexOf('>', i);
          if (gt < 0) { return ''; }
          contentStart = gt + 1;
          i = gt + 1;
          continue;
        }
        i += 4;
      } else if (html.substring(i, i + 6) === '</div>') {
        depth--;
        if (depth === 0 && contentStart >= 0) {
          return html.substring(contentStart, i);
        }
        i += 6;
      } else {
        i++;
      }
    }
    return '';
  }

  /** 提取作业附件文件名（div.list.fujian 区域内的链接文本） */
  private extractAttachmentNames(html: string): string[] {
    const names: string[] = [];
    const blocks: string[] = this.extractByMarker(html, 'list fujian');
    for (let bi: number = 0; bi < blocks.length; bi++) {
      const text: string = this.extractFirstAnchorText(blocks[bi]);
      if (text.length > 0) {
        names.push(text);
      }
    }
    return names;
  }

  private extractFirstAnchorText(fragment: string): string {
    const aStart: number = fragment.indexOf('<a');
    if (aStart < 0) { return ''; }
    const gt: number = fragment.indexOf('>', aStart);
    if (gt < 0) { return ''; }
    const aEnd: number = fragment.indexOf('</a>', gt);
    if (aEnd < 0) { return ''; }
    return stripHtml(fragment.substring(gt + 1, aEnd)).trim();
  }
}
