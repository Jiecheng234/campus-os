/**
 * DormitoryPage — 宿舍服务（电费 / 洗衣机 分段切换）
 * 电费：余额/房间信息/缴费记录；真实模式 id-roam + webvpn 只读查询，演示模式内置示例。
 * 洗衣机：内联渲染 LaundryPage（楼宇分组 → 楼层/机台，只读；第三方公开接口）。
 * 充值链不迁移，按钮以 toast 提示走网页充值。
 */
import { Theme, SafeTop, Space, Radius } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusDataService, EleRemainder, EleRoomInfo } from '../../services/campus/CampusDataService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { LaundryPage } from './LaundryPage';
import { I18n } from '../../utils/I18n';

/** 缴费记录列名（对齐原项目 RECORD_COLUMNS）；存 i18n 键，展示时经 tr() 本地化 */
const RECORD_COLUMN_KEYS: string[] = [
  'campus.dormitory.colTime',
  'campus.dormitory.colAmount',
  'campus.dormitory.colBefore',
  'campus.dormitory.colAfter',
  'campus.dormitory.colOperator',
  'campus.dormitory.colNote',
];

/** 缴费记录列名 → 本地化文本（index 0 为时间列，摘要行不重复展示） */
function recordColumns(locale: string): string[] {
  const columns: string[] = [];
  for (let i: number = 0; i < RECORD_COLUMN_KEYS.length; i++) {
    columns.push(I18n.t(RECORD_COLUMN_KEYS[i], locale));
  }
  return columns;
}

/** 缴费记录行 → 单行摘要文本（列名 + 值，'—' 兜底空值） */
function formatRecordMeta(row: string[], columns: string[]): string {
  const parts: string[] = [];
  for (let i: number = 1; i < columns.length; i++) {
    const cell: string = i < row.length ? row[i] : '';
    parts.push(columns[i] + ' ' + (cell.length > 0 ? cell : '—'));
  }
  return parts.join(' · ');
}

function getMockRecords(): string[][] {
  return [
    ['2026-09-01 10:23', '50.00', '-7.50', '42.50', '微信充值', '—'],
    ['2026-08-18 19:05', '100.00', '23.30', '123.30', '支付宝充值', '—'],
    ['2026-07-30 08:47', '50.00', '4.10', '54.10', '微信充值', '—'],
  ];
}

@Component
export struct DormitoryPage {
  onBack: () => void = () => {};
  /** 页内切换：洗衣机子页（返回回到电费视图） */
  @State showLaundry: boolean = false;
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  @State remainderText: string = '—';
  @State updateTimeText: string = '';
  @State room: EleRoomInfo = new EleRoomInfo();
  @State records: string[][] = [];
  @State loading: boolean = false;
  @State errorText: string = '';
  private isReal: boolean = false;

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.load();
    } else {
      this.applyMock();
    }
  }

  private applyMock(): void {
    this.remainderText = '42.50';
    this.updateTimeText = '2026-09-20 08:00';
    const room: EleRoomInfo = new EleRoomInfo();
    room.userName = '王小明';
    room.building = '紫荆公寓6号楼';
    room.room = '302B';
    room.studentId = '2021012345';
    this.room = room;
    this.records = getMockRecords();
    this.errorText = '';
  }

  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      // 余额是核心，单独 await；房间信息与记录失败不阻塞（对齐原项目 allSettled 语义）
      const service: CampusDataService = SessionManager.getCampusDataService();
      const balance: EleRemainder = await service.getEleRemainder();
      this.remainderText = String(balance.remainder);
      this.updateTimeText = balance.updateTime;
      try {
        this.room = await service.getEleRoomInfo();
      } catch (e) {
        this.room = new EleRoomInfo();
      }
      try {
        this.records = await service.getElePayRecords();
      } catch (e) {
        this.records = [];
      }
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
  }

  private refresh(): void {
    if (this.isReal) {
      this.load();
    } else {
      this.applyMock();
    }
  }

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  /** 顶部"电费 / 洗衣机"分段切换（FR-001：与电费并列，不新增校园主列表入口） */
  @Builder SegmentTabs() {
    Row({ space: Space.xs }) {
      Text(this.tr('campus.dormitory.tabPower'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textInvert)
        .padding({ left: Space.md, right: Space.md, top: 6, bottom: 6 })
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.primary)
      Text(this.tr('campus.dormitory.tabLaundry'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .padding({ left: Space.md, right: Space.md, top: 6, bottom: 6 })
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.surfaceAlt)
        .onClick(() => {
          this.showLaundry = true;
        })
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
  }

  @Builder RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
      Text(this.tr('common.refresh'))
        .fontSize(14)
        .fontColor(Theme.primary)
        .padding({ left: 12, right: 4, top: 8, bottom: 8 })
        .onClick(() => { this.refresh(); })
    }
  }

  @Builder SectionTitle(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textSecondary)
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder InfoRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
      Text(value.length > 0 ? value : '—')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
  }

  build() {
    Column() {
      SafeTop()

      if (this.showLaundry) {
        // 洗衣机子层：内联渲染（自带头部/逐级返回/刷新；返回回到电费视图）
        LaundryPage({
          onBack: () => {
            this.showLaundry = false;
          },
        })
          .layoutWeight(1)
      } else {
        DetailHeader({
          title: this.tr('campus.dormitory.title'),
          onBack: () => { this.onBack(); },
          right: (): void => { this.RightAction(); },
        })

        Divider().color(Theme.divider)

        this.SegmentTabs()

        if (!this.isReal) {
          Text(this.tr('campus.dormitory.demoHint'))
            .fontSize(12)
            .fontColor(Theme.textMuted)
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 8, bottom: 0 })
        }

        Scroll() {
        Column() {
          // 剩余电量卡片
          Column() {
            Text(this.tr('campus.dormitory.powerTitle'))
              .fontSize(13)
              .fontColor(Theme.textMuted)
            Row() {
              if (this.loading && this.remainderText === '—') {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(Theme.primary)
              } else {
                Text(this.remainderText)
                  .fontSize(40)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.primary)
                Text(this.tr('campus.dormitory.kwh'))
                  .fontSize(16)
                  .fontColor(Theme.textMuted)
                  .margin({ left: 6, bottom: 6 })
              }
            }
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 8 })
            if (this.updateTimeText.length > 0) {
              Text(this.trp('campus.dormitory.updatedAt', { 'name': this.updateTimeText }))
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 6 })
            }
          }
          .width('100%')
          .padding({ top: 24, bottom: 20 })
          .alignItems(HorizontalAlign.Center)

          if (this.errorText.length > 0) {
            Column({ space: Space.sm }) {
              Text(this.tr('campus.dormitory.powerError'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.errorText)
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .textAlign(TextAlign.Center)
              Text(this.tr('status.retry'))
                .fontSize(13)
                .fontColor(Theme.primary)
                .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
                .borderRadius(8)
                .border({ width: 1, color: Theme.primary })
                .onClick(() => { this.load(); })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ left: 16, right: 16, bottom: 8 })
          }

          // 房间信息
          if (this.room.userName.length > 0 || this.room.building.length > 0 ||
            this.room.room.length > 0 || this.room.studentId.length > 0) {
            this.SectionTitle(this.tr('campus.dormitory.roomInfo'))
            Column() {
              this.InfoRow(this.tr('campus.dormitory.owner'), this.room.userName)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.dormitory.building'), this.room.building)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.dormitory.room'), this.room.room)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.dormitory.studentId'), this.room.studentId)
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          }

          // 缴费记录
          if (this.records.length > 0) {
            this.SectionTitle(this.tr('campus.dormitory.records'))
            Column() {
              ForEach(this.records, (row: string[], index: number) => {
                Column() {
                  Text(row.length > 0 && row[0].length > 0 ? row[0] : '—')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.text)
                  Text(formatRecordMeta(row, recordColumns(this.locale)))
                    .fontSize(12)
                    .fontColor(Theme.textMuted)
                    .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                if (index < this.records.length - 1) {
                  Divider().color(Theme.divider).margin({ left: 16 })
                }
              }, (row: string[], index: number) => index.toString() + '-' + (row.length > 0 ? row[0] : ''))
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          }

          // 去充值（充值链不迁移，提示走网页）
          Button(this.tr('campus.dormitory.topUp'))
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .height(44)
            .fontSize(15)
            .fontColor(Theme.textInvert)
            .backgroundColor(Theme.primary)
            .borderRadius(Theme.cardRadius)
            .margin({ left: 16, right: 16, top: 20, bottom: 24 })
            .onClick(() => {
              this.getUIContext().getPromptAction().showToast({
                message: this.tr('campus.dormitory.topUpToast'),
                duration: 2000,
              });
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
