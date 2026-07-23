export class CrSemester {
  id: string = '';
  name: string = '';
  startDate: string = '';
  endDate: string = '';
}

export class SelectedCourse {
  courseId: string = '';
  name: string = '';
  teacher: string = '';
  credits: number = 0;
  scheduleText: string = '';
  selectionStage: string = '';
  willType: string = '';
}

export class CourseSearchParams {
  keyword: string = '';
  courseType: string = '';
  department: string = '';
  page: number = 1;
}

export class CrRemainingInfo {
  semester: CrSemester = new CrSemester();
  remainElectiveCredits: number = 0;
}
