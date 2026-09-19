/**
 * GradesPage — 成绩查询（真实模式：教务 zhjw 成绩单 + GPA；演示模式：内置示例）
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
  semester: string = '';
}

function getMockGrades(): GradeItem[] {
  const list: GradeItem[] = [];
  const rows: string[][] = [
    ['高等数学(1)', '4', 'A', ''],
    ['大学物理B(2)', '4', 'A-', ''],
    ['线性代数', '3', 'B+', ''],
    ['英语阅读(4)', '2', 'B', ''],
    ['物理实验A(1)', '1', 'A', ''],
    ['体育(3)', '1', 'A-', ''],
  ];
  for (let i: number = 0; i < rows.length; i++) {
    const g: GradeItem = new GradeItem();
    g.name = rows[i][0];
    g.credits = Number(rows[i][1]);
    g.grade = rows[i][2];
    g.semester = rows[i][3];
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

@Component
export struct GradesPage {
  onBack: () => void = () => {};
  @State grades: GradeItem[] = getMockGrades();
  @State gpaText: string = '3.72';
  @State subtitleText: string = '2025—2026 春季学期 · 演示数据';
  @State loading: boolean = false;
  @State errorText: string = '';
  private isReal: boolean = false;

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.loadGrades();
    }
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
        item.semester = c.semester;
        items.push(item);
      }
      this.grades = items;
      this.gpaText = report.gpa.toFixed(2);
      this.subtitleText = `已修 ${report.allCredit} 学分（计入绩点 ${report.totalCredit}）· 共 ${items.length} 门`;
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
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

      // 成绩列表
      List() {
        ForEach(this.grades, (item: GradeItem) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
                Text(item.semester.length > 0
                  ? `${item.credits} 学分 · ${item.semester}`
                  : `${item.credits} 学分`)
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
        })
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: Theme.divider })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
