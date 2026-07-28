/**
 * HomePage — 首页仪表盘
 */
import { Theme, SafeTop } from './Theme';
import { getTodayCourses, getBriefingMetrics, getQuickActions, getGreeting,
  getDateString, CourseItem, BriefingMetrics, QuickAction } from './HomeData';
import { promptAction } from '@kit.ArkUI';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusCourse, CampusDataService } from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';

@Component
struct MetricCard {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop tone: string = 'default';

  build() {
    Column() {
      Text(this.value)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.tone === 'warning' ? Theme.warning :
          this.tone === 'success' ? Theme.success : Theme.primary)
        .fontFamily('monospace')
      Text(this.label)
        .fontSize(12)
        .fontColor(Theme.textSecondary)
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }
}

@Component
struct CourseCard {
  @Prop course: CourseItem = new CourseItem();

  build() {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .borderRadius(2)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[Theme.primary, 0], [Theme.primaryDark, 1]]
        })

      Column() {
        Text(this.course.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.course.time}  |  ${this.course.location}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)
    }
    .width('100%')
    .height(56)
    .alignItems(VerticalAlign.Center)
  }
}

@Component
struct QuickActionButton {
  @Prop action: QuickAction = new QuickAction();
  @Link onClickAction: string;

  build() {
    Button() {
      Row() {
        Text(this.action.icon)
          .fontSize(14)
        Text(this.action.label)
          .fontSize(13)
          .fontColor(Theme.primary)
          .margin({ left: 4 })
      }
    }
    .type(ButtonType.Capsule)
    .backgroundColor('rgba(124,92,250,0.08)')
    .onClick(() => {
      this.onClickAction = this.action.label;
      promptAction.showToast({ message: `${this.action.label} — 即将接入`, duration: 2000 });
    })
  }
}

@Component
export struct HomePage {
  @State showActionsToast: string = '';
  @State syncStatus: string = '';
  @State realCourseCount: number = 0;

  syncCampusData(): void {
    if (!AuthManager.isLoggedIn() || StateManager.isDemoMode()) {
      promptAction.showToast({ message: '真实登录后才能同步校园数据', duration: 2000 });
      return;
    }
    this.syncStatus = '同步中...';
    const service: CampusDataService = SessionManager.getCampusDataService();
    service.fetchCourses().then((courses: CampusCourse[]) => {
      this.realCourseCount = courses.length;
      if (courses.length > 0) {
        this.syncStatus = '已同步 ' + String(courses.length) + ' 门课程';
      } else {
        this.syncStatus = '未获取到课程数据';
      }
    }).catch(() => {
      this.syncStatus = '同步失败';
    });
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        // ── 头部 ──
        Column() {
          Text(`${getGreeting()} · ${getDateString()}`)
            .fontSize(13)
            .fontColor(Theme.textMuted)

          Text('CampusOS')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.text)
            .margin({ top: 2 })

          Text('海淀 23° · 晴')
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 4 })

        Row() {
          Button('同步校园数据')
            .type(ButtonType.Capsule)
            .fontSize(12)
            .fontColor(Theme.primary)
            .backgroundColor('rgba(124,92,250,0.08)')
            .onClick(() => { this.syncCampusData(); })

          if (this.syncStatus.length > 0) {
            Text(this.syncStatus)
              .fontSize(12)
              .fontColor(Theme.textMuted)
              .margin({ left: 10 })
          }
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 4 })

        // ── 简报卡片 ──
        Column() {
          Text('📋 今日重点')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)

          Row() {
            MetricCard({ label: '今日课程', value: '3', tone: 'default' })
            MetricCard({ label: '待处理任务', value: '2', tone: 'default' })
            MetricCard({ label: '未读通知', value: '1', tone: 'warning' })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: 16, right: 16 })

        // ── 今日课程 ──
        Column() {
          Text('今日课程')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .margin({ bottom: 12 })

          Column() {
            ForEach(getTodayCourses(), (item: CourseItem, index: number) => {
              CourseCard({ course: item })
              if (index < getTodayCourses().length - 1) {
                Divider()
                  .color(Theme.divider)
                  .margin({ left: 15 })
              }
            })
          }
          .width('100%')
          .padding({ top: 4, bottom: 4 })
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
        }
        .width('100%')
        .padding(16)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: 16, right: 16, top: 16 })

        // ── 快捷操作 ──
        Row() {
          Text('快捷操作')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Blank()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 8 })

        Row() {
          ForEach(getQuickActions(), (action: QuickAction) => {
            QuickActionButton({ action: action, onClickAction: $showActionsToast })
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, bottom: 32 })

        Blank().height(80)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(Theme.background)
  }
}
