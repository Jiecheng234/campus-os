/**
 * HomePage — 首页仪表盘（对齐原项目 HomeScreen 布局 + 设计系统 V1）
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader, SectionHeader, MetricPill, BadgeTone } from '../components/Ui';
import { getTodayCourses, getBriefingMetrics, getQuickActions, getGreeting,
  getDateString, CourseItem, BriefingMetrics, QuickAction } from './HomeData';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusCourse, CampusDataService, CampusHomework, CampusNotification, ScheduleEvent } from '../services/campus/CampusDataService';
import { fetchHomeWeather, buildWeatherSubtitle, HomeWeather } from '../services/campus/WeatherService';
import { emitNavigate, NavTarget } from '../state/UiEvents';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';
import { Log } from '../utils/Logger';
/**
 * 今日课程行：3px 渐变竖条 + 课程名 + 时间地点（对齐原项目 scheduleRow）。
 * 竖条禁止 height('100%')：父级行高自适应时，百分比按"最近固定高度祖先"解析，
 * 会被上层 height('100%') 容器撑到视口高度导致整行爆高。
 * 改用 Flex + ItemAlign.Stretch：竖条沿交叉轴拉伸、行高由文本内容自适应决定。
 */
@Component
struct CourseRow {
  @Prop course: CourseItem = new CourseItem();

  build() {
    Flex({ direction: FlexDirection.Row, alignItems: ItemAlign.Stretch }) {
      Column()
        .width(3)
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
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: Space.md, bottom: Space.md })
  }
}

/** 快捷操作胶囊按钮（primaryMuted 底 pill）；onTap 由父组件注入（真实跳转/降级 toast） */
@Component
struct QuickActionButton {
  @Prop action: QuickAction = new QuickAction();
  onTap: () => void = () => {};

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
      this.onTap();
    })
  }
}

@Component
export struct HomePage {
  @State syncStatus: string = '';
  @State realCourseCount: number = 0;
  @State todayCourses: CourseItem[] = [];
  @State metricClasses: string = '0';
  @State metricTasks: string = '0';
  @State metricUnread: string = '0';
  /** 课表拉取是否成功（区分"今日真的无课"与"教务会话未打通"） */
  @State scheduleOk: boolean = false;
  /** 头部天气副标题（Open-Meteo，免登录） */
  @State weatherSubtitle: string = '';

  aboutToAppear(): void {
    this.loadWeather();
    if (!this.isRealMode()) {
      // 演示模式：指标与演示课程保持一致
      const m: BriefingMetrics = getBriefingMetrics();
      this.metricClasses = String(m.classes);
      this.metricTasks = String(m.tasks);
      this.metricUnread = String(m.unread);
      return;
    }
    this.refreshHomeData(false);
  }

  private isRealMode(): boolean {
    return AuthManager.isLoggedIn() && !StateManager.isDemoMode();
  }

  /** 天气与登录无关（Open-Meteo 公共 API），演示/真实模式均加载 */
  private async loadWeather(): Promise<void> {
    try {
      const w: HomeWeather = await fetchHomeWeather(false);
      this.weatherSubtitle = buildWeatherSubtitle(w);
    } catch (e) {
      Log.i('HomeAct', 'HOME weather ex=%{public}s', e instanceof Error ? e.message : String(e));
      this.weatherSubtitle = '海淀 · 天气暂不可用';
    }
  }

  /**
   * 刷新首页全部真实数据：课程数 + 今日课表 + 待办 + 未读。
   * loadRealData（进入页面）与同步按钮共用；任何子项失败不阻塞其余项。
   */
  private async refreshHomeData(showStatus: boolean): Promise<void> {
    if (!this.isRealMode()) {
      return;
    }
    const service: CampusDataService = SessionManager.getCampusDataService();
    if (showStatus) {
      this.syncStatus = '同步中...';
    }

    // 1. 课程列表（learn 域）
    let courses: CampusCourse[] = [];
    try {
      courses = await service.fetchCourses();
    } catch (e) {
      Log.i('HomeAct', 'HOME courses ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    this.realCourseCount = courses.length;

    // 2. 待办（未交作业数） + 3. 未读通知
    let pending: number = 0;
    let unread: number = 0;
    if (courses.length > 0) {
      try {
        const hw: CampusHomework[] = await service.fetchHomework(courses);
        for (let i: number = 0; i < hw.length; i++) {
          if (!hw[i].submitted && !hw[i].graded) {
            pending++;
          }
        }
      } catch (e) {
        Log.i('HomeAct', 'HOME homework ex=%{public}s', e instanceof Error ? e.message : String(e));
      }
      try {
        const notif: CampusNotification[] = await service.fetchNotifications(courses);
        for (let i: number = 0; i < notif.length; i++) {
          if (notif[i].isNew) {
            unread++;
          }
        }
      } catch (e) {
        Log.i('HomeAct', 'HOME notifications ex=%{public}s', e instanceof Error ? e.message : String(e));
      }
    }
    this.metricTasks = String(pending);
    this.metricUnread = String(unread);

    // 4. 今日课表（zhjw 教务域；scheduleOk 区分"无课"与"拉取失败"）
    let events: ScheduleEvent[] = [];
    try {
      events = await service.fetchTodaySchedule();
    } catch (e) {
      Log.i('HomeAct', 'HOME schedule ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    const mapped: CourseItem[] = [];
    for (let i: number = 0; i < events.length; i++) {
      const item: CourseItem = new CourseItem();
      item.title = events[i].title;
      item.time = events[i].startTime + ' - ' + events[i].endTime;
      item.location = events[i].location;
      mapped.push(item);
    }
    this.todayCourses = mapped;
    this.metricClasses = String(mapped.length);
    this.scheduleOk = service.scheduleStatus === 'ok';

    if (showStatus) {
      let status: string = '已同步 ' + String(courses.length) + ' 门课程';
      if (courses.length > 0) {
        status = status + ' · 待办 ' + String(pending) + ' · 未读 ' + String(unread);
      }
      if (events.length === 0 && !this.scheduleOk) {
        status = status + ' · 课表暂不可用';
      }
      this.syncStatus = status;
    }
  }

  /** 真实模式一律显示真实数据（空则显示"今日无课程安排"）；仅演示模式回落演示数据 */
  private getDisplayTodayCourses(): CourseItem[] {
    return this.isRealMode() ? this.todayCourses : getTodayCourses();
  }

  syncCampusData(): void {
    if (!AuthManager.isLoggedIn() || StateManager.isDemoMode()) {
      this.getUIContext().getPromptAction().showToast({ message: '演示模式下使用本地数据', duration: 2000 });
      return;
    }
    this.refreshHomeData(true);
  }

  /** 快捷操作跳转：已接入的走 emitter 跨页导航，未接入的保留提示 */
  handleQuickAction(action: QuickAction): void {
    if (action.targetTab >= 0) {
      const target: NavTarget = new NavTarget();
      target.tab = action.targetTab;
      target.campusSub = action.campusSub;
      target.learningTab = action.learningTab;
      emitNavigate(target);
      return;
    }
    this.getUIContext().getPromptAction().showToast({ message: `${action.label} — 即将接入`, duration: 2000 });
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
            subtitle: this.weatherSubtitle
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
            MetricPill({ label: '今日课程', value: this.metricClasses, tone: BadgeTone.Default })
            MetricPill({ label: '待处理任务', value: this.metricTasks, tone: BadgeTone.Default })
            MetricPill({ label: '未读通知', value: this.metricUnread, tone: BadgeTone.Warning })
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
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
          ForEach(this.getDisplayTodayCourses(), (item: CourseItem, index: number) => {
            CourseRow({ course: item })
            if (index < this.getDisplayTodayCourses().length - 1) {
              Divider()
                .color(Theme.divider)
                .width('100%')
                .constraintSize({ maxWidth: '100%' })
                .margin({ left: 15 })
            }
          })
          if (this.getDisplayTodayCourses().length === 0) {
            Text(this.scheduleOk ? '今日无课程安排' : '课表暂不可用（教务会话调试中）')
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
              .padding({ top: Space.md, bottom: Space.md })
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
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
            QuickActionButton({ action: action, onTap: () => { this.handleQuickAction(action); } })
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
