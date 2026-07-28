import { HttpClient, HttpResponse } from '../HttpClient';
import { CookieJar } from '../CookieJar';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';

const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
const SCHEDULE_BASE: string = 'https://webvpn.tsinghua.edu.cn/http/77726476706e69737468656265737421eaff4b8b69336153301c9aa596522b20bc86e6e559a9b290';

class CourseRaw {
  wlkcid: string = '';
  kcm: string = '';
  jsm: string = '';
  kch: string = '';
}

export class CampusCourse {
  id: string = '';
  name: string = '';
  teacher: string = '';
  code: string = '';
}

export class CampusDataService {
  private http: HttpClient;
  private csrfToken: string = '';

  constructor(http: HttpClient) {
    this.http = http;
  }

  async getCsrfToken(): Promise<string> {
    if (this.csrfToken.length > 0) {
      return this.csrfToken;
    }
    const resp: HttpResponse = await this.http.get(LEARN_BASE + '/f/wlxt/index/course/student/');
    const body: string = resp.body;
    const pattern: string = '_csrf"\\s+value\\s*=\\s*"([^"]+)"';
    const re: RegExp = new RegExp(pattern, 'i');
    const match = re.exec(body);
    if (match !== null && match.length >= 2) {
      this.csrfToken = match[1];
    }
    return this.csrfToken;
  }

  async fetchCourses(): Promise<CampusCourse[]> {
    try {
      await this.getCsrfToken();
      const csrf: string = this.csrfToken;
      if (csrf.length === 0) {
        return [];
      }
      const url: string = LEARN_BASE + '/b/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/current/zh?_csrf=' + encodeURIComponent(csrf);
      const resp: HttpResponse = await this.http.get(url);
      const jsonStr: string = resp.body;
      const json: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
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
