import { CourseInfo } from './LearningTypes';

export class ManualDeadline {
  id: string = '';
  title: string = '';
  date: string = '';
  time: string = '';
  course: string = '';
  note: string = '';
  createdAt: string = '';
  parentCourse: CourseInfo | undefined = undefined;
}

export class DeadlineListItem {
  type: string = '';
  id: string = '';
  title: string = '';
  course: string = '';
  deadline: string = '';
  status: string = '';
  note: string = '';
}
