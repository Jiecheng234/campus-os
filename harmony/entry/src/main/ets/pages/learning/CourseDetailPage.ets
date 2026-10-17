import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusCourse } from '../../services/campus/CampusDataService';
import { I18n } from '../../utils/I18n';

@Component
export struct CourseDetailPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }
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
              Text(this.tr('learning.course.code'))
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
              Text(this.tr('learning.course.teacher'))
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
              Text(this.tr('learning.course.semester'))
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
          .constraintSize({ maxWidth: '100%' })
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
