import { Theme, SafeTop } from '../Theme';
import { CampusCourse } from '../../services/campus/CampusDataService';

@Component
export struct CourseDetailPage {
  onBack: () => void = () => {};
  course: CampusCourse = new CampusCourse();
  semester: string = '';

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
              Text('学期')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(80)
              Text(this.semester.length > 0 ? this.semester : '—')
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
