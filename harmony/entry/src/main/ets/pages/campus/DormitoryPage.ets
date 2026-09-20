/**
 * DormitoryPage — 宿舍服务（核心：电费余额/房间信息/缴费记录）
 * 真实模式：id-roam 电费子系统 + webvpn 只读查询（对齐原项目 EleBalanceScreen）；
 * 演示模式：内置示例数据。充值链不迁移，按钮以 toast 提示走网页充值。
 */
import { Theme, SafeTop, Space } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusDataService, EleRemainder, EleRoomInfo } from '../../services/campus/CampusDataService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';

/** 缴费记录列名（对齐原项目 RECORD_COLUMNS） */
const RECORD_COLUMNS: string[] = ['充值时间', '充值', '充值前', '充值后', '操作员', '备注'];

/** 缴费记录行 → 单行摘要文本（列名 + 值，'—' 兜底空值） */
function formatRecordMeta(row: string[]): string {
  const parts: string[] = [];
  for (let i: number = 1; i < RECORD_COLUMNS.length; i++) {
    const cell: string = i < row.length ? row[i] : '';
    parts.push(RECORD_COLUMNS[i] + ' ' + (cell.length > 0 ? cell : '—'));
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

  @Builder RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
      Text('刷新')
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

      DetailHeader({
        title: '宿舍服务',
        onBack: () => { this.onBack(); },
        right: (): void => { this.RightAction(); },
      })

      Divider().color(Theme.divider)

      if (!this.isReal) {
        Text('演示数据 · 登录后显示真实电费')
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
            Text('当前剩余电量')
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
                Text('度')
                  .fontSize(16)
                  .fontColor(Theme.textMuted)
                  .margin({ left: 6, bottom: 6 })
              }
            }
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 8 })
            if (this.updateTimeText.length > 0) {
              Text(`更新于 ${this.updateTimeText}`)
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
              Text('电费余额加载失败')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.errorText)
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .textAlign(TextAlign.Center)
              Text('重试')
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
            this.SectionTitle('房间信息')
            Column() {
              this.InfoRow('户名', this.room.userName)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow('楼号', this.room.building)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow('房间', this.room.room)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow('学号', this.room.studentId)
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
            this.SectionTitle('缴费记录')
            Column() {
              ForEach(this.records, (row: string[], index: number) => {
                Column() {
                  Text(row.length > 0 && row[0].length > 0 ? row[0] : '—')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Theme.text)
                  Text(formatRecordMeta(row))
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
          Button('去充值')
            .width('90%')
            .height(44)
            .fontSize(15)
            .fontColor(Theme.textInvert)
            .backgroundColor(Theme.primary)
            .borderRadius(Theme.cardRadius)
            .margin({ top: 20 })
            .onClick(() => {
              this.getUIContext().getPromptAction().showToast({
                message: '充值请通过网页版电费系统操作',
                duration: 2000,
              });
            })

          // 洗衣服务（静态展示，服务暂未接入）
          Row() {
            Column() {
              Text('👕')
                .fontSize(28)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(22,163,74,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text('洗衣服务')
                .fontSize(13)
                .fontColor(Theme.textMuted)
              Text('3 台可用')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#16A34A')
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('空闲')
              .fontSize(13)
              .fontColor(Theme.success)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(8)
              .backgroundColor('rgba(22,163,74,0.10)')
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, top: 16, bottom: 24 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
