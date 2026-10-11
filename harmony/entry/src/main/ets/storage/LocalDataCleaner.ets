/**
 * ============================================================================
 * LocalDataCleaner — 本地数据清理（集中管理清理项，键名不散落页面）
 * ============================================================================
 *
 * 【范围】仅本地偏好存储中的既有占位键：
 *   - AI 会话（StorageKeys.AI_CONVERSATIONS）
 *   - 学习缓存（StorageKeys.LEARNING_CACHE）
 *   不触达服务端、不清理凭证与设置。
 *
 * 【计数】返回清理条数：键不存在/空串 → 0；JSON 数组按元素数计；
 *   非数组/非 JSON 数据按 1 条计。
 *
 * 【容错】任何异常只记日志并返回 0，不向调用方抛出（页面按返回值提示）。
 * ============================================================================
 */
import { PreferencesStorage } from './PreferencesStorage';
import { StorageKeys } from './StorageKeys';
import { Log } from '../utils/Logger';

const LOG_TAG: string = 'DataCleaner';

export class LocalDataCleaner {
  /** 清理 AI 会话本地数据；返回清理条数（无数据/失败返回 0） */
  static async clearAiConversations(): Promise<number> {
    return LocalDataCleaner.clearKey(StorageKeys.AI_CONVERSATIONS, 'AI_CONVERSATIONS');
  }

  /** 清理学习缓存本地数据；返回清理条数（无数据/失败返回 0） */
  static async clearLearningCache(): Promise<number> {
    return LocalDataCleaner.clearKey(StorageKeys.LEARNING_CACHE, 'LEARNING_CACHE');
  }

  private static async clearKey(key: string, label: string): Promise<number> {
    try {
      const raw: string = await PreferencesStorage.getString(key, '');
      if (raw.length === 0) {
        return 0;
      }
      const count: number = LocalDataCleaner.countItems(raw);
      await PreferencesStorage.remove(key);
      Log.i(LOG_TAG, 'CLEAN %{public}s count=%{public}d', label, count);
      return count;
    } catch (e) {
      Log.e(LOG_TAG, 'CLEAN %{public}s failed', label);
      return 0;
    }
  }

  /** 计数：JSON 数组按元素数；其余非空数据按 1 条 */
  private static countItems(raw: string): number {
    try {
      const parsed: Object | null = JSON.parse(raw);
      if (parsed !== null && Array.isArray(parsed)) {
        const items: Object[] = parsed as Object[];
        return items.length;
      }
    } catch (e) {
      Log.d(LOG_TAG, 'CLEAN payload not json, count as 1');
    }
    return 1;
  }
}
