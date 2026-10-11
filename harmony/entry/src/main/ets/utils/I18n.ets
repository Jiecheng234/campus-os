/**
 * ============================================================================
 * I18n — 轻量国际化框架（词典 + 翻译查找 + 运行时切换）
 * ============================================================================
 *
 * 【分期】本轮交付框架 + 设置页双语化；其余页面后续批次迁移。
 *
 * 【词典】key → { zh, en } 成对条目（SETTINGS_DICTIONARY）；新增语言只需扩列。
 *
 * 【回退链】t(key)：当前 locale 未命中/空串 → 回退中文 → 仍缺返回可读占位
 *   （PLACEHOLDER），禁止空白或键名外泄。
 *
 * 【locale 运行时状态】AppStorage 键 'locale'（LOCALE_STORAGE_KEY）：
 *   - 页面用 @StorageLink('locale') 订阅即可随切换即时重渲染；
 *   - setLocale() 校验（仅 zh/en，非法回退 zh）→ 写 AppStorage → 经
 *     SettingsManager.setLocale 持久化（单一写入路径，保证两者一致）；
 *   - init() 由 EntryAbility 在页面装载前调用，把持久化 locale 灌入 AppStorage。
 * ============================================================================
 */
import { SettingsManager } from '../state/SettingsManager';
import { Log } from './Logger';

/** AppStorage 中的语言键（后续页面 @StorageLink('locale') 直接复用） */
const LOCALE_STORAGE_KEY: string = 'locale';
const LOCALE_ZH: string = 'zh';
const LOCALE_EN: string = 'en';
/** 词典完全未命中时的可读占位（非空白、非键名） */
const PLACEHOLDER: string = '—';
const LOG_TAG: string = 'I18n';

/** 翻译词条：zh/en 成对（新增语言在此扩列） */
interface I18nEntry {
  zh: string;
  en: string;
}

/** 设置页全部文案词典（后续页面迁移时按前缀扩列） */
const SETTINGS_DICTIONARY: Record<string, I18nEntry> = {
  'common.cancel': { zh: '取消', en: 'Cancel' },

  'settings.eyebrow': { zh: 'SETTINGS', en: 'SETTINGS' },
  'settings.title': { zh: '设置', en: 'Settings' },
  'settings.statusDemo': { zh: '演示模式', en: 'Demo mode' },
  'settings.statusLoggedIn': { zh: '已登录', en: 'Signed in' },
  'settings.statusLoggedOut': { zh: '未登录', en: 'Not signed in' },

  'settings.sectionAccount': { zh: '账号', en: 'Account' },
  'settings.accountStatus': { zh: '状态', en: 'Status' },
  'settings.accountStudentId': { zh: '学号', en: 'Student ID' },

  'settings.sectionPreferences': { zh: '偏好设置', en: 'Preferences' },
  'settings.demoMode': { zh: '演示模式', en: 'Demo mode' },
  'settings.trustDevice': { zh: '信任此设备', en: 'Trust this device' },
  'settings.language': { zh: '语言', en: 'Language' },
  'settings.langZh': { zh: '中文', en: '中文' },
  'settings.langEn': { zh: 'English', en: 'English' },
  'settings.selectLanguage': { zh: '选择语言', en: 'Select language' },

  'settings.sectionFeatures': { zh: '功能', en: 'Features' },
  'settings.aiMemory': { zh: 'AI 记忆', en: 'AI memory' },
  'settings.actionHistory': { zh: '操作记录', en: 'Action history' },
  'settings.smartMonitor': { zh: '智能监控', en: 'Smart monitor' },
  'settings.notSupported': { zh: '暂不支持', en: 'Not available yet' },

  'settings.clearLocalData': { zh: '清理本地数据', en: 'Clear local data' },
  'settings.clearDataTitle': { zh: '清理本地数据', en: 'Clear local data' },
  'settings.clearDataConfirm': { zh: '确认清理', en: 'Clear' },
  'settings.clearDataMessage': {
    zh: '将清除 AI 会话与学习缓存等本地数据，不影响账号与云端数据。',
    en: 'This will clear local AI chats and learning cache. Your account and cloud data are not affected.'
  },
  'settings.clearItemAi': { zh: 'AI 会话', en: 'AI chats' },
  'settings.clearItemLearning': { zh: '学习缓存', en: 'Learning cache' },
  'settings.countUnit': { zh: '条', en: 'items' },
  'settings.clearListSep': { zh: '、', en: ', ' },
  'settings.clearResultDone': { zh: '已清理：', en: 'Cleared: ' },
  'settings.clearResultNone': { zh: '未发现可清理的本地数据', en: 'No local data to clear' },

  'settings.logout': { zh: '退出登录', en: 'Sign out' },
  'settings.logoutConfirmTitle': { zh: '退出登录', en: 'Sign out' },
  'settings.logoutConfirmMessage': {
    zh: '退出后将清除本机会话与登录凭证，下次使用需重新登录。',
    en: 'This will sign out and clear saved credentials on this device. You will need to sign in again.'
  },
  'settings.logoutConfirmOk': { zh: '确认退出', en: 'Sign out' },
  'settings.logoutSuccess': { zh: '已退出登录', en: 'Signed out' },
  'settings.logoutFailed': { zh: '退出登录失败，请重试', en: 'Failed to sign out. Please try again.' },

  'settings.saveFailed': { zh: '设置保存失败，请重试', en: 'Failed to save settings. Please try again.' },

  'settings.appName': { zh: 'CampusOS', en: 'CampusOS' },
  'settings.platformLine': { zh: 'HarmonyOS ArkTS', en: 'HarmonyOS ArkTS' },
  'settings.versionUnknown': { zh: '版本未知', en: 'Version unknown' },
};

export class I18n {
  /**
   * 启动初始化：把持久化设置中的 locale 灌入 AppStorage。
   * 由 EntryAbility 在页面装载前调用（须在 SettingsManager.ensureLoaded 之后）。
   */
  static init(): void {
    const locale: string = I18n.normalizeLocale(SettingsManager.getLocale());
    AppStorage.setOrCreate<string>(LOCALE_STORAGE_KEY, locale);
  }

  /**
   * 翻译查找：按当前 locale 取词。
   * 回退链：当前语言缺 → 中文 → 可读占位（禁止空白/键名外泄）。
   *
   * 【locale 参数】可选。页面若传入 `@StorageLink('locale')` 的当前值，
   * 可在渲染期建立状态依赖，使语言切换即时刷新该元素（ArkUI 局部更新）。
   */
  static t(key: string, locale?: string): string {
    const entry: I18nEntry | undefined = SETTINGS_DICTIONARY[key];
    if (entry === undefined) {
      return PLACEHOLDER;
    }
    const current: string = locale !== undefined ? I18n.normalizeLocale(locale) : I18n.getLocale();
    if (current === LOCALE_EN && entry.en.length > 0) {
      return entry.en;
    }
    if (entry.zh.length > 0) {
      return entry.zh;
    }
    return PLACEHOLDER;
  }

  /**
   * 切换语言：仅接受 zh/en（非法回退 zh）→ 写 AppStorage（页面即时重渲染）
   * → 经 SettingsManager.setLocale 持久化。
   */
  static setLocale(locale: string): void {
    const valid: string = I18n.normalizeLocale(locale);
    AppStorage.setOrCreate<string>(LOCALE_STORAGE_KEY, valid);
    SettingsManager.setLocale(valid);
    Log.i(LOG_TAG, 'locale set %{public}s', valid);
  }

  /** 当前 locale（AppStorage 缺失/非法时回退 zh） */
  static getLocale(): string {
    const stored: string | undefined = AppStorage.get<string>(LOCALE_STORAGE_KEY);
    if (stored !== undefined) {
      return I18n.normalizeLocale(stored);
    }
    return LOCALE_ZH;
  }

  /** 校验：仅 zh/en，其余一律回退 zh */
  private static normalizeLocale(locale: string): string {
    return locale === LOCALE_EN ? LOCALE_EN : LOCALE_ZH;
  }
}
