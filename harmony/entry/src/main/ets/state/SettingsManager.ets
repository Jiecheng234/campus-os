import { StateManager, AppSettings } from './StateManager';

export class SettingsManager {
  static getLocale(): string {
    return StateManager.settings.locale;
  }

  static setLocale(locale: string): void {
    StateManager.settings.locale = locale;
  }

  static isDemoMode(): boolean {
    return StateManager.settings.demoMode;
  }

  static setDemoMode(enabled: boolean): void {
    StateManager.settings.demoMode = enabled;
  }

  static isTrustDevice(): boolean {
    return StateManager.settings.trustDevice;
  }

  static setTrustDevice(enabled: boolean): void {
    StateManager.settings.trustDevice = enabled;
  }

  static getApiProvider(): string {
    return StateManager.settings.apiProvider;
  }

  static getApiKey(): string {
    return StateManager.settings.apiKey;
  }

  static setApiConfig(provider: string, apiKey: string): void {
    StateManager.settings.apiProvider = provider;
    StateManager.settings.apiKey = apiKey;
  }
}
