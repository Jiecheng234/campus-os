/**
 * ============================================================================
 * LibraryRoomPage — 研读间只读查询（类型 → 近 5 天 → 资源 + 我的预约）
 * ============================================================================
 *
 * 层级（页内状态切换，不走路由）：
 *   KIND（类型卡片（类型名 + "N 个房间 · 点选查看近 5 天"）—— 点击展开"近 5 天"日期项
 *         + 我的预约入口 + 只读引导）
 *     → RESOURCE（某类型某天资源：房间名（maxUser>1 附最少~最多人）、类型名、
 *                 开放时间、"可浏览/未开放"徽标；空态；返回回到类型）
 *   KIND → BOOKINGS（我的预约记录：房间/类型/日期与起止/成员；空态）
 *
 * 会话：进入自动完成研读间子系统登录（动态认证地址 → 重定向解析标识 →
 *   id 漫游 → 用户信息账号校验），会话失效自动重建（服务层 withCabRetry）。
 * 只读边界：完整下单（选时段、邀请成员）请在官方小程序完成；
 * 演示模式零网络请求（内置示例数据）。
 * ============================================================================
 */
import { Theme, Space, FontSize } from '../Theme';
import { EmptyHint, StateBlock, StateTone, StatusBadge, BadgeTone } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import {
  LibRoomKind,
  LibRoomBrief,
  LibRoomResource,
  LibRoomBookRecord,
  formatLibRoomDateIso,
  formatLibRoomDateYmd,
} from '../../services/campus/LibraryRoomService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';

/** 页内层级（不走路由） */
const LEVEL_KIND: number = 0;
const LEVEL_RESOURCE: number = 1;
const LEVEL_BOOKINGS: number = 2;
/** 近 5 天（今天起偏移 0–4，对齐参考 validDateNum） */
const VALID_DATE_NUM: number = 5;
/** 近 5 天日期偏移序列（ForEach 用） */
const DATE_OFFSETS: number[] = [0, 1, 2, 3, 4];

// ============================================================
// 演示模式示例数据（零网络请求）
// ============================================================

function getDemoKinds(): LibRoomKind[] {
  const rows: string[][] = [
    ['1', '研读间（主馆）', '101|主馆研读间 A01', '102|主馆研读间 A02', '103|主馆研读间 A03'],
    ['2', '研讨间（文科图书馆）', '201|文科研讨间 B01', '202|文科研讨间 B02'],
    ['3', '研读间（医学图书馆）', '301|医学研读间 C01'],
  ];
  const kinds: LibRoomKind[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const kind: LibRoomKind = new LibRoomKind();
    kind.kindId = Number(rows[i][0]);
    kind.kindName = rows[i][1];
    for (let j: number = 2; j < rows[i].length; j++) {
      const parts: string[] = rows[i][j].split('|');
      const brief: LibRoomBrief = new LibRoomBrief();
      brief.devId = Number(parts[0]);
      brief.devName = parts[1];
      brief.minReserveMinute = 30;
      kind.rooms.push(brief);
    }
    kind.roomCount = kind.rooms.length;
    kinds.push(kind);
  }
  return kinds;
}

function getDemoResources(): LibRoomResource[] {
  // devId / 名称 / 类型名 / 最少人 / 最多人 / 开放起 / 开放止 / 占用条数
  const rows: string[][] = [
    ['101', '主馆研读间 A01', '研读间（主馆）', '1', '1', '08:00', '22:00', '2'],
    ['102', '主馆研读间 A02', '研读间（主馆）', '2', '8', '08:00', '22:00', '0'],
    ['103', '主馆研读间 A03', '研读间（主馆）', '4', '10', '08:00', '22:00', '1'],
    ['104', '主馆研读间 A04', '研读间（主馆·暂未开放）', '1', '4', '', '', '0'],
  ];
  const list: LibRoomResource[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const res: LibRoomResource = new LibRoomResource();
    res.devId = Number(rows[i][0]);
    res.devName = rows[i][1];
    res.roomName = rows[i][1];
    res.kindId = 1;
    res.kindName = rows[i][2];
    res.minUser = Number(rows[i][3]);
    res.maxUser = Number(rows[i][4]);
    res.openStart = rows[i][5];
    res.openEnd = rows[i][6];
    res.usageCount = Number(rows[i][7]);
    list.push(res);
  }
  return list;
}

function getDemoRoomBookings(): LibRoomBookRecord[] {
  const list: LibRoomBookRecord[] = [];
  const r1: LibRoomBookRecord = new LibRoomBookRecord();
  r1.uuid = 'demo-1';
  r1.rsvId = 1001;
  r1.owner = '张同学';
  r1.ownerId = '2026010101';
  r1.date = formatLibRoomDateIso(1);
  r1.beginText = '08:00';
  r1.endText = '12:00';
  r1.devName = '主馆研读间 A02';
  r1.kindName = '研读间（主馆）';
  r1.membersText = '张同学、李同学';
  list.push(r1);
  const r2: LibRoomBookRecord = new LibRoomBookRecord();
  r2.uuid = 'demo-2';
  r2.rsvId = 1002;
  r2.owner = '张同学';
  r2.ownerId = '2026010101';
  r2.date = formatLibRoomDateIso(3);
  r2.beginText = '14:00';
  r2.endText = '18:00';
  r2.devName = '文科研讨间 B01';
  r2.kindName = '研讨间（文科图书馆）';
  r2.membersText = '张同学';
  list.push(r2);
  return list;
}

// ============================================================
// 页面组件
// ============================================================

@Component
export struct LibraryRoomPage {
  onBack: () => void = () => {};

  @State level: number = LEVEL_KIND;
  @State titleText: string = '研读间';
  @State loading: boolean = false;
  @State loadingText: string = '正在建立研读间会话…';
  @State errorMessage: string = '';

  // KIND 层
  @State kinds: LibRoomKind[] = [];
  @State expandedKindId: number = -1;

  // RESOURCE / BOOKINGS 层
  @State resources: LibRoomResource[] = [];
  @State bookings: LibRoomBookRecord[] = [];

  private isDemo: boolean = true;
  private currentKindId: number = 0;
  private currentKindName: string = '';
  private currentDateOffset: number = 0;

  /** 系统返回拦截：深层层级逐级 pop，KIND 层交回入口卡片 */
  private backHandler: BackHandler = (): boolean => {
    if (this.level === LEVEL_KIND) {
      this.onBack();
      return true;
    }
    this.goBackOneLevel();
    return true;
  };

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    this.loadKinds();
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
  }

  // ── 层级导航 ────────────────────────────────

  private goBackOneLevel(): void {
    this.level = LEVEL_KIND;
    this.titleText = '研读间';
    this.errorMessage = '';
  }

  private handleHeaderBack(): void {
    if (this.level === LEVEL_KIND) {
      this.onBack();
    } else {
      this.goBackOneLevel();
    }
  }

  // ── 数据加载（演示模式零网络请求） ────────────────────────────────

  private extractError(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  /** KIND 层：类型列表（首次进入自动完成研读间子系统登录与账号校验） */
  private async loadKinds(): Promise<void> {
    this.level = LEVEL_KIND;
    this.titleText = '研读间';
    this.errorMessage = '';
    this.loadingText = this.kinds.length === 0 ? '正在建立研读间会话…' : '正在刷新研读间类型…';
    if (this.isDemo) {
      this.kinds = getDemoKinds();
      return;
    }
    this.loading = true;
    try {
      this.kinds = await SessionManager.getLibraryRoomService().getRoomKindList();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private onToggleKind(kind: LibRoomKind): void {
    if (this.expandedKindId === kind.kindId) {
      this.expandedKindId = -1;
    } else {
      this.expandedKindId = kind.kindId;
    }
  }

  /** RESOURCE 层：某类型某天资源（dateOffset 0–4 → yyyyMMdd 请求） */
  private async openResources(kind: LibRoomKind, dateOffset: number): Promise<void> {
    this.currentKindId = kind.kindId;
    this.currentKindName = kind.kindName;
    this.currentDateOffset = dateOffset;
    this.level = LEVEL_RESOURCE;
    this.titleText = kind.kindName.length > 0 ? kind.kindName : '研读间资源';
    this.errorMessage = '';
    this.loadingText = '正在读取研读间资源…';
    if (this.isDemo) {
      this.resources = getDemoResources();
      return;
    }
    this.loading = true;
    try {
      this.resources = await SessionManager.getLibraryRoomService()
        .getRoomResourceList(formatLibRoomDateYmd(dateOffset), kind.kindId);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** BOOKINGS 层：我的预约记录 */
  private async openBookings(): Promise<void> {
    this.level = LEVEL_BOOKINGS;
    this.titleText = '我的预约';
    this.errorMessage = '';
    this.loadingText = '正在读取我的预约…';
    if (this.isDemo) {
      this.bookings = getDemoRoomBookings();
      return;
    }
    this.loading = true;
    try {
      this.bookings = await SessionManager.getLibraryRoomService().getRoomBookingRecords();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 右上角刷新 / 错误重试：按当前层级重拉 */
  private async refreshCurrentLevel(): Promise<void> {
    if (this.level === LEVEL_RESOURCE) {
      const kind: LibRoomKind = new LibRoomKind();
      kind.kindId = this.currentKindId;
      kind.kindName = this.currentKindName;
      await this.openResources(kind, this.currentDateOffset);
    } else if (this.level === LEVEL_BOOKINGS) {
      await this.openBookings();
    } else {
      this.kinds = [];
      this.expandedKindId = -1;
      await this.loadKinds();
    }
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

  /** 右上角刷新：加载中显示进度 */
  @Builder
  private RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
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
  }

  @Builder
  private LoadingView() {
    Column({ space: Space.md }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.primary)
      Text(this.loadingText)
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

  /** KIND 层：类型卡片（类型名 + 房间数；点击展开"近 5 天"日期项） */
  @Builder
  private KindCard(kind: LibRoomKind) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(kind.kindName.length > 0 ? kind.kindName : ('类型 ' + String(kind.kindId)))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(String(kind.roomCount) + ' 个房间 · 点选查看近 ' + String(VALID_DATE_NUM) + ' 天')
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.expandedKindId === kind.kindId ? '⌄' : '›')
          .fontSize(FontSize.label)
          .fontColor(Theme.textMuted)
      }
      .width('100%')
      .onClick(() => {
        this.onToggleKind(kind);
      })

      if (this.expandedKindId === kind.kindId) {
        Divider()
          .color(Theme.divider)
          .margin({ top: Space.sm, bottom: Space.sm })

        ForEach(DATE_OFFSETS, (offset: number) => {
          Row() {
            Text(formatLibRoomDateIso(offset))
              .fontSize(FontSize.body)
              .fontColor(Theme.text)
              .layoutWeight(1)
            Text('›')
              .fontSize(FontSize.label)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .padding({ top: Space.sm, bottom: Space.sm })
          .onClick(() => {
            this.openResources(kind, offset);
          })
        }, (offset: number) => String(offset))
      }
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
  private KindLayer() {
    Scroll() {
      Column() {
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
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })
        .onClick(() => {
          this.openBookings();
        })

        // 只读引导
        StateBlock({
          tone: StateTone.Info,
          message: '研读间数据仅供查询，完整下单请在官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, bottom: Space.md })

        if (this.kinds.length === 0) {
          EmptyHint({ title: '无研读间类型', message: '接口未返回研读间类型数据，可稍后刷新' })
        } else {
          ForEach(this.kinds, (kind: LibRoomKind) => {
            this.KindCard(kind)
          }, (kind: LibRoomKind) => String(kind.kindId))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** RESOURCE 层：资源卡片（房间名（含人数区间）、类型名、开放时间、开放徽标） */
  @Builder
  private ResourceCard(res: LibRoomResource) {
    Row() {
      Column({ space: 2 }) {
        Text((res.roomName.length > 0 ? res.roomName : res.devName)
          + (res.maxUser > 1 ? ('（' + String(res.minUser) + '~' + String(res.maxUser) + '人）') : ''))
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(res.kindName)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
        if (res.openStart.length > 0 && res.openEnd.length > 0) {
          Text('开放 ' + res.openStart + '–' + res.openEnd)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (res.kindName.indexOf('暂未开放') >= 0) {
        StatusBadge({ text: '未开放', tone: BadgeTone.Warning })
      } else {
        StatusBadge({ text: '可浏览', tone: BadgeTone.Default })
      }
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
  private ResourceLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: '资源仅供浏览，完整下单请在官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.resources.length === 0) {
          EmptyHint({ title: '暂无可预约资源', message: '该类型当天暂无可预约研读间' })
        } else {
          ForEach(this.resources, (res: LibRoomResource) => {
            this.ResourceCard(res)
          }, (res: LibRoomResource) => String(res.devId) + '-' + String(res.roomId))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** BOOKINGS 层：预约记录卡片（房间/类型/日期与起止/成员） */
  @Builder
  private BookingCard(rec: LibRoomBookRecord) {
    Column({ space: Space.xs }) {
      Text(rec.devName.length > 0 ? rec.devName : ('研读间 ' + String(rec.rsvId)))
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Text(rec.kindName)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
      Text((rec.date.length > 0 ? rec.date + ' ' : '') + rec.beginText + ' – ' + rec.endText)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
      if (rec.membersText.length > 0) {
        Text('成员：' + rec.membersText)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
      }
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
          message: '记录仅供查询，预约与取消请在官方小程序完成',
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.bookings.length === 0) {
          EmptyHint({ title: '暂无预约记录', message: '预约研读间请前往官方小程序完成' })
        } else {
          ForEach(this.bookings, (rec: LibRoomBookRecord) => {
            this.BookingCard(rec)
          }, (rec: LibRoomBookRecord, index: number) => rec.uuid + '#' + String(index))
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
          if (this.level === LEVEL_KIND) {
            this.KindLayer()
          } else {
            if (this.level === LEVEL_RESOURCE) {
              this.ResourceLayer()
            } else {
              this.BookingsLayer()
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
