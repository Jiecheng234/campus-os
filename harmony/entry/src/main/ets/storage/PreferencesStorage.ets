import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

export class PreferencesStorage {
  private static context: common.Context | undefined = undefined;
  private static storeName: string = 'campusos_preferences';

  static init(ctx: common.Context): void {
    PreferencesStorage.context = ctx;
  }

  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return defaultValue;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    const value: preferences.ValueType = prefs.getSync(key, defaultValue);
    if (typeof value === 'string') {
      return value;
    }
    return defaultValue;
  }

  static async setString(key: string, value: string): Promise<void> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    prefs.putSync(key, value);
    await prefs.flush();
  }

  static async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return defaultValue;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    const value: preferences.ValueType = prefs.getSync(key, defaultValue);
    if (typeof value === 'boolean') {
      return value;
    }
    return defaultValue;
  }

  static async setBoolean(key: string, value: boolean): Promise<void> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    prefs.putSync(key, value);
    await prefs.flush();
  }

  static async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return defaultValue;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    const value: preferences.ValueType = prefs.getSync(key, defaultValue);
    if (typeof value === 'number') {
      return value;
    }
    return defaultValue;
  }

  static async setNumber(key: string, value: number): Promise<void> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    prefs.putSync(key, value);
    await prefs.flush();
  }

  static async getJson<T>(key: string): Promise<T | undefined> {
    const raw: string = await PreferencesStorage.getString(key, '');
    if (raw.length === 0) {
      return undefined;
    }
    return JSON.parse(raw) as T;
  }

  static async setJson<T>(key: string, value: T): Promise<void> {
    const raw: string = JSON.stringify(value);
    await PreferencesStorage.setString(key, raw);
  }

  static async remove(key: string): Promise<void> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    prefs.deleteSync(key);
    await prefs.flush();
  }

  static async clear(): Promise<void> {
    const ctx: common.Context | undefined = PreferencesStorage.context;
    if (ctx === undefined) {
      return;
    }
    const prefs: preferences.Preferences = await preferences.getPreferences(ctx, PreferencesStorage.storeName);
    prefs.clearSync();
    await prefs.flush();
  }
}
