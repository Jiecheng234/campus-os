import { HttpClient, HttpResponse } from '../HttpClient';

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

  async activateLearn(): Promise<boolean> {
    if (this.learnReady) {
      return true;
    }
    try {
      this.trace = 'home_page';
      const homeHtml: string = await this.http.get(LEARN_BASE + '/f/wlxt/index/course/student/').then((r: HttpResponse) => r.body);

      let csrfFound: string = '';
      const p1: RegExp = new RegExp('_csrf"\\s+value\\s*=\\s*"([^"]+)"', 'i');
      const m1 = p1.exec(homeHtml);
      if (m1 !== null && m1.length >= 2) { csrfFound = m1[1]; }

      if (csrfFound.length === 0) {
        const p2: RegExp = new RegExp('&_csrf=([a-zA-Z0-9\\-]+)', 'g');
        const m2 = p2.exec(homeHtml);
        if (m2 !== null && m2.length >= 2) { csrfFound = m2[1]; }
      }

      if (csrfFound.length > 0) {
        this.csrfToken = csrfFound;
        this.learnReady = true;
        this.trace = 'learn_ok';
        return true;
      }

      if (homeHtml.indexOf('sm2publicKey') >= 0) {
        this.trace = 'need_sso';
      } else if (homeHtml.length < 500) {
        this.trace = 'short;' + homeHtml.length;
      } else {
        this.trace = 'no_csrf;' + homeHtml.length;
      }
      return false;
    } catch (e) {
      this.trace = 'ex';
      return false;
    }
  }

  async getCsrfToken(): Promise<string> {
    if (this.csrfToken.length > 0) {
      return this.csrfToken;
    }
    await this.activateLearn();
    return this.csrfToken;
  }

  async fetchCourses(): Promise<CampusCourse[]> {
    try {
      await this.activateLearn();
      const csrf: string = this.csrfToken;
      if (csrf.length === 0) {
        return [];
      }
      const url: string = LEARN_BASE + '/b/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/current/zh?_csrf=' + encodeURIComponent(csrf);
      const resp: HttpResponse = await this.http.get(url);
      const json: Record<string, Object> = JSON.parse(resp.body) as Record<string, Object>;
      const resultList = json['resultList'] as Object[];
      if (resultList === undefined || resultList === null) {
        return [];
      }
      const courses: CampusCourse[] = [];
      for (let i: number = 0; i < resultList.length; i++) {
        const row: Record<string, Object> = resultList[i] as Record<string, Object>;
        const c: CampusCourse = new CampusCourse();
        c.id = String(row['wlkcid'] ?? '');
        c.name = String(row['kcm'] ?? '');
        c.teacher = String(row['jsm'] ?? '');
        c.code = String(row['kch'] ?? '');
        courses.push(c);
      }
      return courses;
    } catch (e) {
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
