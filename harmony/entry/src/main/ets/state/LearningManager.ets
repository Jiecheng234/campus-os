import { LearningSnapshot, CourseInfo, HomeworkItem, NotificationItem, CourseFile, ScheduleEvent } from '../domain/LearningTypes';
import { StateManager, DataSourceType } from './StateManager';

export class LearningManager {
  static setSnapshot(snapshot: LearningSnapshot): void {
    StateManager.learningData = snapshot;
  }

  static getCourses(): CourseInfo[] {
    return StateManager.learningData.courses;
  }

  static getHomework(): HomeworkItem[] {
    return StateManager.learningData.homework;
  }

  static getNotifications(): NotificationItem[] {
    return StateManager.learningData.notifications;
  }

  static getFiles(): CourseFile[] {
    return StateManager.learningData.files;
  }

  static getTodaySchedule(): ScheduleEvent[] {
    const today: Date = new Date();
    const dayOfWeek: number = today.getDay();
    const mappedDay: number = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
    const all: CourseInfo[] = StateManager.learningData.courses;
    const events: ScheduleEvent[] = [];
    for (let i: number = 0; i < all.length; i++) {
      const schedule: ScheduleEvent[] = all[i].schedule;
      for (let j: number = 0; j < schedule.length; j++) {
        if (schedule[j].dayOfWeek === mappedDay) {
          events.push(schedule[j]);
        }
      }
    }
    return events;
  }

  static setDataSource(source: DataSourceType): void {
    StateManager.dataSource = source;
  }

  static getDataSource(): DataSourceType {
    return StateManager.dataSource;
  }
}
