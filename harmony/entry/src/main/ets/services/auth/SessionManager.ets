/**
 * ============================================================================
 * SessionManager — 认证/会话协调层（UI 与 TsinghuaAuthService 之间的门面）
 * ============================================================================
 *
 * 职责：
 *   - 持有 TsinghuaAuthService / CampusDataService 单例（懒加载）。
 *   - login()：组装凭证（复用 SecureStorage 持久化的 fingerprint，避免设备信任超限），
 *     驱动 TsinghuaAuthService.login，并同步 AuthManager 状态 + 写 SESSION_SAVED_KEY。
 *     可选 trustDevice 参数决定凭证是否持久化（信任→写 ASSET；不信任→仅内存会话；
 *     缺省沿用设置值——既有调用零改动）。
 *   - tryAutoLogin()：自动登录——读保存的凭证并执行完整 login() 静默重建 WebVPN 会话
 *     （fingerprint 持久化使 2FA 可跳过）。由 Index.aboutToAppear 在冷启动时调用。
 *   - demoLogin()：演示模式（无需账号，用本地 Mock 数据）。
 *   - logout()：退出登录——仅清会话态（复位登录态 + 自动登录标记；不清 Cookie、
 *     不重置运行期会话复用状态）；凭证按信任策略处理（信任→保留；未信任→清除）。
 *
 * 注意：
 *   - fingerprint 格式为 32 位无横线 UUID（generateUUID().replace(/-/g,'')）。
 *   - SESSION_SAVED_KEY 标记"用户曾成功登录"，是自动登录的前置条件。
 * ============================================================================
 */
import { TsinghuaAuthService, LoginResult, LoginResultType } from './TsinghuaAuthService';
import { CampusCredentials } from '../../domain/AuthTypes';
import { PreferencesStorage } from '../../storage/PreferencesStorage';
import { StorageKeys } from '../../storage/StorageKeys';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { SettingsManager } from '../../state/SettingsManager';
import { CampusDataService } from '../campus/CampusDataService';
import { CampusCardService } from '../campus/CampusCardService';
import { CampusNetworkService } from '../campus/CampusNetworkService';
import { LibrarySeatService } from '../campus/LibrarySeatService';
import { LibraryRoomService } from '../campus/LibraryRoomService';
import { LaundryService } from '../campus/LaundryService';
import { MailService } from '../campus/MailService';
import { SportsService } from '../campus/SportsService';
import { CourseRegService } from '../campus/CourseRegService';
import { generateUUID } from '../../utils/CryptoUtils';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';

const SESSION_SAVED_KEY: string = 'auth_session_saved';

export class SessionManager {
  private static authService: TsinghuaAuthService | undefined = undefined;
  private static campusDataService: CampusDataService | undefined = undefined;
  private static campusCardService: CampusCardService | undefined = undefined;
  private static networkService: CampusNetworkService | undefined = undefined;
  private static librarySeatService: LibrarySeatService | undefined = undefined;
  private static libraryRoomService: LibraryRoomService | undefined = undefined;
  private static laundryService: LaundryService | undefined = undefined;
  private static mailService: MailService | undefined = undefined;
  private static sportsService: SportsService | undefined = undefined;
  private static courseRegService: CourseRegService | undefined = undefined;

  static getAuthService(): TsinghuaAuthService {
    if (SessionManager.authService === undefined) {
      SessionManager.authService = new TsinghuaAuthService();
    }
    return SessionManager.authService;
  }

  static getCampusDataService(): CampusDataService {
    if (SessionManager.campusDataService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      const http = auth.getHttpClient();
      SessionManager.campusDataService = new CampusDataService(http);
    }
    return SessionManager.campusDataService;
  }

  static getCampusCardService(): CampusCardService {
    if (SessionManager.campusCardService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.campusCardService = new CampusCardService(auth.getHttpClient(), auth);
    }
    return SessionManager.campusCardService;
  }

  /** 选课系统服务（学期/已选课程/课余量搜索/选课/退课，T03） */
  static getCourseRegService(): CourseRegService {
    if (SessionManager.courseRegService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.courseRegService = new CourseRegService(auth.getHttpClient(), auth);
    }
    return SessionManager.courseRegService;
  }

  static getNetworkService(): CampusNetworkService {
    if (SessionManager.networkService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.networkService = new CampusNetworkService(auth.getHttpClient(), auth);
    }
    return SessionManager.networkService;
  }

  static getLibrarySeatService(): LibrarySeatService {
    if (SessionManager.librarySeatService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.librarySeatService = new LibrarySeatService(auth.getHttpClient(), auth);
    }
    return SessionManager.librarySeatService;
  }

  static getLibraryRoomService(): LibraryRoomService {
    if (SessionManager.libraryRoomService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.libraryRoomService = new LibraryRoomService(auth.getHttpClient(), auth);
    }
    return SessionManager.libraryRoomService;
  }

  /**
   * 宿舍洗衣机只读服务（第三方公开接口，无鉴权、不依赖登录态）：
   * 仅以认证服务的 HttpClient 构造，不注入 auth（FR-009）。
   */
  static getLaundryService(): LaundryService {
    if (SessionManager.laundryService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.laundryService = new LaundryService(auth.getHttpClient());
    }
    return SessionManager.laundryService;
  }

  static getMailService(): MailService {
    if (SessionManager.mailService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.mailService = new MailService(
        auth.getHttpClient(), SessionManager.getCampusDataService(), auth);
    }
    return SessionManager.mailService;
  }

  static getSportsService(): SportsService {
    if (SessionManager.sportsService === undefined) {
      const auth: TsinghuaAuthService = SessionManager.getAuthService();
      SessionManager.sportsService = new SportsService(auth.getHttpClient(), auth);
    }
    return SessionManager.sportsService;
  }

  static async tryRestoreCachedLogin(): Promise<boolean> {
    if (StateManager.settings.demoMode) {
      return false;
    }
    const autoLogin: boolean = await PreferencesStorage.getBoolean(SESSION_SAVED_KEY, false);
    if (!autoLogin) {
      return false;
    }
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    const hasCreds: boolean = await service.hydrateCredentials();
    return hasCreds;
  }

  /**
   * 自动登录：读取已保存的凭证并执行完整 login() 建立 WebVPN 会话。
   * fingerprint 已随凭证持久化，设备被信任时会跳过 2FA，实现静默登录。
   * 返回 LoginResult；无凭证/未开启自动登录/演示模式时返回 undefined。
   */
  static async tryAutoLogin(): Promise<LoginResult | undefined> {
    if (StateManager.settings.demoMode) {
      return undefined;
    }
    const autoLogin: boolean = await PreferencesStorage.getBoolean(SESSION_SAVED_KEY, false);
    if (!autoLogin) {
      return undefined;
    }
    const creds: SecureCredentials | undefined = await SecureStorage.getCredentials();
    if (creds === undefined || creds.studentId.length === 0) {
      return undefined;
    }
    const result: LoginResult = await SessionManager.login(creds.studentId, creds.password);
    return result;
  }

  /**
   * 统一会话复位入口：逐一扇出各校园子服务的瞬态会话态复位
   * （各服务"已确保"标志与瞬态缓存：教务/成绩/电费/课表学期、体育会话、
   * 图书馆座位会话+访问令牌/时段、研读间 cab 登录/账号号、Coremail 会话、
   * 校园卡账号/卡号缓存）。
   *
   * 触发点（缺一不可，时序不变）：
   *   - logout()：退出登录即复位——进程内重登不残留上一会话的标志/缓存；
   *   - login()/verify2FACode() 成功后、AuthManager.loginSuccess() 广播门控前：
   *     页面随门控重新挂载后的首次自动加载依赖全新会话态。
   *
   * 【复位方法契约】各子服务暴露一致签名的 `resetSessionState(): void`：
   *   无参、同步、幂等、不抛；仅清本服务进程内瞬态态；
   *   不触及 Cookie/凭证/网络/持久化。
   *
   * 【扇出清单】campusDataService（既有）→ sportsService → librarySeatService
   *   → libraryRoomService → mailService → campusCardService → courseRegService。
   *
   * 【惰性】仅对已实例化服务调用（`!== undefined` 判据），不为复位触发懒加载；
   * 未实例化服务的瞬态态本为初值，无需复位。
   *
   * 【异常隔离】每个服务复位调用独立 try/catch：单服务复位异常不中断
   * 其余复位与登录/退出流程。
   *
   * 【登记指引】新增服务接入复位：实现同签名 `resetSessionState()` 并在
   * 本方法内按上述范式登记一行（判据 + try/catch）。
   *
   * 【边界】只清瞬态会话态：不清 Cookie、不动凭证（信任策略由调用方处理），
   * 不复位认证服务 learn csrf（保持既有学习会话语义），
   * 不改变"退出不清 Cookie"的既有会话复用语义（FR-012）。
   */
  private static resetSessionState(): void {
    // 注意：**不在此复位认证服务的 learn csrf**。
    //   - login() 首步已自行复位 csrfToken 并重新激活 learn 会话；
    //   - 本方法会在“登录成功后（门控广播前）”被调用，若此处再复位，
    //     会把刚激活得到的 csrf 清空 → 学习页 `UI_FETCH_COURSES trace=no_csrf`（实测）。
    // 这里逐一复位各校园子系统的瞬态会话态（“已确保”标志与瞬态缓存：
    // 教务/成绩/电费/体育/图书馆座位/研读间/邮件/校园卡），消除跨会话残留。
    if (SessionManager.campusDataService !== undefined) {
      SessionManager.campusDataService.resetSessionState();
    }
    if (SessionManager.sportsService !== undefined) {
      try {
        SessionManager.sportsService.resetSessionState();
      } catch (e) {
        // 异常隔离：单服务复位异常不中断其余复位与登录/退出流程
      }
    }
    if (SessionManager.librarySeatService !== undefined) {
      try {
        SessionManager.librarySeatService.resetSessionState();
      } catch (e) {
        // 异常隔离：同上
      }
    }
    if (SessionManager.libraryRoomService !== undefined) {
      try {
        SessionManager.libraryRoomService.resetSessionState();
      } catch (e) {
        // 异常隔离：同上
      }
    }
    if (SessionManager.mailService !== undefined) {
      try {
        SessionManager.mailService.resetSessionState();
      } catch (e) {
        // 异常隔离：同上
      }
    }
    if (SessionManager.campusCardService !== undefined) {
      try {
        SessionManager.campusCardService.resetSessionState();
      } catch (e) {
        // 异常隔离：同上
      }
    }
    if (SessionManager.courseRegService !== undefined) {
      try {
        SessionManager.courseRegService.resetSessionState();
      } catch (e) {
        // 异常隔离：同上（选课会话"已激活"标志，RD-10）
      }
    }
  }

  /**
   * 登录（组装凭证 → 驱动 TsinghuaAuthService.login → 同步 AuthManager 状态）。
   *
   * @param trustDevice 可选：是否信任此设备（决定凭证是否持久化）。
   *        - true  → 登录成功后凭证写 ASSET（支持下次自动登录）；
   *        - false → 不写（仅内存会话，退出/强杀自然失效）；
   *        - 缺省 → 沿用设置值（SettingsManager.isTrustDevice，既有调用零改动）。
   */
  static async login(studentId: string, password: string, trustDevice?: boolean): Promise<LoginResult> {
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    AuthManager.startLogin();

    const trust: boolean = trustDevice !== undefined ? trustDevice : SettingsManager.isTrustDevice();

    const credentials: CampusCredentials = new CampusCredentials();
    credentials.studentId = studentId;
    credentials.password = password;

    // 复用已持久化的 fingerprint（首次登录生成，后续复用，避免信任设备数量超限）
    const saved: SecureCredentials | undefined = await SecureStorage.getCredentials();
    if (saved !== undefined && saved.fingerprint.length > 0) {
      credentials.fingerprint = saved.fingerprint;
    } else {
      credentials.fingerprint = generateUUID().replace(/-/g, '');
    }

    const result: LoginResult = await service.login(credentials, trust);

    if (result.type === LoginResultType.SUCCESS) {
      // 会话复位须在门控广播（loginSuccess）前完成：页面重新挂载后的首次
      // 自动加载（HomePage/LearningPage aboutToAppear）依赖全新的 csrf 与子系统标志
      SessionManager.resetSessionState();
      AuthManager.loginSuccess();
      StateManager.settings.demoMode = false;
      // 持久化 demoMode=false：否则冷启动 ensureLoaded 会读回旧的演示模式，
      // tryAutoLogin 因 demoMode 早退 → 表现为"重启后无法自动登录"
      await StateManager.saveSettings();
      await PreferencesStorage.setBoolean(SESSION_SAVED_KEY, true);
    } else if (result.type === LoginResultType.TWO_FACTOR) {
      AuthManager.require2FA([]);
    } else {
      AuthManager.loginFailed(result.message);
    }

    return result;
  }

  static async verify2FACode(code: string): Promise<LoginResult> {
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    const result: LoginResult = await service.verify2FACode(code);

    if (result.type === LoginResultType.SUCCESS) {
      // 同 login()：门控广播前复位会话瞬态态，保证页面重挂载后首次加载可用
      SessionManager.resetSessionState();
      AuthManager.loginSuccess();
      StateManager.settings.demoMode = false;
      // 同上：2FA 通过后同样持久化，保证重启可自动登录
      await StateManager.saveSettings();
      await PreferencesStorage.setBoolean(SESSION_SAVED_KEY, true);
    } else {
      AuthManager.loginFailed(result.message);
    }

    return result;
  }

  static async send2FACode(method: string): Promise<boolean> {
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    return service.send2FACode(method);
  }

  /**
   * 退出登录（2026-10-13 修订，FR-012）：仅清"会话/登录态"，凭证按信任策略处理。
   *
   * - 先统一复位会话瞬态态（learn csrf/trace + 各子系统"已确保"标志/缓存——
   *   进程内"退出→再登录"不得复用陈旧态），再复位登录态（AuthManager → 门控
   *   信号广播，整应用回登录页）与自动登录标记；不清 Cookie、不重置运行期
   *   会话复用相关状态（不打断进行中的请求与漫游）。
   *   故不再透传 service.logout()——其内部会 clearSession（清 Cookie）并无条件
   *   清除凭证，与修订语义冲突（服务层保持不动，重新登录时 login 首步自会清旧会话）。
   * - 凭证策略：信任开启 → 保留 ASSET 凭证（登录页回填 + 一键直达主页/自动登录可用）；
   *   未信任 → 清除凭证并复位"待清除"标记（不得留残留，含历史遗留）。
   */
  static async logout(): Promise<void> {
    // 退出即复位会话瞬态态：learn csrf 缓存、教务/成绩/电费"已确保"标志等
    // 均指向旧会话，进程内重登前必须复位，否则重登后首次数据拉取静默失败
    SessionManager.resetSessionState();
    AuthManager.logout();
    await PreferencesStorage.setBoolean(SESSION_SAVED_KEY, false);
    if (!SettingsManager.isTrustDevice()) {
      await SecureStorage.clearCredentials();
      await SettingsManager.setPendingClear(false);
    }
  }

  static demoLogin(): void {
    AuthManager.startLogin();
    AuthManager.loginSuccess();
    StateManager.settings.demoMode = true;
  }
}
