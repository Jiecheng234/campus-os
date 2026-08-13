import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

@Component
export struct ReservationPage {
  onBack: () => void = () => {};

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '场馆预约', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          // 图书馆座位
          Row() {
            Column() {
              Text('📖')
                .fontSize(32)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(124,92,250,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('图书馆座位预约')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text('已预约 0 个座位')
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('>')
              .fontSize(14)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 12 })

          // 研读间
          Row() {
            Column() {
              Text('🏫')
                .fontSize(32)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(22,163,74,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('研读间预约')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text('已预约 0 间')
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('>')
              .fontSize(14)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 12 })

          // 体育场馆
          Row() {
            Column() {
              Text('🏃')
                .fontSize(32)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(217,119,6,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('体育场馆预约')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text('羽毛球 · 乒乓球 · 游泳馆')
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('>')
              .fontSize(14)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })
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
