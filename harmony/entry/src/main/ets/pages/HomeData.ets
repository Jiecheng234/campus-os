/**
 * 首页 Mock 数据（硬编码）
 *
 * 【i18n】getGreeting/getQuickActions 的 label 返回词典键（由页面 tr() 解析）；
 * getDateString 返回按当前 locale 翻译后的日期文案（显式传 I18n.getLocale()）。
 * 导出名与函数签名保持不变。
 */
import { I18n } from '../utils/I18n';

export class CourseItem {
  time: string = '';
  title: string = '';
  location: string = '';
}

export class BriefingMetrics {
  classes: number = 0;
  tasks: number = 0;
  unread: number = 0;
}

export class QuickAction {
  label: string = '';
  icon: string = '';
  /** 目标底部 Tab（-1 = 未接入，保留 toast 提示） */
  targetTab: number = -1;
  /** 校园 Tab 下钻子页键（classroom/grades/news...），空则不下钻 */
  campusSub: string = '';
  /** 学习 Tab 子标签（课程/作业/通知/文件），空则不切换 */
  learningTab: string = '';
}

export function getTodayCourses(): CourseItem[] {
  const list: CourseItem[] = [];
  const c1: CourseItem = new CourseItem();
  c1.time = '08:00 - 09:35';
  c1.title = '高等数学(1)';
  c1.location = '六教 6A118';
  list.push(c1);

  const c2: CourseItem = new CourseItem();
  c2.time = '10:10 - 11:45';
  c2.title = '大学物理B(2)';
  c2.location = '四教 4302';
  list.push(c2);

  const c3: CourseItem = new CourseItem();
  c3.time = '14:00 - 15:35';
  c3.title = '线性代数';
  c3.location = '六教 6A215';
  list.push(c3);
  return list;
}

export function getBriefingMetrics(): BriefingMetrics {
  const m: BriefingMetrics = new BriefingMetrics();
  m.classes = 3;
  m.tasks = 2;
  m.unread = 1;
  return m;
}

export function getQuickActions(): QuickAction[] {
  const actions: QuickAction[] = [];
  const a1: QuickAction = new QuickAction();
  a1.icon = '🏫';
  a1.label = 'home.qa.emptyClassroom';
  a1.targetTab = 3;
  a1.campusSub = 'classroom';
  actions.push(a1);

  const a2: QuickAction = new QuickAction();
  a2.icon = '📚';
  a2.label = 'home.qa.librarySeat';
  actions.push(a2);

  const a3: QuickAction = new QuickAction();
  a3.icon = '📝';
  a3.label = 'home.qa.addDdl';
  a3.targetTab = 1;
  a3.learningTab = '作业';
  actions.push(a3);
  return actions;
}

/** 问候语：返回词典键（home.greet*），由页面经 tr() 按当前语言解析 */
export function getGreeting(): string {
  const hour: number = new Date().getHours();
  if (hour < 6) {
    return 'home.greetNight';
  } else if (hour < 12) {
    return 'home.greetMorning';
  } else if (hour < 14) {
    return 'home.greetNoon';
  } else if (hour < 18) {
    return 'home.greetAfternoon';
  } else {
    return 'home.greetEvening';
  }
}

/** 日期文案：按当前 locale 翻译输出（显式传入 locale，切换语言后由页面重渲染刷新） */
export function getDateString(): string {
  const now: Date = new Date();
  const locale: string = I18n.getLocale();
  return I18n.tp('home.date', {
    'm': String(now.getMonth() + 1),
    'd': String(now.getDate()),
    'w': I18n.t('home.weekday' + String(now.getDay()), locale)
  }, locale);
}
