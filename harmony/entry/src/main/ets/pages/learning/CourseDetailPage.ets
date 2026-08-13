import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusCourse } from '../../services/campus/CampusDataService';

@Component
export struct CourseDetailPage {
  onBack: () => void = () => {};
  course: CampusCourse = new CampusCourse();
  semester: string = '';

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.course.name, onBack: () => { this.onBack(); } })

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
