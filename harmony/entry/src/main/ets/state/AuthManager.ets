import { AuthStatus, AuthState, TwoFactorApproach } from '../domain/AuthTypes';
import { StateManager } from './StateManager';

export class AuthManager {
  static reset(): void {
    const state: AuthState = new AuthState();
    state.status = AuthStatus.IDLE;
    StateManager.authState = state;
  }

  static startLogin(): void {
    StateManager.authState.status = AuthStatus.AUTHENTICATING;
  }

  static loginSuccess(): void {
    StateManager.authState.status = AuthStatus.AUTHENTICATED;
  }

  static loginFailed(errorMsg: string): void {
    StateManager.authState.status = AuthStatus.ERROR;
    StateManager.authState.error = errorMsg;
  }

  static require2FA(methods: TwoFactorApproach[]): void {
    StateManager.authState.status = AuthStatus.TWO_FACTOR;
    StateManager.authState.twoFactorApproaches = methods;
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

  static isDemoMode(): boolean {
    return StateManager.settings.demoMode;
  }
}
