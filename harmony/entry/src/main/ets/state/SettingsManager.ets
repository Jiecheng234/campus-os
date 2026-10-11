/**
 * ============================================================================
 * SettingsManager — 设置项读写门面（内存 + 持久化单一入口）
 * ============================================================================
 *
 * 【持久化】setDemoMode / setTrustDevice / setLocale 写入内存（全应用既有
 * 判定即时读同一对象，演示模式写内存即生效）后立即异步持久化
 * （StateManager.saveSettings）；失败只记日志不抛（flush 供页面提示）。
 *
 * 【加载】ensureLoaded()：启动时加载持久化设置（幂等，仅一次），由
 * EntryAbility 在页面装载前调用——保证偏好重启后保持。
 *
 * 【签名】三个 setter 对外签名与语义不变（调用方零改动）。
 * ============================================================================
 */
import { StateManager } from './StateManager';
import { Log } from '../utils/Logger';

const LOG_TAG: string = 'SettingsMgr';

export class SettingsManager {
  private static loadTask: Promise<void> | undefined = undefined;
  private static saveTask: Promise<boolean> = Promise.resolve(true);

  /** 启动时加载持久化设置（幂等；仅加载一次；失败只记日志不抛） */
  static ensureLoaded(): Promise<void> {
    if (SettingsManager.loadTask === undefined) {
      SettingsManager.loadTask = StateManager.init().then((): void => {
        Log.i(LOG_TAG, 'SETTINGS loaded demo=%{public}s trust=%{public}s locale=%{public}s',
          StateManager.settings.demoMode, StateManager.settings.trustDevice, StateManager.settings.locale);
      }).catch((): void => {
        Log.e(LOG_TAG, 'SETTINGS load failed');
      });
    }
    return SettingsManager.loadTask;
  }

  static getLocale(): string {
    return StateManager.settings.locale;
  }

  static setLocale(locale: string): void {
    StateManager.settings.locale = locale;
    SettingsManager.persist('locale');
  }

  static isDemoMode(): boolean {
    return StateManager.settings.demoMode;
  }

  static setDemoMode(enabled: boolean): void {
    StateManager.settings.demoMode = enabled;
    SettingsManager.persist('demoMode');
  }

  static isTrustDevice(): boolean {
    return StateManager.settings.trustDevice;
  }

  static setTrustDevice(enabled: boolean): void {
    StateManager.settings.trustDevice = enabled;
    SettingsManager.persist('trustDevice');
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

  /** 等待最近一次设置持久化完成：true=已保存，false=保存失败（不抛出） */
  static async flush(): Promise<boolean> {
    return SettingsManager.saveTask;
  }

  /** 写内存后立即异步持久化；失败记日志不抛（经 flush 供页面可读提示） */
  private static persist(field: string): void {
    SettingsManager.saveTask = StateManager.saveSettings().then((): boolean => {
      Log.i(LOG_TAG, 'SETTINGS saved %{public}s', field);
      return true;
    }).catch((): boolean => {
      Log.e(LOG_TAG, 'SETTINGS save failed %{public}s', field);
      return false;
    });
  }
}
