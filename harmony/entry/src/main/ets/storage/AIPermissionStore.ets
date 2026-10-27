import { Log } from '../utils/Logger';
import { PreferencesStorage } from './PreferencesStorage';
import { StorageKeys } from './StorageKeys';

const TAG: string = 'AIPermissionStore';

/** 加载状态常量：idle=未加载 ok=成功 failed=失败（可重试） */
const LOAD_IDLE: string = 'idle';
const LOAD_OK: string = 'ok';
const LOAD_FAILED: string = 'failed';

/**
 * AI 工具权限开关仓库（ai-governance 特性）。
 * - key 为权限键（AgentToolDef.permission），value 为 true 表示禁用
 * - 持久化到 PreferencesStorage（StorageKeys.AI_DISABLED_PERMISSIONS）
 * - 读取失败标记 failed：setDisabled 拒绝写入并上抛（不覆盖其他已禁用权限），
 *   ensureLoaded 可重试；成功后幂等
 * - 写操作走串行队列，toPersist 在队列任务内基于最新内存计算
 * - EntryAbility 启动时 ensureLoaded 预热；运行期同步读内存
 */
export class AIPermissionStore {
  private static disabled: Record<string, boolean> = {};
  private static loadState: string = LOAD_IDLE;
  /** 串行写队列：避免并发 setDisabled 相互覆盖 */
  private static writeChain: Promise<void> = Promise.resolve();

  /** 启动预热 / 失败重试：成功后幂等（EntryAbility.onCreate 调用） */
  static ensureLoaded(): Promise<void> {
    if (AIPermissionStore.loadState === LOAD_OK) {
      return Promise.resolve();
    }
    const next: Promise<void> = AIPermissionStore.writeChain.then((): Promise<void> => {
      return AIPermissionStore.loadInternal();
    });
    AIPermissionStore.writeChain = next.catch((): void => {
    });
    return next;
  }

  /** 是否已成功加载 */
  static isLoaded(): boolean {
    return AIPermissionStore.loadState === LOAD_OK;
  }

  private static async loadInternal(): Promise<void> {
    try {
      const parsed: Record<string, boolean> | undefined =
        await PreferencesStorage.getJson<Record<string, boolean>>(StorageKeys.AI_DISABLED_PERMISSIONS);
      const clean: Record<string, boolean> = {};
      if (parsed !== undefined && parsed !== null) {
        const keys: string[] = Object.keys(parsed);
        for (const key of keys) {
          const value: boolean = parsed[key];
          if (value === true) {
            clean[key] = true;
          }
        }
      }
      AIPermissionStore.disabled = clean;
      AIPermissionStore.loadState = LOAD_OK;
    } catch (error) {
      // 读取失败：保留内存现状并标记 failed——setDisabled 拒绝写入，
      // 避免以空集落盘覆盖其他已禁用权限；ensureLoaded 可重试
      AIPermissionStore.loadState = LOAD_FAILED;
      Log.w(TAG, 'permission load failed');
      throw new Error(`AIPermissionStore load failed: ${String(error)}`);
    }
  }

  /** 同步查询：该权限是否被用户禁用（未加载完成时视为未禁用） */
  static isDisabled(permission: string): boolean {
    const value: boolean | undefined = AIPermissionStore.disabled[permission];
    return value === true;
  }

  /** 当前全部被禁用的权限键（供 AgentTools.all 过滤） */
  static disabledKeys(): string[] {
    const out: string[] = [];
    const keys: string[] = Object.keys(AIPermissionStore.disabled);
    for (const key of keys) {
      if (AIPermissionStore.disabled[key] === true) {
        out.push(key);
      }
    }
    return out;
  }

  /**
   * 设置单个权限开关并持久化（true=禁用），走串行写队列。
   * 读取失败时直接上抛、不写入；持久化失败回滚该键内存后上抛，
   * 由调用方（页面）负责 toast 与 UI 回滚——内存、持久化与 UI 三者一致。
   */
  static setDisabled(permission: string, disabled: boolean): Promise<void> {
    const next: Promise<void> = AIPermissionStore.writeChain.then((): Promise<void> => {
      return AIPermissionStore.setDisabledInternal(permission, disabled);
    });
    AIPermissionStore.writeChain = next.catch((): void => {
    });
    return next;
  }

  private static async setDisabledInternal(permission: string, disabled: boolean): Promise<void> {
    if (AIPermissionStore.loadState !== LOAD_OK) {
      // 未加载 / 上次读取失败：先（重）试加载；失败上抛，本次不写入
      await AIPermissionStore.loadInternal();
    }
    const prev: boolean | undefined = AIPermissionStore.disabled[permission];
    AIPermissionStore.disabled[permission] = disabled;
    // 在队列任务内基于最新内存计算落盘内容（后续排队写入不会被旧快照覆盖）
    const toPersist: Record<string, boolean> = AIPermissionStore.compact();
    try {
      await PreferencesStorage.setJson<Record<string, boolean>>(StorageKeys.AI_DISABLED_PERMISSIONS, toPersist);
    } catch (error) {
      // 回滚内存：键原不存在 → 重建映射剔除该键（ArkTS 禁 delete，重建代替）
      if (prev === undefined) {
        const restored: Record<string, boolean> = {};
        const keys: string[] = Object.keys(AIPermissionStore.disabled);
        for (const key of keys) {
          if (key !== permission) {
            restored[key] = AIPermissionStore.disabled[key];
          }
        }
        AIPermissionStore.disabled = restored;
      } else {
        AIPermissionStore.disabled[permission] = prev;
      }
      // ArkTS 禁抛任意类型：包装为 Error（页面 catch 只关心失败本身）
      throw new Error(`AIPermissionStore persist failed: ${String(error)}`);
    }
  }

  /** 仅保留 true 条目（false / 空值不入库，保持存储精简；ArkTS 禁用 delete 重建代替） */
  private static compact(): Record<string, boolean> {
    const next: Record<string, boolean> = {};
    const keys: string[] = Object.keys(AIPermissionStore.disabled);
    for (const key of keys) {
      if (AIPermissionStore.disabled[key] === true) {
        next[key] = true;
      }
    }
    return next;
  }
}
