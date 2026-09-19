/**
 * UiEvents — 跨页面 UI 导航事件（emitter 总线）
 *
 * 用途：首页快捷操作 → 切换底部 Tab / 打开校园子页 / 切换学习子标签。
 * Tab 容器（Index）与各 Tab 页（CampusPage/LearningPage）各自订阅，
 * 携带字段按需消费（campusSub / learningTab 为空则忽略）。
 */
import { emitter } from '@kit.BasicServicesKit';

export const EVT_NAVIGATE: number = 10001;

/** 导航目标：tab 为底部标签索引；campusSub/learningTab 为可选下钻目标 */
export class NavTarget {
  tab: number = 0;
  campusSub: string = '';
  learningTab: string = '';
}

export function emitNavigate(target: NavTarget): void {
  emitter.emit({ eventId: EVT_NAVIGATE }, {
    data: {
      'tab': target.tab,
      'campusSub': target.campusSub,
      'learningTab': target.learningTab
    } as Record<string, Object>
  });
}

/** 从 emitter EventData.data 解析 NavTarget（字段缺失时保持默认值） */
export function readNavTarget(data: Record<string, Object>): NavTarget {
  const t: NavTarget = new NavTarget();
  const tab: Object | undefined = data['tab'];
  if (typeof tab === 'number') {
    t.tab = tab;
  }
  const sub: Object | undefined = data['campusSub'];
  if (typeof sub === 'string') {
    t.campusSub = sub;
  }
  const lt: Object | undefined = data['learningTab'];
  if (typeof lt === 'string') {
    t.learningTab = lt;
  }
  return t;
}

/** 订阅句柄（消费者只透传给 unsubscribeNavigate，不感知 emitter 类型） */
export class NavigateSubscription {
  cb: (event: emitter.EventData) => void = (event: emitter.EventData) => {};
}

/** 统一订阅入口，返回句柄供 unsubscribeNavigate 使用 */
export function subscribeNavigate(handler: (target: NavTarget) => void): NavigateSubscription {
  const sub: NavigateSubscription = new NavigateSubscription();
  sub.cb = (event: emitter.EventData) => {
    const d: Record<string, Object> = event.data ?? {};
    handler(readNavTarget(d));
  };
  emitter.on({ eventId: EVT_NAVIGATE }, sub.cb);
  return sub;
}

export function unsubscribeNavigate(sub: NavigateSubscription): void {
  emitter.off(EVT_NAVIGATE, sub.cb);
}
