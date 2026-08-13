import { HttpClient, HttpResponse } from '../HttpClient';
import { SessionManager } from '../auth/SessionManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
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

function decodeHtmlEntities(value: string): string {
  return value
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"');
}

function withCsrf(url: string, csrf: string): string {
  const sep: string = url.indexOf('?') >= 0 ? '&' : '?';
  return url + sep + '_csrf=' + encodeURIComponent(csrf);
}

export class CampusCourse {
  id: string = '';
  name: string = '';
  teacher: string = '';
  code: string = '';
}

export class CampusHomework {
  id: string = '';
  title: string = '';
  courseName: string = '';
  deadline: string = '';
  status: string = '';
  submitted: boolean = false;
  graded: boolean = false;
}

export class CampusNotification {
  id: string = '';
  title: string = '';
  publisher: string = '';
  publishTime: string = '';
  isNew: boolean = false;
}

export class CampusFile {
  id: string = '';
  title: string = '';
  courseName: string = '';
  size: string = '';
  isNew: boolean = false;
}

export class CampusDataService {
  private http: HttpClient;
  private csrfToken: string = '';
  private learnReady: boolean = false;
  public trace: string = '';

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
      hilog.info(0xCAFE, 'LearnAct', 'SEMESTER code=%{public}d body=%{public}s',
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

      // 2. 用真实学期 ID 获取课程列表（正确路径含 /wlxt/）
      const listUrl: string = LEARN_BASE + '/b/wlxt/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/'
        + semesterId + '/zh?_csrf=' + encodeURIComponent(csrf);
      const resp: HttpResponse = await this.http.get(listUrl);
      hilog.info(0xCAFE, 'LearnAct', 'FETCH_COURSES code=%{public}d len=%{public}d body=%{public}s',
        resp.statusCode, resp.body.length, resp.body.substring(0, 200));
      const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const resultList = json['resultList'] as Object[];
      if (resultList === undefined || resultList === null) {
        this.trace = 'no_list';
        hilog.info(0xCAFE, 'LearnAct', 'FETCH_COURSES no_list keys=%{public}s', Object.keys(json).join(','));
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
      hilog.info(0xCAFE, 'LearnAct', 'FETCH_COURSES ex=%{public}s', e instanceof Error ? e.message : String(e));
      return [];
    }
  }

  async fetchSchedule(yyyymmdd: string): Promise<string> {
    try {
      const url: string = SCHEDULE_BASE + '/jxmh_out.do?m=bks_jxrl_all&p_start_date=' + yyyymmdd + '&p_end_date=' + yyyymmdd + '&jsoncallback=m';
      const resp: HttpResponse = await this.http.get(url);
      return resp.body;
    } catch (e) {
      return '';
    }
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
            item.title = decodeHtmlEntities(String(row['bt'] ?? ''));
            item.courseName = course.name;
            item.deadline = formatDateTime(row['jzsj']);
            item.submitted = submittedFlags[si];
            item.graded = gradedFlags[si];
            item.status = gradedFlags[si] ? '已批改' : (submittedFlags[si] ? '已提交' : '待提交');
            result.push(item);
          }
        } catch (e) {
          // 单门课某状态失败跳过
        }
      }
    }
    hilog.info(0xCAFE, 'LearnAct', 'FETCH_HW courses=%{public}d count=%{public}d', courses.length, result.length);
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
          hilog.info(0xCAFE, 'LearnAct', 'NOTIF_RESP sfx=%{public}s code=%{public}d body=%{public}s',
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
            result.push(item);
          }
        } catch (e) {
          // skip
        }
      }
    }
    hilog.info(0xCAFE, 'LearnAct', 'FETCH_NOTIF courses=%{public}d count=%{public}d', courses.length, result.length);
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
        hilog.info(0xCAFE, 'LearnAct', 'FILE_RESP code=%{public}d body=%{public}s',
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
          item.title = decodeHtmlEntities(String(row['bt'] ?? ''));
          item.courseName = course.name;
          item.size = String(row['fileSize'] ?? row['wjdx'] ?? '');
          item.isNew = String(row['sfqd'] ?? '') === '是';
          result.push(item);
        }
      } catch (e) {
        // skip
      }
    }
    hilog.info(0xCAFE, 'LearnAct', 'FETCH_FILES courses=%{public}d count=%{public}d', courses.length, result.length);
    return result;
  }
}
