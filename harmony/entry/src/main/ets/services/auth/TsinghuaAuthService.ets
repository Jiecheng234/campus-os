import { CookieJar } from '../CookieJar';
import { HttpClient, HttpResponse } from '../HttpClient';
import { WebvpnTransport } from '../WebvpnTransport';
import { WEBVPN_OAUTH_LOGIN_URL, WEBVPN_BASE_URL } from '../WebvpnConstants';
import {
  encryptPassword, extractSm2PublicKey, extractCsrfToken,
  extractFirstAnchorHref, extractMsgNote, extractFormAction
} from '../../utils/SM2Crypto';
import { generateUUID } from '../../utils/CryptoUtils';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';
import { CampusCredentials } from '../../domain/AuthTypes';

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
  private cookieJar: CookieJar;
  private http: HttpClient;
  private transport: WebvpnTransport;

  constructor() {
    this.cookieJar = new CookieJar();
    this.http = new HttpClient(this.cookieJar);
    this.transport = new WebvpnTransport(this.http, this.cookieJar);
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
    this.cookieJar.clear();

    this.cachedCredentials = credentials;

    let oauthPage: string = '';
    try {
      oauthPage = await this.transport.getOAuthPage();
    } catch (e) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '无法连接校园网: ' + (e instanceof Error ? e.message : '网络不可达');
      result.trace = this.trace;
      return result;
    }
    this.addTrace('oauth_page_fetched');

    if (oauthPage.indexOf('sm2publicKey') < 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '无法获取登录页面，请检查网络连接';
      result.trace = this.trace;
      return result;
    }

    const sm2Key: string = extractSm2PublicKey(oauthPage);
    this.csrfToken = extractCsrfToken(oauthPage);
    const formAction: string = extractFormAction(oauthPage);
    const postUrl: string = formAction.length > 0 ? formAction : WEBVPN_OAUTH_LOGIN_URL;
    this.addTrace('sm2_key_extracted form_action:' + postUrl);

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
      'username': credentials.studentId,
      'password': encryptedPw,
    };
    if (this.csrfToken.length > 0) {
      formData['_csrf'] = this.csrfToken;
    }

    this.addTrace('posting_login to:' + postUrl);
    let loginResp: HttpResponse;
    try {
      loginResp = await this.transport.postLoginForm(formData, postUrl);
    } catch (e) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.ERROR;
      result.message = '登录请求失败: ' + (e instanceof Error ? e.message : '未知错误');
      result.trace = this.trace;
      return result;
    }
    this.addTrace('login_response:' + String(loginResp.statusCode));

    const body: string = loginResp.body;

    if (body.indexOf('two_factor') >= 0 || body.indexOf('tfa') >= 0 ||
      body.indexOf('authCode') >= 0 || body.indexOf('验证码') >= 0) {
      const result: LoginResult = new LoginResult();
      result.type = LoginResultType.TWO_FACTOR;
      result.message = '需要双因子认证';
      result.twoFactorHint = '请选择验证方式';
      result.trace = this.trace;
      return result;
    }

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
      this.addTrace('following_redirect');
      const redirectResp: HttpResponse = await this.http.get(redirectUrl);
      this.addTrace('redirect_done:' + String(redirectResp.statusCode));
    }

    const successResult: LoginResult = new LoginResult();
    successResult.type = LoginResultType.SUCCESS;
    successResult.message = '登录成功';
    successResult.trace = this.trace;

    await SecureStorage.saveCredentials(credentials.studentId, credentials.password);
    await this.transport.roamToAllSubsystems();

    return successResult;
  }

  async send2FACode(method: string): Promise<boolean> {
    this.addTrace('sending_2fa:' + method);
    const formData: Record<string, string> = {
      'authType': method,
    };
    try {
      const resp: HttpResponse = await this.transport.post2FAForm(formData);
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
    const resp: HttpResponse = await this.transport.post2FAForm(formData);
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

    await this.transport.roamToAllSubsystems();

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
    this.cookieJar.clear();
    this.csrfToken = '';
    this.trace = [];
    await SecureStorage.clearCredentials();
  }

  getCookieString(url: string): string {
    return this.cookieJar.getCookieString(url);
  }
}
