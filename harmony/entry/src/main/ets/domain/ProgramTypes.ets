export class CourseSetItem {
  courseId: string = '';
  name: string = '';
  credits: number = 0;
  completed: boolean = false;
  grade: string = '';
}

export class CourseSetCompletion {
  setId: string = '';
  setName: string = '';
  requiredCredits: number = 0;
  earnedCredits: number = 0;
  items: CourseSetItem[] = [];
}

export class ProgramCompletion {
  programId: string = '';
  programName: string = '';
  totalRequired: number = 0;
  totalEarned: number = 0;
  courseSets: CourseSetCompletion[] = [];
}
