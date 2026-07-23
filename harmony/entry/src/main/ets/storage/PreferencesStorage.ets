import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

export class PreferencesStorage {
  private static context: object | undefined = undefined;
  private static storeName: string = 'campusos_preferences';

  static init(context: object): void {
    PreferencesStorage.context = context;
  }

  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    const value: string = prefs.getSync(key, defaultValue) as string;
    return value;
  }

  static async setString(key: string, value: string): Promise<void> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    prefs.putSync(key, value);
    await prefs.flush();
  }

  static async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    const value: boolean = prefs.getSync(key, defaultValue) as boolean;
    return value;
  }

  static async setBoolean(key: string, value: boolean): Promise<void> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    prefs.putSync(key, value);
    await prefs.flush();
  }

  static async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    const value: number = prefs.getSync(key, defaultValue) as number;
    return value;
  }

  static async setNumber(key: string, value: number): Promise<void> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
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
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    prefs.deleteSync(key);
    await prefs.flush();
  }

  static async clear(): Promise<void> {
    const prefs: preferences.Preferences = await PreferencesStorage.getPreferences();
    prefs.clearSync();
    await prefs.flush();
  }

  private static async getPreferences(): Promise<preferences.Preferences> {
    const ctx: object = PreferencesStorage.context;
    if (ctx === undefined) {
      throw new Error('PreferencesStorage not initialized');
    }
    const opts: preferences.Options = { name: PreferencesStorage.storeName };
    return preferences.getPreferences(ctx, PreferencesStorage.storeName);
  }
}
