/**
 * ============================================================================
 * SessionManager — 认证/会话协调层（UI 与 TsinghuaAuthService 之间的门面）
 * ============================================================================
 *
 * 职责：
 *   - 持有 TsinghuaAuthService / CampusDataService 单例（懒加载）。
 *   - login()：组装凭证（复用 SecureStorage 持久化的 fingerprint，避免设备信任超限），
 *     驱动 TsinghuaAuthService.login，并同步 AuthManager 状态 + 写 SESSION_SAVED_KEY。
 *   - tryAutoLogin()：自动登录——读保存的凭证并执行完整 login() 静默重建 WebVPN 会话
 *     （fingerprint 持久化使 2FA 可跳过）。由 Index.aboutToAppear 在冷启动时调用。
 *   - demoLogin()：演示模式（无需账号，用本地 Mock 数据）。
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
import { CampusDataService } from '../campus/CampusDataService';
import { generateUUID } from '../../utils/CryptoUtils';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';

const SESSION_SAVED_KEY: string = 'auth_session_saved';

export class SessionManager {
  private static authService: TsinghuaAuthService | undefined = undefined;
  private static campusDataService: CampusDataService | undefined = undefined;

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

  static async login(studentId: string, password: string): Promise<LoginResult> {
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    AuthManager.startLogin();

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

    const result: LoginResult = await service.login(credentials);

    if (result.type === LoginResultType.SUCCESS) {
      AuthManager.loginSuccess();
      StateManager.settings.demoMode = false;
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
      AuthManager.loginSuccess();
      StateManager.settings.demoMode = false;
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

  static async logout(): Promise<void> {
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    await service.logout();
    AuthManager.logout();
    await PreferencesStorage.setBoolean(SESSION_SAVED_KEY, false);
  }

  static demoLogin(): void {
    AuthManager.startLogin();
    AuthManager.loginSuccess();
    StateManager.settings.demoMode = true;
  }
}
