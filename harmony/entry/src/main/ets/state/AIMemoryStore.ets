/**
 * ============================================================================
 * AIMemoryStore — Agent 个性化记忆的持久化存取（US4）
 * ============================================================================
 *
 * 【语义】对齐 RN aiMemoryStorage：跨会话保存用户长期偏好，注入系统提示。
 * 【实现】基于既有 PreferencesStorage + StorageKeys.AI_MEMORY；
 *   存储形态为 AIMemory[]（key/value/updatedAt），失败不抛（持久化失败
 *   不影响对话主流程）。
 * 【结构化键位】与 RN AIMemory 字段一一对应：
 *   favoriteLibrary / favoriteSection / defaultRechargeAmount /
 *   watchedCourses（顿号分隔）/ notes（分号分隔）。
 * ============================================================================
 */
import { AIMemory } from '../domain/AIAgentTypes';
import { PreferencesStorage } from '../storage/PreferencesStorage';
import { StorageKeys } from '../storage/StorageKeys';
import { Log } from '../utils/Logger';

const LOG_TAG: string = 'AIMemoryStore';
/** 记忆项数量上界（防失控增长；超出时淘汰最旧项） */
const MAX_MEMORY_ITEMS: number = 64;

export class AIMemoryStore {
  private static cache: AIMemory[] = [];
  private static loaded: boolean = false;

  /** 读取全部记忆（带内存缓存；冷启动后首次读取走持久化） */
  static async load(): Promise<AIMemory[]> {
    if (AIMemoryStore.loaded) {
      return AIMemoryStore.cache;
    }
    const items: AIMemory[] = [];
    try {
      const raw: string = await PreferencesStorage.getString(StorageKeys.AI_MEMORY, '');
      if (raw.length > 0) {
        const parsed: object = JSON.parse(raw);
        if (Array.isArray(parsed)) {
          const arr: Object[] = parsed as Object[];
          for (let i: number = 0; i < arr.length; i++) {
            const entry: Object = arr[i];
            const item: AIMemory | undefined = AIMemoryStore.parseItem(entry);
            if (item !== undefined) {
              items.push(item);
            }
          }
        }
      }
    } catch (e) {
      // 损坏数据按空记忆处理，不阻断对话
      Log.w(LOG_TAG, 'load failed, fallback to empty');
    }
    AIMemoryStore.cache = items;
    AIMemoryStore.loaded = true;
    return AIMemoryStore.cache;
  }

  /** 写入/更新一条记忆（同 key 覆盖，异 key 追加；失败不抛） */
  static async remember(key: string, value: string): Promise<void> {
    const trimmedKey: string = key.trim();
    if (trimmedKey.length === 0) {
      return;
    }
    const items: AIMemory[] = await AIMemoryStore.load();
    const stamp: string = AIMemoryStore.formatTimestamp(new Date());
    let found: boolean = false;
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].key === trimmedKey) {
        items[i].value = value;
        items[i].updatedAt = stamp;
        found = true;
        break;
      }
    }
    if (!found) {
      const item: AIMemory = new AIMemory();
      item.key = trimmedKey;
      item.value = value;
      item.updatedAt = stamp;
      items.push(item);
    }
    // 超出上界时淘汰最旧项（updated 最旧优先）
    while (items.length > MAX_MEMORY_ITEMS) {
      items.shift();
    }
    await AIMemoryStore.persist(items);
  }

  /** 删除一条记忆（不存在时静默；失败不抛） */
  static async forget(key: string): Promise<void> {
    const items: AIMemory[] = await AIMemoryStore.load();
    const next: AIMemory[] = [];
    for (let i: number = 0; i < items.length; i++) {
      if (items[i].key !== key) {
        next.push(items[i]);
      }
    }
    if (next.length === items.length) {
      return;
    }
    await AIMemoryStore.persist(next);
  }

  /** 清空全部记忆（失败不抛） */
  static async clear(): Promise<void> {
    await AIMemoryStore.persist([]);
  }

  /**
   * 把记忆压成适合注入 system prompt 的中文摘要（对齐 RN summarizeMemory）。
   * 结构化键位渲染为可读短语，其余键位按「key：value」通用行渲染。
   */
  static summarizeText(items: AIMemory[]): string {
    const byKey: Record<string, string> = {};
    const others: AIMemory[] = [];
    for (let i: number = 0; i < items.length; i++) {
      const item: AIMemory = items[i];
      if (AIMemoryStore.isStructuredKey(item.key)) {
        byKey[item.key] = item.value;
      } else {
        others.push(item);
      }
    }
    const parts: string[] = [];
    const favoriteLibrary: string = byKey['favoriteLibrary'] ?? '';
    const favoriteSection: string = byKey['favoriteSection'] ?? '';
    if (favoriteLibrary.length > 0) {
      parts.push('常用图书馆：' + favoriteLibrary +
        (favoriteSection.length > 0 ? '（' + favoriteSection + '）' : ''));
    }
    const rechargeAmount: string = byKey['defaultRechargeAmount'] ?? '';
    if (rechargeAmount.length > 0) {
      parts.push('默认电费充值金额：' + rechargeAmount + ' 元');
    }
    const watchedCourses: string = byKey['watchedCourses'] ?? '';
    if (watchedCourses.length > 0) {
      parts.push('重点关注课程：' + watchedCourses);
    }
    const notes: string = byKey['notes'] ?? '';
    if (notes.length > 0) {
      parts.push('其它偏好：' + notes);
    }
    for (let i: number = 0; i < others.length; i++) {
      parts.push(others[i].key + '：' + others[i].value);
    }
    return parts.length > 0 ? parts.join('\n') : '（暂无个性化记忆）';
  }

  // ============================================================
  // 内部：解析与持久化
  // ============================================================

  private static isStructuredKey(key: string): boolean {
    return key === 'favoriteLibrary' || key === 'favoriteSection' ||
      key === 'defaultRechargeAmount' || key === 'watchedCourses' || key === 'notes';
  }

  /** 单条记忆解析（字段缺失/类型不符返回 undefined） */
  private static parseItem(entry: Object): AIMemory | undefined {
    if (typeof entry !== 'object' || entry === null) {
      return undefined;
    }
    const rec: Record<string, Object> = entry as Record<string, Object>;
    const key: Object | undefined = rec['key'];
    const value: Object | undefined = rec['value'];
    const updatedAt: Object | undefined = rec['updatedAt'];
    if (typeof key !== 'string' || key.length === 0 || typeof value !== 'string') {
      return undefined;
    }
    const item: AIMemory = new AIMemory();
    item.key = key;
    item.value = value;
    item.updatedAt = typeof updatedAt === 'string' ? updatedAt : '';
    return item;
  }

  /** 写回持久化并刷新缓存（失败不抛） */
  private static async persist(items: AIMemory[]): Promise<void> {
    AIMemoryStore.cache = items;
    AIMemoryStore.loaded = true;
    try {
      await PreferencesStorage.setJson<AIMemory[]>(StorageKeys.AI_MEMORY, items);
    } catch (e) {
      Log.w(LOG_TAG, 'persist failed len=%{public}d', items.length);
    }
  }

  /** 本地时间戳：YYYY-MM-DD HH:mm:ss */
  private static formatTimestamp(date: Date): string {
    return date.getFullYear() + '-' + AIMemoryStore.pad2(date.getMonth() + 1) + '-' + AIMemoryStore.pad2(date.getDate()) +
      ' ' + AIMemoryStore.pad2(date.getHours()) + ':' + AIMemoryStore.pad2(date.getMinutes()) + ':' +
      AIMemoryStore.pad2(date.getSeconds());
  }

  /** 两位数字补零 */
  private static pad2(n: number): string {
    return n < 10 ? '0' + n : '' + n;
  }
}
