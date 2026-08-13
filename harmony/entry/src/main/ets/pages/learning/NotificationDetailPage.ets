import { Theme, SafeTop } from '../Theme';
import { CampusNotification } from '../../services/campus/CampusDataService';

@Component
export struct NotificationDetailPage {
  onBack: () => void = () => {};
  item: CampusNotification = new CampusNotification();

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

        Text('通知详情')
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

            Text(this.item.content.length > 0 ? this.item.content : '暂无内容')
              .fontSize(15)
              .fontColor(Theme.text)
              .lineHeight(26)
          }
          .width('100%')
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
