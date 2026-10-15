/**
 * HomePage — 首页仪表盘（对齐原项目 HomeScreen 布局 + 设计系统 V1）
 * 「建议操作」区块只读移植自原项目 homeWorkbench.buildHomeWorkbenchBlocks 的
 * task_plan 语义：下一节课 → 最近截止 → 未读通知 →（全空时）轻量日回退，
 * 按紧急度与上下文排序，最多 4 条；底部保留 查空教室/图书馆座位/添加 DDL 入口。
 * 数据来源与原页面一致（refreshHomeData 同一批请求），不新增请求/不改服务层。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader, SectionHeader, MetricPill, BadgeTone } from '../components/Ui';
import { getTodayCourses, getBriefingMetrics, getGreeting,
  getDateString, CourseItem, BriefingMetrics } from './HomeData';
import { getHomeworkList, HomeworkItem } from './LearningData';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusCourse, CampusDataService, CampusHomework, CampusNotification, ScheduleEvent } from '../services/campus/CampusDataService';
import { fetchHomeWeather, buildWeatherSubtitle, HomeWeather } from '../services/campus/WeatherService';
import { emitNavigate, NavTarget } from '../state/UiEvents';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';
import { Log } from '../utils/Logger';
import { I18n } from '../utils/I18n';

/** 解析 "HH:MM(:SS)" 为当日分钟数；解析失败返回 -1（对齐原项目 findNextClass 的时间比较） */
function parseHHmm(text: string): number {
  const parts: string[] = text.split(':');
  if (parts.length < 2) {
    return -1;
  }
  const h: number = Number(parts[0]);
  const m: number = Number(parts[1]);
  if (isNaN(h) || isNaN(m)) {
    return -1;
  }
  return h * 60 + m;
}

/** 解析 "YYYY-MM-DD HH:mm" 截止时间为毫秒；失败返回 NaN（对齐原项目 parseDeadline） */
function parseDeadlineMs(deadline: string): number {
  return new Date(deadline.replace(' ', 'T')).getTime();
}

/** 截止时间距离文案（对齐原项目 formatDeadlineDistance；无法解析时回退原文，空串给占位） */
function formatDeadlineDistance(deadline: string, locale: string): string {
  const time: number = parseDeadlineMs(deadline);
  if (isNaN(time)) {
    return deadline.length > 0 ? deadline : I18n.t('home.suggest.noDeadline', locale);
  }
  const diffDays: number = Math.ceil((time - Date.now()) / (24 * 60 * 60 * 1000));
  if (diffDays < 0) {
    return I18n.t('home.suggest.overdue', locale);
  }
  if (diffDays === 0) {
    return I18n.t('home.suggest.dueToday', locale);
  }
  if (diffDays === 1) {
    return I18n.t('home.suggest.dueTomorrow', locale);
  }
  return I18n.tp('home.suggest.dueInDays', { 'n': String(diffDays) }, locale);
}

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

/** 建议操作条目（对齐原项目 AgentUITaskPlanItem：tone 圆点 + 标题/详情 + 右侧动作） */
class SuggestedAction {
  id: string = '';
  title: string = '';
  detail: string = '';
  tone: BadgeTone = BadgeTone.Default;
  actionLabel: string = '';
  /** 目标底部 Tab（-1 = 无跳转，保留提示） */
  targetTab: number = -1;
  campusSub: string = '';
  learningTab: string = '';
}

/** 建议操作行：tone 圆点 + 标题/详情 + 右侧动作文案（对齐原项目 AgentUIRenderer TaskItem） */
@Component
struct SuggestedItemRow {
  @Prop item: SuggestedAction = new SuggestedAction();
  onTap: () => void = () => {};

  private dotColor(): string {
    if (this.item.tone === BadgeTone.Success) { return Theme.success; }
    if (this.item.tone === BadgeTone.Warning) { return Theme.warning; }
    if (this.item.tone === BadgeTone.Error) { return Theme.error; }
    return Theme.primary;
  }

  build() {
    Row({ space: Space.sm }) {
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.dotColor())

      Column({ space: 2 }) {
        Text(this.item.title)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.item.detail.length > 0) {
          Text(this.item.detail)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.item.actionLabel.length > 0) {
        Text(this.item.actionLabel)
          .fontSize(FontSize.micro)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: Space.sm, bottom: Space.sm })
    .onClick(() => {
      this.onTap();
    })
  }
}

@Component
export struct HomePage {
  /** 语言订阅：语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

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
  /** 今日原始课表事件（建议操作"下一节"用；来自既有 fetchTodaySchedule，不新增请求） */
  @State todayEvents: ScheduleEvent[] = [];
  /** 最近一条待交作业（建议操作"优先处理"用；来自既有 fetchHomework，不新增请求） */
  @State ddlTitle: string = '';
  @State ddlCourse: string = '';
  @State ddlDeadline: string = '';

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
      this.weatherSubtitle = this.tr('home.weatherUnavailable');
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
      this.syncStatus = this.tr('home.syncing');
    }

    // 1. 课程列表（learn 域）
    let courses: CampusCourse[] = [];
    try {
      courses = await service.fetchCourses();
    } catch (e) {
      Log.i('HomeAct', 'HOME courses ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    this.realCourseCount = courses.length;

    // 2. 待办（未交作业数，记录最近截止的一条供"建议操作"使用） + 3. 未读通知
    let pending: number = 0;
    let unread: number = 0;
    let earliestDdl: CampusHomework | null = null;
    let earliestMs: number = NaN;
    if (courses.length > 0) {
      try {
        const hw: CampusHomework[] = await service.fetchHomework(courses);
        for (let i: number = 0; i < hw.length; i++) {
          if (!hw[i].submitted && !hw[i].graded) {
            pending++;
            const ms: number = parseDeadlineMs(hw[i].deadline);
            if (!isNaN(ms) && (earliestDdl === null || ms < earliestMs)) {
              earliestDdl = hw[i];
              earliestMs = ms;
            }
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
    this.ddlTitle = earliestDdl !== null ? earliestDdl.title : '';
    this.ddlCourse = earliestDdl !== null ? earliestDdl.courseName : '';
    this.ddlDeadline = earliestDdl !== null ? earliestDdl.deadline : '';

    // 4. 今日课表（zhjw 教务域；scheduleOk 区分"无课"与"拉取失败"）
    let events: ScheduleEvent[] = [];
    try {
      events = await service.fetchTodaySchedule();
    } catch (e) {
      Log.i('HomeAct', 'HOME schedule ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    this.todayEvents = events;
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
      let status: string = this.trp('home.syncDone', { 'n': String(courses.length) });
      if (courses.length > 0) {
        status = status + ' · ' + this.trp('home.syncPending', { 'n': String(pending) })
          + ' · ' + this.trp('home.syncUnread', { 'n': String(unread) });
      }
      if (events.length === 0 && !this.scheduleOk) {
        status = status + ' · ' + this.tr('home.syncScheduleUnavailable');
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
      this.getUIContext().getPromptAction().showToast({ message: this.tr('home.demoToast'), duration: 2000 });
      return;
    }
    this.refreshHomeData(true);
  }

  /** 跨页导航：切底部 Tab（+ 可选校园子页/学习子标签），对齐原 emitNavigate 契约 */
  private navigateTo(tab: number, campusSub: string, learningTab: string): void {
    const target: NavTarget = new NavTarget();
    target.tab = tab;
    target.campusSub = campusSub;
    target.learningTab = learningTab;
    emitNavigate(target);
  }

  /** 建议操作点击：按原项目语义跳转（Schedule/Learning 作业/Learning 通知） */
  private handleSuggestedAction(item: SuggestedAction): void {
    if (item.targetTab >= 0) {
      this.navigateTo(item.targetTab, item.campusSub, item.learningTab);
      return;
    }
    this.getUIContext().getPromptAction().showToast({
      message: `${item.title} — ${this.tr('home.comingSoon')}`,
      duration: 2000
    });
  }

  /** 未读通知条目（真实/演示共用：metricUnread 两模式均维护） */
  private buildUnreadItem(): SuggestedAction | null {
    if (Number(this.metricUnread) <= 0) {
      return null;
    }
    const item: SuggestedAction = new SuggestedAction();
    item.id = 'unread-notifications';
    item.title = this.trp('home.suggest.unread', { 'n': this.metricUnread });
    item.detail = this.tr('home.suggest.unreadDetail');
    item.actionLabel = this.tr('home.suggest.openNotices');
    item.targetTab = 1;
    item.learningTab = '通知';
    return item;
  }

  /** 真实模式条目：下一节课 → 最近截止 → 未读通知（对齐原项目 buildTaskPlanItems 数据链） */
  private appendRealSuggestedItems(items: SuggestedAction[]): void {
    const nowMinutes: number = new Date().getHours() * 60 + new Date().getMinutes();
    for (let i: number = 0; i < this.todayEvents.length; i++) {
      const ev: ScheduleEvent = this.todayEvents[i];
      const start: number = parseHHmm(ev.startTime);
      if (start < 0 || start >= nowMinutes) {
        const parts: string[] = [ev.startTime, ev.endTime, ev.location];
        const kept: string[] = [];
        for (let p: number = 0; p < parts.length; p++) {
          if (parts[p].length > 0) {
            kept.push(parts[p]);
          }
        }
        const next: SuggestedAction = new SuggestedAction();
        next.id = 'next-class';
        next.title = this.trp('home.suggest.nextClass', { 'title': ev.title });
        next.detail = kept.join(' · ');
        next.actionLabel = this.tr('home.suggest.openSchedule');
        next.targetTab = 2;
        items.push(next);
        break;
      }
    }

    if (this.ddlTitle.length > 0) {
      const ms: number = parseDeadlineMs(this.ddlDeadline);
      const urgent: boolean = !isNaN(ms) && ms - Date.now() < 2 * 24 * 60 * 60 * 1000;
      const distance: string = formatDeadlineDistance(this.ddlDeadline, this.locale);
      const ddl: SuggestedAction = new SuggestedAction();
      ddl.id = 'next-deadline';
      ddl.title = this.trp('home.suggest.nextDdl', { 'title': this.ddlTitle });
      ddl.detail = this.ddlCourse.length > 0 ? this.ddlCourse + ' · ' + distance : distance;
      ddl.tone = urgent ? BadgeTone.Warning : BadgeTone.Default;
      ddl.actionLabel = this.tr('home.suggest.open');
      ddl.targetTab = 1;
      ddl.learningTab = '作业';
      items.push(ddl);
    }

    const unread: SuggestedAction | null = this.buildUnreadItem();
    if (unread !== null) {
      items.push(unread);
    }
  }

  /** 演示模式条目：演示课表下一节 + 演示作业最近截止 + 演示未读数 */
  private appendDemoSuggestedItems(items: SuggestedAction[]): void {
    const nowMinutes: number = new Date().getHours() * 60 + new Date().getMinutes();
    const courses: CourseItem[] = getTodayCourses();
    for (let i: number = 0; i < courses.length; i++) {
      const start: number = parseHHmm(courses[i].time.split(' - ')[0]);
      if (start < 0 || start >= nowMinutes) {
        const next: SuggestedAction = new SuggestedAction();
        next.id = 'next-class';
        next.title = this.trp('home.suggest.nextClass', { 'title': courses[i].title });
        next.detail = `${courses[i].time} · ${courses[i].location}`;
        next.actionLabel = this.tr('home.suggest.openSchedule');
        next.targetTab = 2;
        items.push(next);
        break;
      }
    }

    const hw: HomeworkItem[] = getHomeworkList();
    if (hw.length > 0) {
      const ddl: SuggestedAction = new SuggestedAction();
      ddl.id = 'next-deadline';
      ddl.title = this.trp('home.suggest.nextDdl', { 'title': hw[0].title });
      ddl.detail = `${hw[0].course} · ${hw[0].deadline}`;
      ddl.tone = hw[0].status === '即将截止' ? BadgeTone.Warning : BadgeTone.Default;
      ddl.actionLabel = this.tr('home.suggest.open');
      ddl.targetTab = 1;
      ddl.learningTab = '作业';
      items.push(ddl);
    }

    const unread: SuggestedAction | null = this.buildUnreadItem();
    if (unread !== null) {
      items.push(unread);
    }
  }

  /** 建议操作条目（对齐原项目 buildTaskPlanItems 排序与 4 条上限；全空回退轻量日） */
  private getSuggestedItems(): SuggestedAction[] {
    const items: SuggestedAction[] = [];
    if (this.isRealMode()) {
      this.appendRealSuggestedItems(items);
    } else {
      this.appendDemoSuggestedItems(items);
    }
    if (items.length === 0) {
      const quiet: SuggestedAction = new SuggestedAction();
      quiet.id = 'quiet-day';
      quiet.title = this.tr('home.suggest.quietTitle');
      quiet.detail = this.tr('home.suggest.quietDetail');
      quiet.actionLabel = this.tr('home.suggest.openSchedule');
      quiet.targetTab = 2;
      items.push(quiet);
    }
    return items.length > 4 ? items.slice(0, 4) : items;
  }

  build() {
    Scroll() {
      Column() {
        SafeTop()

        // ── 头部（eyebrow=问候语·日期 / 标题 / 天气）──
        Row() {
          ScreenHeader({
            eyebrow: `${this.tr(getGreeting())} · ${getDateString()}`,
            title: this.tr('home.title'),
            subtitle: this.weatherSubtitle
          })
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.md })

        // 同步状态行
        Row({ space: Space.sm }) {
          Text(this.tr('home.syncAction'))
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
          Text(this.tr('home.todayFocus'))
            .fontSize(FontSize.h3)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .margin({ bottom: Space.md })

          Row({ space: Space.sm }) {
            MetricPill({ label: this.tr('home.metricClasses'), value: this.metricClasses, tone: BadgeTone.Default })
            MetricPill({ label: this.tr('home.metricTasks'), value: this.metricTasks, tone: BadgeTone.Default })
            MetricPill({ label: this.tr('home.metricUnread'), value: this.metricUnread, tone: BadgeTone.Warning })
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

        // ── 建议操作（对齐原项目 home task_plan：标题/副标题 + 条目 + 底部入口）──
        Column() {
          Column({ space: 2 }) {
            Text(this.tr('home.suggest.title'))
              .fontSize(FontSize.h3)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
            Text(this.tr('home.suggest.subtitle'))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: Space.xs })

          ForEach(this.getSuggestedItems(), (item: SuggestedAction, index: number) => {
            if (index > 0) {
              Divider().color(Theme.divider)
            }
            SuggestedItemRow({
              item: item,
              onTap: () => { this.handleSuggestedAction(item); }
            })
          }, (item: SuggestedAction) => item.id)

          Flex({ wrap: FlexWrap.Wrap }) {
            Text(this.tr('home.qa.emptyClassroom'))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.primary)
              .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
              .borderRadius(Radius.pill)
              .backgroundColor(Theme.primaryMuted)
              .margin({ right: Space.sm, bottom: Space.sm })
              .constraintSize({ maxWidth: '100%' })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => { this.navigateTo(3, 'classroom', ''); })

            Text(this.tr('home.qa.librarySeat'))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.primary)
              .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
              .borderRadius(Radius.pill)
              .backgroundColor(Theme.primaryMuted)
              .margin({ right: Space.sm, bottom: Space.sm })
              .constraintSize({ maxWidth: '100%' })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                this.getUIContext().getPromptAction().showToast({
                  message: `${this.tr('home.qa.librarySeat')} — ${this.tr('home.comingSoon')}`,
                  duration: 2000
                });
              })

            Text(this.tr('home.qa.addDdl'))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.primary)
              .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
              .borderRadius(Radius.pill)
              .backgroundColor(Theme.primaryMuted)
              .margin({ right: Space.sm, bottom: Space.sm })
              .constraintSize({ maxWidth: '100%' })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => { this.navigateTo(1, '', '作业'); })
          }
          .width('100%')
          .margin({ top: Space.sm })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
        .borderRadius(Radius.lg)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.lg, right: Space.lg, top: Space.md })

        // ── 今日课程 ──
        Column() {
          SectionHeader({ title: this.tr('home.sectionTodayCourses') })
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
            Text(this.scheduleOk ? this.tr('home.noClassesToday') : this.tr('home.scheduleDebugging'))
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
