import { Theme, SafeTop } from '../Theme';

class NotificationDetail {
  title: string = '';
  publisher: string = '';
  time: string = '';
  content: string = '';
}

@Component
export struct NotificationDetailPage {
  onBack: () => void = () => {};
  @State notification: NotificationDetail = new NotificationDetail();

  aboutToAppear(): void {
    const n: NotificationDetail = new NotificationDetail();
    n.title = '补退选课通知';
    n.publisher = '教务处';
    n.time = '2025年7月22日 10:00';
    n.content = '各位同学：\n\n2025-2026学年秋季学期补退选课将于2025年8月15日9:00开始，8月30日17:00结束。请同学们在规定时间内登录网络学堂完成选课操作。\n\n选课流程：\n1. 登录网络学堂（learn.tsinghua.edu.cn）\n2. 进入「选课系统」\n3. 搜索目标课程，查看剩余名额\n4. 选择课程并确认提交\n\n注意事项：\n- 每人选课上限为30学分\n- 实验课、体育课不占用学分上限\n- 选课结果以系统最终确认为准\n- 如有疑问请联系院系教务老师\n\n教务处\n2025年7月22日';
    this.notification = n;
  }

  build() {
    Column() {
      SafeTop()

      Row() {
        Button('← 返回')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontColor(Theme.primary)
          .backgroundColor(Theme.background)
          .onClick(() => { this.onBack(); })

        Text('通知详情')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 60 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          Column() {
            Text(this.notification.title)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
              .margin({ bottom: 12 })

            Row() {
              Text(this.notification.publisher)
                .fontSize(13)
                .fontColor(Theme.primary)
                .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                .borderRadius(4)
                .backgroundColor('rgba(124,92,250,0.08)')
              Blank().width(8)
              Text(this.notification.time)
                .fontSize(13)
                .fontColor(Theme.textMuted)
            }
            .width('100%')
            .margin({ bottom: 16 })

            Divider().color(Theme.divider).margin({ bottom: 16 })

            Text(this.notification.content)
              .fontSize(15)
              .fontColor(Theme.text)
              .lineHeight(26)
          }
          .width('100%')
          .padding(20)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16 })
          .alignItems(HorizontalAlign.Start)

          Blank().height(32)
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
