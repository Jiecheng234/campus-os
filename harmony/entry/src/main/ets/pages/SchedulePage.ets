/**
 * SchedulePage — 课表页（块状周网格 + 周选择器）
 * 真实模式：zhjw 周课表（Monday–Sunday JSONP），‹ › 切周、点中间回本周；
 * 演示模式：内置示例课程（与真实数据同构的 ScheduleBlock，复用同一渲染）。
 *
 * 【节次区间换算】起始索引沿用既有阈值分桶（periodIndexFor 语义）；
 * 结束索引按各大节结束时间判定（结束时间 ≤ 哪节结束时间即为该节）；
 * 异常时间跳过/兜底单节并记日志，不阻塞渲染。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader } from '../components/Ui';
import { ScheduleGrid, ScheduleBlock, assignScheduleColorIndexes, scheduleNowLineOffset, SCHEDULE_PERIOD_STARTS, SCHEDULE_PERIOD_ENDS, SCHEDULE_PERIOD_COUNT } from '../components/ScheduleGrid';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusDataService, ScheduleEvent } from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';
import { Log } from '../utils/Logger';
import { I18n } from '../utils/I18n';

const MAX_WEEK_OFFSET: number = 12;
/** 网格单大节单元高度（vp；与 ScheduleGrid cellHeight 同值） */
const GRID_CELL_HEIGHT: number = 72;
/** 时间线刷新间隔（ms）：每分钟重算当前时刻 */
const NOW_TICK_INTERVAL_MS: number = 60000;
/** 各大节结束时间（分钟）：09:35 / 12:15 / 15:05 / 16:55 / 18:40 / 21:45（结束节次判定 + 与时间轴同源） */
const PERIOD_END_MINUTES: number[] = [575, 735, 905, 1015, 1120, 1305];

/** "HH:mm" → 当日分钟数；解析失败返回 -1 */
function parseHm(text: string): number {
  const parts: string[] = text.trim().split(':');
  if (parts.length < 2) {
    return -1;
  }
  const h: number = Number(parts[0]);
  const m: number = Number(parts[1]);
  if (isNaN(h) || isNaN(m)) {
    return -1;
  }
  if (h < 0 || h > 23 || m < 0 || m > 59) {
    return -1;
  }
  return h * 60 + m;
}

/** 开始时间（分钟）→ 起始大节 0-5（沿用既有 periodIndexFor 阈值语义） */
function startPeriodIndex(startMin: number): number {
  if (startMin < 585) { return 0; }
  if (startMin < 780) { return 1; }
  if (startMin < 910) { return 2; }
  if (startMin < 1020) { return 3; }
  if (startMin < 1140) { return 4; }
  return 5;
}

/** 结束时间（分钟）→ 结束大节：不晚于该节结束时间的最小大节（≥ 起始节；超出末节钳制） */
function endPeriodIndex(endMin: number, startIdx: number): number {
  for (let i: number = startIdx; i < PERIOD_END_MINUTES.length; i++) {
    if (endMin <= PERIOD_END_MINUTES[i]) {
      return i;
    }
  }
  return SCHEDULE_PERIOD_COUNT - 1;
}

/** 演示示例（与真实数据同构的块模型；含跨两节/空地点/长地点等边界样例） */
function getMockBlocks(monday: Date): ScheduleBlock[] {
  const defs: string[][] = [
    ['0', '0', '1', '高等数学(1)', '第六教学楼6A118'],
    ['0', '2', '2', '线性代数', '六教6A215'],
    ['0', '3', '3', '新生研讨', '三教1301'],
    ['1', '1', '2', '大学物理B(2)', '四教4302'],
    ['2', '0', '0', '英语阅读', '五教5102'],
    ['3', '3', '3', '体育课', ''],
    ['4', '5', '5', '实验课', '物理楼B1层基础物理实验中心'],
    ['5', '4', '4', '数据结构', '六教6B201'],
  ];
  const blocks: ScheduleBlock[] = [];
  for (let i: number = 0; i < defs.length; i++) {
    const b: ScheduleBlock = new ScheduleBlock();
    b.dayIndex = Number(defs[i][0]);
    b.startPeriod = Number(defs[i][1]);
    b.endPeriod = Number(defs[i][2]);
    b.title = defs[i][3];
    b.location = defs[i][4];
    // 与真实数据同构：日期 = 当周周一 + dayIndex；起止时间取对应大节起止
    const d: Date = addDays(monday, b.dayIndex);
    b.date = `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
    b.startTime = SCHEDULE_PERIOD_STARTS[b.startPeriod];
    b.endTime = SCHEDULE_PERIOD_ENDS[b.endPeriod];
    blocks.push(b);
  }
  return applyScheduleColors(blocks);
}

/**
 * 两段式配色第二段：对整周课程块统一分配 colorIndex（真实/演示共用同一逻辑）。
 * 先映射全部块，再按「课名去重 → 字典序 → 散列基址 → 线性探测顺延」回填，
 * 保证本周不同课名（≤16）零撞色、同名同色、未冲突课程跨周稳定。
 */
function applyScheduleColors(blocks: ScheduleBlock[]): ScheduleBlock[] {
  const titles: string[] = [];
  for (let i: number = 0; i < blocks.length; i++) {
    titles.push(blocks[i].title);
  }
  const colorMap: Map<string, number> = assignScheduleColorIndexes(titles);
  for (let i: number = 0; i < blocks.length; i++) {
    const idx: number | undefined = colorMap.get(blocks[i].title);
    blocks[i].colorIndex = idx !== undefined ? idx : 0;
  }
  return blocks;
}

function mondayOf(date: Date): Date {
  const d: Date = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const wd: number = d.getDay();
  d.setDate(d.getDate() + (wd === 0 ? -6 : 1 - wd));
  return d;
}

function addDays(date: Date, days: number): Date {
  const d: Date = new Date(date.getTime());
  d.setDate(d.getDate() + days);
  return d;
}

function pad2(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

function ymdCompact(d: Date): string {
  return `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;
}

@Component
export struct SchedulePage {
  /** 语言订阅：语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  /** 日期显示文案（按当前语言格式化：zh "{m}月{d}日" / en "{m}/{d}"） */
  private fmtDate(d: Date): string {
    return this.trp('schedule.dateMd', { 'm': String(d.getMonth() + 1), 'd': String(d.getDate()) });
  }

  @State weekOffset: number = 0;
  @State weekNumber: number = 0;
  @State rangeLabel: string = '';
  @State blocks: ScheduleBlock[] = [];
  @State dateLabels: string[] = [];
  @State loading: boolean = false;
  @State hint: string = '';
  /** 详情弹层：是否展开（bindSheet $$ 双向绑定） */
  @State detailVisible: boolean = false;
  /** 详情弹层：当前选中的课程块（关闭时清空） */
  @State detailBlock: ScheduleBlock | null = null;
  /** 当前时刻距 0 点的分钟数（-1 = 未初始化；驱动时间指示线） */
  @State nowMinuteOfDay: number = -1;
  /** 今天所在日列下标 0-6（仅 weekOffset === 0 有效，否则 -1 不显示指示线） */
  @State todayIndex: number = -1;
  /** 时间线 60s 计时器句柄（aboutToDisappear 清理） */
  private nowTimerId: number = -1;
  /** NOW_LINE 日志去重键：仅跨大节/进入隐藏态时输出，避免每分钟一条 */
  private lastNowLineLogKey: string = '';

  /** 立即重算当前时刻与今日列索引；仅在指示线状态跨大节变化时输出一条换算日志 */
  private recomputeNowState(): void {
    const now: Date = new Date();
    this.nowMinuteOfDay = now.getHours() * 60 + now.getMinutes();
    this.todayIndex = this.weekOffset === 0 ? (now.getDay() + 6) % 7 : -1;
    if (this.todayIndex < 0) {
      this.lastNowLineLogKey = '';
      return;
    }
    const offset: number = scheduleNowLineOffset(this.nowMinuteOfDay, GRID_CELL_HEIGHT);
    const logKey: string = String(this.todayIndex) + ':'
      + (offset >= 0 ? String(Math.min(5, Math.floor(offset / GRID_CELL_HEIGHT))) : 'hidden');
    if (logKey !== this.lastNowLineLogKey) {
      this.lastNowLineLogKey = logKey;
      Log.i('SchedAct', 'NOW_LINE day=%{public}d minute=%{public}d offset=%{public}s',
        this.todayIndex, this.nowMinuteOfDay, offset.toFixed(1));
    }
  }

  /** 启动时间线计时器：立即重算一次 + 每 60s 刷新 */
  private startNowTicker(): void {
    this.recomputeNowState();
    this.nowTimerId = setInterval((): void => {
      this.recomputeNowState();
    }, NOW_TICK_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    if (this.nowTimerId >= 0) {
      clearInterval(this.nowTimerId);
      this.nowTimerId = -1;
    }
  }

  /** 当周周一 → 7 个日列日期标签（MM-DD，随周导航更新） */
  private buildDateLabels(monday: Date): string[] {
    const labels: string[] = [];
    for (let i: number = 0; i < 7; i++) {
      const d: Date = addDays(monday, i);
      labels.push(pad2(d.getMonth() + 1) + '-' + pad2(d.getDate()));
    }
    return labels;
  }

  /** 星期标签（schedule.day0-6 经词典翻译） */
  private dayLabelList(): string[] {
    const labels: string[] = [];
    for (let i: number = 0; i < 7; i++) {
      labels.push(this.tr('schedule.day' + String(i)));
    }
    return labels;
  }

  /** 时间轴标签（各大节"起-止"，纯数字无需 i18n） */
  private axisLabelList(): string[] {
    const labels: string[] = [];
    for (let i: number = 0; i < SCHEDULE_PERIOD_STARTS.length; i++) {
      labels.push(SCHEDULE_PERIOD_STARTS[i] + '-' + SCHEDULE_PERIOD_ENDS[i]);
    }
    return labels;
  }

  aboutToAppear(): void {
    this.startNowTicker();
    if (AuthManager.isLoggedIn() && !StateManager.isDemoMode()) {
      this.loadWeek(0);
      return;
    }
    const monday: Date = mondayOf(new Date());
    this.blocks = getMockBlocks(monday);
    this.dateLabels = this.buildDateLabels(monday);
    this.rangeLabel = this.fmtDate(monday) + ' – ' + this.fmtDate(addDays(monday, 6));
    this.hint = 'schedule.demoHint';
  }

  /** 加载指定周（相对本周偏移）的课表 */
  private async loadWeek(offset: number): Promise<void> {
    this.weekOffset = offset;
    // 切周后今日列立即失效/生效（不等下一次 60s 计时）
    this.recomputeNowState();
    this.loading = true;
    this.hint = '';
    const monday: Date = addDays(mondayOf(new Date()), offset * 7);
    const sunday: Date = addDays(monday, 6);
    this.rangeLabel = this.fmtDate(monday) + ' – ' + this.fmtDate(sunday);
    this.dateLabels = this.buildDateLabels(monday);

    const service: CampusDataService = SessionManager.getCampusDataService();
    const firstDay: string = await service.fetchSemesterInfo();
    if (firstDay.length >= 10) {
      const start: Date = new Date(firstDay.substring(0, 10) + 'T00:00:00');
      const weeks: number = Math.floor((monday.getTime() - start.getTime()) / 604800000) + 1;
      this.weekNumber = weeks > 0 ? weeks : 0;
    } else {
      this.weekNumber = 0;
    }

    try {
      const events: ScheduleEvent[] = await service.fetchScheduleEvents(ymdCompact(monday), ymdCompact(sunday));
      if (service.scheduleStatus !== 'ok') {
        this.blocks = [];
        this.hint = 'schedule.fetchFailedSession';
      } else {
        this.blocks = this.mapEventsToBlocks(events);
        this.hint = this.blocks.length === 0 ? 'schedule.emptyWeek' : '';
      }
    } catch (e) {
      this.blocks = [];
      this.hint = 'schedule.fetchFailed';
      Log.i('SchedAct', 'loadWeek ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    this.loading = false;
  }

  /**
   * zhjw 事件 → 课程块（节次区间换算）：
   * 起始按既有阈值分桶；结束按大节结束时间判定；异常时间跳过或兜底单节并记日志。
   */
  private mapEventsToBlocks(events: ScheduleEvent[]): ScheduleBlock[] {
    const sorted: ScheduleEvent[] = events.slice(0).sort((a: ScheduleEvent, b: ScheduleEvent): number => {
      return a.startTime.localeCompare(b.startTime);
    });
    const blocks: ScheduleBlock[] = [];
    for (let i: number = 0; i < sorted.length; i++) {
      const ev: ScheduleEvent = sorted[i];
      if (ev.date.length < 10) {
        Log.i('SchedAct', 'MAP_SKIP date=%{public}s title=%{public}s', ev.date, ev.title);
        continue;
      }
      const d: Date = new Date(ev.date.substring(0, 10) + 'T00:00:00');
      if (isNaN(d.getTime())) {
        Log.i('SchedAct', 'MAP_SKIP badDate=%{public}s title=%{public}s', ev.date, ev.title);
        continue;
      }
      const startMin: number = parseHm(ev.startTime);
      if (startMin < 0) {
        Log.i('SchedAct', 'MAP_SKIP badStart=%{public}s title=%{public}s', ev.startTime, ev.title);
        continue;
      }
      const startIdx: number = startPeriodIndex(startMin);
      const endMin: number = parseHm(ev.endTime);
      let endIdx: number = startIdx;
      if (endMin < 0 || endMin <= startMin) {
        // 结束时间缺失/非法/不晚于开始：兜底为单节（保留课程可见），记日志
        Log.i('SchedAct', 'MAP_FALLBACK_SINGLE end=%{public}s title=%{public}s', ev.endTime, ev.title);
      } else {
        endIdx = endPeriodIndex(endMin, startIdx);
      }
      const block: ScheduleBlock = new ScheduleBlock();
      block.dayIndex = (d.getDay() + 6) % 7;
      block.startPeriod = startIdx;
      block.endPeriod = endIdx;
      block.title = ev.title;
      block.location = ev.location;
      block.date = ev.date.substring(0, 10);
      block.startTime = ev.startTime;
      block.endTime = ev.endTime;
      blocks.push(block);
    }
    return applyScheduleColors(blocks);
  }

  // ── 课程详情弹层（US1）：取值方法（detailBlock 空安全兜底，文案全部走词典） ──

  private detailTitleText(): string {
    return this.detailBlock !== null ? this.detailBlock.title : '';
  }

  /** 详情日期：YYYY-MM-DD → 按语言格式化；解析失败原样展示 */
  private detailDateText(): string {
    const b: ScheduleBlock | null = this.detailBlock;
    if (b === null) {
      return '';
    }
    if (b.date.length >= 10) {
      const d: Date = new Date(b.date.substring(0, 10) + 'T00:00:00');
      if (!isNaN(d.getTime())) {
        return this.fmtDate(d);
      }
    }
    return b.date;
  }

  /** 星期：schedule.day0-6（周一为 0） */
  private detailWeekdayText(): string {
    const b: ScheduleBlock | null = this.detailBlock;
    if (b === null || b.dayIndex < 0 || b.dayIndex > 6) {
      return '';
    }
    return this.tr('schedule.day' + String(b.dayIndex));
  }

  /** 节次区间（1 基）：第 {start}–{end} 节 */
  private detailPeriodText(): string {
    const b: ScheduleBlock | null = this.detailBlock;
    if (b === null) {
      return '';
    }
    return this.trp('schedule.detail.periodRange',
      { 'start': String(b.startPeriod + 1), 'end': String(b.endPeriod + 1) });
  }

  /** 起止时间：endTime 为空时只显示 startTime */
  private detailTimeText(): string {
    const b: ScheduleBlock | null = this.detailBlock;
    if (b === null) {
      return '';
    }
    if (b.endTime.trim().length === 0) {
      return b.startTime;
    }
    return b.startTime + ' – ' + b.endTime;
  }

  /** 地点：空/纯空白 → 「未填写」占位 */
  private detailLocationText(): string {
    const b: ScheduleBlock | null = this.detailBlock;
    if (b === null) {
      return '';
    }
    const loc: string = b.location.trim();
    return loc.length > 0 ? loc : this.tr('schedule.detail.noLocation');
  }

  @Builder
  private DetailRowBuilder(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
        .width(76)
      Text(value)
        .fontSize(FontSize.body)
        .fontColor(Theme.text)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private DetailSheetBuilder() {
    // 内容区可滚动：360vp 固定高度下，超长课程名/地点仍可完整查看
    Scroll() {
      Column() {
        // 弹层标题区：小标签 + 课程名（完整展示，不截断）
        Column({ space: Space.xs }) {
          Text(this.tr('schedule.detail.title'))
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
          Text(this.detailTitleText())
            .fontSize(FontSize.h2)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: Space.lg, bottom: Space.md })

        Divider()
          .color(Theme.divider)

        // 详情字段：日期 / 星期 / 节次 / 时间 / 地点
        Column({ space: Space.md }) {
          this.DetailRowBuilder(this.tr('schedule.detail.date'), this.detailDateText())
          this.DetailRowBuilder(this.tr('schedule.detail.weekday'), this.detailWeekdayText())
          this.DetailRowBuilder(this.tr('schedule.detail.periods'), this.detailPeriodText())
          this.DetailRowBuilder(this.tr('schedule.detail.time'), this.detailTimeText())
          this.DetailRowBuilder(this.tr('schedule.location'), this.detailLocationText())
        }
        .width('100%')
        .padding({ left: Space.lg, right: Space.lg, top: Space.md, bottom: Space.lg })
      }
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      SafeTop()

      // 头部
      Column() {
        ScreenHeader({
          eyebrow: 'SCHEDULE',
          title: this.tr('schedule.title'),
          subtitle: this.rangeLabel.length > 0
            ? (this.weekNumber > 0
              ? `${this.rangeLabel} · ${this.trp('schedule.week', { 'n': String(this.weekNumber) })}`
              : this.rangeLabel)
            : this.tr('schedule.subtitle'),
        })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.sm })

      // 周选择器（36×36 白底方块 ‹ › + 周标签，点中间回本周）
      Row() {
        Text('‹')
          .fontSize(20)
          .fontColor(Theme.text)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(Radius.sm)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .onClick(() => {
            if (!this.loading && this.weekOffset > -MAX_WEEK_OFFSET) {
              this.loadWeek(this.weekOffset - 1);
            }
          })

        Column() {
          Text(this.weekNumber > 0
            ? this.trp('schedule.week', { 'n': String(this.weekNumber) })
            : (this.weekOffset === 0 ? this.tr('schedule.thisWeek') : this.tr('schedule.offSemester')))
            .fontSize(FontSize.h3)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.rangeLabel)
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
        }
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        .onClick(() => {
          if (!this.loading && this.weekOffset !== 0) {
            this.loadWeek(0);
          }
        })

        Text('›')
          .fontSize(20)
          .fontColor(Theme.text)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(Radius.sm)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .onClick(() => {
            if (!this.loading && this.weekOffset < MAX_WEEK_OFFSET) {
              this.loadWeek(this.weekOffset + 1);
            }
          })
      }
      .width('100%')
      .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })

      // 加载/空态提示行
      if (this.loading || this.hint.length > 0) {
        Row({ space: Space.sm }) {
          if (this.loading) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(Theme.primary)
          }
          Text(this.loading ? this.tr('status.loading') : this.tr(this.hint))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: Space.xs, bottom: Space.xs })
      }

      // 分割线
      Divider()
        .color(Theme.divider)

      // 块状课表网格（时间轴 + 日列头 + 跨节课程块；纯展示，字样经 props 传入）
      Scroll() {
        ScheduleGrid({
          blocks: this.blocks,
          axisLabels: this.axisLabelList(),
          dayLabels: this.dayLabelList(),
          dateLabels: this.dateLabels,
          cellHeight: GRID_CELL_HEIGHT,
          todayIndex: this.todayIndex,
          nowMinuteOfDay: this.nowMinuteOfDay,
          onBlockSelect: (block: ScheduleBlock): void => {
            this.detailBlock = block;
            this.detailVisible = true;
          },
        })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.surface)
    // 课程详情底部弹层（唯一 bindSheet；$$ 双向绑定关闭，onDisappear 清空选中块）
    .bindSheet($$this.detailVisible, this.DetailSheetBuilder(), {
      height: 360,
      dragBar: false,
      showClose: true,
      // 仅禁用下滑关闭；关闭按钮 / 点击遮罩 / 返回键仍可关闭
      onWillDismiss: (dismissAction: DismissSheetAction) => {
        if (dismissAction.reason !== DismissReason.SLIDE_DOWN) {
          dismissAction.dismiss();
        }
      },
      onDisappear: () => {
        this.detailBlock = null;
        this.detailVisible = false;
      },
    })
  }
}
