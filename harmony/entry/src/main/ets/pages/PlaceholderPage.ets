/**
 * 占位页面 — 用于 Learning / Campus / AI 标签页
 */
import { Theme } from './Theme';

@Component
export struct PlaceholderPage {
  @Prop icon: string = '📦';
  @Prop title: string = '页面';

  build() {
    Column() {
      Column() {
        Text(this.icon)
          .fontSize(48)
          .margin({ bottom: 16 })

        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)

        Text('功能开发中')
          .fontSize(14)
          .fontColor(Theme.textMuted)
          .margin({ top: 8 })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
