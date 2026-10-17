import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusNotification } from '../../services/campus/CampusDataService';
import { I18n } from '../../utils/I18n';

@Component
export struct NotificationDetailPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }
  item: CampusNotification = new CampusNotification();

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.tr('learning.notification.title'), onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          Column() {
            Text(this.item.title)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
              .margin({ bottom: 12 })

            Row() {
              Text(this.item.publisher)
                .fontSize(13)
                .fontColor(Theme.primary)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .borderRadius(4)
                .backgroundColor('rgba(124,92,250,0.08)')
              Blank().width(8)
              Text(this.item.publishTime)
                .fontSize(13)
                .fontColor(Theme.textMuted)
            }
            .width('100%')
            .margin({ bottom: 16 })

            Divider().color(Theme.divider).margin({ bottom: 16 })

            Text(this.item.content.length > 0 ? this.item.content : this.tr('learning.notification.empty'))
              .fontSize(15)
              .fontColor(Theme.text)
              .lineHeight(26)
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(20)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)

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
