/**
 * GradesPage — 成绩查询（真实模式：教务 zhjw 成绩单 + GPA；演示模式：内置示例）
 * 按学期分组展示（新 → 旧），组头显示学期绩点（对齐原项目 GradesScreen bySemester）。
 */
import { Theme, SafeTop, Space, FontSize } from './Theme';
import { DetailHeader } from '../components/Ui';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusGrade, GradeReport } from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';

class GradeItem {
  name: string = '';
  credits: number = 0;
  grade: string = '';
  point: number = 0;
  semester: string = '';
}

/** 学期分组（gpaValid=false 表示整组无计入绩点课程，如全部 P/F） */
class SemesterGroup {
  semester: string = '';
  courses: GradeItem[] = [];
  gpa: number = 0;
  gpaValid: boolean = false;
  credits: number = 0;
}

function getMockGrades(): GradeItem[] {
  const list: GradeItem[] = [];
  const rows: string[][] = [
    ['英语阅读(4)', '2', 'B', '2025—2026 春季', '3.0'],
    ['物理实验A(1)', '1', 'A', '2025—2026 春季', '4.0'],
    ['体育(3)', '1', 'A-', '2025—2026 春季', '3.7'],
    ['高等数学(1)', '4', 'A', '2024—2025 秋季', '4.0'],
    ['大学物理B(2)', '4', 'A-', '2024—2025 秋季', '3.7'],
    ['线性代数', '3', 'B+', '2024—2025 秋季', '3.3'],
  ];
  for (let i: number = 0; i < rows.length; i++) {
    const g: GradeItem = new GradeItem();
    g.name = rows[i][0];
    g.credits = Number(rows[i][1]);
    g.grade = rows[i][2];
    g.semester = rows[i][3];
    g.point = Number(rows[i][4]);
    list.push(g);
  }
  return list;
}

function gradeColor(grade: string): string {
  if (grade.startsWith('A')) {
    return '#16A34A';
  }
  if (grade.startsWith('B')) {
    return '#D97706';
  }
  if (grade.startsWith('C')) {
    return '#DC2626';
  }
  return '#6B7280';
}

/** 学分绩 = Σ(学分×绩点)/Σ(学分)，point 为 NaN 的 P/F 课不计（对齐 fetchGrades 汇总口径） */
function computeGpa(items: GradeItem[]): number {
  let totalPoint: number = 0;
  let totalCredit: number = 0;
  for (let i: number = 0; i < items.length; i++) {
    if (isNaN(items[i].point)) {
      continue;
    }
    totalCredit += items[i].credits;
    totalPoint += items[i].credits * items[i].point;
  }
  return totalCredit > 0 ? totalPoint / totalCredit : 0;
}

/** 按学期首遇顺序分组（入参须为新 → 旧），绩点/学分按组内汇总 */
function buildSemesterGroups(items: GradeItem[]): SemesterGroup[] {
  const groups: SemesterGroup[] = [];
  const indexBySemester: Record<string, number> = {};
  for (let i: number = 0; i < items.length; i++) {
    const item: GradeItem = items[i];
    const key: string = item.semester.length > 0 ? item.semester : '未分学期';
    let idx: number = indexBySemester[key];
    if (idx === undefined) {
      const group: SemesterGroup = new SemesterGroup();
      group.semester = key;
      groups.push(group);
      idx = groups.length - 1;
      indexBySemester[key] = idx;
    }
    groups[idx].courses.push(item);
    groups[idx].credits += item.credits;
  }
  for (let i: number = 0; i < groups.length; i++) {
    const group: SemesterGroup = groups[i];
    group.gpa = computeGpa(group.courses);
    let hasGraded: boolean = false;
    for (let j: number = 0; j < group.courses.length; j++) {
      if (!isNaN(group.courses[j].point)) {
        hasGraded = true;
        break;
      }
    }
    group.gpaValid = hasGraded;
  }
  return groups;
}

@Component
export struct GradesPage {
  onBack: () => void = () => {};
  @State grades: GradeItem[] = getMockGrades();
  @State groups: SemesterGroup[] = [];
  @State gpaText: string = '0.00';
  @State subtitleText: string = '演示数据 · 登录后显示真实成绩';
  @State loading: boolean = false;
  @State errorText: string = '';
  private isReal: boolean = false;

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.loadGrades();
    } else {
      this.applyItems(this.grades);
      this.subtitleText = '演示数据 · 登录后显示真实成绩';
    }
  }

  private applyItems(items: GradeItem[]): void {
    this.grades = items;
    this.groups = buildSemesterGroups(items);
    this.gpaText = computeGpa(items).toFixed(2);
  }

  private async loadGrades(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const report: GradeReport = await SessionManager.getCampusDataService().fetchGrades();
      const items: GradeItem[] = [];
      // 倒序：最新学期在前
      for (let i: number = report.courses.length - 1; i >= 0; i--) {
        const c: CampusGrade = report.courses[i];
        const item: GradeItem = new GradeItem();
        item.name = c.name;
        item.credits = c.credit;
        item.grade = c.grade;
        item.point = c.point;
        item.semester = c.semester;
        items.push(item);
      }
      this.applyItems(items);
      // 总 GPA 用服务端口径（P/F 课不计入 totalCredit）
      this.gpaText = report.gpa.toFixed(2);
      this.subtitleText = `已修 ${report.allCredit} 学分（计入绩点 ${report.totalCredit}）· 共 ${items.length} 门`;
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
  }

  @Builder SemesterHeader(group: SemesterGroup) {
    Row() {
      Text(group.semester)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.text)
      Blank()
      if (group.gpaValid) {
        Text(`绩点 ${group.gpa.toFixed(2)}`)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.primary)
      }
      Text(`${group.credits} 学分`)
        .fontSize(12)
        .fontColor(Theme.textMuted)
        .margin({ left: Space.sm })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder GradeRow(item: GradeItem) {
    Row() {
      Column() {
        Text(item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${item.credits} 学分 · 绩点 ${isNaN(item.point) ? 'N/A' : item.point.toFixed(1)}`)
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(item.grade.length > 0 ? item.grade : '-')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(gradeColor(item.grade))
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .borderRadius(8)
        .backgroundColor(`${gradeColor(item.grade)}20`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '成绩查询', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      // GPA 汇总
      Column() {
        Text(this.subtitleText)
          .fontSize(13)
          .fontColor(Theme.textMuted)
          .textAlign(TextAlign.Center)
        Row({ space: Space.sm }) {
          Text('GPA')
            .fontSize(14)
            .fontColor(Theme.textMuted)
          Text(this.gpaText)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.primary)
          if (this.loading) {
            LoadingProgress()
              .width(18)
              .height(18)
              .color(Theme.primary)
              .margin({ left: Space.xs })
          }
        }
        .margin({ top: 4 })

        if (this.errorText.length > 0) {
          Column({ space: Space.sm }) {
            Text(this.errorText)
              .fontSize(FontSize.caption)
              .fontColor(Theme.warning)
              .textAlign(TextAlign.Center)
            Text('重试')
              .fontSize(FontSize.caption)
              .fontColor(Theme.primary)
              .padding({
                left: Space.md, right: Space.md,
                top: Space.xs, bottom: Space.xs,
              })
              .borderRadius(8)
              .border({ width: 1, color: Theme.primary })
              .onClick(() => { this.loadGrades(); })
          }
          .margin({ top: Space.sm })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 24, bottom: 20 })

      // 成绩列表（按学期分组）
      List() {
        ForEach(this.groups, (group: SemesterGroup) => {
          ListItemGroup({ header: this.SemesterHeader(group) }) {
            ForEach(group.courses, (item: GradeItem) => {
              ListItem() {
                this.GradeRow(item)
              }
            }, (item: GradeItem) => item.semester + '|' + item.name)
          }
          .divider({ strokeWidth: 0.5, color: Theme.divider })
        }, (group: SemesterGroup) => group.semester)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
