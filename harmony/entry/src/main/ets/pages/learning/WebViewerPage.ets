import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { webview } from '@kit.ArkWeb';

@Component
export struct WebViewerPage {
  onBack: () => void = () => {};
  @State url: string = 'https://learn.tsinghua.edu.cn';
  @State title: string = '浏览器';
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.title, onBack: () => { this.onBack(); } })

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
