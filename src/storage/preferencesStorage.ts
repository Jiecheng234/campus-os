import Storage from './asyncStorage';
import {AIProviderConfig} from '../domain/agent';

const KEYS = {
  locale: '@campusos/locale',
  aiProvider: '@campusos/ai_provider',
  demoMode: '@campusos/demo_mode',
  trustDevice: '@campusos/trust_device',
  sessionStudentId: '@campusos/session_student_id',
} as const;

export async function getSessionStudentId(): Promise<string | null> {
  return Storage.getItem(KEYS.sessionStudentId);
}

export async function setSessionStudentId(studentId: string): Promise<void> {
  await Storage.setItem(KEYS.sessionStudentId, studentId);
}

export async function clearSessionStudentId(): Promise<void> {
  await Storage.removeItem(KEYS.sessionStudentId);
}

export async function getLocale(): Promise<'zh' | 'en'> {
  const value = await Storage.getItem(KEYS.locale);
  return value === 'en' ? 'en' : 'zh';
}

export async function setLocale(locale: 'zh' | 'en'): Promise<void> {
  await Storage.setItem(KEYS.locale, locale);
}

export async function getAIProviderConfig(): Promise<Omit<AIProviderConfig, 'apiKey'> | null> {
  try {
    const raw = await Storage.getItem(KEYS.aiProvider);
    return raw ? (JSON.parse(raw) as Omit<AIProviderConfig, 'apiKey'>) : null;
  } catch {
    return null;
  }
}

export async function setAIProviderConfig(
  config: Omit<AIProviderConfig, 'apiKey'>,
): Promise<void> {
  await Storage.setItem(KEYS.aiProvider, JSON.stringify(config));
}

export async function isDemoMode(): Promise<boolean> {
  const value = await Storage.getItem(KEYS.demoMode);
  return value === 'true';
}

export async function setDemoMode(enabled: boolean): Promise<void> {
  await Storage.setItem(KEYS.demoMode, enabled ? 'true' : 'false');
}

export async function getTrustDevice(): Promise<boolean> {
  const value = await Storage.getItem(KEYS.trustDevice);
  return value !== 'false';
}

export async function setTrustDevice(enabled: boolean): Promise<void> {
  await Storage.setItem(KEYS.trustDevice, enabled ? 'true' : 'false');
}
