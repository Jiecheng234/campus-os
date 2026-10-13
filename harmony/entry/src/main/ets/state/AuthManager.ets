/**
 * ============================================================================
 * AuthManager — 登录态管理（AuthStatus 状态机 + 整应用门控信号）
 * ============================================================================
 *
 * 【门控信号】AUTH_GATE_TICK_KEY（AppStorage 时间戳）：每次登录态变化
 * （登录成功/失败/需 2FA/复位/退出）广播一次；Index 以
 * @StorageLink + @Watch 订阅并按 AuthManager.isLoggedIn() 重算门控——
 * 退出登录/会话失效时整应用立即切换（Tabs ↔ 登录页）。
 * "需 2FA"（AuthStatus.TWO_FACTOR）同样是登录态：门控渲染登录页，
 * LoginPage 检测 needs2FA() 后直接进入 2FA 视图（自动登录遇 2FA 的进入路径）。
 *
 * 【信号边界】信号只承载"变化时刻"，不承载状态本身——状态唯一事实源
 * 仍是 StateManager.authState。信号不驱动任何会话/凭证操作。
 * ============================================================================
 */
import { AuthStatus, AuthState, TwoFactorApproach } from '../domain/AuthTypes';
import { StateManager } from './StateManager';

/** 整应用登录门控信号键（AppStorage 时间戳；Index @StorageLink + @Watch 订阅） */
const AUTH_GATE_TICK_KEY: string = 'authGateTick';

export class AuthManager {
  static reset(): void {
    const state: AuthState = new AuthState();
    state.status = AuthStatus.IDLE;
    StateManager.authState = state;
    AuthManager.notifyGateChange();
  }

  static startLogin(): void {
    StateManager.authState.status = AuthStatus.AUTHENTICATING;
    AuthManager.notifyGateChange();
  }

  static loginSuccess(): void {
    StateManager.authState.status = AuthStatus.AUTHENTICATED;
    AuthManager.notifyGateChange();
  }

  static loginFailed(errorMsg: string): void {
    StateManager.authState.status = AuthStatus.ERROR;
    StateManager.authState.error = errorMsg;
    AuthManager.notifyGateChange();
  }

  static require2FA(methods: TwoFactorApproach[]): void {
    StateManager.authState.status = AuthStatus.TWO_FACTOR;
    StateManager.authState.twoFactorApproaches = methods;
    AuthManager.notifyGateChange();
  }

  static select2FAMethod(type: string): void {
    StateManager.authState.selectedTwoFactor = type;
  }

  static logout(): void {
    AuthManager.reset();
  }

  static isLoggedIn(): boolean {
    return StateManager.authState.status === AuthStatus.AUTHENTICATED;
  }

  /** 当前是否"需 2FA"（自动登录遇服务端要求二次认证时置位；待验证上下文保留在服务层） */
  static needs2FA(): boolean {
    return StateManager.authState.status === AuthStatus.TWO_FACTOR;
  }

  /** 最近一次登录失败的可读原因（供登录页进入时提示，如自动登录失败） */
  static getLastError(): string {
    return StateManager.authState.error;
  }

  static isDemoMode(): boolean {
    return StateManager.settings.demoMode;
  }

  /** 广播登录态门控信号（AppStorage 时间戳；不承载状态内容，仅驱动订阅方重算） */
  private static notifyGateChange(): void {
    AppStorage.setOrCreate<number>(AUTH_GATE_TICK_KEY, Date.now());
  }
}
