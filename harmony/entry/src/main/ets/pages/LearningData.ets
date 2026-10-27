/**
 * LearningPage Mock Data
 *
 * 演示原始数据（学习详情深链 US5）：getDemoCampus* 提供字段完整的
 * Campus* 原始对象（id 带 demo- 前缀、courseId 关联），供详情页按课程
 * 过滤与下钻；不含可请求的 url/previewUrl/downloadUrl（FR-023 演示零请求）。
 */
import { CampusCourse, CampusHomework, CampusNotification, CampusFile } from '../services/campus/CampusDataService';

export class CourseItem {
  name: string = '';
  teacher: string = '';
  code: string = '';
}

export class HomeworkItem {
  /** 条目标识（手动 DDL 为 md- 前缀 id；远程作业为 xszyid；演示项为 demo- 前缀） */
  id: string = '';
  title: string = '';
  course: string = '';
  deadline: string = '';
  status: string = '';
  /** 是否手动 DDL（区分来源徽标与删除入口；远程项 false） */
  manual: boolean = false;
  /** 备注（手动 DDL 可选备注；远程项空） */
  note: string = '';
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

/** 演示日期（相对今天偏移 N 天，YYYY-MM-DD；演示 DDL 永远"未来几天内"，排序/过期判定可复用） */
function demoDateStr(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

/** 演示课程原始数据（与 getCourses() 同源对齐，id 带 demo- 前缀） */
export function getDemoCampusCourses(): CampusCourse[] {
  const list: CampusCourse[] = [];
  const c1: CampusCourse = new CampusCourse();
  c1.id = 'demo-course-1'; c1.name = '高等数学(1)'; c1.teacher = '李老师'; c1.code = 'MATH101';
  list.push(c1);
  const c2: CampusCourse = new CampusCourse();
  c2.id = 'demo-course-2'; c2.name = '大学物理B(2)'; c2.teacher = '王老师'; c2.code = 'PHYS201';
  list.push(c2);
  const c3: CampusCourse = new CampusCourse();
  c3.id = 'demo-course-3'; c3.name = '线性代数'; c3.teacher = '张老师'; c3.code = 'MATH201';
  list.push(c3);
  return list;
}

/** 演示作业原始数据（未提交、截止时间相对今天，url 为空保证详情零请求） */
export function getDemoCampusHomework(): CampusHomework[] {
  const list: CampusHomework[] = [];
  const h1: CampusHomework = new CampusHomework();
  h1.id = 'demo-hw-1'; h1.courseId = 'demo-course-1'; h1.courseName = '高等数学(1)';
  h1.title = '习题集 第5章'; h1.deadline = `${demoDateStr(2)} 23:59`; h1.status = '即将截止';
  list.push(h1);
  const h2: CampusHomework = new CampusHomework();
  h2.id = 'demo-hw-2'; h2.courseId = 'demo-course-2'; h2.courseName = '大学物理B(2)';
  h2.title = '实验报告 2'; h2.deadline = `${demoDateStr(5)} 17:00`; h2.status = '进行中';
  list.push(h2);
  return list;
}

/** 演示通知原始数据（正文内联，content 非空保证详情页不补拉） */
export function getDemoCampusNotifications(): CampusNotification[] {
  const list: CampusNotification[] = [];
  const n1: CampusNotification = new CampusNotification();
  n1.id = 'demo-notif-1'; n1.courseId = 'demo-course-1'; n1.courseName = '高等数学(1)';
  n1.title = '期中习题课调整通知'; n1.publisher = '李老师'; n1.publishTime = '7月22日';
  n1.isNew = true;
  n1.content = '本周习题课调整到周四 19:20，地点改到六教 6A101，请携带习题集第 5 章。';
  list.push(n1);
  const n2: CampusNotification = new CampusNotification();
  n2.id = 'demo-notif-2'; n2.courseId = 'demo-course-2'; n2.courseName = '大学物理B(2)';
  n2.title = '实验报告提交要求'; n2.publisher = '王老师'; n2.publishTime = '7月20日';
  n2.isNew = false;
  n2.content = '实验报告需在截止时间前提交纸质版与电子版各一份，电子版命名格式：学号-姓名-实验2。';
  list.push(n2);
  return list;
}

/** 演示资料原始数据（无 downloadUrl/previewUrl：预览/下载按钮提示演示态，零请求） */
export function getDemoCampusFiles(): CampusFile[] {
  const list: CampusFile[] = [];
  const f1: CampusFile = new CampusFile();
  f1.id = 'demo-file-1'; f1.fileId = 'demo-wj-1'; f1.courseId = 'demo-course-1'; f1.courseName = '高等数学(1)';
  f1.title = '第5章习题参考答案.pdf'; f1.size = '1.2 MB'; f1.isNew = true;
  f1.description = '第 5 章习题的参考答案，供订正使用。'; f1.uploadTime = '7月20日';
  list.push(f1);
  const f2: CampusFile = new CampusFile();
  f2.id = 'demo-file-2'; f2.fileId = 'demo-wj-2'; f2.courseId = 'demo-course-2'; f2.courseName = '大学物理B(2)';
  f2.title = '实验报告模板.docx'; f2.size = '45 KB'; f2.isNew = false;
  f2.description = ''; f2.uploadTime = '7月18日';
  list.push(f2);
  return list;
}
