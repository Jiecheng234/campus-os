import { HttpClient, HttpResponse } from '../HttpClient';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CookieManager } from '../CookieManager';
import { WEBVPN_OAUTH_LOGIN_URL, WEBVPN_BASE_URL, wrapWebVPNUrl, ID_HOST_URL, ID_LOGIN_URL, DOUBLE_AUTH_URL, SAVE_FINGER_URL, INFO_PORTAL_YYFWID, getSubsystemUrl, SUBSYSTEM_LEARN } from '../WebvpnConstants';
import {
  encryptPassword, extractSm2PublicKey, extractCsrfToken,
  extractFirstAnchorHref, extractMsgNote, extractMetaRedirect, extractFormAction
} from '../../utils/SM2Crypto';
import { generateUUID } from '../../utils/CryptoUtils';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';
import { CampusCredentials } from '../../domain/AuthTypes';

const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
const ID_BASE_URL: string = 'https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/';
const LEARN_LOGIN_YYFWID: string = 'bb5df85216504820be7bba2b0ae1535b/0';

export enum LoginResultType {
  SUCCESS = 'success',
  TWO_FACTOR = 'two_factor',
  ERROR = 'error',
}

export class LoginResult {
  type: LoginResultType = LoginResultType.ERROR;
  message: string = '';
  twoFactorHint: string = '';
  trace: string[] = [];
}

export class TwoFactorApproach {
  type: string = '';
  label: string = '';
}

export class TwoFactorHandler {
  resolve: (() => void) = () => {};
  reject: ((reason: string) => void) = () => {};
}

export class TsinghuaAuthService {
  private csrfToken: string = '';
  private trace: string[] = [];
  private cachedCredentials: CampusCredentials | undefined = undefined;
  private twoFactorHandler: TwoFactorHandler | undefined = undefined;
  private http: HttpClient;

  constructor() {
    this.http = new HttpClient(new CookieManager());
  }

  setTwoFactorHandler(handler: TwoFactorHandler): void {
    this.twoFactorHandler = handler;
  }

  getCsrfToken(): string {
    return this.csrfToken;
  }

  getLastTrace(): string[] {
    return this.trace;
  }

  addTrace(msg: string): void {
    this.trace.push(msg);
  }

  async hydrateCredentials(): Promise<boolean> {
    const creds: SecureCredentials | undefined = await SecureStorage.getCredentials();
    if (creds !== undefined) {
      const campusCreds: CampusCredentials = new CampusCredentials();
      campusCreds.studentId = creds.studentId;
      campusCreds.password = creds.password;
      campusCreds.fingerprint = generateUUID();
      this.cachedCredentials = campusCreds;
      return true;
    }
    return false;
  }

  async login(credentials: CampusCredentials): Promise<LoginResult> {
    this.trace = [];
    this.addTrace('login_start');
    this.http.clearSession();

    this.cachedCredentials = credentials;

    let oauthPage: string = '';
    try {
      this.addTrace('warmup');
      const w1: HttpResponse = await this.http.get(WEBVPN_OAUTH_LOGIN_URL);
      hilog.info(0xCAFE, 'LearnAct', 'WARMUP code=%{public}d len=%{public}d', w1.statusCode, w1.body.length);

      this.addTrace('fetch_form');
      const formResp: HttpResponse = await this.http.get(WEBVPN_OAUTH_LOGIN_URL);
      oauthPage = formResp.body;
      hilog.info(0xCAFE, 'LearnAct', 'FORM code=%{public}d len=%{public}d has_sm2=%{public}s',
        formResp.statusCode, oauthPage.length, oauthPage.indexOf('sm2publicKey') >= 0);
      this.addTrace('form_len:' + oauthPage.length);
    } catch (e) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '无法连接校园网: ' + (e instanceof Error ? e.message : '网络不可达');
      result.trace = this.trace;
      return result;
    }

    if (oauthPage.indexOf('sm2publicKey') < 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '认证链异常（需清华校园网）；详细信息：' + oauthPage.substring(0, 80);
      result.trace = this.trace;
      return result;
    }

    const sm2Key: string = extractSm2PublicKey(oauthPage);
    this.addTrace('pk:' + sm2Key.length);
    const formAction: string = extractFormAction(oauthPage);
    hilog.info(0xCAFE, 'LearnAct', 'FORM_ACTION=%{public}s', formAction);
    const loginFormIdx: number = oauthPage.indexOf('sm2publicKey');
    if (loginFormIdx >= 0) {
      hilog.info(0xCAFE, 'LearnAct', 'SM2EL=%{public}s', oauthPage.substring(loginFormIdx - 20, loginFormIdx + 150));
    }
    const ajaxIdx: number = oauthPage.indexOf('ajax');
    if (ajaxIdx >= 0) {
      const ajaxStr: string = oauthPage.substring(ajaxIdx, ajaxIdx + 900);
      hilog.info(0xCAFE, 'LearnAct', 'AJAX1=%{public}s', ajaxStr.substring(0, 300));
      hilog.info(0xCAFE, 'LearnAct', 'AJAX2=%{public}s', ajaxStr.substring(300, 600));
      hilog.info(0xCAFE, 'LearnAct', 'AJAX3=%{public}s', ajaxStr.substring(600, 900));
    }
    const csrfIdx: number = oauthPage.indexOf('_csrf');
    if (csrfIdx >= 0) {
      hilog.info(0xCAFE, 'LearnAct', 'CSRF=%{public}s', oauthPage.substring(csrfIdx - 20, csrfIdx + 60));
    }

    if (sm2Key.length === 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '获取SM2公钥失败';
      result.trace = this.trace;
      return result;
    }

    const encryptedPw: string = await encryptPassword(credentials.password, sm2Key);
    if (encryptedPw.length === 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = 'SM2加密失败';
      result.trace = this.trace;
      return result;
    }
    hilog.info(0xCAFE, 'LearnAct', 'SM2 prefix=%{public}s len=%{public}d', encryptedPw.substring(0, 8), encryptedPw.length);

    const formData: Record<string, string> = {
      'i_user': credentials.studentId,
      'i_pass': encryptedPw,
      'fingerPrint': credentials.fingerprint,
      'fingerGenPrint': '',
      'fingerGenPrint3': '',
      'i_captcha': '',
    };
    this.addTrace('post_id_login');

    let idResponse: string = '';
    try {
      const idResp: HttpResponse = await this.http.postForm(ID_LOGIN_URL, formData);
      idResponse = idResp.body;
    } catch (e) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '登录请求失败: ' + (e instanceof Error ? e.message : '未知错误');
      result.trace = this.trace;
      return result;
    }
    this.addTrace('id_resp:' + idResponse.length);
    hilog.info(0xCAFE, 'LearnAct', 'MAIN_POST len=%{public}d has_ok=%{public}s has_err=%{public}s',
      idResponse.length, idResponse.indexOf('登录成功') >= 0, idResponse.indexOf('出错了') >= 0);
    const mainCb: string = extractFirstAnchorHref(idResponse);
    hilog.info(0xCAFE, 'LearnAct', 'MAIN_POST cb=%{public}s', mainCb.substring(0, 80));

    const TWO_FACTOR_MARK: string = '/b/doubleAuth/login';
    if (idResponse.indexOf(TWO_FACTOR_MARK) >= 0 || idResponse.indexOf('doubleAuth') >= 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.TWO_FACTOR;
      result.message = '需要双因子认证';
      result.twoFactorHint = '请选择验证方式';
      result.trace = this.trace;
      return result;
    }

    const errorMsg: string = extractMsgNote(idResponse);
    if (errorMsg.length > 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = errorMsg;
      result.trace = this.trace;
      return result;
    }

    const redirectUrl: string = extractFirstAnchorHref(idResponse);
    if (redirectUrl.length > 0) {
      this.addTrace('following_redirect');
      const cbResp: HttpResponse = await this.http.get(redirectUrl);
      hilog.info(0xCAFE, 'LearnAct', 'MAIN_CB code=%{public}d len=%{public}d', cbResp.statusCode, cbResp.body.length);
    }

    const successResult: LoginResult = new LoginResult();
    successResult.type = LoginResultType.SUCCESS;
    successResult.message = '登录成功';
    successResult.trace = this.trace;

    await SecureStorage.saveCredentials(credentials.studentId, credentials.password, credentials.fingerprint);

    // 先建立 info 门户会话（校园通用门户漫游），再激活 learn
    try {
      await this.roamIdPolicy(credentials, INFO_PORTAL_YYFWID);
      this.addTrace('info_roam_ok');
    } catch (e) {
      this.addTrace('info_roam_fail:' + (e instanceof Error ? e.message : ''));
    }

    this.addTrace('activating_learn');
    try {
      await this.activateLearnSession(credentials);
      this.addTrace('learn_activated');
      successResult.message = '登录成功 (learn已激活)';
    } catch (e) {
      this.addTrace('learn_fail:' + (e instanceof Error ? e.message : ''));
      successResult.message = '登录成功 (learn未激活: ' + (e instanceof Error ? e.message : '') + ')';
    }

    return successResult;
  }

  private async roamIdPolicy(credentials: CampusCredentials, payload: string): Promise<void> {
    let response: string = '';
    for (let i: number = 0; i < 2; i++) {
      const formHtml: string = await this.http.get(ID_BASE_URL + payload).then((r: HttpResponse) => r.body);
      const pk: string = extractSm2PublicKey(formHtml);
      if (pk.length === 0) {
        throw new Error('roam: no sm2 key');
      }
      const epw: string = await encryptPassword(credentials.password, pk);
      const fd: Record<string, string> = {
        'i_user': credentials.studentId,
        'i_pass': epw,
        'fingerPrint': credentials.fingerprint,
        'fingerGenPrint': '',
        'fingerGenPrint3': '',
        'i_captcha': '',
      };
      response = await this.http.postForm(ID_LOGIN_URL, fd).then((r: HttpResponse) => r.body);
      if (response.indexOf('登录成功') >= 0) {
        break;
      }
    }
    if (response.indexOf('登录成功') < 0) {
      throw new Error('roam: login failed');
    }
    const callbackHref: string = extractFirstAnchorHref(response);
    if (callbackHref.length === 0) {
      throw new Error('roam: no callback');
    }
    const wrapped: string = wrapWebVPNUrl(callbackHref);
    const lbResp: HttpResponse = await this.http.get(wrapped);
    hilog.info(0xCAFE, 'LearnAct', 'ROAM_LB code=%{public}d len=%{public}d has_sm2=%{public}s',
      lbResp.statusCode, lbResp.body.length, lbResp.body.indexOf('sm2publicKey') >= 0);
    hilog.info(0xCAFE, 'LearnAct', 'ROAM_LB_BODY=%{public}s', lbResp.body.substring(0, 150));
  }

  private async activateLearnSession(credentials: CampusCredentials): Promise<void> {
    const formUrl: string = ID_BASE_URL + LEARN_LOGIN_YYFWID;
    hilog.info(0xCAFE, 'LearnAct', 'form_url=%{public}s', formUrl);
    const formHtml: string = await this.http.get(formUrl).then((r: HttpResponse) => r.body);
    hilog.info(0xCAFE, 'LearnAct', 'form_len=%{public}d has_sm2=%{public}s', formHtml.length, formHtml.indexOf('sm2publicKey') >= 0);

    const pk: string = extractSm2PublicKey(formHtml);
    if (pk.length === 0) {
      throw new Error('no_sm2;len=' + formHtml.length);
    }

    const epw: string = await encryptPassword(credentials.password, pk);
    if (epw.length === 0) {
      throw new Error('learn encrypt failed');
    }

    const fd: Record<string, string> = {
      'i_user': credentials.studentId,
      'i_pass': epw,
      'fingerPrint': credentials.fingerprint,
      'fingerGenPrint': '',
      'fingerGenPrint3': '',
      'i_captcha': '',
    };

    let response: string = '';
    for (let i: number = 0; i < 2; i++) {
      const respObj: HttpResponse = await this.http.postForm(ID_LOGIN_URL, fd);
      response = respObj.body;
      hilog.info(0xCAFE, 'LearnAct', 'POST code=%{public}d body_len=%{public}d body=%{public}s',
        respObj.statusCode, response.length, response.substring(0, 300));
      if (response.indexOf('/b/doubleAuth/login') >= 0) {
        throw new Error('learn 2FA required');
      }
      if (response.indexOf('登录成功') >= 0) {
        break;
      }
    }

    if (response.indexOf('登录成功') < 0) {
      throw new Error('not_ok;len=' + response.length + ';' + response.substring(20, 120));
    }

    // Try the home page directly - the CSS login should have established the session
    const homeHtml: string = await this.http.get(LEARN_BASE + '/f/wlxt/index/course/student/').then((r: HttpResponse) => r.body);
    let csrfFound: string = '';
    const p: RegExp = new RegExp('_csrf"\\s+value\\s*=\\s*"([^"]+)"', 'i');
    const m = p.exec(homeHtml);
    if (m !== null && m.length >= 2) { csrfFound = m[1]; }

    if (csrfFound.length > 0) {
      this.csrfToken = csrfFound;
      return;
    }

    if (homeHtml.indexOf('sm2publicKey') >= 0) {
      throw new Error('home_needs_login;len=' + homeHtml.length);
    }
    throw new Error('no_csrf_home;len=' + homeHtml.length);
  }

  async send2FACode(method: string): Promise<boolean> {
    this.addTrace('sending_2fa:' + method);
    const formData: Record<string, string> = {
      'action': 'SEND_CODE',
      'type': method,
    };
    try {
      const resp: HttpResponse = await this.http.postForm(DOUBLE_AUTH_URL, formData);
      const body: string = resp.body;
      if (body.indexOf('success') >= 0) {
        this.addTrace('2fa_sent_ok');
        return true;
      }
      this.addTrace('2fa_sent_fail:' + body.substring(0, 40));
      return false;
    } catch (e) {
      this.addTrace('2fa_send_exception');
      return false;
    }
  }

  async verify2FACode(code: string): Promise<LoginResult> {
    this.addTrace('verifying_2fa');
    const formData: Record<string, string> = {
      'action': 'VERITY_CODE',
      'type': 'mobile',
      'vericode': code,
    };
    try {
      const resp: HttpResponse = await this.http.postForm(DOUBLE_AUTH_URL, formData);
      const body: string = resp.body;
      this.addTrace('2fa_resp:' + body.length);
      hilog.info(0xCAFE, 'LearnAct', '2FA_VERIFY len=%{public}d body=%{public}s', body.length, body.substring(0, 200));

      if (body.indexOf('success') < 0) {
        const result: LoginResult = new LoginResult();
        result.type = LoginResultType.ERROR;
        result.message = '验证码错误或已过期';
        result.trace = this.trace;
        return result;
      }

      // 信任此设备（必须在 redirectUrl 之前，避免后续 roam 再次要求 2FA）
      if (this.cachedCredentials !== undefined) {
        try {
          const saveFinger: Record<string, string> = {
            'fingerprint': this.cachedCredentials.fingerprint,
            'deviceName': 'CampusOS',
            'radioVal': '是',
          };
          const sfResp: HttpResponse = await this.http.postForm(SAVE_FINGER_URL, saveFinger);
          hilog.info(0xCAFE, 'LearnAct', 'SAVE_FINGER resp=%{public}s', sfResp.body.substring(0, 100));
          this.addTrace('trust_device_ok');
        } catch (e) {
          hilog.info(0xCAFE, 'LearnAct', 'SAVE_FINGER err=%{public}s', e instanceof Error ? e.message : '');
          this.addTrace('trust_device_fail');
        }
      }

      // 从 JSON 提取 redirectUrl
      const redirectUrl: string = this.extractRedirectUrl(body);
      if (redirectUrl.length > 0) {
        this.addTrace('2fa_following_redirect');
        const redirectResp: HttpResponse = await this.http.get(ID_HOST_URL + redirectUrl);
        const redirectHtml: string = redirectResp.body;
        hilog.info(0xCAFE, 'LearnAct', '2FA_REDIRECT len=%{public}d has_ok=%{public}s', redirectHtml.length, redirectHtml.indexOf('登录成功') >= 0);

        // 从登录成功页提取 callback href，follow 建立 webvpn 会话
        const callbackUrl: string = extractFirstAnchorHref(redirectHtml);
        hilog.info(0xCAFE, 'LearnAct', '2FA_CALLBACK=%{public}s', callbackUrl.substring(0, 120));
        if (callbackUrl.length > 0) {
          this.addTrace('2fa_following_callback');
          const cbResp: HttpResponse = await this.http.get(callbackUrl);
          hilog.info(0xCAFE, 'LearnAct', '2FA_CB_RESP code=%{public}d len=%{public}d', cbResp.statusCode, cbResp.body.length);
        } else {
          this.addTrace('2fa_no_callback');
        }
      }

      // 继续主登录链：先建立 info 门户会话，再激活 learn
      if (this.cachedCredentials !== undefined) {
        await SecureStorage.saveCredentials(
          this.cachedCredentials.studentId,
          this.cachedCredentials.password,
          this.cachedCredentials.fingerprint
        );
        try {
          await this.roamIdPolicy(this.cachedCredentials, INFO_PORTAL_YYFWID);
          this.addTrace('info_roam_ok_2fa');
        } catch (e) {
          this.addTrace('info_roam_fail_2fa:' + (e instanceof Error ? e.message : ''));
        }
        try {
          await this.activateLearnSession(this.cachedCredentials);
          this.addTrace('learn_activated_after_2fa');
        } catch (e) {
          this.addTrace('learn_fail_after_2fa:' + (e instanceof Error ? e.message : ''));
        }
      }

      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.SUCCESS;
      result.message = '认证成功';
      result.trace = this.trace;
      return result;
    } catch (e) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '验证失败: ' + (e instanceof Error ? e.message : '');
      result.trace = this.trace;
      return result;
    }
  }

  private extractRedirectUrl(jsonStr: string): string {
    const pattern: string = 'redirectUrl["\\s]*[:=]["\\s]*["\']?([^"\'\\s}]+)';
    const re: RegExp = new RegExp(pattern, 'i');
    const match = re.exec(jsonStr);
    if (match === null || match.length < 2) {
      return '';
    }
    return match[1];
  }

  async logout(): Promise<void> {
    this.http.clearSession();
    this.csrfToken = '';
    this.trace = [];
    await SecureStorage.clearCredentials();
  }

  getHttpClient(): HttpClient {
    return this.http;
  }
}
