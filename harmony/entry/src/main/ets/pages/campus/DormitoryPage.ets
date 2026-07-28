import { Theme, SafeTop } from '../Theme';

interface DormInfo {
  building: string;
  room: string;
  elecBalance: number;
  laundryStatus: string;
  laundryRemaining: number;
}

@Component
export struct DormitoryPage {
  onBack: () => void = () => {};
  @State dormInfo: DormInfo = {
    building: '紫荆公寓',
    room: '6号楼 302B',
    elecBalance: 42.50,
    laundryStatus: '空闲',
    laundryRemaining: 3
  };

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

        Text('宿舍服务')
          .fontSize(18)
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
          // 房间信息卡片
          Column() {
            Text(this.dormInfo.building)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
            Text(this.dormInfo.room)
              .fontSize(14)
              .fontColor(Theme.textMuted)
              .margin({ top: 4 })
          }
          .width('100%')
          .padding({ top: 24, bottom: 16 })
          .alignItems(HorizontalAlign.Center)

          // 电费卡片
          Row() {
            Column() {
              Text('💰')
                .fontSize(28)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(124,92,250,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('电费余额')
                .fontSize(13)
                .fontColor(Theme.textMuted)
              Text(`¥${this.dormInfo.elecBalance.toFixed(2)}`)
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.primary)
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Button('充值')
              .type(ButtonType.Capsule)
              .fontSize(13)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 12 })

          // 洗衣卡片
          Row() {
            Column() {
              Text('👕')
                .fontSize(28)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(22,163,74,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('洗衣服务')
                .fontSize(13)
                .fontColor(Theme.textMuted)
              Text(`${this.dormInfo.laundryRemaining} 台可用`)
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#16A34A')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text(this.dormInfo.laundryStatus)
              .fontSize(13)
              .fontColor(Theme.success)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(8)
              .backgroundColor('rgba(22,163,74,0.10)')
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 12 })

          // 电费记录快捷入口
          Column() {
            Row() {
              Text('电费充值记录')
                .fontSize(14)
                .fontColor(Theme.text)
              Blank()
              Text('>')
                .fontSize(14)
                .fontColor(Theme.textMuted)
            }
            .width('100%')
            .padding(14)
            .onClick(() => {})
          }
          .width('100%')
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
