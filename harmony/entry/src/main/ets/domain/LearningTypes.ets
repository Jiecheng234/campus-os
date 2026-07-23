export class ScheduleEvent {
  name: string = '';
  location: string = '';
  dayOfWeek: number = 0;
  startPeriod: number = 0;
  endPeriod: number = 0;
  weeks: string = '';
  teacher: string = '';
  courseId: string = '';
}

export class CourseInfo {
  courseId: string = '';
  name: string = '';
  teacher: string = '';
  code: string = '';
  credits: number = 0;
  schedule: ScheduleEvent[] = [];
}

export class HomeworkItem {
  title: string = '';
  course: string = '';
  deadline: string = '';
  status: string = '';
  detailUrl: string = '';
  attachments: string[] = [];
  description: string = '';
  grade: string = '';
}

export class NotificationItem {
  title: string = '';
  publisher: string = '';
  time: string = '';
  isNew: boolean = false;
  detailUrl: string = '';
}

export class CourseFile {
  title: string = '';
  course: string = '';
  size: string = '';
  isNew: boolean = false;
  downloadUrl: string = '';
  extension: string = '';
}

export class LearningSnapshot {
  courses: CourseInfo[] = [];
  homework: HomeworkItem[] = [];
  notifications: NotificationItem[] = [];
  files: CourseFile[] = [];
  dataSource: string = '';
  lastSyncedAt: string = '';
}
