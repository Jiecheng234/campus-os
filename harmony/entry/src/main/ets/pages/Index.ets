/**
 * Index — 底部 6 标签页导航容器
 */
import { Theme } from './Theme';
import { HomePage } from './HomePage';
import { SchedulePage } from './SchedulePage';
import { SettingsPage } from './SettingsPage';
import { PlaceholderPage } from './PlaceholderPage';

@Entry
@Component
struct Index {
  @State currentIndex: number = 0;
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

  build() {
    Tabs({
      barPosition: BarPosition.End,
      index: this.currentIndex
    }) {
      TabContent() {
        HomePage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[0], this.tabIcons[0], 0))

      TabContent() {
        PlaceholderPage({ icon: '📚', title: '学习' })
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[1], this.tabIcons[1], 1))

      TabContent() {
        SchedulePage()
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[2], this.tabIcons[2], 2))

      TabContent() {
        PlaceholderPage({ icon: '🏫', title: '校园' })
      }
      .tabBar(this.TabBarBuilder(this.tabTitles[3], this.tabIcons[3], 3))

      TabContent() {
        PlaceholderPage({ icon: '🤖', title: 'AI 助手' })
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
}
