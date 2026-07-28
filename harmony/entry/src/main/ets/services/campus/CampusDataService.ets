import { HttpClient, HttpResponse } from '../HttpClient';
import { CookieJar } from '../CookieJar';
import { encryptPassword, extractSm2PublicKey, extractFirstAnchorHref } from '../../utils/SM2Crypto';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';

const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
const ID_HOST: string = 'https://id.tsinghua.edu.cn';
const ID_LOGIN_URL: string = ID_HOST + '/do/off/ui/auth/login/check';
const ID_BASE_URL: string = ID_HOST + '/do/off/ui/auth/login/form/';
const LEARN_LOGIN_YYFWID: string = 'bb5df85216504820be7bba2b0ae1535b/0';
const LOGIN_SUCCESS_MARK: string = '登录成功';

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
  private learnReady: boolean = false;
  public trace: string = '';

  constructor(http: HttpClient) {
    this.http = http;
  }

  async activateLearn(): Promise<boolean> {
    if (this.learnReady) {
      this.trace = 'already_ready';
      return true;
    }
    try {
      const creds: SecureCredentials | undefined = await SecureStorage.getCredentials();
      if (creds === undefined) {
        this.trace = 'no_stored_creds';
        return false;
      }

      this.trace = 'fetching_form';
      const formUrl: string = ID_BASE_URL + LEARN_LOGIN_YYFWID;
      let formHtml: string;
      try {
        formHtml = await this.http.get(formUrl).then((r: HttpResponse) => r.body);
      } catch (e) {
        this.trace = 'form_get_failed:' + (e instanceof Error ? e.message : 'unknown');
        return false;
      }

      const pk: string = extractSm2PublicKey(formHtml);
      if (pk.length === 0) {
        this.trace = 'no_sm2_key;html_len=' + formHtml.length;
        return false;
      }
      this.trace = 'got_sm2_key_len=' + pk.length;

      const epw: string = await encryptPassword(creds.password, pk);
      if (epw.length === 0) {
        this.trace = 'encrypt_failed';
        return false;
      }
      this.trace = 'encrypted_pw_len=' + epw.length;

      const formData: Record<string, string> = {
        'i_user': creds.studentId,
        'i_pass': epw,
        'fingerPrint': '',
        'fingerGenPrint': '',
        'fingerGenPrint3': '',
        'i_captcha': '',
      };

      let response: string = '';
      for (let i: number = 0; i < 2; i++) {
        try {
          response = await this.http.postForm(ID_LOGIN_URL, formData).then((r: HttpResponse) => r.body);
        } catch (e) {
          this.trace = 'post_failed:' + (e instanceof Error ? e.message : 'unknown');
          return false;
        }
        if (response.indexOf(LOGIN_SUCCESS_MARK) >= 0) {
          break;
        }
      }

      if (response.indexOf(LOGIN_SUCCESS_MARK) < 0) {
        this.trace = 'no_success_mark;resp_len=' + response.length;
        return false;
      }
      this.trace = 'login_ok';

      const callbackUrl: string = extractFirstAnchorHref(response);
      if (callbackUrl.length === 0) {
        this.trace = 'no_callback_url';
        return false;
      }

      const parts: string[] = callbackUrl.split('=');
      const ticket: string = parts[parts.length - 1];
      if (ticket.length === 0) {
        this.trace = 'no_ticket';
        return false;
      }
      this.trace = 'ticket_len=' + ticket.length;

      try {
        await this.http.get(LEARN_BASE + '/b/j_spring_security_thauth_roaming_entry?ticket=' + ticket);
      } catch (e) {
        this.trace = 'roam_failed:' + (e instanceof Error ? e.message : 'unknown');
        return false;
      }
      this.trace = 'roam_done';

      const homeHtml: string = await this.http.get(LEARN_BASE + '/f/wlxt/index/course/student/').then((r: HttpResponse) => r.body);

      const csrfPattern: string = '&_csrf=(\\S+?)["\']';
      const csrfRe: RegExp = new RegExp(csrfPattern, 'g');
      const csrfMatch = csrfRe.exec(homeHtml);
      if (csrfMatch !== null && csrfMatch.length >= 2) {
        this.csrfToken = csrfMatch[1];
        this.learnReady = true;
        this.trace = 'learn_ok';
        return true;
      }

      this.trace = 'no_csrf;home_len=' + homeHtml.length;
      return false;
    } catch (e) {
      this.trace = 'exception:' + (e instanceof Error ? e.message : 'unknown');
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
      await this.getCsrfToken();
      const csrf: string = this.csrfToken;
      if (csrf.length === 0) {
        return [];
      }

      const semesterUrl: string = LEARN_BASE + '/b/kc/zhjw_v_code_xnxq/getCurrentAndNextSemester?_csrf=' + encodeURIComponent(csrf);
      const semResp: HttpResponse = await this.http.get(semesterUrl);
      const semJson: Record<string, Object> = JSON.parse(semResp.body) as Record<string, Object>;
      const semResult: Record<string, Object> = semJson['result'] as Record<string, Object>;
      let semesterId: string = '';
      if (semResult !== undefined && semResult !== null) {
        semesterId = String(semResult['id'] ?? '');
      }
      if (semesterId.length === 0) {
        return [];
      }

      const url: string = LEARN_BASE + '/b/kc/v_wlkc_xs_xkb_kcb_extend/student/loadCourseBySemesterId/' + semesterId + '/zh?_csrf=' + encodeURIComponent(csrf);
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
