/**
 * ClassroomPage — 空教室查询（真实：zhjw 教学楼列表 + 按周教室状态；演示：内置示例）
 * 每天 6 节、每周 7 天（status 数组 42 项），UI 按 activeDay 切片展示。
 */
import { Theme, SafeTop } from './Theme';
import { DetailHeader } from '../components/Ui';
import { SessionManager } from '../services/auth/SessionManager';
import {
  ClassroomBuilding,
  ClassroomPeriod,
  ClassroomStateResult,
  ClassroomStateRow,
  ClassroomStatus,
  CLASSROOM_PERIODS,
} from '../services/campus/CampusDataService';
import { AuthManager } from '../state/AuthManager';
import { StateManager } from '../state/StateManager';

const DAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
/** 每天 6 节（与上游 status 7×6 约定绑定） */
const PERIODS_PER_DAY: number = CLASSROOM_PERIODS.length;

const ALL_STATUSES: ClassroomStatus[] = [
  ClassroomStatus.AVAILABLE,
  ClassroomStatus.TEACHING,
  ClassroomStatus.EXAM,
  ClassroomStatus.BORROWED,
  ClassroomStatus.DISABLED,
];

function statusColorOf(status: ClassroomStatus): string {
  if (status === ClassroomStatus.AVAILABLE) {
    return Theme.success;
  }
  if (status === ClassroomStatus.TEACHING) {
    return Theme.primary;
  }
  if (status === ClassroomStatus.EXAM) {
    return Theme.error;
  }
  if (status === ClassroomStatus.BORROWED) {
    return Theme.warning;
  }
  return '#9CA3AF';
}

function statusLabelOf(status: ClassroomStatus): string {
  if (status === ClassroomStatus.AVAILABLE) {
    return '空闲';
  }
  if (status === ClassroomStatus.TEACHING) {
    return '上课';
  }
  if (status === ClassroomStatus.EXAM) {
    return '考试';
  }
  if (status === ClassroomStatus.BORROWED) {
    return '借用';
  }
  if (status === ClassroomStatus.DISABLED) {
    return '停用';
  }
  return '保留';
}

function todayWeekdayIndex(): number {
  const d: number = new Date().getDay();
  return d === 0 ? 6 : d - 1;
}

function pad2Local(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

/** 上游教室名格式 "6A101:60(人)" → id / capacity 两段 */
class RoomDisplay {
  id: string = '';
  capacity: string = '';
}

function splitClassroomName(name: string): RoomDisplay {
  const r: RoomDisplay = new RoomDisplay();
  const idx: number = name.indexOf(':');
  if (idx < 0) {
    r.id = name.trim();
    return r;
  }
  r.id = name.substring(0, idx).trim();
  r.capacity = name.substring(idx + 1).replace(/[（(].*?[)）]/g, '').trim();
  return r;
}

/** 当天状态切片（day*6 .. day*6+6）；空切片回退为全空闲展示 */
function statusSlice(row: ClassroomStateRow, day: number): ClassroomStatus[] {
  const s: ClassroomStatus[] = row.status.slice(day * PERIODS_PER_DAY, (day + 1) * PERIODS_PER_DAY);
  if (s.length === 0) {
    const full: ClassroomStatus[] = [];
    for (let i: number = 0; i < PERIODS_PER_DAY; i++) {
      full.push(ClassroomStatus.AVAILABLE);
    }
    return full;
  }
  return s;
}

function freeCountOf(row: ClassroomStateRow, day: number): number {
  const s: ClassroomStatus[] = statusSlice(row, day);
  let n: number = 0;
  for (let i: number = 0; i < s.length; i++) {
    if (s[i] === ClassroomStatus.AVAILABLE) {
      n++;
    }
  }
  return n;
}

function isAllFree(row: ClassroomStateRow, day: number): boolean {
  const s: ClassroomStatus[] = statusSlice(row, day);
  return s.length > 0 && freeCountOf(row, day) === s.length;
}

// ---------------- 演示数据 ----------------

function demoBuilding(name: string, week: number, searchName: string): ClassroomBuilding {
  const b: ClassroomBuilding = new ClassroomBuilding();
  b.name = name;
  b.weekNumber = week;
  b.searchName = searchName;
  return b;
}

const DEMO_BUILDINGS: ClassroomBuilding[] = [
  demoBuilding('六教', 15, 'demo-0'),
  demoBuilding('四教', 15, 'demo-1'),
  demoBuilding('五教', 15, 'demo-2'),
  demoBuilding('新水', 15, 'demo-3'),
  demoBuilding('三教', 15, 'demo-4'),
];

function demoStatusAt(buildingIdx: number, roomIdx: number, slot: number, week: number): ClassroomStatus {
  const seed: number = buildingIdx * 53 + roomIdx * 11 + slot * 3 + week;
  if (seed % 23 === 0) {
    return ClassroomStatus.DISABLED;
  }
  if (seed % 11 === 0) {
    return ClassroomStatus.EXAM;
  }
  if (seed % 5 === 0) {
    return ClassroomStatus.TEACHING;
  }
  if (seed % 17 === 0) {
    return ClassroomStatus.BORROWED;
  }
  return ClassroomStatus.AVAILABLE;
}

function buildDemoState(buildingIdx: number, week: number): ClassroomStateResult {
  const result: ClassroomStateResult = new ClassroomStateResult();
  result.currentWeekNumber = week;
  const wns: number[] = [];
  for (let w: number = week - 2; w <= week + 2; w++) {
    if (w >= 1) {
      wns.push(w);
    }
  }
  result.validWeekNumbers = wns;
  // 本周日期按真实日历生成
  const now: Date = new Date();
  const monday: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() - todayWeekdayIndex());
  const dates: string[] = [];
  for (let i: number = 0; i < 7; i++) {
    const d: Date = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
    dates.push(pad2Local(d.getMonth() + 1) + '-' + pad2Local(d.getDate()));
  }
  result.datesOfCurrentWeek = dates;
  const prefixes: string[] = ['6', '4', '5', 'S', '3'];
  const caps: number[] = [60, 80, 120, 40];
  const prefix: string = prefixes[buildingIdx % prefixes.length];
  const rooms: ClassroomStateRow[] = [];
  for (let r: number = 0; r < 8; r++) {
    const row: ClassroomStateRow = new ClassroomStateRow();
    row.name = `${prefix}A${101 + r}:${caps[r % caps.length]}(人)`;
    const status: ClassroomStatus[] = [];
    for (let slot: number = 0; slot < 7 * PERIODS_PER_DAY; slot++) {
      status.push(demoStatusAt(buildingIdx, r, slot, week));
    }
    row.status = status;
    rooms.push(row);
  }
  result.classroomStates = rooms;
  return result;
}

@Component
export struct ClassroomPage {
  onBack: () => void = () => {};
  @State buildings: ClassroomBuilding[] = [];
  @State selectedSearchName: string = '';
  @State week: number = 0;
  @State activeDay: number = todayWeekdayIndex();
  @State stateResult: ClassroomStateResult = new ClassroomStateResult();
  @State hasState: boolean = false;
  @State loading: boolean = false;
  @State errorText: string = '';
  @State stateLoading: boolean = false;
  @State stateErrorText: string = '';
  private isReal: boolean = false;

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.loadList();
    } else {
      this.buildings = DEMO_BUILDINGS;
      this.selectedSearchName = DEMO_BUILDINGS[0].searchName;
      this.week = DEMO_BUILDINGS[0].weekNumber;
      this.loadState();
    }
  }

  private async loadList(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const list: ClassroomBuilding[] =
        await SessionManager.getCampusDataService().fetchClassroomList();
      this.buildings = list;
      // 已选楼栋仍在列表中则保留（刷新不覆盖选择）
      let stillSelected: boolean = false;
      for (let i: number = 0; i < list.length; i++) {
        if (list[i].searchName === this.selectedSearchName) {
          stillSelected = true;
          break;
        }
      }
      if (!stillSelected && list.length > 0) {
        this.selectedSearchName = list[0].searchName;
        this.week = list[0].weekNumber;
      }
      this.loading = false;
      await this.loadState();
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
      this.loading = false;
    }
  }

  private async loadState(): Promise<void> {
    if (this.selectedSearchName.length === 0 || this.week <= 0) {
      return;
    }
    this.stateLoading = true;
    this.stateErrorText = '';
    this.hasState = false;
    try {
      const result: ClassroomStateResult = this.isReal
        ? await SessionManager.getCampusDataService().fetchClassroomState(this.selectedSearchName, this.week)
        : buildDemoState(this.demoBuildingIdx(), this.week);
      this.stateResult = result;
      this.hasState = true;
    } catch (e) {
      this.stateErrorText = e instanceof Error ? e.message : String(e);
    }
    this.stateLoading = false;
  }

  private demoBuildingIdx(): number {
    if (this.selectedSearchName.length > 5) {
      const n: number = Number(this.selectedSearchName.substring(5));
      if (!isNaN(n)) {
        return n;
      }
    }
    return 0;
  }

  private currentBuildingName(): string {
    for (let i: number = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].searchName === this.selectedSearchName) {
        return this.buildings[i].name;
      }
    }
    return '';
  }

  private selectedBuildingWeekNumber(): number {
    for (let i: number = 0; i < this.buildings.length; i++) {
      if (this.buildings[i].searchName === this.selectedSearchName) {
        return this.buildings[i].weekNumber;
      }
    }
    return 0;
  }

  private isTodayCell(i: number): boolean {
    return i === todayWeekdayIndex() && this.week === this.selectedBuildingWeekNumber();
  }

  private freeRoomCount(): number {
    let n: number = 0;
    const rows: ClassroomStateRow[] = this.stateResult.classroomStates;
    for (let i: number = 0; i < rows.length; i++) {
      if (isAllFree(rows[i], this.activeDay)) {
        n++;
      }
    }
    return n;
  }

  @Builder RightAction() {
    if (this.loading || this.stateLoading) {
      LoadingProgress()
        .width(18)
        .height(18)
        .color(Theme.primary)
    } else {
      Text('刷新')
        .fontSize(13)
        .fontColor(Theme.primary)
        .onClick(() => {
          if (this.isReal) {
            this.loadList();
          } else {
            this.loadState();
          }
        })
    }
  }

  @Builder RoomRow(row: ClassroomStateRow) {
    Row() {
      Column() {
        Text(splitClassroomName(row.name).id)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
        Text(`${freeCountOf(row, this.activeDay)}/${statusSlice(row, this.activeDay).length} 节空`)
          .fontSize(10)
          .fontColor(Theme.textMuted)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(3)

      Text(splitClassroomName(row.name).capacity.length > 0
        ? splitClassroomName(row.name).capacity : '—')
        .fontSize(13)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)

      Row({ space: 3 }) {
        ForEach(statusSlice(row, this.activeDay), (st: ClassroomStatus, i: number) => {
          Column()
            .layoutWeight(1)
            .height(20)
            .borderRadius(3)
            .backgroundColor(statusColorOf(st))
        }, (st: ClassroomStatus, i: number) => `${row.name}-${i}`)
      }
      .layoutWeight(5)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(10)
    .backgroundColor(Theme.surface)
    .border({
      width: 1,
      color: isAllFree(row, this.activeDay) ? Theme.success : Theme.borderSubtle,
    })
    .margin({ bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({
        title: '空教室查询',
        onBack: () => { this.onBack(); },
        right: (): void => { this.RightAction(); },
      })

      Divider().color(Theme.divider)

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(Theme.primary)
          Text('正在加载教学楼列表...')
            .fontSize(13)
            .fontColor(Theme.textMuted)
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column({ space: 8 }) {
          Text('教学楼列表加载失败')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.errorText)
            .fontSize(12)
            .fontColor(Theme.textMuted)
            .textAlign(TextAlign.Center)
          Text('重试')
            .fontSize(13)
            .fontColor(Theme.primary)
            .padding({ left: 16, right: 16, top: 6, bottom: 6 })
            .borderRadius(8)
            .border({ width: 1, color: Theme.primary })
            .onClick(() => { this.loadList(); })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 32, right: 32 })
      } else {
        Column() {
          // 教学楼芯片
          Scroll() {
            Row() {
              ForEach(this.buildings, (b: ClassroomBuilding) => {
                Text(b.name)
                  .fontSize(13)
                  .fontColor(this.selectedSearchName === b.searchName
                    ? Theme.textInvert : Theme.textSecondary)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .borderRadius(999)
                  .backgroundColor(this.selectedSearchName === b.searchName
                    ? Theme.primary : Theme.surfaceAlt)
                  .margin({ right: 8 })
                  .onClick(() => {
                    if (this.selectedSearchName !== b.searchName) {
                      this.selectedSearchName = b.searchName;
                      this.week = b.weekNumber;
                      this.loadState();
                    }
                  })
              }, (b: ClassroomBuilding) => b.searchName)
            }
            .padding({ left: 16, right: 16, top: 10, bottom: 8 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          // 周次选择
          if (this.hasState && this.stateResult.validWeekNumbers.length > 0) {
            Scroll() {
              Row() {
                ForEach(this.stateResult.validWeekNumbers, (w: number) => {
                  Text(`第 ${w} 周`)
                    .fontSize(12)
                    .fontWeight(this.week === w ? FontWeight.Medium : FontWeight.Normal)
                    .fontColor(this.week === w ? Theme.primary : Theme.textSecondary)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(8)
                    .backgroundColor(this.week === w ? Theme.primaryMuted : Theme.surfaceAlt)
                    .margin({ right: 8 })
                    .onClick(() => {
                      if (this.week !== w) {
                        this.week = w;
                        this.loadState();
                      }
                    })
                }, (w: number) => w.toString())
              }
              .padding({ left: 16, right: 16, bottom: 8 })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          // 周一 → 周日
          Row() {
            ForEach(DAYS, (d: string, i: number) => {
              Column() {
                Text(`周${d}${this.isTodayCell(i) ? '·今' : ''}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.activeDay === i ? Theme.textInvert : Theme.text)
                if (this.hasState && i < this.stateResult.datesOfCurrentWeek.length
                  && this.stateResult.datesOfCurrentWeek[i].length > 0) {
                  Text(this.stateResult.datesOfCurrentWeek[i])
                    .fontSize(10)
                    .fontColor(this.activeDay === i ? Theme.textInvert : Theme.textMuted)
                    .margin({ top: 2 })
                }
              }
              .layoutWeight(1)
              .padding({ top: 8, bottom: 8 })
              .alignItems(HorizontalAlign.Center)
              .backgroundColor(this.activeDay === i ? Theme.primary : Color.Transparent)
              .onClick(() => { this.activeDay = i; })
            }, (d: string) => d)
          }
          .width('100%')
          .margin({ left: 16, right: 16 })
          .backgroundColor(Theme.surface)
          .borderRadius(10)
          .border({ width: 1, color: Theme.borderSubtle })
          .clip(true)

          // 汇总条
          Row() {
            Text(`${this.currentBuildingName()} · 周${DAYS[this.activeDay]}${
              this.hasState && this.activeDay < this.stateResult.datesOfCurrentWeek.length
              && this.stateResult.datesOfCurrentWeek[this.activeDay].length > 0
                ? ` (${this.stateResult.datesOfCurrentWeek[this.activeDay]})` : ''}`)
              .fontSize(12)
              .fontColor(Theme.textSecondary)
              .layoutWeight(1)
              .maxLines(1)
            if (this.hasState && this.stateResult.classroomStates.length > 0) {
              Text(`${this.freeRoomCount()}/${this.stateResult.classroomStates.length} 间全天空闲`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.primary)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 8, bottom: 6 })

          // 教室状态区
          if (this.stateLoading) {
            Column() {
              LoadingProgress()
                .width(32)
                .height(32)
                .color(Theme.primary)
              Text('加载教室状态...')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .margin({ top: 8 })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.stateErrorText.length > 0) {
            Column({ space: 8 }) {
              Text('教室状态加载失败')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.stateErrorText)
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .textAlign(TextAlign.Center)
              Text('重试')
                .fontSize(13)
                .fontColor(Theme.primary)
                .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                .borderRadius(8)
                .border({ width: 1, color: Theme.primary })
                .onClick(() => { this.loadState(); })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding({ left: 32, right: 32 })
          } else if (!this.hasState || this.stateResult.classroomStates.length === 0) {
            Column({ space: 4 }) {
              Text('该教学楼无教室数据')
                .fontSize(14)
                .fontColor(Theme.textSecondary)
              Text('可以切换其它教学楼、周次或稍后刷新')
                .fontSize(12)
                .fontColor(Theme.textMuted)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            Scroll() {
              Column() {
                // 状态图例
                Row() {
                  ForEach(ALL_STATUSES, (s: ClassroomStatus) => {
                    Row() {
                      LegendDot({ color: statusColorOf(s) })
                      Text(statusLabelOf(s))
                        .fontSize(11)
                        .fontColor(Theme.textMuted)
                    }
                    .margin({ right: 12 })
                    .alignItems(VerticalAlign.Center)
                  }, (s: ClassroomStatus) => s.toString())
                }
                .width('100%')
                .margin({ bottom: 8 })

                // 节次图例
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(CLASSROOM_PERIODS, (p: ClassroomPeriod) => {
                    Text(`${p.period} ${p.timeRange}`)
                      .fontSize(10)
                      .fontColor(Theme.textMuted)
                      .backgroundColor(Theme.surfaceAlt)
                      .borderRadius(4)
                      .padding({ left: 5, right: 5, top: 2, bottom: 2 })
                      .margin({ right: 6, bottom: 4 })
                  }, (p: ClassroomPeriod) => p.period.toString())
                }
                .width('100%')
                .margin({ bottom: 6 })

                // 表头
                Row() {
                  Text('教室')
                    .fontSize(11)
                    .fontColor(Theme.textMuted)
                    .layoutWeight(3)
                  Text('容量')
                    .fontSize(11)
                    .fontColor(Theme.textMuted)
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                  Text('1  2  3  4  5  6')
                    .fontSize(11)
                    .fontColor(Theme.textMuted)
                    .layoutWeight(5)
                    .textAlign(TextAlign.Center)
                }
                .width('100%')
                .padding({ left: 12, right: 12 })
                .margin({ bottom: 4 })

                // 教室行
                ForEach(this.stateResult.classroomStates, (row: ClassroomStateRow) => {
                  this.RoomRow(row)
                }, (row: ClassroomStateRow) => row.name)
              }
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 16, right: 16, bottom: 24 })
            }
            .layoutWeight(1)
            .scrollBar(BarState.Off)
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}

@Component
struct LegendDot {
  @Prop color: string = '';

  build() {
    Row()
      .width(8)
      .height(8)
      .borderRadius(4)
      .backgroundColor(this.color)
      .margin({ right: 4 })
  }
}
