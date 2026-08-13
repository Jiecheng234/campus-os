import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

class CourseSetItem {
  courseId: string = '';
  name: string = '';
  credits: number = 0;
  completed: boolean = false;
  grade: string = '';
}

class CourseSet {
  setId: string = '';
  name: string = '';
  requiredCredits: number = 0;
  earnedCredits: number = 0;
  items: CourseSetItem[] = [];
}

class ProgramData {
  programName: string = '';
  totalRequired: number = 0;
  totalEarned: number = 0;
  sets: CourseSet[] = [];
}

function getMockProgram(): ProgramData {
  const items1: CourseSetItem[] = [];
  const i1: CourseSetItem = new CourseSetItem();
  i1.name = '高等数学(1)'; i1.credits = 4; i1.completed = true; i1.grade = 'A';
  items1.push(i1);
  const i2: CourseSetItem = new CourseSetItem();
  i2.name = '高等数学(2)'; i2.credits = 4; i2.completed = false; i2.grade = '';
  items1.push(i2);
  const i3: CourseSetItem = new CourseSetItem();
  i3.name = '线性代数'; i3.credits = 3; i3.completed = true; i3.grade = 'B+';
  items1.push(i3);

  const items2: CourseSetItem[] = [];
  const i4: CourseSetItem = new CourseSetItem();
  i4.name = '大学物理B(1)'; i4.credits = 4; i4.completed = true; i4.grade = 'A-';
  items2.push(i4);
  const i5: CourseSetItem = new CourseSetItem();
  i5.name = '大学物理B(2)'; i5.credits = 4; i5.completed = false; i5.grade = '';
  items2.push(i5);

  const items3: CourseSetItem[] = [];
  const i6: CourseSetItem = new CourseSetItem();
  i6.name = '英语阅读(4)'; i6.credits = 2; i6.completed = true; i6.grade = 'B';
  items3.push(i6);

  const set1: CourseSet = new CourseSet();
  set1.setId = 'math'; set1.name = '数学基础'; set1.requiredCredits = 14; set1.earnedCredits = 7; set1.items = items1;
  const set2: CourseSet = new CourseSet();
  set2.setId = 'physics'; set2.name = '物理基础'; set2.requiredCredits = 8; set2.earnedCredits = 4; set2.items = items2;
  const set3: CourseSet = new CourseSet();
  set3.setId = 'english'; set3.name = '外语能力'; set3.requiredCredits = 4; set3.earnedCredits = 2; set3.items = items3;

  const data: ProgramData = new ProgramData();
  data.programName = '计算机科学与技术';
  data.totalRequired = 170;
  data.totalEarned = 85;
  data.sets = [set1, set2, set3];
  return data;
}

@Component
export struct ProgramPage {
  onBack: () => void = () => {};
  private data = getMockProgram();

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '培养方案', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          Column() {
            Text(this.data.programName)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 12 })

            Row() {
              Text(`已完成 ${this.data.totalEarned} / ${this.data.totalRequired} 学分`)
                .fontSize(14)
                .fontColor(Theme.primary)
            }
            .width('100%')

            Row() {
              Row()
                .width(Math.floor(this.data.totalEarned / this.data.totalRequired * 100) + '%')
                .height(8)
                .borderRadius(4)
                .backgroundColor(Theme.primary)
            }
            .width('100%')
            .height(8)
            .borderRadius(4)
            .backgroundColor(Theme.surfaceAlt)
            .margin({ top: 8 })
          }
          .width('100%')
          .padding(20)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          ForEach(this.data.sets, (set: CourseSet) => {
            Column() {
              Row() {
                Text(set.name)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
                Blank()
                Text(`${set.earnedCredits}/${set.requiredCredits} 学分`)
                  .fontSize(13)
                  .fontColor(Theme.primary)
              }
              .width('100%')
              .margin({ bottom: 10 })

              ForEach(set.items, (item: CourseSetItem) => {
                Row() {
                  Row()
                    .width(6)
                    .height(6)
                    .borderRadius(3)
                    .backgroundColor(item.completed ? '#16A34A' : Theme.textMuted)
                    .margin({ right: 10 })

                  Text(item.name)
                    .fontSize(14)
                    .fontColor(item.completed ? Theme.text : Theme.textMuted)
                    .layoutWeight(1)

                  Text(`${item.credits} 学分`)
                    .fontSize(12)
                    .fontColor(Theme.textMuted)
                    .margin({ right: 12 })

                  Text(item.grade)
                    .fontSize(13)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(item.completed ? '#16A34A' : Theme.textMuted)
                }
                .width('100%')
                .padding({ top: 6, bottom: 6 })
              })
            }
            .width('100%')
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16, bottom: 12 })
          })

          Blank().height(32)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
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
