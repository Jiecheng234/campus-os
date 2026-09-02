import { HttpClient, HttpResponse } from '../HttpClient';
import { Log } from '../../utils/Logger';
import { CookieManager } from '../CookieManager';
import { WEBVPN_OAUTH_LOGIN_URL, WEBVPN_BASE_URL, wrapWebVPNUrl, ID_HOST_URL, ID_LOGIN_URL, DOUBLE_AUTH_URL, SAVE_FINGER_URL, INFO_PORTAL_YYFWID, getSubsystemUrl, SUBSYSTEM_LEARN } from '../WebvpnConstants';
import {
  encryptPassword, extractSm2PublicKey, extractCsrfToken,
  extractFirstAnchorHref, extractMsgNote, extractMetaRedirect, extractFormAction
} from '../../utils/SM2Crypto';
import { generateUUID } from '../../utils/CryptoUtils';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';
import { CampusCredentials } from '../../domain/AuthTypes';

/**
 * ============================================================================
 * TsinghuaAuthService — 清华大学统一身份认证服务（项目最核心、最易出错的部分）
 * ============================================================================
 *
 * 【认证链路总览】（login()，顺序不可调整，每步依赖前一步写入的 Cookie）：
 *   1. clearSession()                    清旧 Cookie，避免污染
 *   2. GET WEBVPN_OAUTH_LOGIN_URL ×2     预热 WebVPN→OAuth→ID 链至登录表单
 *   3. 提取 sm2publicKey                 #sm2publicKey 元素文本
 *   4. SM2 加密密码                      输出需 DER→裸格式（见 SM2Crypto.derToRawSM2）
 *   5. POST ID_LOGIN_URL                 i_user/i_pass/fingerPrint/.../i_captcha
 *        - 含 TWO_FACTOR_MARK           → 返回 TWO_FACTOR，UI 走 verify2FACode 续链
 *        - 含 LOGIN_SUCCESS_MARK        → 成功（设备被信任时跳过 2FA）
 *   6. follow callback href（仅用一次）   建立 WebVPN 会话（重复消费会清会话）
 *   7. roamIdPolicy(INFO_PORTAL_YYFWID)  建立 info 门户会话（校园通用门户漫游）
 *   8. activateLearnSession              learn 域激活（ticket → learnAuthRoam → _csrf）
 *
 * 【判定标记】（极易错，务必用对）：
 *   - LOGIN_SUCCESS_MARK = '登录成功。正在重定向到'（带后缀，不是裸「登录成功」）
 *   - TWO_FACTOR_MARK    = '二次认证'（中文文本，不是 URL 路径 /b/doubleAuth/login）
 *
 * 【关键约束】：
 *   - POST 必须带 Content-Type: application/x-www-form-urlencoded（HttpClient 已处理）
 *   - fingerprint 复用 SecureStorage 持久化值（32 位无横线 UUID），避免设备信任超限
 *   - learn csrf（本服务 csrfToken）≠ WebVPN csrf（教务等漫游用 XSRF-TOKEN）
 *
 * 参考：原项目 src/services/auth/tsinghuaAuth.ts、docs/login-to-thu.md
 * ============================================================================
 */
const LEARN_BASE: string = 'https://learn.tsinghua.edu.cn';
const ID_BASE_URL: string = 'https://id.tsinghua.edu.cn/do/off/ui/auth/login/form/';
const LEARN_LOGIN_YYFWID: string = 'bb5df85216504820be7bba2b0ae1535b/0';
const LEARN_AUTH_ROAM: string = LEARN_BASE + '/b/j_spring_security_thauth_roaming_entry';
const LEARN_STUDENT_HOME: string = LEARN_BASE + '/f/wlxt/index/course/student/';
// 与原项目一致的权威判定标记
const LOGIN_SUCCESS_MARK: string = '登录成功。正在重定向到';
const TWO_FACTOR_MARK: string = '二次认证';

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
  private twoFactorMethod: string = 'mobile';
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

  /**
   * 从 SecureStorage 恢复凭证到内存（hydrate）。
   * 【关键】fingerprint 复用已持久化值（服务器已信任的设备指纹）；
   * 若无则生成 32 位无横线 UUID（与 SessionManager.login 格式一致）。
   * 注意：仅恢复凭证，不执行 login()；建立会话需调 login()（见 SessionManager.tryAutoLogin）。
   */
  async hydrateCredentials(): Promise<boolean> {
    const creds: SecureCredentials | undefined = await SecureStorage.getCredentials();
    if (creds !== undefined) {
      const campusCreds: CampusCredentials = new CampusCredentials();
      campusCreds.studentId = creds.studentId;
      campusCreds.password = creds.password;
      // 复用已持久化的 fingerprint（与服务器信任的设备保持一致）；
      // 若无则生成 32 位无横线格式，与 SessionManager.login 保持一致
      if (creds.fingerprint.length > 0) {
        campusCreds.fingerprint = creds.fingerprint;
      } else {
        campusCreds.fingerprint = generateUUID().replace(/-/g, '');
      }
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
      Log.i('LearnAct',  'WARMUP code=%{public}d len=%{public}d', w1.statusCode, w1.body.length);

      this.addTrace('fetch_form');
      const formResp: HttpResponse = await this.http.get(WEBVPN_OAUTH_LOGIN_URL);
      oauthPage = formResp.body;
      Log.i('LearnAct',  'FORM code=%{public}d len=%{public}d has_sm2=%{public}s',
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
    Log.i('LearnAct',  'FORM_ACTION=%{public}s', formAction);
    const loginFormIdx: number = oauthPage.indexOf('sm2publicKey');
    if (loginFormIdx >= 0) {
      Log.i('LearnAct',  'SM2EL=%{public}s', oauthPage.substring(loginFormIdx - 20, loginFormIdx + 150));
    }
    const ajaxIdx: number = oauthPage.indexOf('ajax');
    if (ajaxIdx >= 0) {
      const ajaxStr: string = oauthPage.substring(ajaxIdx, ajaxIdx + 900);
      Log.i('LearnAct',  'AJAX1=%{public}s', ajaxStr.substring(0, 300));
      Log.i('LearnAct',  'AJAX2=%{public}s', ajaxStr.substring(300, 600));
      Log.i('LearnAct',  'AJAX3=%{public}s', ajaxStr.substring(600, 900));
    }
    const csrfIdx: number = oauthPage.indexOf('_csrf');
    if (csrfIdx >= 0) {
      Log.i('LearnAct',  'CSRF=%{public}s', oauthPage.substring(csrfIdx - 20, csrfIdx + 60));
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
    Log.i('LearnAct',  'SM2 prefix=%{public}s len=%{public}d', encryptedPw.substring(0, 8), encryptedPw.length);

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
    Log.i('LearnAct',  'MAIN_POST len=%{public}d has_ok=%{public}s has_err=%{public}s',
      idResponse.length, idResponse.indexOf('登录成功') >= 0, idResponse.indexOf('出错了') >= 0);
    const mainCb: string = extractFirstAnchorHref(idResponse);
    Log.i('LearnAct',  'MAIN_POST cb=%{public}s', mainCb.substring(0, 80));

    if (idResponse.indexOf(TWO_FACTOR_MARK) >= 0 || idResponse.indexOf('/b/doubleAuth/login') >= 0) {
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
      Log.i('LearnAct',  'MAIN_CB code=%{public}d len=%{public}d', cbResp.statusCode, cbResp.body.length);
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

  /**
   * 门户漫游（roamIdPolicy）：为目标 yyfwid 重新走一遍 ID 登录，建立该子系统会话。
   * 用于 info 门户（INFO_PORTAL_YYFWID，校园通用门户）等。
   * 步骤：取表单+SM2 → POST ID_LOGIN_URL → 提取 callback → wrapWebVPNUrl → follow lbredirect。
   * 注意：原项目 roam 时若遇 2FA 会用 performTwoFactor 内联处理；本实现暂未触发。
   */
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
    Log.i('LearnAct', 'ROAM_LB code=%{public}d len=%{public}d has_sm2=%{public}s',
      lbResp.statusCode, lbResp.body.length, lbResp.body.indexOf('sm2publicKey') >= 0);
    Log.i('LearnAct', 'ROAM_LB_FULL=%{public}s', lbResp.body);
  }

  /**
   * learn 域激活（建立 learn.tsinghua.edu.cn 会话并取 _csrf）。
   *
   * 步骤（对齐原项目 activateLearn）：
   *   1. GET  ID_BASE_URL + LEARN_LOGIN_YYFWID  取 learn 登录表单 + SM2 公钥
   *   2. POST ID_LOGIN_URL                      learn yyfwid 的 ID 登录
   *      - 含 TWO_FACTOR_MARK → throw（learn 激活遇 2FA 时原项目也 throw）
   *      - 含 LOGIN_SUCCESS_MARK → 继续
   *   3. 提取 callback href 末段 ticket（= 号后部分）
   *   4. GET learnAuthRoam?ticket=…             【关键】建立 learn 域会话（漏了这步会拿不到 _csrf）
   *   5. GET learnStudentHome（学生首页）
   *   6. 提取 _csrf（正则 &_csrf=(\S+?)["'&]）   后续所有 learn API 的 CSRF token
   *
   * 注意：learn 激活返回的「登录成功页」内嵌 doubleauth JS，易被误判为 2FA 页，
   *       必须用 TWO_FACTOR_MARK（'二次认证'）而非 URL 路径判定。
   */
  private async activateLearnSession(credentials: CampusCredentials): Promise<void> {
    let response: string = '';
    Log.i('LearnAct',  'LEARN_FP=%{public}s len=%{public}d', credentials.fingerprint.substring(0, 8), credentials.fingerprint.length);
    for (let i: number = 0; i < 2; i++) {
      const formUrl: string = ID_BASE_URL + LEARN_LOGIN_YYFWID;
      const formHtml: string = await this.http.get(formUrl).then((r: HttpResponse) => r.body);
      Log.i('LearnAct',  'form_len=%{public}d has_sm2=%{public}s', formHtml.length, formHtml.indexOf('sm2publicKey') >= 0);

      const pk: string = extractSm2PublicKey(formHtml);
      if (pk.length === 0) {
        throw new Error('learn: missing sm2publicKey;len=' + formHtml.length);
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

      const respObj: HttpResponse = await this.http.postForm(ID_LOGIN_URL, fd);
      response = respObj.body;
      const has2fa: boolean = response.indexOf(TWO_FACTOR_MARK) >= 0;
      const hasSuccess: boolean = response.indexOf(LOGIN_SUCCESS_MARK) >= 0;
      Log.i('LearnAct',  'LEARN_POST len=%{public}d has_2fa=%{public}s has_success=%{public}s',
        response.length, has2fa, hasSuccess);
      // 完整 body（951 字节级别，用于判定页面真实类型）
      if (response.length < 2000) {
        Log.i('LearnAct',  'LEARN_BODY=%{public}s', response);
      }
      if (has2fa) {
        throw new Error('learn: 2FA reappeared');
      }
      if (hasSuccess) {
        break;
      }
    }

    if (response.indexOf(LOGIN_SUCCESS_MARK) < 0) {
      throw new Error('learn: id login failed;len=' + response.length);
    }

    // 提取 callback → ticket
    const callbackUrl: string = extractFirstAnchorHref(response);
    if (callbackUrl.length === 0) {
      throw new Error('learn: no callback href');
    }
    const cbParts: string[] = callbackUrl.split('=');
    const ticket: string = cbParts[cbParts.length - 1];
    if (ticket.length === 0) {
      throw new Error('learn: no ticket in callback');
    }
    Log.i('LearnAct',  'LEARN_TICKET len=%{public}d', ticket.length);

    // learnAuthRoam：直接请求 learn.tsinghua.edu.cn 建立 learn 域会话
    const roamResp: HttpResponse = await this.http.get(LEARN_AUTH_ROAM + '?ticket=' + ticket);
    Log.i('LearnAct',  'LEARN_ROAM code=%{public}d len=%{public}d', roamResp.statusCode, roamResp.body.length);
    if (roamResp.statusCode !== 200) {
      throw new Error('learn: roam HTTP ' + roamResp.statusCode);
    }

    // 学生首页提取 _csrf
    const homeHtml: string = await this.http.get(LEARN_STUDENT_HOME).then((r: HttpResponse) => r.body);
    Log.i('LearnAct',  'LEARN_HOME len=%{public}d', homeHtml.length);
    const csrfPattern: RegExp = new RegExp('&_csrf=(\\S+?)["\'&]', 'g');
    let csrfFound: string = '';
    const m = csrfPattern.exec(homeHtml);
    if (m !== null && m.length >= 2) {
      csrfFound = m[1];
    }
    if (csrfFound.length > 0) {
      this.csrfToken = csrfFound;
      Log.i('LearnAct',  'LEARN_CSRF ok len=%{public}d', csrfFound.length);
      return;
    }
    throw new Error('learn: no _csrf in student home;len=' + homeHtml.length);
  }

  async send2FACode(method: string): Promise<boolean> {
    this.addTrace('sending_2fa:' + method);
    this.twoFactorMethod = method;
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

  /**
   * 二次认证验证码校验（主登录触发 2FA 后由 UI 调用，续主链）。
   * 步骤：POST DOUBLE_AUTH_URL(VERITY_CODE) → saveFinger（信任设备，须在 redirectUrl 之前）
   *       → follow redirectUrl → follow callback → roamIdPolicy(info) → activateLearnSession。
   * twoFactorMethod 由 send2FACode 保存（mobile/wechat/totp），此处复用，避免方式不匹配。
   */
  async verify2FACode(code: string): Promise<LoginResult> {
    this.addTrace('verifying_2fa');
    const formData: Record<string, string> = {
      'action': 'VERITY_CODE',
      'type': this.twoFactorMethod,
      'vericode': code,
    };
    try {
      const resp: HttpResponse = await this.http.postForm(DOUBLE_AUTH_URL, formData);
      const body: string = resp.body;
      this.addTrace('2fa_resp:' + body.length);
      Log.i('LearnAct',  '2FA_VERIFY len=%{public}d body=%{public}s', body.length, body.substring(0, 200));

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
          Log.i('LearnAct',  'SAVE_FINGER resp=%{public}s', sfResp.body.substring(0, 100));
          this.addTrace('trust_device_ok');
        } catch (e) {
          Log.i('LearnAct',  'SAVE_FINGER err=%{public}s', e instanceof Error ? e.message : '');
          this.addTrace('trust_device_fail');
        }
      }

      // 从 JSON 提取 redirectUrl
      const redirectUrl: string = this.extractRedirectUrl(body);
      if (redirectUrl.length > 0) {
        this.addTrace('2fa_following_redirect');
        const redirectResp: HttpResponse = await this.http.get(ID_HOST_URL + redirectUrl);
        const redirectHtml: string = redirectResp.body;
        Log.i('LearnAct',  '2FA_REDIRECT len=%{public}d has_ok=%{public}s', redirectHtml.length, redirectHtml.indexOf('登录成功') >= 0);

        // 从登录成功页提取 callback href，follow 建立 webvpn 会话
        const callbackUrl: string = extractFirstAnchorHref(redirectHtml);
        Log.i('LearnAct',  '2FA_CALLBACK=%{public}s', callbackUrl.substring(0, 120));
        if (callbackUrl.length > 0) {
          this.addTrace('2fa_following_callback');
          const cbResp: HttpResponse = await this.http.get(callbackUrl);
          Log.i('LearnAct',  '2FA_CB_RESP code=%{public}d len=%{public}d', cbResp.statusCode, cbResp.body.length);
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
