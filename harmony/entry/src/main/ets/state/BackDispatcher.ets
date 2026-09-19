/**
 * BackDispatcher — 系统返回事件分发器
 *
 * 子页面由集线页（LearningPage/CampusPage）的 subScreen 状态驱动、无路由栈，
 * 系统返回手势原本会直接退出应用。集线页在子页面打开时注册处理器，
 * @Entry 页在 onBackPress 中按当前激活标签页分发：消费返回事件关闭子页面。
 */

/** 返回处理器：返回 true 表示已消费本次返回事件 */
export type BackHandler = () => boolean;

/** 持有子页面的标签页归属 */
export enum BackOwner {
  LEARNING = 'learning',
  CAMPUS = 'campus',
}

interface BackEntry {
  owner: string;
  handler: BackHandler;
}

export class BackDispatcher {
  private static entries: BackEntry[] = [];

  /** 注册处理器（同一处理器按引用去重） */
  static push(owner: string, handler: BackHandler): void {
    BackDispatcher.remove(handler);
    const entry: BackEntry = { owner: owner, handler: handler };
    BackDispatcher.entries.push(entry);
  }

  /** 按引用移除处理器 */
  static remove(handler: BackHandler): void {
    for (let i: number = BackDispatcher.entries.length - 1; i >= 0; i--) {
      if (BackDispatcher.entries[i].handler === handler) {
        BackDispatcher.entries.splice(i, 1);
      }
    }
  }

  /** 分发给指定归属的栈顶处理器；返回是否已消费 */
  static dispatch(owner: string): boolean {
    for (let i: number = BackDispatcher.entries.length - 1; i >= 0; i--) {
      if (BackDispatcher.entries[i].owner === owner) {
        return BackDispatcher.entries[i].handler();
      }
    }
    return false;
  }
}
