import { Theme, SafeTop } from './Theme';
import { ClassroomPage } from './ClassroomPage';
import { GradesPage } from './GradesPage';
import { PETestPage } from './campus/PETestPage';
import { DormitoryPage } from './campus/DormitoryPage';
import { FinancePage } from './campus/FinancePage';
import { NetworkPage } from './campus/NetworkPage';
import { MailPage } from './campus/MailPage';
import { ReservationPage } from './campus/ReservationPage';

class CampusEntry {
  key: string = '';
  icon: string = '';
  title: string = '';
  subtitle: string = '';
  action: string = '';
}

@Component
struct EntryRow {
  @Prop entry: CampusEntry = new CampusEntry();

  build() {
    Row() {
      Text(this.entry.icon)
        .fontSize(24)
        .width(44)

      Column() {
        Text(this.entry.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(this.entry.subtitle)
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('>')
        .fontSize(14)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct CampusPage {
  @State subScreen: string = '';
  private entries: CampusEntry[] = [];

  aboutToAppear(): void {
    const e1: CampusEntry = new CampusEntry();
    e1.icon = '🏫'; e1.title = '空教室查询'; e1.subtitle = '查询空闲教室'; e1.action = 'classroom';
    this.entries.push(e1);
    const e2: CampusEntry = new CampusEntry();
    e2.icon = '📊'; e2.title = '成绩查询'; e2.subtitle = '查看成绩绩点'; e2.action = 'grades';
    this.entries.push(e2);
    const e3: CampusEntry = new CampusEntry();
    e3.icon = '🏃'; e3.title = '体测成绩'; e3.subtitle = '查看体测结果'; e3.action = 'petest';
    this.entries.push(e3);
    const e4: CampusEntry = new CampusEntry();
    e4.icon = '🛏️'; e4.title = '宿舍服务'; e4.subtitle = '电费 · 洗衣机'; e4.action = 'dormitory';
    this.entries.push(e4);
    const e5: CampusEntry = new CampusEntry();
    e5.icon = '💰'; e5.title = '校园财务'; e5.subtitle = '校园卡 · 消费记录'; e5.action = 'finance';
    this.entries.push(e5);
    const e6: CampusEntry = new CampusEntry();
    e6.icon = '🌐'; e6.title = '校园网络'; e6.subtitle = '余额 · 在线设备'; e6.action = 'network';
    this.entries.push(e6);
    const e7: CampusEntry = new CampusEntry();
    e7.icon = '📅'; e7.title = '场馆预约'; e7.subtitle = '研读间 · 体育'; e7.action = 'reservation';
    this.entries.push(e7);
    const e8: CampusEntry = new CampusEntry();
    e8.icon = '✉️'; e8.title = '校园邮件'; e8.subtitle = '清华邮箱'; e8.action = 'mail';
    this.entries.push(e8);
  }

  handleEntryClick(entry: CampusEntry): void {
    this.subScreen = entry.action;
  }

  build() {
    if (this.subScreen === 'classroom') {
      ClassroomPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'grades') {
      GradesPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'petest') {
      PETestPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'dormitory') {
      DormitoryPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'finance') {
      FinancePage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'network') {
      NetworkPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'reservation') {
      ReservationPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'mail') {
      MailPage({ onBack: () => { this.subScreen = ''; } })
    } else {
      Scroll() {
        Column() {
          SafeTop()

          Text('校园服务')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .width('100%')
            .padding({ left: 20, top: 12, bottom: 16 })

          Column() {
            ForEach(this.entries, (entry: CampusEntry, index: number) => {
              EntryRow({ entry: entry })
                .onClick(() => { this.handleEntryClick(entry); })
              if (index < this.entries.length - 1) {
                Divider().color(Theme.divider).margin({ left: 60 })
              }
            })
          }
          .width('100%')
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })

          Blank().height(32)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.background)
      .scrollBar(BarState.Off)
    }
  }
}
