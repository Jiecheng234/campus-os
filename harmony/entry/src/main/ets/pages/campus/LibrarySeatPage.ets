/**
 * ============================================================================
 * LibrarySeatPage — 图书馆座位只读查询（馆/楼层使用率 → 区域 → 座位 + 我的预约）
 * ============================================================================
 *
 * 层级（页内状态切换，不走路由）：
 *   LIBRARY（馆 chips + 今天/明天切换 + 楼层使用率 + 我的预约入口）
 *     → SECTION（区域：可用/总数/已预约）
 *       → SEAT（座位：名称 + 状态标签与着色）
 *   LIBRARY → BOOKINGS（我的预约记录/空态）
 *
 * 只读边界：座位数据仅供查询，预约引导至官方小程序；
 * 演示模式零网络请求（内置示例数据）。
 * ============================================================================
 */
import { Theme, Space, Radius, FontSize } from '../Theme';
import { EmptyHint, StateBlock, StateTone, StatusBadge, BadgeTone } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import {
  LibrarySeatService,
  LibraryInfo,
  LibraryFloorInfo,
  LibrarySectionInfo,
  LibrarySeatInfo,
  LibraryBookingRecord,
  seatStatusLabel,
} from '../../services/campus/LibrarySeatService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';

/** 页内层级（不走路由） */
const LEVEL_LIBRARY: number = 0;
const LEVEL_SECTION: number = 1;
const LEVEL_SEAT: number = 2;
const LEVEL_BOOKINGS: number = 3;

// ============================================================
// 演示模式示例数据（零网络请求）
// ============================================================

function getDemoLibraries(): LibraryInfo[] {
  const list: LibraryInfo[] = [];
  const rows: string[][] = [
    ['1', '主馆', '1'],
    ['2', '文科图书馆', '1'],
    ['3', '医学图书馆', '0'],
    ['4', '经济管理学院图书馆', '1'],
  ];
  for (let i: number = 0; i < rows.length; i++) {
    const lib: LibraryInfo = new LibraryInfo();
    lib.id = Number(rows[i][0]);
    lib.zhName = rows[i][1];
    lib.valid = rows[i][2] === '1';
    list.push(lib);
  }
  return list;
}

function getDemoFloors(): LibraryFloorInfo[] {
  const rows: string[][] = [
    ['101', '一层', '320', '145', '1'],
    ['102', '二层', '280', '210', '1'],
    ['103', '三层', '150', '0', '1'],
    ['104', '负一层', '0', '0', '0'],
  ];
  const list: LibraryFloorInfo[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const f: LibraryFloorInfo = new LibraryFloorInfo();
    f.id = Number(rows[i][0]);
    f.zhName = rows[i][1];
    f.total = Number(rows[i][2]);
    f.available = Number(rows[i][3]);
    f.valid = rows[i][4] === '1';
    list.push(f);
  }
  return list;
}

function getDemoSections(): LibrarySectionInfo[] {
  const rows: string[][] = [
    ['201', 'A 区', '120', '45', '3', '1'],
    ['202', 'B 区', '80', '12', '5', '1'],
    ['203', 'C 区', '96', '0', '8', '1'],
    ['204', '研讨区', '30', '0', '0', '0'],
  ];
  const list: LibrarySectionInfo[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const s: LibrarySectionInfo = new LibrarySectionInfo();
    s.id = Number(rows[i][0]);
    s.zhName = rows[i][1];
    s.total = Number(rows[i][2]);
    s.available = Number(rows[i][3]);
    s.reservedCount = Number(rows[i][4]);
    s.valid = rows[i][5] === '1';
    list.push(s);
  }
  return list;
}

function getDemoSeats(): LibrarySeatInfo[] {
  // 名称 / 状态（1=可用 6=已预约 7=已被占用）
  const rows: string[][] = [
    ['001', '1'], ['002', '6'], ['003', '7'], ['004', '1'],
    ['005', '1'], ['006', '6'], ['007', '1'], ['008', '7'],
    ['009', '1'], ['010', '1'], ['011', '6'], ['012', '1'],
  ];
  const list: LibrarySeatInfo[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const seat: LibrarySeatInfo = new LibrarySeatInfo();
    seat.id = i + 1;
    seat.name = rows[i][0];
    seat.status = Number(rows[i][1]);
    list.push(seat);
  }
  return list;
}

function getDemoBookings(): LibraryBookingRecord[] {
  const list: LibraryBookingRecord[] = [];
  const r1: LibraryBookingRecord = new LibraryBookingRecord();
  r1.id = '20261012001';
  r1.pos = '主馆二层 A 区 · 015 号座位';
  r1.time = '10月12日 08:00 - 12:00';
  r1.status = '使用中';
  list.push(r1);
  const r2: LibraryBookingRecord = new LibraryBookingRecord();
  r2.id = '20261011008';
  r2.pos = '主馆一层 C 区 · 032 号座位';
  r2.time = '10月11日 18:00 - 22:00';
  r2.status = '已完成';
  list.push(r2);
  return list;
}

// ============================================================
// 页面组件
// ============================================================

@Component
export struct LibrarySeatPage {
  onBack: () => void = () => {};

  @State level: number = LEVEL_LIBRARY;
  @State dateChoice: number = 0;
  @State titleText: string = '图书馆座位';
  @State loading: boolean = false;
  @State errorMessage: string = '';

  // LIBRARY 层
  @State libraries: LibraryInfo[] = [];
  @State selectedLibraryId: number = 0;
  @State floors: LibraryFloorInfo[] = [];

  // SECTION / SEAT 层（上下文为普通成员：仅取值展示，不驱动刷新）
  @State sections: LibrarySectionInfo[] = [];
  @State seats: LibrarySeatInfo[] = [];
  @State bookings: LibraryBookingRecord[] = [];

  private isDemo: boolean = true;
  private currentFloorId: number = 0;
  private currentFloorName: string = '';
  private currentSectionId: number = 0;
  private currentSectionName: string = '';

  /** 系统返回拦截：深层层级逐级 pop，LIBRARY 层交回入口卡片 */
  private backHandler: BackHandler = (): boolean => {
    if (this.level === LEVEL_LIBRARY) {
      this.onBack();
      return true;
    }
    this.goBackOneLevel();
    return true;
  };

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    this.loadLibraryLevel();
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
  }

  // ── 层级导航 ────────────────────────────────

  private goBackOneLevel(): void {
    if (this.level === LEVEL_SEAT) {
      this.level = LEVEL_SECTION;
      this.titleText = this.currentFloorName;
    } else {
      this.level = LEVEL_LIBRARY;
      this.titleText = '图书馆座位';
    }
  }

  private handleHeaderBack(): void {
    if (this.level === LEVEL_LIBRARY) {
      this.onBack();
    } else {
      this.goBackOneLevel();
    }
  }

  // ── 数据加载（演示模式零网络请求） ────────────────────────────────

  private extractError(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  /** LIBRARY 层：馆列表（仅首次）+ 默认选中开放馆 + 楼层使用率 */
  private async loadLibraryLevel(): Promise<void> {
    this.level = LEVEL_LIBRARY;
    this.titleText = '图书馆座位';
    this.errorMessage = '';
    if (this.isDemo) {
      this.libraries = getDemoLibraries();
      if (this.selectedLibraryId === 0 && this.libraries.length > 0) {
        this.selectedLibraryId = this.libraries[0].id;
      }
      this.floors = getDemoFloors();
      return;
    }
    this.loading = true;
    try {
      const service: LibrarySeatService = SessionManager.getLibrarySeatService();
      if (this.libraries.length === 0) {
        this.libraries = await service.getLibraryList();
      }
      if (this.libraries.length === 0) {
        throw new Error('未获取到图书馆列表');
      }
      // 默认选中开放馆（无开放馆时回退第一个）
      let found: boolean = false;
      for (let i: number = 0; i < this.libraries.length; i++) {
        if (this.libraries[i].id === this.selectedLibraryId && this.libraries[i].valid) {
          found = true;
          break;
        }
      }
      if (!found) {
        this.selectedLibraryId = this.libraries[0].id;
        for (let i: number = 0; i < this.libraries.length; i++) {
          if (this.libraries[i].valid) {
            this.selectedLibraryId = this.libraries[i].id;
            break;
          }
        }
      }
      this.floors = await service.getLibraryFloorList(this.selectedLibraryId, this.dateChoice);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 切馆 / 切日期后仅重拉楼层使用率 */
  private async reloadFloors(): Promise<void> {
    this.errorMessage = '';
    if (this.isDemo) {
      this.floors = getDemoFloors();
      return;
    }
    this.loading = true;
    try {
      this.floors = await SessionManager.getLibrarySeatService()
        .getLibraryFloorList(this.selectedLibraryId, this.dateChoice);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private onSelectLibrary(lib: LibraryInfo): void {
    if (!lib.valid || lib.id === this.selectedLibraryId) {
      return;
    }
    this.selectedLibraryId = lib.id;
    this.reloadFloors();
  }

  private onDateChoice(choice: number): void {
    if (choice === this.dateChoice) {
      return;
    }
    this.dateChoice = choice;
    this.reloadFloors();
  }

  private async openFloor(floor: LibraryFloorInfo): Promise<void> {
    if (!floor.valid) {
      return;
    }
    this.currentFloorId = floor.id;
    this.currentFloorName = floor.zhName.length > 0 ? floor.zhName : floor.enName;
    this.level = LEVEL_SECTION;
    this.titleText = this.currentFloorName;
    this.errorMessage = '';
    if (this.isDemo) {
      this.sections = getDemoSections();
      return;
    }
    this.loading = true;
    try {
      this.sections = await SessionManager.getLibrarySeatService()
        .getLibrarySectionList(floor.id, this.dateChoice);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private async openSection(section: LibrarySectionInfo): Promise<void> {
    if (!section.valid) {
      return;
    }
    this.currentSectionId = section.id;
    this.currentSectionName = section.zhName.length > 0 ? section.zhName : section.enName;
    this.level = LEVEL_SEAT;
    this.titleText = this.currentSectionName;
    this.errorMessage = '';
    if (this.isDemo) {
      this.seats = getDemoSeats();
      return;
    }
    this.loading = true;
    try {
      this.seats = await SessionManager.getLibrarySeatService()
        .getLibrarySeatList(section.id, this.dateChoice);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private async openBookings(): Promise<void> {
    this.level = LEVEL_BOOKINGS;
    this.titleText = '我的预约';
    this.errorMessage = '';
    if (this.isDemo) {
      this.bookings = getDemoBookings();
      return;
    }
    this.loading = true;
    try {
      this.bookings = await SessionManager.getLibrarySeatService().getLibraryBookingRecords();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 右上角刷新 / 错误重试：按当前层级重拉 */
  private async refreshCurrentLevel(): Promise<void> {
    if (this.level === LEVEL_SECTION) {
      const floor: LibraryFloorInfo = new LibraryFloorInfo();
      floor.id = this.currentFloorId;
      floor.zhName = this.currentFloorName;
      floor.valid = true;
      await this.openFloor(floor);
    } else if (this.level === LEVEL_SEAT) {
      const section: LibrarySectionInfo = new LibrarySectionInfo();
      section.id = this.currentSectionId;
      section.zhName = this.currentSectionName;
      section.valid = true;
      await this.openSection(section);
    } else if (this.level === LEVEL_BOOKINGS) {
      await this.openBookings();
    } else {
      this.libraries = [];
      this.selectedLibraryId = 0;
      await this.loadLibraryLevel();
    }
  }

  /** 座位状态 → 徽标色调 */
  private seatTone(status: number): BadgeTone {
    if (status === 1) {
      return BadgeTone.Success;
    }
    if (status === 6) {
      return BadgeTone.Warning;
    }
    if (status === 7) {
      return BadgeTone.Error;
    }
    return BadgeTone.Default;
  }

  /** 预约记录状态 → 徽标色调（文本匹配：使用中/已预约→警示，已取消→错误） */
  private bookingTone(status: string): BadgeTone {
    if (status.indexOf('使用中') >= 0 || status.indexOf('已预约') >= 0) {
      return BadgeTone.Warning;
    }
    if (status.indexOf('取消') >= 0) {
      return BadgeTone.Error;
    }
    if (status.indexOf('完成') >= 0 || status.indexOf('结束') >= 0) {
      return BadgeTone.Success;
    }
    return BadgeTone.Default;
  }

  // ── UI ────────────────────────────────

  /**
   * 页内头部（复刻 DetailHeader 版式）：
   * 标题直接绑定 this.titleText（自定义组件普通成员只初始化一次、不随父状态刷新，
   * 故不能经 DetailHeader 传入动态标题）。
   */
  @Builder
  private HeaderBar() {
    Row() {
      Text('‹')
        .fontSize(32)
        .fontWeight(FontWeight.Lighter)
        .fontColor(Theme.text)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.handleHeaderBack();
        })

      Text(this.titleText)
        .fontSize(FontSize.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Column() {
        this.RightAction()
      }
      .width(40)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: Space.sm, right: Space.md, top: Space.sm, bottom: Space.sm })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private RightAction() {
    Text('↻')
      .fontSize(20)
      .fontColor(Theme.primary)
      .width(40)
      .height(40)
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.refreshCurrentLevel();
      })
  }

  @Builder
  private LoadingView() {
    Column({ space: Space.md }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.primary)
      Text('加载中…')
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column() {
      StateBlock({
        tone: StateTone.Error,
        title: '加载失败',
        message: this.errorMessage,
        actionText: '重试',
        onAction: () => {
          this.refreshCurrentLevel();
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
  }

  @Builder
  private DateChip(label: string, choice: number) {
    Text(label)
      .fontSize(FontSize.label)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.dateChoice === choice ? Theme.textInvert : Theme.textMuted)
      .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })
      .borderRadius(Radius.pill)
      .backgroundColor(this.dateChoice === choice ? Theme.primary : Theme.surface)
      .border({ width: 1, color: this.dateChoice === choice ? Theme.primary : Theme.borderSubtle })
      .onClick(() => {
        this.onDateChoice(choice);
      })
  }

  @Builder
  private LibraryChip(lib: LibraryInfo) {
    Text(lib.zhName)
      .fontSize(FontSize.label)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selectedLibraryId === lib.id ? Theme.textInvert : Theme.textSecondary)
      .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
      .borderRadius(Radius.pill)
      .backgroundColor(this.selectedLibraryId === lib.id ? Theme.primary : Theme.surfaceAlt)
      .onClick(() => {
        this.onSelectLibrary(lib);
      })
  }

  @Builder
  private FloorRow(floor: LibraryFloorInfo) {
    Row() {
      Column({ space: 2 }) {
        Text(floor.zhName.length > 0 ? floor.zhName : ('楼层 ' + String(floor.id)))
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(floor.valid ? ('可用 ' + String(floor.available) + ' / 共 ' + String(floor.total) + ' 座位') : '暂不开放')
          .fontSize(FontSize.caption)
          .fontColor(floor.valid ? (floor.available > 0 ? Theme.success : Theme.textMuted) : Theme.textMuted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (floor.valid) {
        Text('>')
          .fontSize(FontSize.label)
          .fontColor(Theme.textMuted)
      } else {
        StatusBadge({ text: '未开放', tone: BadgeTone.Default })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
    .onClick(() => {
      this.openFloor(floor);
    })
  }

  @Builder
  private LibraryLayer() {
    Scroll() {
      Column() {
        // 今天 / 明天切换
        Row({ space: Space.xs }) {
          this.DateChip('今天', 0)
          this.DateChip('明天', 1)
        }
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        // 馆列表（横向 chips）
        Scroll() {
          Row({ space: Space.sm }) {
            ForEach(this.libraries, (lib: LibraryInfo) => {
              this.LibraryChip(lib)
            }, (lib: LibraryInfo) => String(lib.id))
          }
          .padding({ left: Space.md, right: Space.md })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ bottom: Space.md })

        // 我的预约入口
        Row() {
          Text('📋')
            .fontSize(20)
          Text('我的预约')
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .margin({ left: 12 })
            .layoutWeight(1)
          Text('>')
            .fontSize(FontSize.label)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .padding(Space.md)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.md, right: Space.md, bottom: Space.md })
        .onClick(() => {
          this.openBookings();
        })

        // 只读引导
        StateBlock({
          tone: StateTone.Info,
          message: '座位数据仅供查询，预约请前往官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, bottom: Space.md })

        // 楼层使用率
        if (this.floors.length === 0) {
          EmptyHint({ title: '暂无楼层信息', message: '该图书馆暂无可用楼层' })
        } else {
          ForEach(this.floors, (floor: LibraryFloorInfo) => {
            this.FloorRow(floor)
          }, (floor: LibraryFloorInfo) => String(floor.id))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private SectionRow(section: LibrarySectionInfo) {
    Row() {
      Column({ space: 2 }) {
        Text(section.zhName.length > 0 ? section.zhName : ('区域 ' + String(section.id)))
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(section.valid
          ? ('可用 ' + String(section.available) + ' / 共 ' + String(section.total)
            + ' · 已预约 ' + String(section.reservedCount))
          : '暂不开放')
          .fontSize(FontSize.caption)
          .fontColor(section.valid ? (section.available > 0 ? Theme.success : Theme.textMuted) : Theme.textMuted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (section.valid) {
        Text('>')
          .fontSize(FontSize.label)
          .fontColor(Theme.textMuted)
      } else {
        StatusBadge({ text: '未开放', tone: BadgeTone.Default })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
    .onClick(() => {
      this.openSection(section);
    })
  }

  @Builder
  private SectionLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: '区域座位实时查询，预约请前往官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.sections.length === 0) {
          EmptyHint({ title: '暂无区域信息', message: '该楼层暂无开放区域' })
        } else {
          ForEach(this.sections, (section: LibrarySectionInfo) => {
            this.SectionRow(section)
          }, (section: LibrarySectionInfo) => String(section.id))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private SeatRow(seat: LibrarySeatInfo) {
    Row() {
      Text(seat.name)
        .fontSize(FontSize.body)
        .fontColor(Theme.text)
        .layoutWeight(1)
      StatusBadge({ text: seatStatusLabel(seat.status), tone: this.seatTone(seat.status) })
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
  }

  @Builder
  private SeatLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: '座位状态实时查询，预约请前往官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.seats.length === 0) {
          EmptyHint({ title: '暂无座位信息', message: '该区域暂无可查询座位' })
        } else {
          ForEach(this.seats, (seat: LibrarySeatInfo) => {
            this.SeatRow(seat)
          }, (seat: LibrarySeatInfo) => String(seat.id))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  private BookingRow(record: LibraryBookingRecord) {
    Column({ space: Space.xs }) {
      Text(record.pos.length > 0 ? record.pos : ('预约 ' + record.id))
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Row() {
        Text(record.time)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
          .layoutWeight(1)
        StatusBadge({ text: record.status.length > 0 ? record.status : '未知', tone: this.bookingTone(record.status) })
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
  }

  @Builder
  private BookingsLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: '记录仅供查询，预约与取消请前往官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.bookings.length === 0) {
          EmptyHint({ title: '暂无预约记录', message: '预约座位请前往官方小程序完成' })
        } else {
          ForEach(this.bookings, (record: LibraryBookingRecord) => {
            this.BookingRow(record)
          }, (record: LibraryBookingRecord, index: number) => record.id + '#' + String(index))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.HeaderBar()
      Divider().color(Theme.divider)

      if (this.loading) {
        this.LoadingView()
      } else {
        if (this.errorMessage.length > 0) {
          this.ErrorView()
        } else {
          if (this.level === LEVEL_LIBRARY) {
            this.LibraryLayer()
          } else {
            if (this.level === LEVEL_SECTION) {
              this.SectionLayer()
            } else {
              if (this.level === LEVEL_SEAT) {
                this.SeatLayer()
              } else {
                this.BookingsLayer()
              }
            }
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
