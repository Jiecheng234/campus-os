export class PersonalEvent {
  id: string = '';
  title: string = '';
  dayOfWeek: number = 0;
  startPeriod: number = 0;
  endPeriod: number = 0;
  location: string = '';
  note: string = '';
  createdAt: string = '';
}

export class SemesterCalendar {
  semesterId: string = '';
  semesterName: string = '';
  startDate: string = '';
  endDate: string = '';
  weeks: number = 0;
  currentWeekIndex: number = 0;
}

export class CampusSchedule {
  scheduleId: string = '';
  semesterId: string = '';
  events: ScheduleEvent[] = [];
}
