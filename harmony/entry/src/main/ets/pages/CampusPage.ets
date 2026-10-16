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
import { LibrarySeatPage } from './campus/LibrarySeatPage';
import { NewsPage } from './campus/NewsPage';
import { ProgramPage } from './campus/ProgramPage';
import { BackDispatcher, BackOwner, BackHandler } from '../state/BackDispatcher';
import { subscribeNavigate, unsubscribeNavigate, NavigateSubscription, NavTarget, takePendingCampusSub } from '../state/UiEvents';
import { I18n } from '../utils/I18n';

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
  /** 语言订阅：语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  @State @Watch('onSubScreenChange') subScreen: string = '';
  private backHandler: BackHandler = () => {
    this.subScreen = '';
    return true;
  };
  private navSub: NavigateSubscription = new NavigateSubscription();
  private entries: CampusEntry[] = [];

  private makeEntry(iconRes: Resource, title: string, subtitle: string, action: string): CampusEntry {
    const e: CampusEntry = new CampusEntry();
    e.iconRes = iconRes;
    e.title = title;
    e.subtitle = subtitle;
    e.action = action;
    return e;
  }

  /** 渲染用副本：title/subtitle 存词典键，此处按当前语言解析（语言切换即时重渲染） */
  private localizedEntry(entry: CampusEntry): CampusEntry {
    const copy: CampusEntry = new CampusEntry();
    copy.iconRes = entry.iconRes;
    copy.title = this.tr(entry.title);
    copy.subtitle = this.tr(entry.subtitle);
    copy.action = entry.action;
    return copy;
  }

  aboutToAppear(): void {
    // 「培养方案」入口暂时隐藏（不删除）：makeEntry 定义、i18n 键（campus.program.*）、
    // ProgramPage 路由分支与导入均保留。
    // 恢复方式：将 SHOW_PROGRAM_ENTRY 改回 true 即可（原为列表末位，顺序不变）。
    const SHOW_PROGRAM_ENTRY: boolean = false;
    this.entries = [
      this.makeEntry($r('app.media.news'), 'campus.news.title', 'campus.news.subtitle', 'news'),
      this.makeEntry($r('app.media.classroom'), 'campus.classroom.title', 'campus.classroom.subtitle', 'classroom'),
      this.makeEntry($r('app.media.grades'), 'campus.grades.title', 'campus.grades.subtitle', 'grades'),
      this.makeEntry($r('app.media.petest'), 'campus.petest.title', 'campus.petest.subtitle', 'petest'),
      this.makeEntry($r('app.media.dormitory'), 'campus.dormitory.title', 'campus.dormitory.subtitle', 'dormitory'),
      this.makeEntry($r('app.media.finance'), 'campus.finance.title', 'campus.finance.subtitle', 'finance'),
      this.makeEntry($r('app.media.network'), 'campus.network.title', 'campus.network.subtitle', 'network'),
      this.makeEntry($r('app.media.reservation'), 'campus.reservation.title', 'campus.reservation.subtitle', 'reservation'),
      this.makeEntry($r('app.media.mail'), 'campus.mail.title', 'campus.mail.subtitle', 'mail'),
    ];
    if (SHOW_PROGRAM_ENTRY) {
      this.entries.push(this.makeEntry($r('app.media.campus'), 'campus.program.title', 'campus.program.subtitle', 'program'));
    }

    // 跨页导航（如首页"查空教室"）：切到校园 Tab 后直接打开子页
    this.navSub = subscribeNavigate((target: NavTarget) => {
      if (target.campusSub.length > 0) {
        this.subScreen = target.campusSub;
      }
      // 已挂载时实时生效后清除本页负责的待处理字段，避免后续挂载陈旧误触发（字段级）
      takePendingCampusSub();
    });
    // 冷启动补偿：本页挂载前发起的跨页导航（emit 即发即弃、当时本页尚未挂载未订阅）
    // 已被记录为待处理目标，此处消费一次（取值即清除）
    const pendingSub: string = takePendingCampusSub();
    if (pendingSub.length > 0) {
      this.subScreen = pendingSub;
    }
  }

  handleEntryClick(entry: CampusEntry): void {
    this.subScreen = entry.action;
  }

  onSubScreenChange(): void {
    if (this.subScreen !== '') {
      BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    } else {
      BackDispatcher.remove(this.backHandler);
    }
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
    unsubscribeNavigate(this.navSub);
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
    } else if (this.subScreen === 'library-seat') {
      // 首页"图书馆座位"入口一次直达（复用待处理导航目标机制；FR-018）
      // 顶部安全区由宿主提供：LibrarySeatPage 为内嵌组件（不自带 SafeTop），
      // 经校园页进入时由 ReservationPage 提供，此处须同样提供，否则标题贴顶、
      // 返回键被状态栏/通知中心遮挡。
      Column() {
        SafeTop()
        LibrarySeatPage({ onBack: () => { this.subScreen = ''; } })
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.background)
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
            ScreenHeader({ eyebrow: this.tr('campus.eyebrow'), title: this.tr('campus.title'), subtitle: this.trp('campus.services', { 'n': String(this.entries.length) }) })
          }
          .width('100%')
          .padding({ left: Space.lg, right: Space.lg, top: Space.lg, bottom: Space.lg })

          Column() {
            ForEach(this.entries, (entry: CampusEntry, index: number) => {
              EntryRow({ entry: this.localizedEntry(entry) })
                .onClick(() => { this.handleEntryClick(entry); })
              if (index < this.entries.length - 1) {
                Divider().color(Theme.divider)
                  .width('100%')
                  .constraintSize({ maxWidth: '100%' })
                  .margin({ left: 72 })
              }
            })
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
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
