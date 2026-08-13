import { HttpClient, HttpResponse } from '../HttpClient';
import { SessionManager } from '../auth/SessionManager';
import { hilog } from '@kit.PerformanceAnalysisKit';

const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
const SCHEDULE_BASE: string = 'https://webvpn.tsinghua.edu.cn/http/77726476706e69737468656265737421eaff4b8b69336153301c9aa596522b20bc86e6e559a9b290';

export class CampusCourse {
  id: string = '';
  name: string = '';
  teacher: string = '';
  code: string = '';
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
}
