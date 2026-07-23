import { PersonalEvent, CampusSchedule, SemesterCalendar } from '../domain/ScheduleTypes';
import { StateManager } from './StateManager';
import { generateUUID } from '../utils/CryptoUtils';

export class ScheduleManager {
  static getPersonalEvents(): PersonalEvent[] {
    return StateManager.personalEvents;
  }

  static addPersonalEvent(title: string, dayOfWeek: number, startPeriod: number, endPeriod: number, location: string, note: string): PersonalEvent {
    const event: PersonalEvent = new PersonalEvent();
    event.id = generateUUID();
    event.title = title;
    event.dayOfWeek = dayOfWeek;
    event.startPeriod = startPeriod;
    event.endPeriod = endPeriod;
    event.location = location;
    event.note = note;
    event.createdAt = new Date().toISOString();
    StateManager.personalEvents = [event].concat(StateManager.personalEvents);
    return event;
  }

  static removePersonalEvent(id: string): void {
    const kept: PersonalEvent[] = [];
    for (let i: number = 0; i < StateManager.personalEvents.length; i++) {
      if (StateManager.personalEvents[i].id !== id) {
        kept.push(StateManager.personalEvents[i]);
      }
    }
    StateManager.personalEvents = kept;
  }

  static getEventsForDay(dayOfWeek: number): PersonalEvent[] {
    const result: PersonalEvent[] = [];
    for (let i: number = 0; i < StateManager.personalEvents.length; i++) {
      if (StateManager.personalEvents[i].dayOfWeek === dayOfWeek) {
        result.push(StateManager.personalEvents[i]);
      }
    }
    return result;
  }

  static setCampusSchedules(schedules: CampusSchedule[]): void {
    StateManager.campusSchedules = schedules;
  }

  static setSemesterCalendar(calendar: SemesterCalendar): void {
    StateManager.semesterCalendar = calendar;
  }

  static getCurrentWeek(): number {
    return StateManager.semesterCalendar.currentWeekIndex;
  }
}
