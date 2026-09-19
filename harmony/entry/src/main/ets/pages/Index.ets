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
import { BackDispatcher, BackOwner } from '../state/BackDispatcher';
import { subscribeNavigate, unsubscribeNavigate, NavigateSubscription, NavTarget } from '../state/UiEvents';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State isLoggedIn: boolean = false;
  @State isAutoLogging: boolean = true;
  private navSub: NavigateSubscription = new NavigateSubscription();

  aboutToAppear(): void {
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
      this.getUIContext().getPromptAction().showToast({ message: '再按一次退出应用', duration: 1500 });
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
    return '';
  }
  private lastBackAt: number = 0;
  private tabTitles: string[] = ['首页', '学习', '课表', '校园', 'AI', '设置'];
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
      .tabBar(this.TabBarBuilder(this.tabTitles[0], this.tabIcons[0], 0))

      TabContent() {
        LearningPage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[1], this.tabIcons[1], 1))

      TabContent() {
        SchedulePage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[2], this.tabIcons[2], 2))

      TabContent() {
        CampusPage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[3], this.tabIcons[3], 3))

      TabContent() {
        AIChatPage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[4], this.tabIcons[4], 4))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[5], this.tabIcons[5], 5))
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
    if (this.isAutoLogging) {
      Column() {
        LoadingProgress()
          .width(48)
          .color(Theme.primary)
        Text('正在恢复登录…')
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
