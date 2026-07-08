/**
 * 首页 Mock 数据（硬编码）
 */
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
  a1.label = '查空教室';
  actions.push(a1);

  const a2: QuickAction = new QuickAction();
  a2.icon = '📚';
  a2.label = '图书馆座位';
  actions.push(a2);

  const a3: QuickAction = new QuickAction();
  a3.icon = '📝';
  a3.label = '添加 DDL';
  actions.push(a3);
  return actions;
}

export function getGreeting(): string {
  const hour: number = new Date().getHours();
  if (hour < 6) {
    return '夜深了';
  } else if (hour < 12) {
    return '早上好';
  } else if (hour < 14) {
    return '中午好';
  } else if (hour < 18) {
    return '下午好';
  } else {
    return '晚上好';
  }
}

export function getDateString(): string {
  const now: Date = new Date();
  const weekdays: string[] = ['日', '一', '二', '三', '四', '五', '六'];
  return `${now.getMonth() + 1}月${now.getDate()}日 周${weekdays[now.getDay()]}`;
}
