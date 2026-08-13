import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

class PETestResult {
  name: string = '';
  score: number = 0;
  grade: string = '';
  standard: string = '';
  date: string = '';
}

function getMockPETest(): PETestResult[] {
  const list: PETestResult[] = [];
  const r1: PETestResult = new PETestResult();
  r1.name = '50米跑'; r1.score = 78; r1.grade = '良好'; r1.standard = '≥70'; r1.date = '2025-11-15';
  list.push(r1);
  const r2: PETestResult = new PETestResult();
  r2.name = '1000米跑'; r2.score = 85; r2.grade = '优秀'; r2.standard = '≥80'; r2.date = '2025-11-15';
  list.push(r2);
  const r3: PETestResult = new PETestResult();
  r3.name = '立定跳远'; r3.score = 72; r3.grade = '良好'; r3.standard = '≥70'; r3.date = '2025-11-15';
  list.push(r3);
  const r4: PETestResult = new PETestResult();
  r4.name = '引体向上'; r4.score = 65; r4.grade = '及格'; r4.standard = '≥60'; r4.date = '2025-11-15';
  list.push(r4);
  const r5: PETestResult = new PETestResult();
  r5.name = '坐位体前屈'; r5.score = 90; r5.grade = '优秀'; r5.standard = '≥80'; r5.date = '2025-11-15';
  list.push(r5);
  const r6: PETestResult = new PETestResult();
  r6.name = '肺活量'; r6.score = 82; r6.grade = '优秀'; r6.standard = '≥80'; r6.date = '2025-11-15';
  list.push(r6);
  return list;
}

function gradeColor(grade: string): string {
  if (grade === '优秀') { return '#16A34A'; }
  if (grade === '良好') { return '#CA8A04'; }
  if (grade === '及格') { return '#D97706'; }
  return '#DC2626';
}

@Component
export struct PETestPage {
  onBack: () => void = () => {};
  private results: PETestResult[] = getMockPETest();
  private totalScore: number = 472;
  private totalGrade: string = '良好';

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '体测成绩', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Column() {
        Text('2025-2026 学年度')
          .fontSize(13)
          .fontColor(Theme.textMuted)
        Text(`${this.totalScore} 分  ·  ${this.totalGrade}`)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(gradeColor(this.totalGrade))
          .margin({ top: 4 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 24, bottom: 20 })

      List() {
        ForEach(this.results, (item: PETestResult) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
                Text(item.date)
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text(String(item.score))
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(gradeColor(item.grade))
                Text(item.grade)
                  .fontSize(11)
                  .fontColor(gradeColor(item.grade))
              }
              .alignItems(HorizontalAlign.End)
              .margin({ right: 4 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
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
