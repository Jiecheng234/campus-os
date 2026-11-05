/**
 * ============================================================================
 * ManualDeadlineStore — 手动 DDL 共享存储（学习详情深链）
 * ============================================================================
 *
 * 【定位】手动 DDL 数据的唯一读写入口：
 *   - 学习页（表单新增 / 卡片删除）、首页（最近 DDL 合并）、
 *     AgentWriteTools（AI add/remove_manual_deadline）统一走本 store，
 *     消除此前 AgentWriteTools 私有缓存与页面内存列表的两套数据源。
 *
 * 【持久化】StorageKeys.MANUAL_DEADLINES（@campusos/manual_deadlines），
 * 值为 ManualDeadline[] 的 JSON 字符串，字段与顺序沿用现状、不做迁移。
 *
 * 【订阅】append/remove 成功后广播全部监听器；页面在 aboutToAppear 订阅、
 * aboutToDisappear 取消，实现 AI 写入后页面即时刷新（FR-019/FR-020）。
 */
import { ManualDeadline } from '../domain/DeadlineTypes';
import { PreferencesStorage } from '../storage/PreferencesStorage';
import { StorageKeys } from '../storage/StorageKeys';
import { Log } from '../utils/Logger';

const LOG_TAG: string = 'ManualDDLStore';
/** AppStorage 变更信号：页面用 @StorageLink 订阅，即使 Tab 隐藏也能收到刷新通知 */
const MANUAL_DDL_TICK_KEY: string = 'manualDdlTick';

/** 订阅条目：id 由 subscribe 递增分配，unsubscribe 按 id 定位 */
class DeadlineListenerEntry {
  id: number = 0;
  callback: () => void = () => {};
}

/** 进程内缓存（已排序数据源；load 幂等填充） */
let cache: ManualDeadline[] = [];
let loaded: boolean = false;
let loadTask: Promise<void> | undefined = undefined;
let listenerSeq: number = 0;
const listenerEntries: DeadlineListenerEntry[] = [];
/** 串行写队列尾：append/remove 依次执行，避免并发写丢失更新；失败也推进队尾（不永久 rejected） */
let writeTail: Promise<void> = Promise.resolve();

/** 入队一个写操作：前一个写 settle 后才执行（cache.slice 必须在队列内、await 持久化之前执行） */
function enqueueWrite<T>(task: () => Promise<T>): Promise<T> {
  const run: Promise<T> = writeTail.then(task);
  writeTail = run.then((): void => {}, (): void => {});
  return run;
}

/** 校验真实日期 YYYY-MM-DD：解析后回读年/月/日一致（拒绝 2026-02-31 这类自动进位日期） */
function isValidDateText(s: string): boolean {
  const re: RegExp = /^\d{4}-\d{2}-\d{2}$/;
  if (!re.test(s)) {
    return false;
  }
  const parts: string[] = s.split('-');
  const y: number = Number(parts[0]);
  const m: number = Number(parts[1]);
  const d: number = Number(parts[2]);
  if (isNaN(y) || isNaN(m) || isNaN(d)) {
    return false;
  }
  const parsed: Date = new Date(y, m - 1, d);
  return parsed.getFullYear() === y && parsed.getMonth() === m - 1 && parsed.getDate() === d;
}

/** 校验并归一时间：接受 H:mm / HH:mm，归一为 HH:mm（小时 0–23、分钟 0–59）；非法返回空串 */
function normalizeTimeText(s: string): string {
  const re: RegExp = /^\d{1,2}:\d{2}$/;
  if (!re.test(s)) {
    return '';
  }
  const parts: string[] = s.split(':');
  const h: number = Number(parts[0]);
  const m: number = Number(parts[1]);
  if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) {
    return '';
  }
  return (h < 10 ? '0' + String(h) : String(h)) + ':' + (m < 10 ? '0' + String(m) : String(m));
}

/** 解析单条持久化记录（字段缺失/类型不符返回 undefined，跳过脏数据） */
function parseStoredDeadline(entry: Object): ManualDeadline | undefined {
  if (entry === null || typeof entry !== 'object') {
    return undefined;
  }
  const rec: Record<string, Object> = entry as Record<string, Object>;
  const id: Object | undefined = rec['id'];
  const title: Object | undefined = rec['title'];
  const date: Object | undefined = rec['date'];
  if (typeof id !== 'string' || typeof title !== 'string' || typeof date !== 'string') {
    return undefined;
  }
  const item: ManualDeadline = new ManualDeadline();
  item.id = id;
  item.title = title;
  item.date = date;
  const time: Object | undefined = rec['time'];
  item.time = typeof time === 'string' ? time : '';
  const course: Object | undefined = rec['course'];
  item.course = typeof course === 'string' ? course : '';
  const note: Object | undefined = rec['note'];
  item.note = typeof note === 'string' ? note : '';
  const createdAt: Object | undefined = rec['createdAt'];
  item.createdAt = typeof createdAt === 'string' ? createdAt : '';
  return item;
}

/** 按 date + time 升序副本（无法解析的字段按字符串比较自然兜底） */
function sortedCopy(): ManualDeadline[] {
  const sorted: ManualDeadline[] = cache.slice();
  sorted.sort((a: ManualDeadline, b: ManualDeadline): number =>
    (a.date + ' ' + a.time).localeCompare(b.date + ' ' + b.time));
  return sorted;
}

/** 数据变更广播：遍历监听器快照（回调内订阅/退订不影响本轮遍历，避免跳项）；任一监听器异常不影响其余 */
function broadcastChange(): void {
  const snapshot: DeadlineListenerEntry[] = listenerEntries.slice();
  for (let i: number = 0; i < snapshot.length; i++) {
    try {
      snapshot[i].callback();
    } catch (e) {
      Log.w(LOG_TAG, 'listener notify failed idx=%{public}d', i);
    }
  }
  // AppStorage 信号：Tabs 常驻/隐藏页面收不到可见性回调时，仍能通过 @StorageLink @Watch 刷新
  try {
    AppStorage.setOrCreate<number>(MANUAL_DDL_TICK_KEY, Date.now());
  } catch (e) {
    Log.w(LOG_TAG, 'tick publish failed');
  }
}

export class ManualDeadlineStore {
  /**
   * 懒加载持久化数据（幂等；并发调用共享同一任务）。
   * 解析失败回退空数组，不抛出。try/finally 清理 loadTask，避免 rejected Promise 被永久缓存。
   */
  static async load(): Promise<void> {
    if (loaded) {
      return;
    }
    if (loadTask !== undefined) {
      await loadTask;
      return;
    }
    const task: Promise<void> = ManualDeadlineStore.doLoad();
    loadTask = task;
    try {
      await task;
    } finally {
      if (loadTask === task) {
        loadTask = undefined;
      }
    }
  }

  private static async doLoad(): Promise<void> {
    const items: ManualDeadline[] = [];
    try {
      const raw: string = await PreferencesStorage.getString(StorageKeys.MANUAL_DEADLINES, '');
      if (raw.length > 0) {
        const parsed: Object = JSON.parse(raw) as Object;
        if (Array.isArray(parsed)) {
          const arr: Object[] = parsed as Object[];
          for (let i: number = 0; i < arr.length; i++) {
            const item: ManualDeadline | undefined = parseStoredDeadline(arr[i]);
            if (item !== undefined) {
              items.push(item);
            }
          }
        }
      }
    } catch (e) {
      Log.w(LOG_TAG, 'load failed, fallback to empty');
    }
    cache = items;
    loaded = true;
  }

  /** 已加载列表的升序副本（未 load 时返回空；需要数据先 await load/listAsync） */
  static list(): ManualDeadline[] {
    return sortedCopy();
  }

  /** 加载（幂等）后返回升序列表副本（页面与 AI 上下文共用入口） */
  static async listAsync(): Promise<ManualDeadline[]> {
    await ManualDeadlineStore.load();
    return sortedCopy();
  }

  /**
   * 新增手动 DDL：生成 md- 前缀 id 与 createdAt，持久化成功后广播。
   * 校验：标题非空；日期为真实 YYYY-MM-DD（回读年月日，拒绝进位日期）；
   * 时间接受 H:mm/HH:mm 并归一为 HH:mm（非法返回 undefined，不落盘）。
   * 持久化失败返回 undefined（调用方给可读失败提示）。
   */
  static async append(title: string, date: string, time: string,
    course: string, note: string): Promise<ManualDeadline | undefined> {
    await ManualDeadlineStore.load();
    const trimmedTitle: string = title.trim();
    const trimmedDate: string = date.trim();
    const trimmedTime: string = time.trim();
    const normalizedTime: string = trimmedTime.length > 0 ? normalizeTimeText(trimmedTime) : '';
    if (trimmedTitle.length === 0 || !isValidDateText(trimmedDate)) {
      return undefined;
    }
    if (trimmedTime.length > 0 && normalizedTime.length === 0) {
      return undefined;
    }
    // 串行写队列：cache 快照必须在队列内、await 持久化之前执行（并发调用不丢更新）
    return enqueueWrite<ManualDeadline | undefined>(async (): Promise<ManualDeadline | undefined> => {
      const item: ManualDeadline = new ManualDeadline();
      item.id = 'md-' + Date.now() + '-' + Math.random().toString(36).substring(2, 8);
      item.title = trimmedTitle;
      item.date = trimmedDate;
      item.time = normalizedTime;
      item.course = course.trim();
      item.note = note.trim();
      item.createdAt = new Date().toISOString();
      const next: ManualDeadline[] = cache.slice();
      next.push(item);
      try {
        await PreferencesStorage.setJson<ManualDeadline[]>(StorageKeys.MANUAL_DEADLINES, next);
      } catch (e) {
        Log.w(LOG_TAG, 'append persist failed len=%{public}d', next.length);
        return undefined;
      }
      cache = next;
      broadcastChange();
      return item;
    });
  }

  /**
   * 按 id 删除：不存在或持久化失败返回 false；持久化成功后广播并返回 true。
   * 同一条被 AI 与页面先后删除时，第二次按「已不存在」返回 false，不报错。
   * 写走串行队列，与 append 互斥，避免并发丢更新。
   */
  static async remove(id: string): Promise<boolean> {
    await ManualDeadlineStore.load();
    const trimmed: string = id.trim();
    if (trimmed.length === 0) {
      return false;
    }
    return enqueueWrite<boolean>(async (): Promise<boolean> => {
      let removed: boolean = false;
      const next: ManualDeadline[] = [];
      for (let i: number = 0; i < cache.length; i++) {
        if (cache[i].id === trimmed) {
          removed = true;
        } else {
          next.push(cache[i]);
        }
      }
      if (!removed) {
        return false;
      }
      try {
        await PreferencesStorage.setJson<ManualDeadline[]>(StorageKeys.MANUAL_DEADLINES, next);
      } catch (e) {
        Log.w(LOG_TAG, 'remove persist failed len=%{public}d', next.length);
        return false;
      }
      cache = next;
      broadcastChange();
      return true;
    });
  }

  /** 已加载缓存中定位：id 精确 → 标题全等 → 标题包含（对齐 RN findManualDeadline） */
  static find(key: string): ManualDeadline | undefined {
    const trimmed: string = key.trim();
    if (trimmed.length === 0) {
      return undefined;
    }
    for (let i: number = 0; i < cache.length; i++) {
      if (cache[i].id === trimmed) {
        return cache[i];
      }
    }
    for (let i: number = 0; i < cache.length; i++) {
      if (cache[i].title === trimmed) {
        return cache[i];
      }
    }
    for (let i: number = 0; i < cache.length; i++) {
      if (cache[i].title.includes(trimmed)) {
        return cache[i];
      }
    }
    return undefined;
  }

  /** 加载（幂等）后定位（AI 工具首次调用时缓存未必已加载，用本入口） */
  static async findAsync(key: string): Promise<ManualDeadline | undefined> {
    await ManualDeadlineStore.load();
    return ManualDeadlineStore.find(key);
  }

  /** 订阅数据变更；返回订阅 id，页面在 aboutToDisappear 调 unsubscribe 取消 */
  static subscribe(listener: () => void): number {
    listenerSeq++;
    const entry: DeadlineListenerEntry = new DeadlineListenerEntry();
    entry.id = listenerSeq;
    entry.callback = listener;
    listenerEntries.push(entry);
    return entry.id;
  }

  /** 取消订阅（id 不存在时静默忽略） */
  static unsubscribe(id: number): void {
    for (let i: number = 0; i < listenerEntries.length; i++) {
      if (listenerEntries[i].id === id) {
        listenerEntries.splice(i, 1);
        return;
      }
    }
  }
}
