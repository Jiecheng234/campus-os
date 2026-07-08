/**
 * SchedulePage — 课表页（周网格 + 周选择器）
 */
import { Theme, SafeTop } from './Theme';

class ScheduleCourse {
  day: number = 0;
  period: number = 0;
  title: string = '';
  location: string = '';
  span: number = 1;
}

const WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const PERIODS: string[] = ['08:00', '10:10', '13:30', '15:20', '19:20'];

function getMockCourses(): ScheduleCourse[] {
  const courses: ScheduleCourse[] = [];
  const c1: ScheduleCourse = new ScheduleCourse();
  c1.day = 0; c1.period = 0; c1.title = '高等数学'; c1.location = '六教6A118';
  courses.push(c1);

  const c2: ScheduleCourse = new ScheduleCourse();
  c2.day = 1; c2.period = 1; c2.title = '大学物理'; c2.location = '四教4302';
  courses.push(c2);

  const c3: ScheduleCourse = new ScheduleCourse();
  c3.day = 0; c3.period = 2; c3.title = '线性代数'; c3.location = '六教6A215';
  courses.push(c3);

  const c4: ScheduleCourse = new ScheduleCourse();
  c4.day = 2; c4.period = 0; c4.title = '英语阅读'; c4.location = '五教5102';
  courses.push(c4);

  const c5: ScheduleCourse = new ScheduleCourse();
  c5.day = 3; c5.period = 3; c5.title = '实验课'; c5.location = '物理楼B1';
  courses.push(c5);

  const c6: ScheduleCourse = new ScheduleCourse();
  c6.day = 0; c6.period = 3; c6.title = '体育课'; c6.location = '东操';
  courses.push(c6);
  return courses;
}

function findCourse(courses: ScheduleCourse[], day: number, period: number): ScheduleCourse | null {
  for (const c of courses) {
    if (c.day === day && c.period === period) {
      return c;
    }
  }
  return null;
}

@Component
export struct SchedulePage {
  @State currentWeek: number = 18;
  private courses: ScheduleCourse[] = getMockCourses();

  build() {
    Column() {
      SafeTop()

      // 周选择器
      Row() {
        Button('←')
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .fontSize(14)
          .backgroundColor('rgba(124,92,250,0.10)')
          .fontColor(Theme.primary)
          .onClick(() => {
            if (this.currentWeek > 1) {
              this.currentWeek--;
            }
          })

        Column() {
          Text(`第 ${this.currentWeek} 周`)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text('2026年7月')
            .fontSize(11)
            .fontColor(Theme.textMuted)
        }
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)

        Button('→')
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .fontSize(14)
          .backgroundColor('rgba(124,92,250,0.10)')
          .fontColor(Theme.primary)
          .onClick(() => {
            this.currentWeek++;
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      // 分割线
      Divider()
        .color(Theme.divider)

      // 星期头
      Row() {
        Blank().width(56).height(36)
        ForEach(WEEKDAYS, (day: string) => {
          Text(day)
            .fontSize(12)
            .fontColor(Theme.textMuted)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        })
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })
      .border({ width: { bottom: 1 }, color: Theme.divider })

      // 课程网格
      Scroll() {
        Column() {
          ForEach(PERIODS, (time: string, periodIdx: number) => {
            Row() {
              // 时间列
              Column() {
                Text(time)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
                  .textAlign(TextAlign.Center)
              }
              .width(56)
              .height(64)
              .justifyContent(FlexAlign.Start)
              .padding({ top: 8 })

              // 每天一列
              ForEach(WEEKDAYS, (dayName: string, dayIdx: number) => {
                Column() {
                  if (findCourse(this.courses, dayIdx, periodIdx) !== null) {
                    Column() {
                      Text(findCourse(this.courses, dayIdx, periodIdx)!.title)
                        .fontSize(10)
                        .fontColor(Theme.primaryDark)
                        .maxLines(1)
                      Text(findCourse(this.courses, dayIdx, periodIdx)!.location)
                        .fontSize(9)
                        .fontColor(Theme.primary)
                        .maxLines(1)
                    }
                    .width('90%')
                    .height('90%')
                    .padding(3)
                    .borderRadius(6)
                    .backgroundColor('rgba(124,92,250,0.12)')
                    .border({ width: 1, color: 'rgba(124,92,250,0.25)' })
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }
                }
                .layoutWeight(1)
                .height(64)
                .border({ width: { right: 1, bottom: 1 }, color: Theme.divider })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
              })
            }
            .width('100%')
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.surface)
  }
}
