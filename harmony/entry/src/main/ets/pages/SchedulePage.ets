/**
 * SchedulePage — 课表页（周网格 + 周选择器）
 * 真实模式：zhjw 周课表（Monday–Sunday JSONP），‹ › 切周、点中间回本周；
 * 演示模式：内置示例课程。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader } from '../components/Ui';
import { SessionManager } from '../services/auth/SessionManager';
import { CampusDataService, ScheduleEvent } from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';
import { Log } from '../utils/Logger';

class ScheduleCell {
  day: number = 0;
  period: number = 0;
  title: string = '';
  location: string = '';
}

const WEEKDAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
/** 大节起始时间（清华：1-2节 08:00 / 3-4节 09:50 / 5-6节 13:30 / 7-8节 15:20 / 9-10节 17:05 / 11-12节 19:20） */
const PERIODS: string[] = ['08:00', '09:50', '13:30', '15:20', '17:05', '19:20'];
const MAX_WEEK_OFFSET: number = 12;

function getMockCells(): ScheduleCell[] {
  const cells: ScheduleCell[] = [];
  const defs: number[][] = [
    [0, 0], [0, 2], [0, 3],
    [1, 1],
    [2, 0],
    [3, 3],
    [5, 4],
  ];
  const titles: string[] = ['高等数学', '线性代数', '体育课', '大学物理', '英语阅读', '实验课', '新生研讨'];
  const locations: string[] = ['六教6A118', '六教6A215', '东操', '四教4302', '五教5102', '物理楼B1', '三教1301'];
  for (let i: number = 0; i < defs.length; i++) {
    const c: ScheduleCell = new ScheduleCell();
    c.day = defs[i][0];
    c.period = defs[i][1];
    c.title = titles[i];
    c.location = locations[i];
    cells.push(c);
  }
  return cells;
}

function findCell(cells: ScheduleCell[], day: number, period: number): ScheduleCell | null {
  for (let i: number = 0; i < cells.length; i++) {
    if (cells[i].day === day && cells[i].period === period) {
      return cells[i];
    }
  }
  return null;
}

/** 事件开始时间（HH:mm）→ 大节序 0-5 */
function periodIndexFor(start: string): number {
  const parts: string[] = start.split(':');
  if (parts.length < 2) {
    return 0;
  }
  const t: number = Number(parts[0]) * 60 + Number(parts[1]);
  if (isNaN(t)) {
    return 0;
  }
  if (t < 585) { return 0; }
  if (t < 780) { return 1; }
  if (t < 910) { return 2; }
  if (t < 1020) { return 3; }
  if (t < 1140) { return 4; }
  return 5;
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

function monthDay(d: Date): string {
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

@Component
export struct SchedulePage {
  @State weekOffset: number = 0;
  @State weekNumber: number = 0;
  @State rangeLabel: string = '';
  @State cells: ScheduleCell[] = [];
  @State loading: boolean = false;
  @State hint: string = '';

  aboutToAppear(): void {
    if (AuthManager.isLoggedIn() && !StateManager.isDemoMode()) {
      this.loadWeek(0);
      return;
    }
    const monday: Date = mondayOf(new Date());
    this.cells = getMockCells();
    this.rangeLabel = monthDay(monday) + ' – ' + monthDay(addDays(monday, 6));
    this.hint = '演示数据 · 登录后显示真实课表';
  }

  /** 加载指定周（相对本周偏移）的课表 */
  private async loadWeek(offset: number): Promise<void> {
    this.weekOffset = offset;
    this.loading = true;
    this.hint = '';
    const monday: Date = addDays(mondayOf(new Date()), offset * 7);
    const sunday: Date = addDays(monday, 6);
    this.rangeLabel = monthDay(monday) + ' – ' + monthDay(sunday);

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
        this.cells = [];
        this.hint = '课表拉取失败（教务会话未打通）';
      } else {
        this.cells = this.mapEventsToCells(events);
        this.hint = this.cells.length === 0 ? '本周无课程安排' : '';
      }
    } catch (e) {
      this.cells = [];
      this.hint = '课表拉取失败';
      Log.i('SchedAct', 'loadWeek ex=%{public}s', e instanceof Error ? e.message : String(e));
    }
    this.loading = false;
  }

  /** zhjw 事件 → 网格单元（同格多课取最早开始的一门） */
  private mapEventsToCells(events: ScheduleEvent[]): ScheduleCell[] {
    const sorted: ScheduleEvent[] = events.slice(0).sort((a: ScheduleEvent, b: ScheduleEvent): number => {
      return a.startTime.localeCompare(b.startTime);
    });
    const cells: ScheduleCell[] = [];
    for (let i: number = 0; i < sorted.length; i++) {
      const ev: ScheduleEvent = sorted[i];
      if (ev.date.length < 10) {
        continue;
      }
      const d: Date = new Date(ev.date.substring(0, 10) + 'T00:00:00');
      if (isNaN(d.getTime())) {
        continue;
      }
      const dayIdx: number = (d.getDay() + 6) % 7;
      const periodIdx: number = periodIndexFor(ev.startTime);
      if (findCell(cells, dayIdx, periodIdx) !== null) {
        continue;
      }
      const cell: ScheduleCell = new ScheduleCell();
      cell.day = dayIdx;
      cell.period = periodIdx;
      cell.title = ev.title;
      cell.location = ev.location;
      cells.push(cell);
    }
    return cells;
  }

  build() {
    Column() {
      SafeTop()

      // 头部
      Column() {
        ScreenHeader({
          eyebrow: 'SCHEDULE',
          title: '课表',
          subtitle: this.rangeLabel.length > 0
            ? (this.weekNumber > 0 ? `${this.rangeLabel} · 第 ${this.weekNumber} 周` : this.rangeLabel)
            : '每周课程安排',
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
          Text(this.weekNumber > 0 ? `第 ${this.weekNumber} 周` : (this.weekOffset === 0 ? '本周' : '非本学期周次'))
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
          Text(this.loading ? '加载中...' : this.hint)
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

      // 星期头
      Row() {
        Blank().width(56).height(36)
        ForEach(WEEKDAYS, (day: string) => {
          Text(day)
            .fontSize(12)
            .fontColor(Theme.textMuted)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
        })
      }
      .width('100%')
      .padding({ top: 8, bottom: 4 })
      .border({ width: { bottom: 1 }, color: Theme.divider })

      // 课程网格
      Scroll() {
        Column() {
          ForEach(PERIODS, (time: string, periodIdx: number) => {
            Row() {
              // 时间列
              Column() {
                Text(time)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
                  .textAlign(TextAlign.Center)
              }
              .width(56)
              .height(64)
              .justifyContent(FlexAlign.Start)
              .padding({ top: 8 })

              // 每天一列
              ForEach(WEEKDAYS, (dayName: string, dayIdx: number) => {
                Column() {
                  if (findCell(this.cells, dayIdx, periodIdx) !== null) {
                    Column() {
                      Text(findCell(this.cells, dayIdx, periodIdx)!.title)
                        .fontSize(10)
                        .fontColor(Theme.primaryDark)
                        .maxLines(1)
                      Text(findCell(this.cells, dayIdx, periodIdx)!.location)
                        .fontSize(9)
                        .fontColor(Theme.primary)
                        .maxLines(1)
                    }
                    .width('90%')
                    .height('90%')
                    .padding(3)
                    .borderRadius(6)
                    .backgroundColor('rgba(124,92,250,0.12)')
                    .border({ width: 1, color: 'rgba(124,92,250,0.25)' })
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                  }
                }
                .layoutWeight(1)
                .height(64)
                .border({ width: { right: 1, bottom: 1 }, color: Theme.divider })
                .alignItems(HorizontalAlign.Center)
                .justifyContent(FlexAlign.Center)
              })
            }
            .width('100%')
          })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.surface)
  }
}
