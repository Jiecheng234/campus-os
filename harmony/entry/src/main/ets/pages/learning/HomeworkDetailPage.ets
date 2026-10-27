import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusHomework, HomeworkDetailData, CampusDataService } from '../../services/campus/CampusDataService';
import { SessionManager } from '../../services/auth/SessionManager';
import { I18n } from '../../utils/I18n';

@Component
export struct HomeworkDetailPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }
  item: CampusHomework = new CampusHomework();
  /** 演示模式：不补拉详情（演示原始数据 url 为空，双保险保证零请求） */
  demoMode: boolean = false;
  @State detail: HomeworkDetailData = new HomeworkDetailData();
  @State detailLoaded: boolean = false;

  aboutToAppear(): void {
    if (this.demoMode) {
      this.detailLoaded = true;
      return;
    }
    if (this.item.url.length > 0) {
      const service: CampusDataService = SessionManager.getCampusDataService();
      service.fetchHomeworkDetail(this.item.url).then((d: HomeworkDetailData) => {
        this.detail = d;
        this.detailLoaded = true;
      }).catch((e: Object) => {
        this.detailLoaded = true;
      });
    } else {
      this.detailLoaded = true;
    }
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.tr('learning.homework.title'), onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          // 标题卡片
          Column() {
            Row() {
              Text(this.item.title)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.text)
              Blank()
              Text(this.item.status)
                .fontSize(12)
                .fontColor(Theme.warning)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(8)
                .backgroundColor('rgba(217,119,6,0.10)')
            }
            .width('100%')
            .margin({ bottom: 10 })

            Row() {
              Text(this.tr('learning.homework.course'))
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(60)
              Text(this.item.courseName)
                .fontSize(14)
                .fontColor(Theme.text)
            }
            .width('100%')
            .margin({ bottom: 6 })

            Row() {
              Text(this.tr('learning.homework.deadline'))
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .width(60)
              Text(this.item.deadline.length > 0 ? this.item.deadline : '—')
                .fontSize(14)
                .fontColor(Theme.warning)
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 作业要求
          Column() {
            Text(this.tr('learning.homework.requirements'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            if (!this.detailLoaded) {
              Text(this.tr('status.loading'))
                .fontSize(14)
                .fontColor(Theme.textMuted)
                .lineHeight(22)
            } else {
              Text(this.detail.description.length > 0 ? this.detail.description : this.tr('learning.homework.emptyRequirements'))
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .lineHeight(22)
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 附件
          if (this.detail.attachments.length > 0) {
            Column() {
              Text(this.trp('learning.homework.attachments', {
                'n': String(this.detail.attachments.length)
              }))
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
                .margin({ bottom: 12 })

              ForEach(this.detail.attachments, (file: string, index: number) => {
                Row() {
                  Text('📄')
                    .fontSize(16)
                    .margin({ right: 10 })
                  Text(file)
                    .fontSize(14)
                    .fontColor(Theme.primary)
                  Blank()
                  Text(this.tr('learning.homework.download'))
                    .fontSize(12)
                    .fontColor(Theme.textMuted)
                }
                .width('100%')
                .padding({ top: 8, bottom: 8 })
              })
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16, bottom: 16 })
          }

          // 成绩反馈
          Column() {
            Text(this.tr('learning.homework.feedback'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            if (this.item.grade.length > 0) {
              Text(this.trp('learning.homework.grade', { 'grade': this.item.grade }))
                .fontSize(14)
                .fontColor(Theme.text)
            }
            if (this.item.gradeContent.length > 0) {
              Text(this.item.gradeContent)
                .fontSize(14)
                .fontColor(Theme.textSecondary)
                .margin({ top: 6 })
            }
            if (this.item.grade.length === 0 && this.item.gradeContent.length === 0) {
              Text(this.item.graded
                ? this.tr('learning.homework.graded')
                : this.tr('learning.homework.notGraded'))
                .fontSize(14)
                .fontColor(Theme.textMuted)
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
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
