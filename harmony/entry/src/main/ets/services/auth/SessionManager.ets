import { TsinghuaAuthService, LoginResult, LoginResultType } from './TsinghuaAuthService';
import { CampusCredentials } from '../../domain/AuthTypes';
import { PreferencesStorage } from '../../storage/PreferencesStorage';
import { StorageKeys } from '../../storage/StorageKeys';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { CampusDataService } from '../campus/CampusDataService';

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

  static async login(studentId: string, password: string): Promise<LoginResult> {
    const service: TsinghuaAuthService = SessionManager.getAuthService();
    AuthManager.startLogin();

    const credentials: CampusCredentials = new CampusCredentials();
    credentials.studentId = studentId;
    credentials.password = password;

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
