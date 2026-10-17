import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { LibrarySeatPage } from './LibrarySeatPage';
import { LibraryRoomPage } from './LibraryRoomPage';
import { SportsBookingPage } from './SportsBookingPage';
import { I18n } from '../../utils/I18n';

@Component
export struct ReservationPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }
  /** 页内切换：图书馆座位子页（返回回到入口卡片） */
  @State showLibrarySeat: boolean = false;
  /** 页内切换：研读间子页（返回回到入口卡片） */
  @State showLibraryRoom: boolean = false;
  /** 页内切换：体育场馆子页（返回回到入口卡片） */
  @State showSports: boolean = false;

  build() {
    Column() {
      SafeTop()

      if (this.showLibrarySeat) {
        LibrarySeatPage({
          onBack: () => {
            this.showLibrarySeat = false;
          },
        })
          .layoutWeight(1)
      } else if (this.showLibraryRoom) {
        LibraryRoomPage({
          onBack: () => {
            this.showLibraryRoom = false;
          },
        })
          .layoutWeight(1)
      } else if (this.showSports) {
        SportsBookingPage({
          onBack: () => {
            this.showSports = false;
          },
        })
          .layoutWeight(1)
      } else {
        DetailHeader({ title: this.tr('campus.reservation.title'), onBack: () => { this.onBack(); } })

        Divider().color(Theme.divider)

      Scroll() {
        Column() {
          // 图书馆座位
          Row() {
            Column() {
              Text('📖')
                .fontSize(32)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(124,92,250,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text(this.tr('campus.reservation.libSeat'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.tr('campus.reservation.libSeatHint'))
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('>')
              .fontSize(14)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 12 })
          .onClick(() => {
            this.showLibrarySeat = true;
          })

          // 研读间
          Row() {
            Column() {
              Text('🏫')
                .fontSize(32)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(22,163,74,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text(this.tr('campus.reservation.libRoom'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.tr('campus.reservation.libRoomHint'))
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('>')
              .fontSize(14)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 12 })
          .onClick(() => {
            this.showLibraryRoom = true;
          })

          // 体育场馆
          Row() {
            Column() {
              Text('🏃')
                .fontSize(32)
            }
            .width(56)
            .height(56)
            .borderRadius(14)
            .backgroundColor('rgba(217,119,6,0.08)')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)

            Column() {
              Text(this.tr('campus.reservation.sports'))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.tr('campus.reservation.sportsHint'))
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 16 })
            .layoutWeight(1)

            Text('>')
              .fontSize(14)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })
          .onClick(() => {
            this.showSports = true;
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
