import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { webview } from '@kit.ArkWeb';
import { I18n } from '../../utils/I18n';

@Component
export struct WebViewerPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  @State url: string = 'https://learn.tsinghua.edu.cn';
  /** 外部可覆盖的标题（空串回退 i18n 默认标题） */
  @State title: string = '';
  private controller: webview.WebviewController = new webview.WebviewController();

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({
        title: this.title.length > 0 ? this.title : this.tr('webviewer.defaultTitle'),
        onBack: () => { this.onBack(); },
      })

      Divider().color(Theme.divider)

      Web({ src: this.url, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
