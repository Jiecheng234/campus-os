/**
 * ============================================================================
 * SportsBookingPage — 体育场馆只读查询（场馆 × 近 7 天资源 + 限额/联系电话 + 预约记录）
 * ============================================================================
 *
 * 视图（页内状态切换，不走路由）：
 *   RESOURCES（场馆 chips + 近 7 天日期行 + 限额/联系电话 + 我的预约记录入口 + 资源列表）
 *     → RECORDS（未支付 + 已支付合并记录 / 空态）
 *
 * 只读边界：资源与记录仅供查询，下单与支付请通过官方渠道完成；
 * 演示模式零网络请求（内置示例数据）。
 * ============================================================================
 */
import { Theme, Space, Radius, FontSize } from '../Theme';
import { EmptyHint, StateBlock, StateTone, StatusBadge, BadgeTone } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import {
  SportsVenue,
  SportsResource,
  SportsResourceInfo,
  SportsRecord,
  SPORTS_VENUES,
  sportsDateString,
} from '../../services/campus/SportsService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';
import { I18n } from '../../utils/I18n';

/** 页内视图（不走路由） */
const VIEW_RESOURCES: number = 0;
const VIEW_RECORDS: number = 1;

// ============================================================
// 演示模式示例数据（零网络请求）
// ============================================================

function getDemoResourceInfo(): SportsResourceInfo {
  const info: SportsResourceInfo = new SportsResourceInfo();
  info.count = 1;
  info.init = 3;
  info.phone = '010-62785001';
  // resId / 时段 / 场地 / 费用 / 可网上预约 / 已锁定
  const rows: string[][] = [
    ['101', '09:00 - 10:00', '1 号场地', '30', '1', '0'],
    ['102', '09:00 - 10:00', '2 号场地', '30', '1', '0'],
    ['103', '10:00 - 11:00', '1 号场地', '30', '1', '1'],
    ['104', '10:00 - 11:00', '2 号场地', '30', '0', '0'],
    ['105', '11:00 - 12:00', '1 号场地', '30', '1', '0'],
    ['106', '11:00 - 12:00', '2 号场地', '30', '1', '0'],
  ];
  for (let i: number = 0; i < rows.length; i++) {
    const res: SportsResource = new SportsResource();
    res.resId = rows[i][0];
    res.timeSession = rows[i][1];
    res.fieldName = rows[i][2];
    res.cost = Number(rows[i][3]);
    res.canNetBook = rows[i][4] === '1';
    res.locked = rows[i][5] === '1';
    info.data.push(res);
  }
  return info;
}

function getDemoRecords(): SportsRecord[] {
  const list: SportsRecord[] = [];
  const r1: SportsRecord = new SportsRecord();
  r1.name = '气膜馆羽毛球场';
  r1.field = '3 号场地';
  r1.time = '10月12日 18:00 - 19:00';
  r1.price = '30.00';
  r1.method = '网上支付';
  r1.payId = 'demo-pay-1';
  r1.bookId = 'demo-book-1';
  list.push(r1);
  const r2: SportsRecord = new SportsRecord();
  r2.name = '综体篮球场';
  r2.field = '2 号场地';
  r2.time = '10月10日 20:00 - 21:00';
  r2.price = '40.00';
  r2.method = '已支付';
  list.push(r2);
  return list;
}

/** 日期偏移 → chip 文案（今天 / 明天 / M/D） */
function sportsDateLabel(offsetDays: number, locale: string): string {
  if (offsetDays === 0) {
    return I18n.t('common.today', locale);
  }
  if (offsetDays === 1) {
    return I18n.t('common.tomorrow', locale);
  }
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  return String(d.getMonth() + 1) + '/' + String(d.getDate());
}

// ============================================================
// 页面组件
// ============================================================

@Component
export struct SportsBookingPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  @State view: number = VIEW_RESOURCES;
  @State titleText: string = 'campus.sports.title';
  @State loading: boolean = false;
  @State errorMessage: string = '';

  @State selectedVenueIndex: number = 0;
  @State dateOffset: number = 0;
  @State info: SportsResourceInfo = new SportsResourceInfo();
  @State records: SportsRecord[] = [];

  private isDemo: boolean = true;

  /** 系统返回拦截：RECORDS 视图先回资源视图，RESOURCES 视图交回入口卡片 */
  private backHandler: BackHandler = (): boolean => {
    if (this.view === VIEW_RECORDS) {
      this.closeRecords();
      return true;
    }
    this.onBack();
    return true;
  };

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    this.loadResources();
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
  }

  // ── 视图导航 ────────────────────────────────

  private closeRecords(): void {
    this.view = VIEW_RESOURCES;
    this.titleText = 'campus.sports.title';
  }

  private handleHeaderBack(): void {
    if (this.view === VIEW_RECORDS) {
      this.closeRecords();
    } else {
      this.onBack();
    }
  }

  // ── 数据加载（演示模式零网络请求） ────────────────────────────────

  private extractError(e: Object): string {
    const raw: string = e instanceof Error ? e.message : String(e);
    // 服务层错误文案为中文常量：按已知语义映射到词典，避免英文模式泄露中文
    if (raw.indexOf('无法获取体育场馆预约限额') >= 0) {
      return this.tr('campus.sports.errorLimit');
    }
    if (raw.indexOf('会话未登录') >= 0) {
      return this.tr('campus.sports.errorSession');
    }
    if (raw.indexOf('会话建立失败') >= 0) {
      return this.tr('campus.sports.errorSessionBuild');
    }
    if (raw.indexOf('无法加载体育场馆预约订单') >= 0) {
      return this.tr('campus.sports.errorOrders');
    }
    return this.tr('campus.sports.errorGeneric');
  }

  /** 当前选中场馆（索引越界回退第一个） */
  private currentVenue(): SportsVenue {
    if (this.selectedVenueIndex < 0 || this.selectedVenueIndex >= SPORTS_VENUES.length) {
      return SPORTS_VENUES[0];
    }
    return SPORTS_VENUES[this.selectedVenueIndex];
  }

  /** 场馆 × 日期资源 + 限额 + 联系电话 */
  private async loadResources(): Promise<void> {
    this.errorMessage = '';
    if (this.isDemo) {
      this.info = getDemoResourceInfo();
      return;
    }
    this.loading = true;
    try {
      this.info = await SessionManager.getSportsService()
        .getSportsResources(this.currentVenue(), sportsDateString(this.dateOffset));
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private onSelectVenue(index: number): void {
    if (index === this.selectedVenueIndex) {
      return;
    }
    this.selectedVenueIndex = index;
    this.loadResources();
  }

  private onDateOffset(offset: number): void {
    if (offset === this.dateOffset) {
      return;
    }
    this.dateOffset = offset;
    this.loadResources();
  }

  /** 我的预约记录（未支付 + 已支付合并） */
  private async openRecords(): Promise<void> {
    this.view = VIEW_RECORDS;
    this.titleText = 'campus.sports.recordsTitle';
    this.errorMessage = '';
    if (this.isDemo) {
      this.records = getDemoRecords();
      return;
    }
    this.loading = true;
    try {
      this.records = await SessionManager.getSportsService().getSportsRecords();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 右上角刷新 / 错误重试：按当前视图重拉 */
  private async refreshCurrent(): Promise<void> {
    if (this.view === VIEW_RECORDS) {
      await this.openRecords();
    } else {
      await this.loadResources();
    }
  }

  // ── 徽标辅助 ────────────────────────────────

  private resourceStatusLabel(res: SportsResource): string {
    if (res.locked) {
      return this.tr('campus.sports.locked');
    }
    if (!res.canNetBook) {
      return this.tr('campus.sports.notBookable');
    }
    return this.tr('campus.sports.bookable');
  }

  private resourceStatusTone(res: SportsResource): BadgeTone {
    if (res.locked) {
      return BadgeTone.Warning;
    }
    if (!res.canNetBook) {
      return BadgeTone.Default;
    }
    return BadgeTone.Success;
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

      Text(this.tr(this.titleText))
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

  /** 右上角刷新（加载时转为进度指示） */
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
          this.refreshCurrent();
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
      Text(this.tr('status.loading'))
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
        title: this.tr('status.failed'),
        message: this.errorMessage,
        actionText: this.tr('status.retry'),
        onAction: () => {
          this.refreshCurrent();
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
  }

  /** 场馆 chip（固定 8 场馆，默认第一个） */
  @Builder
  private VenueChip(venue: SportsVenue, index: number) {
    Text(venue.name)
      .fontSize(FontSize.label)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selectedVenueIndex === index ? Theme.textInvert : Theme.textSecondary)
      .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
      .borderRadius(Radius.pill)
      .backgroundColor(this.selectedVenueIndex === index ? Theme.primary : Theme.surfaceAlt)
      .onClick(() => {
        this.onSelectVenue(index);
      })
  }

  /** 近 7 天日期 chip（默认今天） */
  @Builder
  private DateChip(offset: number) {
    Text(sportsDateLabel(offset, this.locale))
      .fontSize(FontSize.label)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.dateOffset === offset ? Theme.textInvert : Theme.textMuted)
      .padding({ left: Space.lg, right: Space.lg, top: Space.sm, bottom: Space.sm })
      .borderRadius(Radius.pill)
      .backgroundColor(this.dateOffset === offset ? Theme.primary : Theme.surface)
      .border({ width: 1, color: this.dateOffset === offset ? Theme.primary : Theme.borderSubtle })
      .onClick(() => {
        this.onDateOffset(offset);
      })
  }

  /** 限额行（已用/上限）+ 联系电话行（仅服务端返回时展示） */
  @Builder
  private LimitCard() {
    Column({ space: Space.xs }) {
      Row() {
        Text(this.tr('campus.sports.limitTitle'))
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
        Text(this.trp('campus.sports.limitUsed', {
          'used': String(this.info.count),
          'max': String(this.info.init)
        }))
          .fontSize(FontSize.body)
          .fontColor(Theme.textSecondary)
      }
      .width('100%')

      if (this.info.phone.length > 0) {
        Divider().color(Theme.divider)
        Row() {
          Text(this.tr('campus.sports.phone'))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .layoutWeight(1)
          Text(this.info.phone)
            .fontSize(FontSize.body)
            .fontColor(Theme.primary)
        }
        .width('100%')
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: Space.md })
  }

  /** 资源卡片（时段 × 场地 × 费用 × 可预约/已锁定） */
  @Builder
  private ResourceRow(res: SportsResource) {
    Row() {
      Column({ space: 2 }) {
        Text(res.timeSession.length > 0 ? res.timeSession : this.tr('campus.sports.timeTbd'))
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(res.fieldName.length > 0
          ? (res.cost > 0 ? res.fieldName + ' · ¥' + String(res.cost) : res.fieldName)
          : this.tr('campus.sports.fieldTbd'))
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      StatusBadge({ text: this.resourceStatusLabel(res), tone: this.resourceStatusTone(res) })
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
  }

  /** 预约记录卡片（名称/场地/时间/价格/支付方式 + 可取消/可支付标注） */
  @Builder
  private RecordRow(record: SportsRecord) {
    Column({ space: Space.xs }) {
      Text(record.name.length > 0 ? record.name : this.tr('campus.reservation.sports'))
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Text((record.field.length > 0 ? record.field : this.tr('campus.sports.fieldFallback')) + ' · '
        + (record.time.length > 0 ? record.time : this.tr('campus.sports.timeFallback')))
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
      Row({ space: Space.sm }) {
        Text(this.trp('campus.sports.priceLine', {
          'price': record.price.length > 0 ? record.price : '-',
          'method': record.method.length > 0 ? record.method : this.tr('campus.sports.methodFallback')
        }))
          .fontSize(FontSize.caption)
          .fontColor(Theme.textSecondary)
          .layoutWeight(1)
        if (record.payId.length > 0) {
          StatusBadge({ text: this.tr('campus.sports.payable'), tone: BadgeTone.Warning })
        }
        if (record.bookId.length > 0) {
          StatusBadge({ text: this.tr('campus.sports.cancellable'), tone: BadgeTone.Default })
        }
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

  /** RESOURCES 视图 */
  @Builder
  private ResourcesLayer() {
    Scroll() {
      Column() {
        // 场馆 chips（横向，默认第一个）
        Scroll() {
          Row({ space: Space.sm }) {
            ForEach(SPORTS_VENUES, (venue: SportsVenue, index: number) => {
              this.VenueChip(venue, index)
            }, (venue: SportsVenue, index: number) => venue.gymId + '-' + venue.itemId + '-' + String(index))
          }
          .padding({ left: Space.md, right: Space.md })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: Space.md })

        // 近 7 天日期行（横向，默认今天）
        Scroll() {
          Row({ space: Space.xs }) {
            ForEach([0, 1, 2, 3, 4, 5, 6], (offset: number) => {
              this.DateChip(offset)
            }, (offset: number) => String(offset))
          }
          .padding({ left: Space.md, right: Space.md })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: Space.md, bottom: Space.md })

        // 限额 + 联系电话
        this.LimitCard()

        // 我的预约记录入口
        Row() {
          Text('📋')
            .fontSize(20)
          Text(this.tr('campus.sports.recordsTitle'))
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
          this.openRecords();
        })

        // 只读引导
        StateBlock({
          tone: StateTone.Info,
          message: this.tr('campus.sports.readonlyHint'),
        })
        .margin({ left: Space.md, right: Space.md, bottom: Space.md })

        // 资源列表 / 空态
        if (this.info.data.length === 0) {
          EmptyHint({ title: this.tr('campus.sports.emptyResourcesTitle'), message: this.tr('campus.sports.emptyResourcesMessage') })
        } else {
          ForEach(this.info.data, (res: SportsResource) => {
            this.ResourceRow(res)
          }, (res: SportsResource) => res.resId)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** RECORDS 视图 */
  @Builder
  private RecordsLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: this.tr('campus.sports.recordsHint'),
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.records.length === 0) {
          EmptyHint({ title: this.tr('campus.sports.emptyRecordsTitle'), message: this.tr('campus.sports.emptyRecordsMessage') })
        } else {
          ForEach(this.records, (record: SportsRecord, index: number) => {
            this.RecordRow(record)
          }, (record: SportsRecord, index: number) => record.name + '#' + String(index))
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
          if (this.view === VIEW_RESOURCES) {
            this.ResourcesLayer()
          } else {
            this.RecordsLayer()
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
