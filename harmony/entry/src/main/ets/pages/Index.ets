/**
 * Index — 底部 6 标签页导航容器 + 登录门控
 */
import { Theme } from './Theme';
import { HomePage } from './HomePage';
import { SchedulePage } from './SchedulePage';
import { SettingsPage } from './SettingsPage';
import { AIChatPage } from './ai/AIChatPage';
import { LoginPage } from './LoginPage';
import { LearningPage } from './LearningPage';
import { CampusPage } from './CampusPage';
import { SessionManager } from '../services/auth/SessionManager';
import { LoginResult, LoginResultType } from '../services/auth/TsinghuaAuthService';
import { AuthManager } from '../state/AuthManager';
import { BackDispatcher, BackOwner } from '../state/BackDispatcher';
import { subscribeNavigate, unsubscribeNavigate, NavigateSubscription, NavTarget } from '../state/UiEvents';
import { I18n } from '../utils/I18n';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State isLoggedIn: boolean = false;
  @State isAutoLogging: boolean = true;
  /** 语言订阅：随设置页语言切换即时重渲染底部导航 */
  @StorageLink('locale') locale: string = 'zh';
  /** 登录态门控信号（AuthManager 广播）：登录成功/退出登录/需 2FA/会话失效
   *  时立即按 AuthManager.isLoggedIn() 重算门控——整应用切换 Tabs ↔ 登录页 */
  @StorageLink('authGateTick') @Watch('onAuthGateChange') authGateTick: number = 0;
  private navSub: NavigateSubscription = new NavigateSubscription();

  /** 翻译（显式读取 this.locale 以建立渲染依赖） */
  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  /** 登录态门控信号变化（退出登录/会话失效/登录成功）→ 立即重算整应用门控 */
  onAuthGateChange(): void {
    const now: boolean = AuthManager.isLoggedIn();
    // “未登录 → 已登录”时回到首页 Tab：避免重新登录后停留在上一次的 Tab（如设置页）
    if (now && !this.isLoggedIn) {
      this.currentIndex = 0;
    }
    this.isLoggedIn = now;
  }

  aboutToAppear(): void {
    this.isLoggedIn = AuthManager.isLoggedIn();
    // 首页快捷操作等处的跨页导航：切到底部指定 Tab
    this.navSub = subscribeNavigate((target: NavTarget) => {
      if (target.tab >= 0 && target.tab <= 5) {
        this.currentIndex = target.tab;
      }
    });
    SessionManager.tryAutoLogin().then((result: LoginResult | undefined) => {
      this.isAutoLogging = false;
      if (result !== undefined && result.type === LoginResultType.SUCCESS) {
        this.isLoggedIn = true;
      }
      // 非 SUCCESS（需 2FA / 失败）保持未登录门控：渲染登录页——
      // LoginPage 挂载时按 AuthManager 状态直接进入 2FA 视图或展示失败原因
    }).catch((e: Object) => {
      this.isAutoLogging = false;
    });
  }

  aboutToDisappear(): void {
    unsubscribeNavigate(this.navSub);
  }

  onBackPress(): boolean {
    if (BackDispatcher.dispatch(this.activeBackOwner())) {
      return true;
    }
    const now: number = Date.now();
    if (now - this.lastBackAt < 2000) {
      return false;
    }
    this.lastBackAt = now;
    try {
      this.getUIContext().getPromptAction().showToast({ message: this.tr('common.exitHint'), duration: 1500 });
    } catch (e) {
      /* ignore */
    }
    return true;
  }

  private activeBackOwner(): string {
    if (this.currentIndex === 1) {
      return BackOwner.LEARNING;
    }
    if (this.currentIndex === 3) {
      return BackOwner.CAMPUS;
    }
    if (this.currentIndex === 5) {
      return BackOwner.SETTINGS;
    }
    return '';
  }
  private lastBackAt: number = 0;
  private tabKeys: string[] = ['nav.home', 'nav.learning', 'nav.schedule', 'nav.campus', 'nav.ai', 'nav.settings'];
  private tabIcons: Resource[] = [
    $r('app.media.home'), $r('app.media.learning'), $r('app.media.schedule'),
    $r('app.media.campus'), $r('app.media.ai'), $r('app.media.settings')
  ];

  @Builder
  TabBarBuilder(title: string, iconRes: Resource, index: number) {
    Column() {
      Image(iconRes)
        .width(28)
        .height(28)
        .borderRadius(7)
        .objectFit(ImageFit.Cover)
        .opacity(this.currentIndex === index ? 1.0 : 0.55)
        .border({
          width: 1,
          color: this.currentIndex === index ? Theme.primary : Theme.borderSubtle
        })
      Text(title)
        .fontSize(10)
        .margin({ top: 2 })
        .fontColor(this.currentIndex === index ? Theme.primary : Theme.textMuted)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .padding({ top: 8, bottom: 6 })
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentIndex = index;
    })
  }

  @Builder
  MainTabs() {
    Tabs({
      barPosition: BarPosition.End,
      index: this.currentIndex
    }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.TabBarBuilder(this.tr(this.tabKeys[0]), this.tabIcons[0], 0))

      TabContent() {
        LearningPage()
      }
      .tabBar(this.TabBarBuilder(this.tr(this.tabKeys[1]), this.tabIcons[1], 1))

      TabContent() {
        SchedulePage()
      }
      .tabBar(this.TabBarBuilder(this.tr(this.tabKeys[2]), this.tabIcons[2], 2))

      TabContent() {
        CampusPage()
      }
      .tabBar(this.TabBarBuilder(this.tr(this.tabKeys[3]), this.tabIcons[3], 3))

      TabContent() {
        AIChatPage()
      }
      .tabBar(this.TabBarBuilder(this.tr(this.tabKeys[4]), this.tabIcons[4], 4))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBarBuilder(this.tr(this.tabKeys[5]), this.tabIcons[5], 5))
    }
    .width('100%')
    .height('100%')
    .scrollable(false)
    .barHeight(56)
    .animationDuration(200)
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }

  build() {
    // 登录态唯一门控：未登录/需 2FA → 登录页（不渲染 Tabs，底部导航不可访问）；
    // 已登录 → Tabs。退出登录/会话失效经 authGateTick 立即切换。
    if (this.isAutoLogging) {
      Column() {
        LoadingProgress()
          .width(48)
          .color(Theme.primary)
        Text(this.tr('login.restoring'))
          .fontSize(14)
          .fontColor(Theme.textMuted)
          .margin({ top: 16 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Theme.background)
    } else if (this.isLoggedIn) {
      this.MainTabs()
    } else {
      LoginPage({ onLoginSuccess: () => {
        this.isLoggedIn = true;
      } })
    }
  }
}
