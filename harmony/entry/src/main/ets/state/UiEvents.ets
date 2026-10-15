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

/**
 * 待处理导航目标（进程内内存态，不持久化）。
 *
 * 背景：emitNavigate 为即发即弃事件，冷启动时目标页（TabContent 惰性创建）
 * 尚未挂载、未订阅事件 → 首次点击丢失下钻目标。emitNavigate 在 emit 的同时
 * 将下钻目标记录于此；目标页挂载（aboutToAppear）时经 takePendingXxx() 消费。
 *
 * 语义：
 * - 每次 emitNavigate 覆盖写入（含空串），新目标自然覆盖旧目标；
 * - 字段级消费/清除：CampusPage 只消费 campusSub，LearningPage 只消费 learningTab；
 * - 取值即清除，避免目标页后续挂载时陈旧误触发。
 */
let pendingCampusSub: string = '';
let pendingLearningTab: string = '';

export function emitNavigate(target: NavTarget): void {
  // 先记录待处理下钻目标、后 emit：目标页未挂载时由其挂载后消费（FR-005/FR-006）；
  // 已挂载时订阅回调应用后会清除对应字段——若 emit 在前，回调清除会被随后的
  // 记录覆盖，留下陈旧目标（下次挂载误触发），故记录必须先于 emit。
  pendingCampusSub = target.campusSub;
  pendingLearningTab = target.learningTab;
  emitter.emit({ eventId: EVT_NAVIGATE }, {
    data: {
      'tab': target.tab,
      'campusSub': target.campusSub,
      'learningTab': target.learningTab
    } as Record<string, Object>
  });
}

/** 返回待处理的校园子页目标并将其清空（取值即清除） */
export function takePendingCampusSub(): string {
  const sub: string = pendingCampusSub;
  pendingCampusSub = '';
  return sub;
}

/** 返回待处理的学习子标签目标并将其清空（取值即清除） */
export function takePendingLearningTab(): string {
  const tab: string = pendingLearningTab;
  pendingLearningTab = '';
  return tab;
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
