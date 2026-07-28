import { HttpClient, HttpResponse } from '../HttpClient';
import { CookieManager } from '../CookieManager';
import { WEBVPN_OAUTH_LOGIN_URL, WEBVPN_BASE_URL, wrapWebVPNUrl, ID_HOST_URL, ID_LOGIN_URL, getSubsystemUrl, SUBSYSTEM_LEARN } from '../WebvpnConstants';
import {
  encryptPassword, extractSm2PublicKey, extractCsrfToken,
  extractFirstAnchorHref, extractMsgNote, extractMetaRedirect
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
      await this.http.get(WEBVPN_OAUTH_LOGIN_URL);

      this.addTrace('fetch_form');
      const formResp: HttpResponse = await this.http.get(WEBVPN_OAUTH_LOGIN_URL);
      oauthPage = formResp.body;
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

    const TWO_FACTOR_MARK: string = '/b/doubleAuth/login';
    if (idResponse.indexOf(TWO_FACTOR_MARK) >= 0) {
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
      await this.http.get(redirectUrl);
    }

    const successResult: LoginResult = new LoginResult();
    successResult.type = LoginResultType.SUCCESS;
    successResult.message = '登录成功';
    successResult.trace = this.trace;

    await SecureStorage.saveCredentials(credentials.studentId, credentials.password);
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

  private async activateLearnSession(credentials: CampusCredentials): Promise<void> {
    const formUrl: string = ID_BASE_URL + LEARN_LOGIN_YYFWID;
    const formHtml: string = await this.http.get(formUrl).then((r: HttpResponse) => r.body);

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
      'fingerPrint': '',
      'fingerGenPrint': '',
      'fingerGenPrint3': '',
      'i_captcha': '',
    };

    let response: string = '';
    for (let i: number = 0; i < 2; i++) {
      response = await this.http.postForm(ID_LOGIN_URL, fd).then((r: HttpResponse) => r.body);
      if (response.indexOf('/b/doubleAuth/login') >= 0) {
        throw new Error('learn 2FA required');
      }
      const cb: string = extractFirstAnchorHref(response);
      if (cb.length > 0) { break; }
    }

    let callbackUrl: string = extractFirstAnchorHref(response);
    if (callbackUrl.length === 0) {
      callbackUrl = extractMetaRedirect(response);
    }
    if (callbackUrl.length === 0) {
      throw new Error('no_cb;len=' + response.length + ';pre=' + response.substring(0, 80));
    }

    const parts: string[] = callbackUrl.split('=');
    const ticket: string = parts[parts.length - 1];
    if (ticket.length === 0) {
      throw new Error('no ticket');
    }

    await this.http.get(LEARN_BASE + '/b/j_spring_security_thauth_roaming_entry?ticket=' + ticket);
    const homeHtml: string = await this.http.get(LEARN_BASE + '/f/wlxt/index/course/student/').then((r: HttpResponse) => r.body);

    let csrfFound: string = '';
    const p: RegExp = new RegExp('_csrf"\\s+value\\s*=\\s*"([^"]+)"', 'i');
    const m = p.exec(homeHtml);
    if (m !== null && m.length >= 2) { csrfFound = m[1]; }

    if (csrfFound.length > 0) {
      this.csrfToken = csrfFound;
    }
  }

  async send2FACode(method: string): Promise<boolean> {
    this.addTrace('sending_2fa:' + method);
    const formData: Record<string, string> = {
      'authType': method,
    };
    try {
      const resp: HttpResponse = await this.http.postForm(WEBVPN_OAUTH_LOGIN_URL, formData);
      this.addTrace('2fa_sent:' + String(resp.statusCode));
      return true;
    } catch (e) {
      this.addTrace('2fa_send_failed');
      return false;
    }
  }

  async verify2FACode(code: string): Promise<LoginResult> {
    this.addTrace('verifying_2fa');
    const formData: Record<string, string> = {
      'authCode': code,
    };
    const resp: HttpResponse = await this.http.postForm(WEBVPN_OAUTH_LOGIN_URL, formData);
    const body: string = resp.body;

    const errorMsg: string = extractMsgNote(body);
    if (errorMsg.length > 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = errorMsg;
      result.trace = this.trace;
      return result;
    }

    const redirectUrl: string = extractFirstAnchorHref(body);
    if (redirectUrl.length > 0) {
      this.addTrace('2fa_following_redirect');
      await this.http.get(redirectUrl);
    }

      await this.http.get(getSubsystemUrl(SUBSYSTEM_LEARN));

    if (this.cachedCredentials !== undefined) {
      await SecureStorage.saveCredentials(
        this.cachedCredentials.studentId,
        this.cachedCredentials.password
      );
    }

    const result: LoginResult = new LoginResult();
    result.type = LoginResultType.SUCCESS;
    result.message = '认证成功';
    result.trace = this.trace;
    return result;
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
