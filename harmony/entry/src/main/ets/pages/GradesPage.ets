/**
 * GradesPage — 成绩查询
 */
import { Theme, SafeTop } from './Theme';

class GradeItem {
  name: string = '';
  credits: number = 0;
  grade: string = '';
}

function getMockGrades(): GradeItem[] {
  const list: GradeItem[] = [];
  const g1: GradeItem = new GradeItem();
  g1.name = '高等数学(1)'; g1.credits = 4; g1.grade = 'A';
  list.push(g1);
  const g2: GradeItem = new GradeItem();
  g2.name = '大学物理B(2)'; g2.credits = 4; g2.grade = 'A-';
  list.push(g2);
  const g3: GradeItem = new GradeItem();
  g3.name = '线性代数'; g3.credits = 3; g3.grade = 'B+';
  list.push(g3);
  const g4: GradeItem = new GradeItem();
  g4.name = '英语阅读(4)'; g4.credits = 2; g4.grade = 'B';
  list.push(g4);
  const g5: GradeItem = new GradeItem();
  g5.name = '物理实验A(1)'; g5.credits = 1; g5.grade = 'A';
  list.push(g5);
  const g6: GradeItem = new GradeItem();
  g6.name = '体育(3)'; g6.credits = 1; g6.grade = 'A-';
  list.push(g6);
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
  private grades: GradeItem[] = getMockGrades();

  build() {
    Column() {
      SafeTop()

      Row() {
        Button('← 返回')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(Theme.primary)
          .backgroundColor(Theme.background)
          .onClick(() => { this.onBack(); })

        Text('成绩查询')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 60 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })

      Divider().color(Theme.divider)

      // 学期信息 + GPA
      Column() {
        Text('2025—2026 春季学期')
          .fontSize(13)
          .fontColor(Theme.textMuted)
        Text('GPA: 3.72')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary)
          .margin({ top: 4 })
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
                Text(`${item.credits} 学分`)
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text(item.grade)
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
