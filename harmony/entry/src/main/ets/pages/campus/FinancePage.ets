import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';

class Transaction {
  date: string = '';
  location: string = '';
  amount: number = 0;
  balance: number = 0;
}

function getMockTransactions(): Transaction[] {
  const list: Transaction[] = [];
  const t1: Transaction = new Transaction();
  t1.date = '2025-07-20'; t1.location = '紫荆园餐厅'; t1.amount = -15.50; t1.balance = 285.30;
  list.push(t1);
  const t2: Transaction = new Transaction();
  t2.date = '2025-07-20'; t2.location = '桃李园餐厅'; t2.amount = -12.00; t2.balance = 300.80;
  list.push(t2);
  const t3: Transaction = new Transaction();
  t3.date = '2025-07-19'; t2.amount = 0; t3.location = '支付宝充值'; t3.amount = 100.00; t3.balance = 312.80;
  list.push(t3);
  const t4: Transaction = new Transaction();
  t4.date = '2025-07-19'; t4.location = '清芬园餐厅'; t4.amount = -8.50; t4.balance = 212.80;
  list.push(t4);
  const t5: Transaction = new Transaction();
  t5.date = '2025-07-18'; t5.location = '观畴园餐厅'; t5.amount = -22.00; t5.balance = 221.30;
  list.push(t5);
  return list;
}

@Component
export struct FinancePage {
  onBack: () => void = () => {};
  private transactions: Transaction[] = getMockTransactions();
  private balance: number = 285.30;
  private cardNumber: string = '**** **** **** 6821';

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '校园财务', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Column() {
        Text('校园卡余额')
          .fontSize(14)
          .fontColor(Theme.textMuted)
        Text(`¥${this.balance.toFixed(2)}`)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary)
          .margin({ top: 4 })
        Text(this.cardNumber)
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .margin({ top: 4 })

        Row() {
          Button('充值')
            .type(ButtonType.Capsule)
            .fontSize(13)
            .fontColor(Theme.textInvert)
            .backgroundColor(Theme.primary)
            .margin({ right: 12 })
          Button('挂失')
            .type(ButtonType.Capsule)
            .fontSize(13)
            .fontColor(Theme.textSecondary)
            .backgroundColor(Theme.surfaceAlt)
        }
        .margin({ top: 16 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 24, bottom: 20 })

      Row() {
        Text('消费记录')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
      }
      .width('100%')
      .padding({ left: 16, bottom: 8 })

      List() {
        ForEach(this.transactions, (item: Transaction) => {
          ListItem() {
            Row() {
              Column() {
                Text(item.location)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.text)
                Text(item.date)
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column() {
                Text(item.amount > 0 ? `+¥${item.amount.toFixed(2)}` : `-¥${Math.abs(item.amount).toFixed(2)}`)
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(item.amount > 0 ? Theme.success : Theme.text)
                Text(`余额 ¥${item.balance.toFixed(2)}`)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
              }
              .alignItems(HorizontalAlign.End)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .alignItems(VerticalAlign.Center)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: Theme.divider })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
