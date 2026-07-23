/**
 * LearningPage Mock Data
 */
export class CourseItem {
  name: string = '';
  teacher: string = '';
  code: string = '';
}

export class HomeworkItem {
  title: string = '';
  course: string = '';
  deadline: string = '';
  status: string = '';
}

export class NotificationItem {
  title: string = '';
  publisher: string = '';
  time: string = '';
  isNew: boolean = false;
}

export class FileItem {
  title: string = '';
  course: string = '';
  size: string = '';
  isNew: boolean = false;
}

export class DeadlineForm {
  title: string = '';
  date: string = '';
  time: string = '';
  course: string = '';
  note: string = '';
}

export function getCourses(): CourseItem[] {
  const list: CourseItem[] = [];
  const c1: CourseItem = new CourseItem();
  c1.name = '高等数学(1)'; c1.teacher = '李老师'; c1.code = 'MATH101';
  list.push(c1);
  const c2: CourseItem = new CourseItem();
  c2.name = '大学物理B(2)'; c2.teacher = '王老师'; c2.code = 'PHYS201';
  list.push(c2);
  const c3: CourseItem = new CourseItem();
  c3.name = '线性代数'; c3.teacher = '张老师'; c3.code = 'MATH201';
  list.push(c3);
  return list;
}

export function getHomeworkList(): HomeworkItem[] {
  const list: HomeworkItem[] = [];
  const h1: HomeworkItem = new HomeworkItem();
  h1.title = '习题集 第5章'; h1.course = '高等数学(1)';
  h1.deadline = '7月25日 23:59'; h1.status = '即将截止';
  list.push(h1);
  const h2: HomeworkItem = new HomeworkItem();
  h2.title = '实验报告 2'; h2.course = '大学物理B(2)';
  h2.deadline = '7月28日 17:00'; h2.status = '进行中';
  list.push(h2);
  return list;
}

export function getNotifications(): NotificationItem[] {
  const list: NotificationItem[] = [];
  const n1: NotificationItem = new NotificationItem();
  n1.title = '补退选课通知'; n1.publisher = '教务处';
  n1.time = '7月22日'; n1.isNew = true;
  list.push(n1);
  return list;
}

export function getFiles(): FileItem[] {
  return [];
}

export function getTodayDateStr(): string {
  const d: Date = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
