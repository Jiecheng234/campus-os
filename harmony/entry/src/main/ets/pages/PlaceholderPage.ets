/**
 * 占位页面 — 用于 Learning / Campus / AI 标签页
 */
import { Theme } from './Theme';
import { I18n } from '../utils/I18n';

@Component
export struct PlaceholderPage {
  @Prop icon: string = '📦';
  /** 父组件传入的标题（空串回退 i18n 默认标题） */
  @Prop title: string = '';
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  build() {
    Column() {
      Column() {
        Text(this.icon)
          .fontSize(48)
          .margin({ bottom: 16 })

        Text(this.title.length > 0 ? this.title : this.tr('common.placeholder.defaultTitle'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)

        Text(this.tr('common.placeholder.wip'))
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
