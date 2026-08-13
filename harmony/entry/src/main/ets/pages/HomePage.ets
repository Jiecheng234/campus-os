/**
 * HomePage — 首页仪表盘（对齐原项目 HomeScreen 布局 + 设计系统 V1）
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader, SectionHeader, MetricPill, BadgeTone } from '../components/Ui';
import { getTodayCourses, getBriefingMetrics, getQuickActions, getGreeting,
  getDateString, CourseItem, BriefingMetrics, QuickAction } from './HomeData';
import { promptAction } from '@kit.ArkUI';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusCourse, CampusDataService } from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';

/** 今日课程行：3px 渐变竖条 + 课程名 + 时间地点（对齐原项目 scheduleRow） */
@Component
struct CourseRow {
  @Prop course: CourseItem = new CourseItem();

  build() {
    Row({ space: 12 }) {
      Column()
        .width(3)
        .height('100%')
        .borderRadius(2)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[Theme.primary, 0], [Theme.primaryDark, 1]]
        })

      Column({ space: 4 }) {
        Text(this.course.title)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
        Text(`${this.course.time}  ·  ${this.course.location}`)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textSecondary)
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: Space.md, bottom: Space.md })
    .alignItems(VerticalAlign.Center)
  }
}

/** 快捷操作胶囊按钮（primaryMuted 底 pill） */
@Component
struct QuickActionButton {
  @Prop action: QuickAction = new QuickAction();
  @Link onClickAction: string;

  build() {
    Row({ space: 4 }) {
      Text(this.action.icon)
        .fontSize(FontSize.label)
      Text(this.action.label)
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.primary)
    }
    .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
    .borderRadius(Radius.pill)
    .backgroundColor(Theme.primaryMuted)
    .margin({ right: Space.sm })
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
      promptAction.showToast({ message: '演示模式下使用本地数据', duration: 2000 });
      return;
    }
    this.syncStatus = '同步中...';
    const service: CampusDataService = SessionManager.getCampusDataService();
    service.fetchCourses().then((courses: CampusCourse[]) => {
      this.realCourseCount = courses.length;
      if (courses.length > 0) {
        this.syncStatus = '已同步 ' + String(courses.length) + ' 门课程';
      } else {
        this.syncStatus = '数据同步需完整 WebVPN 传输层';
      }
    }).catch(() => {
      this.syncStatus = '同步失败';
    });
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        // ── 头部（eyebrow=问候语·日期 / 标题 / 天气）──
        Row() {
          ScreenHeader({
            eyebrow: `${getGreeting()} · ${getDateString()}`,
            title: 'CampusOS',
            subtitle: '海淀 23° · 晴'
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.md })

        // 同步状态行
        Row({ space: Space.sm }) {
          Text('同步校园数据')
            .fontSize(FontSize.caption)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.primary)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
            .borderRadius(Radius.pill)
            .backgroundColor(Theme.primaryMuted)
            .onClick(() => { this.syncCampusData(); })

          if (this.syncStatus.length > 0) {
            Text(this.syncStatus)
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: Space.lg, right: Space.lg, bottom: Space.sm })

        // ── 今日重点（简报卡 + 指标凹槽块）──
        Column() {
          Text('今日重点')
            .fontSize(FontSize.h3)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .margin({ bottom: Space.md })

          Row({ space: Space.sm }) {
            MetricPill({ label: '今日课程', value: '3', tone: BadgeTone.Default })
            MetricPill({ label: '待处理任务', value: '2', tone: BadgeTone.Default })
            MetricPill({ label: '未读通知', value: '1', tone: BadgeTone.Warning })
          }
          .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── 今日课程 ──
        Column() {
          SectionHeader({ title: '今日课程' })
            .padding({ left: Space.lg, right: Space.lg })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column() {
          ForEach(getTodayCourses(), (item: CourseItem, index: number) => {
            CourseRow({ course: item })
            if (index < getTodayCourses().length - 1) {
              Divider().color(Theme.divider).margin({ left: 15 })
            }
          })
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg })

        // ── 快捷操作 ──
        Column() {
          SectionHeader({ title: '快捷操作' })
            .padding({ left: Space.lg, right: Space.lg })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row() {
          ForEach(getQuickActions(), (action: QuickAction) => {
            QuickActionButton({ action: action, onClickAction: $showActionsToast })
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg })

        Blank().height(Space.xxl)
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
