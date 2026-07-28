import { Theme, SafeTop } from '../Theme';

class HomeworkDetail {
  title: string = '';
  course: string = '';
  deadline: string = '';
  status: string = '';
  description: string = '';
  grade: string = '';
  feedback: string = '';
  attachments: string[] = [];
}

@Component
export struct HomeworkDetailPage {
  onBack: () => void = () => {};
  @State hw: HomeworkDetail = new HomeworkDetail();

  aboutToAppear(): void {
    const h: HomeworkDetail = new HomeworkDetail();
    h.title = '习题集 第5章';
    h.course = '高等数学(1)';
    h.deadline = '2025年7月25日 23:59';
    h.status = '即将截止';
    h.description = '完成教材第5章课后习题：\n\n1. 习题5.1：第1、3、5、7、9题\n2. 习题5.2：第2、4、6、8、10题\n3. 习题5.3：第1、3、5题\n4. 综合练习：第5章全部复习题\n\n要求：手写或打印均可，务必标注姓名和学号，拍照上传至网络学堂。';
    h.grade = '未批改';
    h.feedback = '';
    h.attachments = ['第5章习题集.pdf', '高等数学教材第5章.pdf', '参考答案_第5章.pdf'];
    this.hw = h;
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

        Text('作业详情')
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
          // 标题卡片
          Column() {
            Row() {
              Text(this.hw.title)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.text)
              Blank()
              Text(this.hw.status)
                .fontSize(12)
                .fontColor(Theme.warning)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor('rgba(217,119,6,0.10)')
            }
            .width('100%')
            .margin({ bottom: 10 })

            Row() {
              Text('课程')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(60)
              Text(this.hw.course)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ bottom: 6 })

            Row() {
              Text('截止时间')
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(60)
              Text(this.hw.deadline)
                .fontSize(14)
                .fontColor(Theme.warning)
            }
            .width('100%')
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 作业要求
          Column() {
            Text('作业要求')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            Text(this.hw.description)
              .fontSize(14)
              .fontColor(Theme.textSecondary)
              .lineHeight(22)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 附件
          if (this.hw.attachments.length > 0) {
            Column() {
              Text('附件材料 (' + String(this.hw.attachments.length) + ')')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
                .margin({ bottom: 12 })

              ForEach(this.hw.attachments, (file: string, index: number) => {
                Row() {
                  Text('📄')
                    .fontSize(16)
                    .margin({ right: 10 })
                  Text(file)
                    .fontSize(14)
                    .fontColor(Theme.primary)
                  Blank()
                  Text('下载')
                    .fontSize(12)
                    .fontColor(Theme.textMuted)
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              })
            }
            .width('100%')
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16, bottom: 16 })
          }

          // 成绩反馈
          Column() {
            Text('成绩反馈')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            if (this.hw.grade.length > 0) {
              Text('等级：' + this.hw.grade)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            if (this.hw.feedback.length > 0) {
              Text(this.hw.feedback)
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .margin({ top: 6 })
            }
            if (this.hw.grade === '未批改' && this.hw.feedback.length === 0) {
              Text('作业尚未批改，请耐心等待。')
                .fontSize(14)
                .fontColor(Theme.textMuted)
            }
          }
          .width('100%')
          .padding(16)
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
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
