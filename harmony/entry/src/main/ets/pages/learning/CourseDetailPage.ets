import { Theme, SafeTop } from '../Theme';

class CourseDetail {
  name: string = '';
  teacher: string = '';
  code: string = '';
  credits: number = 0;
  semester: string = '';
  schedule: string = '';
  description: string = '';
  announcements: string[] = [];
}

@Component
export struct CourseDetailPage {
  onBack: () => void = () => {};
  @State course: CourseDetail = new CourseDetail();

  aboutToAppear(): void {
    const c: CourseDetail = new CourseDetail();
    c.name = '高等数学(1)';
    c.teacher = '李老师';
    c.code = 'MATH101';
    c.credits = 4;
    c.semester = '2025-2026 秋季学期';
    c.schedule = '周一 1-2节 · 六教6A201\n周三 3-4节 · 六教6A201';
    c.description = '本课程讲授一元函数微积分学，包括极限与连续、导数与微分、不定积分与定积分、常微分方程等内容。';
    c.announcements = ['请于8月15日前完成线上选课','期中考试定于第8周周三', '期末考核方式为闭卷考试'];
    this.course = c;
  }

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

        Text(this.course.name)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 60 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          // 基本信息卡片
          Column() {
            Row() {
              Text('课程代码')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(80)
              Text(this.course.code)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ bottom: 8 })

            Row() {
              Text('授课教师')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(80)
              Text(this.course.teacher)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ bottom: 8 })

            Row() {
              Text('学分')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(80)
              Text(String(this.course.credits))
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ bottom: 8 })

            Row() {
              Text('学期')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(80)
              Text(this.course.semester)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ bottom: 8 })

            Row() {
              Text('上课安排')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(80)
              Text(this.course.schedule)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 课程简介
          Column() {
            Text('课程简介')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            Text(this.course.description)
              .fontSize(14)
              .fontColor(Theme.textSecondary)
              .lineHeight(22)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 课程通知
          Column() {
            Text('课程通知')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 12 })

            ForEach(this.course.announcements, (item: string, index: number) => {
              Row() {
                Text(`📢`)
                  .fontSize(14)
                  .margin({ right: 8 })
                Text(item)
                  .fontSize(14)
                  .fontColor(Theme.textSecondary)
              }
              .width('100%')
              .margin({ bottom: 10 })
            })
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })

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
