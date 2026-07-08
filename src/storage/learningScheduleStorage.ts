import Storage from './asyncStorage';
import {ScheduleEvent} from '../domain/learning';

const KEY = '@campusos/learning_schedule_cache';

export async function loadLearningScheduleCache(): Promise<ScheduleEvent[]> {
  try {
    const raw = await Storage.getItem(KEY);
    if (!raw) {
      return [];
    }
    const parsed = JSON.parse(raw) as ScheduleEvent[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export async function saveLearningScheduleCache(
  events: ScheduleEvent[],
): Promise<void> {
  try {
    if (events.length === 0) {
      await Storage.removeItem(KEY);
      return;
    }
    await Storage.setItem(KEY, JSON.stringify(events));
  } catch {
    // 缓存失败不影响主流程
  }
}
