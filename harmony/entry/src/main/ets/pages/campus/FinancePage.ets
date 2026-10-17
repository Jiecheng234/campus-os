/**
 * FinancePage — 校园财务（核心：校园卡余额/信息/近 7 天流水）
 * 真实模式：roamCardPolicy 卡系统会话 + 只读查询（对齐原项目 CampusFinanceScreen）；
 * 演示模式：内置示例数据。充值链（支付宝）不迁移，按钮以 toast 提示。
 */
import { Theme, SafeTop, Space } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusCardService, CampusCardInfo, CampusCardTransaction } from '../../services/campus/CampusCardService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { I18n } from '../../utils/I18n';

/** 卡号打码（对齐原项目 mask：空→'—'；≤4→'****'；否则 ab***yz） */
function mask(value: string): string {
  if (value.length === 0) {
    return '—';
  }
  if (value.length <= 4) {
    return '****';
  }
  return value.substring(0, 2) + '***' + value.substring(value.length - 2);
}

/** 'MM-DD HH:mm'（对齐原项目 formatDate：空→'—'；非法日期原样返回） */
function formatTxDate(value: string): string {
  if (value.length === 0) {
    return '—';
  }
  const d: Date = new Date(value);
  if (Number.isNaN(d.getTime())) {
    return value;
  }
  const month: string = String(d.getMonth() + 1).padStart(2, '0');
  const day: string = String(d.getDate()).padStart(2, '0');
  const hour: string = String(d.getHours()).padStart(2, '0');
  const minute: string = String(d.getMinutes()).padStart(2, '0');
  return `${month}-${day} ${hour}:${minute}`;
}

/** 今天偏移 offsetDays 天的 'YYYY-MM-DD'（对齐原项目 isoDateOffset） */
function isoDateOffset(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  const month: string = String(d.getMonth() + 1).padStart(2, '0');
  const day: string = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${month}-${day}`;
}

function mockTx(id: string, name: string, summary: string, txName: string, amount: number,
  balance: number, timestamp: string, address: string): CampusCardTransaction {
  const tx: CampusCardTransaction = new CampusCardTransaction();
  tx.id = id;
  tx.name = name;
  tx.summary = summary;
  tx.txName = txName;
  tx.amount = amount;
  tx.balance = balance;
  tx.timestamp = timestamp;
  tx.address = address;
  return tx;
}

function getMockTransactions(): CampusCardTransaction[] {
  const list: CampusCardTransaction[] = [];
  list.push(mockTx('1', '紫荆园餐厅', '', '', -15.50, 285.30, '2026-09-20 11:42', '紫荆园一层'));
  list.push(mockTx('2', '桃李园餐厅', '', '', -12.00, 300.80, '2026-09-20 08:15', '桃李园一层'));
  list.push(mockTx('3', '', '支付宝充值', '', 100.00, 312.80, '2026-09-19 21:03', '支付宝'));
  list.push(mockTx('4', '清芬园餐厅', '', '', -8.50, 212.80, '2026-09-19 12:20', '清芬园一层'));
  list.push(mockTx('5', '观畴园餐厅', '', '', -22.00, 221.30, '2026-09-18 18:47', '观畴园一层'));
  return list;
}

@Component
export struct FinancePage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  @State info: CampusCardInfo = new CampusCardInfo();
  @State infoLoaded: boolean = false;
  @State transactions: CampusCardTransaction[] = [];
  @State loading: boolean = false;
  @State errorText: string = '';
  private isReal: boolean = false;

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.load();
    } else {
      this.applyMock();
    }
  }

  private applyMock(): void {
    const info: CampusCardInfo = new CampusCardInfo();
    info.userName = '王小明';
    info.departmentName = '计算机科学与技术系';
    info.balance = 285.30;
    info.cardId = '1000752000016821';
    info.cardStatus = '正常';
    info.lastTransactionTimestamp = '2026-09-20 11:42';
    info.maxOneTimeTransactionAmount = 200;
    info.maxDailyTransactionAmount = 400;
    this.info = info;
    this.infoLoaded = true;
    this.transactions = getMockTransactions();
    this.errorText = '';
  }

  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      // 信息与流水同一条链（对齐原项目 CampusFinanceScreen 的单 try 语义）
      const service: CampusCardService = SessionManager.getCampusCardService();
      this.info = await service.getCampusCardInfo();
      this.infoLoaded = true;
      const rows: CampusCardTransaction[] =
        await service.getCampusCardTransactions(isoDateOffset(-7), isoDateOffset(0), -1);
      this.transactions = rows.length > 30 ? rows.slice(0, 30) : rows;
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

  /** 流水副文本：时间 · 余额 x.xx · 地点 */
  private txMeta(item: CampusCardTransaction): string {
    let meta: string = `${formatTxDate(item.timestamp)} · `
      + this.trp('campus.finance.balanceLabel', { 'n': item.balance.toFixed(2) });
    if (item.address.length > 0) {
      meta += ` · ${item.address}`;
    }
    return meta;
  }

  /** 流水标题：name → summary → txName → '校园卡交易'（对齐原项目取值链） */
  private txTitle(item: CampusCardTransaction): string {
    if (item.name.length > 0) {
      return item.name;
    }
    if (item.summary.length > 0) {
      return item.summary;
    }
    if (item.txName.length > 0) {
      return item.txName;
    }
    return this.tr('campus.finance.txFallback');
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

      DetailHeader({
        title: this.tr('campus.finance.pageTitle'),
        onBack: () => { this.onBack(); },
        right: (): void => { this.RightAction(); },
      })

      Divider().color(Theme.divider)

      if (!this.isReal) {
        Text(this.tr('campus.finance.demoHint'))
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 0 })
      }

      Scroll() {
        Column() {
          // 校园卡余额 hero
          Column() {
            Text(this.tr('campus.finance.balanceTitle'))
              .fontSize(13)
              .fontColor(Theme.textMuted)
            Row() {
              if (this.loading && !this.infoLoaded) {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(Theme.primary)
              } else {
                Text(this.infoLoaded ? this.info.balance.toFixed(2) : '—')
                  .fontSize(40)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(Theme.primary)
                Text(this.tr('campus.finance.yuan'))
                  .fontSize(16)
                  .fontColor(Theme.textMuted)
                  .margin({ left: 6, bottom: 6 })
              }
            }
            .alignItems(VerticalAlign.Bottom)
            .margin({ top: 8 })
            if (this.infoLoaded && this.info.lastTransactionTimestamp.length > 0) {
              Text(this.trp('campus.finance.lastTx', { 'name': formatTxDate(this.info.lastTransactionTimestamp) }))
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
              Text(this.tr('campus.finance.errorTitle'))
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

          // 校园卡信息
          if (this.infoLoaded) {
            this.SectionTitle(this.tr('campus.finance.cardInfo'))
            Column() {
              this.InfoRow(this.tr('campus.finance.name'), this.info.userName)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.finance.department'), this.info.departmentName)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.finance.cardId'), mask(this.info.cardId))
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.finance.status'), this.info.cardStatus)
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.finance.perTxLimit'),
                this.trp('campus.finance.yuanAmount', { 'n': this.info.maxOneTimeTransactionAmount.toFixed(2) }))
              Divider().color(Theme.divider).margin({ left: 16 })
              this.InfoRow(this.tr('campus.finance.dailyLimit'),
                this.trp('campus.finance.yuanAmount', { 'n': this.info.maxDailyTransactionAmount.toFixed(2) }))
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          }

          // 近 7 天流水
          this.SectionTitle(this.tr('campus.finance.recentTx'))
          Column() {
            if (this.loading) {
              Row({ space: Space.sm }) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(Theme.primary)
                Text(this.tr('campus.finance.loadingTx'))
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 20, bottom: 20 })
            } else if (this.transactions.length === 0) {
              Column({ space: Space.xs }) {
                Text(this.tr('campus.finance.emptyTxTitle'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
                Text(this.tr('campus.finance.emptyTxMessage'))
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Center)
              .padding({ top: 20, bottom: 20 })
            } else {
              ForEach(this.transactions, (item: CampusCardTransaction, index: number) => {
                Column() {
                  Row() {
                    Text(this.txTitle(item))
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text((item.amount >= 0 ? '+' : '') + item.amount.toFixed(2))
                      .fontSize(15)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(item.amount >= 0 ? Theme.success : Theme.text)
                      .margin({ left: 12 })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  Text(this.txMeta(item))
                    .fontSize(12)
                    .fontColor(Theme.textMuted)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                if (index < this.transactions.length - 1) {
                  Divider().color(Theme.divider).margin({ left: 16 })
                }
              }, (item: CampusCardTransaction, index: number) => item.id + '-' + index.toString())
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })

          // 去充值（充值链不迁移，提示走支付宝/网页）
          Button(this.tr('campus.finance.topUp'))
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
                message: this.tr('campus.finance.topUpToast'),
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
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
