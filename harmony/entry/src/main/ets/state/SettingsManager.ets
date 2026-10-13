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
 * 【AI provider 配置（ai-chat 特性）】preset/baseUrl/model 持久化于独立
 * 偏好键（AI_PROVIDER_SETTINGS_KEY），与 AppSettings 解耦：
 *  - getAIProviderSettings() / setAIProviderSettings() / resetAIProviderSettings()
 *  - 【配置变更信号】setAIProviderSettings / resetAIProviderSettings / setDemoMode
 *    会向 AppStorage 写 'aiConfigTick' 时间戳信号（AI 页 @StorageLink 订阅，
 *    设置页保存后对话页胶囊无需重启即时刷新）。
 *  - 【apiKey 字段已弃用】AppSettings.apiKey 不再承载真实 Key：
 *    API Key 一律经 services/ai/ApiKeyStore（系统关键资产存储 ASSET）读写，
 *    禁止写入偏好设置明文（FR-002 / SC-008）；ensureLoaded 若发现历史
 *    明文残留会立即清除。
 *
 * 【签名】三个 setter 对外签名与语义不变（调用方零改动）。
 * ============================================================================
 */
import { StateManager } from './StateManager';
import { PreferencesStorage } from '../storage/PreferencesStorage';
import { Log } from '../utils/Logger';

const LOG_TAG: string = 'SettingsMgr';
/** AI provider 配置持久化键（沿用 StorageKeys 的 @campusos/ 前缀约定） */
const AI_PROVIDER_SETTINGS_KEY: string = '@campusos/ai_provider_config';
/** AppStorage 配置变更信号键（AI 页 @StorageLink 订阅：保存/清除/演示开关后无需重启即时刷新 provider·model 胶囊） */
const AI_CONFIG_TICK_KEY: string = 'aiConfigTick';

/** AI provider 配置（预设标识 + 自定义 baseUrl/model；不含 API Key） */
export class AIProviderSettings {
  preset: string = 'openai';
  baseUrl: string = '';
  model: string = '';
}

/** AI provider 配置持久化原始形态（JSON 读入断言；字段可能缺失，读取后归一） */
class AIProviderSettingsRaw {
  preset?: string;
  baseUrl?: string;
  model?: string;
}

export class SettingsManager {
  private static loadTask: Promise<void> | undefined = undefined;
  private static saveTask: Promise<boolean> = Promise.resolve(true);
  private static aiSaveTask: Promise<boolean> = Promise.resolve(true);
  /** AI provider 配置内存缓存（单一事实源；启动加载，写后异步持久化） */
  private static aiProvider: AIProviderSettings = new AIProviderSettings();

  /** 启动时加载持久化设置（幂等；仅加载一次；失败只记日志不抛） */
  static ensureLoaded(): Promise<void> {
    if (SettingsManager.loadTask === undefined) {
      SettingsManager.loadTask = StateManager.init().then((): void => {
        SettingsManager.scrubLegacyApiKey();
        Log.i(LOG_TAG, 'SETTINGS loaded demo=%{public}s trust=%{public}s locale=%{public}s',
          StateManager.settings.demoMode, StateManager.settings.trustDevice, StateManager.settings.locale);
      }).then((): Promise<void> => SettingsManager.loadAIProviderSettings())
        .catch((): void => {
          Log.e(LOG_TAG, 'SETTINGS load failed');
        });
    }
    return SettingsManager.loadTask;
  }

  /** 清除历史明文 Key 残留（AppSettings.apiKey 已弃用；FR-002/SC-008） */
  private static scrubLegacyApiKey(): void {
    const legacy: string = StateManager.settings.apiKey;
    if (legacy.length > 0) {
      StateManager.settings.apiKey = '';
      StateManager.saveSettings().then((): void => {
        Log.w(LOG_TAG, 'SETTINGS legacy apiKey scrubbed');
      }).catch((): void => {
        Log.e(LOG_TAG, 'SETTINGS legacy apiKey scrub failed');
      });
    }
  }

  // ============================================================
  // 通用偏好（签名与语义不变）
  // ============================================================

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
    SettingsManager.notifyAiConfigChanged();
  }

  static isTrustDevice(): boolean {
    return StateManager.settings.trustDevice;
  }

  static setTrustDevice(enabled: boolean): void {
    StateManager.settings.trustDevice = enabled;
    SettingsManager.persist('trustDevice');
  }

  // ============================================================
  // AI provider 配置（preset/baseUrl/model 持久化；Key 走 ApiKeyStore）
  // ============================================================

  /** 读取 AI provider 配置（返回副本，避免外部绕过 setter 直接改内存） */
  static getAIProviderSettings(): AIProviderSettings {
    const copy: AIProviderSettings = new AIProviderSettings();
    copy.preset = SettingsManager.aiProvider.preset;
    copy.baseUrl = SettingsManager.aiProvider.baseUrl;
    copy.model = SettingsManager.aiProvider.model;
    return copy;
  }

  /** 写入 AI provider 配置（内存即生效 + 异步持久化 + 配置变更信号广播） */
  static setAIProviderSettings(preset: string, baseUrl: string, model: string): void {
    SettingsManager.aiProvider.preset = preset;
    SettingsManager.aiProvider.baseUrl = baseUrl;
    SettingsManager.aiProvider.model = model;
    SettingsManager.persistAIProvider();
    SettingsManager.notifyAiConfigChanged();
  }

  /** 重置 AI provider 配置为默认（openai 预设、空 baseUrl/model） */
  static resetAIProviderSettings(): void {
    SettingsManager.aiProvider = new AIProviderSettings();
    SettingsManager.persistAIProvider();
    SettingsManager.notifyAiConfigChanged();
  }

  /** 从持久化键加载 AI provider 配置（字段缺失回退默认；失败保持默认） */
  private static async loadAIProviderSettings(): Promise<void> {
    let raw: AIProviderSettingsRaw | undefined = undefined;
    try {
      raw = await PreferencesStorage.getJson<AIProviderSettingsRaw>(AI_PROVIDER_SETTINGS_KEY);
    } catch (e) {
      Log.e(LOG_TAG, 'AI_PROVIDER load failed');
      return;
    }
    if (raw === undefined) {
      Log.i(LOG_TAG, 'AI_PROVIDER load none (defaults)');
      return;
    }
    if (raw.preset !== undefined && raw.preset.length > 0) {
      SettingsManager.aiProvider.preset = raw.preset;
    }
    if (raw.baseUrl !== undefined) {
      SettingsManager.aiProvider.baseUrl = raw.baseUrl;
    }
    if (raw.model !== undefined) {
      SettingsManager.aiProvider.model = raw.model;
    }
    Log.i(LOG_TAG, 'AI_PROVIDER loaded preset=%{public}s', SettingsManager.aiProvider.preset);
  }

  /** AI provider 配置异步持久化（失败记日志不抛，经 flush 供页面提示） */
  private static persistAIProvider(): void {
    SettingsManager.aiSaveTask = PreferencesStorage.setJson<AIProviderSettings>(
      AI_PROVIDER_SETTINGS_KEY, SettingsManager.aiProvider).then((): boolean => {
      Log.i(LOG_TAG, 'AI_PROVIDER saved');
      return true;
    }).catch((): boolean => {
      Log.e(LOG_TAG, 'AI_PROVIDER save failed');
      return false;
    });
  }

  /** 广播 AI 配置变更（AppStorage 时间戳信号；不承载配置内容，仅驱动订阅页重算） */
  private static notifyAiConfigChanged(): void {
    AppStorage.setOrCreate<number>(AI_CONFIG_TICK_KEY, Date.now());
  }

  // ============================================================
  // 已弃用接口（保留签名兼容；不再向偏好设置写入 Key 明文）
  // ============================================================

  /** @deprecated provider 配置改经 getAIProviderSettings()/setAIProviderSettings() 读写 */
  static getApiProvider(): string {
    return SettingsManager.aiProvider.preset;
  }

  /** @deprecated API Key 不再存偏好设置（FR-002）：由 services/ai/ApiKeyStore（ASSET）承载；恒返回空串 */
  static getApiKey(): string {
    return '';
  }

  /** @deprecated 不再把 Key 写入偏好设置明文（FR-002/SC-008）：
   *  provider 经 setAIProviderSettings() 持久化，Key 经 ApiKeyStore.save() 入 ASSET */
  static setApiConfig(provider: string, apiKey: string): void {
    SettingsManager.setAIProviderSettings(provider, '', '');
    if (apiKey.length > 0) {
      Log.w(LOG_TAG, 'setApiConfig ignored apiKey (use ApiKeyStore.save)');
    }
  }

  // ============================================================
  // 持久化收口
  // ============================================================

  /** 等待最近一次设置持久化完成：true=已保存，false=保存失败（不抛出） */
  static async flush(): Promise<boolean> {
    const settingsOk: boolean = await SettingsManager.saveTask;
    const aiOk: boolean = await SettingsManager.aiSaveTask;
    return settingsOk && aiOk;
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
