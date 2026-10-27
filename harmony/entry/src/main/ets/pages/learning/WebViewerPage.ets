/**
 * WebViewerPage — 内嵌浏览器（学习详情深链 US3，FR-013）
 *
 * 承载资料预览（CampusFile.previewUrl）：
 *   - 加载前同步 learn 域 Cookie（会话失效会导致预览页跳登录）；
 *   - 桌面 Chrome UA（learn 预览页对移动 UA 有降级布局）；
 *   - 加载进度条 + 主资源失败态（覆盖层 + 重试，对齐 ArkWeb 官方错误页方案）。
 * 演示模式不进入本页（LearningPage 负责拦截）。
 */
import { Theme, SafeTop, Space, Radius } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { webview } from '@kit.ArkWeb';
import { I18n } from '../../utils/I18n';
import { Log } from '../../utils/Logger';
import { SessionManager } from '../../services/auth/SessionManager';

/** 桌面 Chrome UA（避免 learn 预览页按移动端降级渲染） */
const DESKTOP_UA: string = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

@Component
export struct WebViewerPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  /** 预览地址（父页面传入，构造后不变） */
  url: string = '';
  /** 外部可覆盖的标题（空串回退 i18n 默认标题） */
  title: string = '';
  /** 加载进度（0~100） */
  @State progress: number = 0;
  /** 主资源加载失败（覆盖层 + 重试） */
  @State loadFailed: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  aboutToAppear(): void {
    // 加载前把 learn 域会话 Cookie 同步进 ArkWeb（Cookie 管理 + Web 组件 Cookie 分池存储）
    SessionManager.getCampusDataService().syncLearnCookiesForWebView();
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({
        title: this.title.length > 0 ? this.title : this.tr('webviewer.defaultTitle'),
        onBack: () => { this.onBack(); },
      })

      Divider().color(Theme.divider)

      // 加载进度（0 < progress < 100 且未失败时显示）
      if (this.progress > 0 && this.progress < 100 && !this.loadFailed) {
        Progress({ value: this.progress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(3)
          .color(Theme.primary)
      }

      Stack() {
        Web({ src: this.url, controller: this.controller })
          .width('100%')
          .height('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .userAgent(DESKTOP_UA)
          .visibility(this.loadFailed ? Visibility.Hidden : Visibility.Visible)
          .onProgressChange((event) => {
            if (event) {
              this.progress = event.newProgress;
            }
          })
          .onErrorReceive((event) => {
            // 主资源与子资源出错都回调；仅主资源失败切覆盖层
            if (event && event.request.isMainFrame()) {
              this.loadFailed = true;
              Log.i('WebViewer', 'PREVIEW_LOAD_FAILED url_len=%{public}d code=%{public}d',
                this.url.length, event.error.getErrorCode());
            }
          })
          .onPageEnd(() => {
            this.loadFailed = false;
            this.progress = 100;
          })

        // 失败覆盖层（重试走 controller.refresh）
        Column({ space: Space.md }) {
          Text(this.tr('webviewer.loadFailed'))
            .fontSize(15)
            .fontColor(Theme.textSecondary)
          Text(this.tr('common.retry'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.primary)
            .padding({
              left: Space.lg,
              right: Space.lg,
              top: Space.sm,
              bottom: Space.sm
            })
            .borderRadius(Radius.md)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .onClick(() => { this.retryLoad(); })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(Theme.background)
        .visibility(this.loadFailed ? Visibility.Visible : Visibility.None)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }

  private retryLoad(): void {
    this.progress = 0;
    this.loadFailed = false;
    try {
      this.controller.refresh();
    } catch (e) {
      Log.i('WebViewer', 'PREVIEW_RETRY refresh ex');
    }
  }
}
