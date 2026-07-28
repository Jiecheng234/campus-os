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

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
  @State isLoggedIn: boolean = false;
  private tabTitles: string[] = ['首页', '学习', '课表', '校园', 'AI', '设置'];
  private tabIcons: string[] = ['🏠', '📚', '📅', '🏫', '🤖', '⚙️'];

  @Builder
  TabBarBuilder(title: string, icon: string, index: number) {
    Column() {
      Text(icon)
        .fontSize(20)
      Text(title)
        .fontSize(10)
        .margin({ top: 2 })
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
    if (this.isLoggedIn) {
      this.MainTabs()
    } else {
      LoginPage({ onLoginSuccess: () => {
        this.isLoggedIn = true;
      } })
    }
  }
}
