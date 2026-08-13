import { Theme, SafeTop, Space, Radius, FontSize } from './Theme';
import { ScreenHeader } from '../components/Ui';
import { ClassroomPage } from './ClassroomPage';
import { GradesPage } from './GradesPage';
import { PETestPage } from './campus/PETestPage';
import { DormitoryPage } from './campus/DormitoryPage';
import { FinancePage } from './campus/FinancePage';
import { NetworkPage } from './campus/NetworkPage';
import { MailPage } from './campus/MailPage';
import { ReservationPage } from './campus/ReservationPage';
import { NewsPage } from './campus/NewsPage';
import { ProgramPage } from './campus/ProgramPage';

class CampusEntry {
  iconRes: Resource = $r('app.media.campus');
  title: string = '';
  subtitle: string = '';
  action: string = '';
}

/** 校园入口行：40×40 图标瓷砖（圆角 10 + hairline 描边）+ 标题/副标题 + 右侧 › */
@Component
struct EntryRow {
  @Prop entry: CampusEntry = new CampusEntry();

  build() {
    Row({ space: Space.md }) {
      Image(this.entry.iconRes)
        .width(40)
        .height(40)
        .borderRadius(Radius.sm)
        .border({ width: 1, color: Theme.borderSubtle })
        .objectFit(ImageFit.Cover)

      Column({ space: 2 }) {
        Text(this.entry.title)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(this.entry.subtitle)
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(22)
        .fontWeight(FontWeight.Lighter)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .padding(Space.md)
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct CampusPage {
  @State subScreen: string = '';
  private entries: CampusEntry[] = [];

  private makeEntry(iconRes: Resource, title: string, subtitle: string, action: string): CampusEntry {
    const e: CampusEntry = new CampusEntry();
    e.iconRes = iconRes;
    e.title = title;
    e.subtitle = subtitle;
    e.action = action;
    return e;
  }

  aboutToAppear(): void {
    this.entries = [
      this.makeEntry($r('app.media.news'), '校园资讯', '清华快讯 · 公告', 'news'),
      this.makeEntry($r('app.media.classroom'), '空闲教室', '查询空闲教室', 'classroom'),
      this.makeEntry($r('app.media.grades'), '成绩查询', '查看成绩绩点', 'grades'),
      this.makeEntry($r('app.media.petest'), '体测成绩', '查看体测结果', 'petest'),
      this.makeEntry($r('app.media.dormitory'), '宿舍服务', '电费 · 洗衣机', 'dormitory'),
      this.makeEntry($r('app.media.finance'), '财务缴费', '校园卡 · 消费记录', 'finance'),
      this.makeEntry($r('app.media.network'), '校园网', '余额 · 在线设备', 'network'),
      this.makeEntry($r('app.media.reservation'), '场馆预约', '研读间 · 体育场馆', 'reservation'),
      this.makeEntry($r('app.media.mail'), '校园邮箱', '清华邮箱', 'mail'),
      this.makeEntry($r('app.media.campus'), '培养方案', '学分完成度', 'program'),
    ];
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
    } else if (this.subScreen === 'news') {
      NewsPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'program') {
      ProgramPage({ onBack: () => { this.subScreen = ''; } })
    } else {
      Scroll() {
        Column() {
          SafeTop()

          Column() {
            ScreenHeader({ eyebrow: 'CAMPUS', title: '校园', subtitle: `${this.entries.length} 项校园服务` })
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.lg })

          Column() {
            ForEach(this.entries, (entry: CampusEntry, index: number) => {
              EntryRow({ entry: entry })
                .onClick(() => { this.handleEntryClick(entry); })
              if (index < this.entries.length - 1) {
                Divider().color(Theme.divider).margin({ left: 72 })
              }
            })
          }
          .width('100%')
          .borderRadius(Radius.lg)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: Space.lg, right: Space.lg })

          Blank().height(Space.xxl)
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
