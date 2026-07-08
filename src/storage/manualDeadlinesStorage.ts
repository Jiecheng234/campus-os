import Storage from './asyncStorage';
import {ManualDeadline} from '../domain/deadline';

const KEY = '@campusos/manual_deadlines';

export async function loadManualDeadlines(): Promise<ManualDeadline[]> {
  try {
    const raw = await Storage.getItem(KEY);
    if (!raw) {
      return [];
    }
    const parsed = JSON.parse(raw) as ManualDeadline[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export async function saveManualDeadlines(items: ManualDeadline[]): Promise<void> {
  try {
    await Storage.setItem(KEY, JSON.stringify(items));
  } catch {
    // 本地持久化失败不影响主流程
  }
}

