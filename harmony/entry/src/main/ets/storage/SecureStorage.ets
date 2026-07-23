import { PreferencesStorage } from './PreferencesStorage';

const SECURE_KEY_PREFIX: string = '@secure:';

export class SecureStorage {
  static async saveCredentials(studentId: string, password: string): Promise<void> {
    const encodedId: string = encodeURIComponent(studentId);
    const encodedPw: string = encodeURIComponent(password);
    const combined: string = `${encodedId}:${encodedPw}`;
    await PreferencesStorage.setString(SECURE_KEY_PREFIX + 'credentials', combined);
  }

  static async getCredentials(): Promise<SecureCredentials | undefined> {
    const raw: string = await PreferencesStorage.getString(SECURE_KEY_PREFIX + 'credentials', '');
    if (raw.length === 0) {
      return undefined;
    }
    const parts: string[] = raw.split(':');
    if (parts.length < 2) {
      return undefined;
    }
    const result: SecureCredentials = new SecureCredentials();
    result.studentId = decodeURIComponent(parts[0]);
    result.password = decodeURIComponent(parts[1]);
    return result;
  }

  static async clearCredentials(): Promise<void> {
    await PreferencesStorage.remove(SECURE_KEY_PREFIX + 'credentials');
  }
}

export class SecureCredentials {
  studentId: string = '';
  password: string = '';
}
