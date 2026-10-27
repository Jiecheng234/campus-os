/**
 * NotificationDetailPage — 通知详情（学习详情深链）
 *
 * 展示 标题 / 所属课程 / 发布人 / 发布时间 / 正文（FR-007）：
 *   - 正文优先使用同步时已解码的内容；
 *   - 正文为空且非演示模式时，按 courseId 补拉一次通知列表并按 id 匹配（FR-008）；
 *   - 补拉失败保留元信息，正文区给出失败提示与重试入口（FR-009）；
 *   - 页面只读，不回写已读状态（FR-010）；演示模式不补拉、零请求（FR-023）。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusCourse, CampusNotification, CampusDataService } from '../../services/campus/CampusDataService';
import { SessionManager } from '../../services/auth/SessionManager';
import { I18n } from '../../utils/I18n';
import { Log } from '../../utils/Logger';

@Component
export struct NotificationDetailPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  item: CampusNotification = new CampusNotification();
  /** 演示模式：不补拉、不发请求，直接展示传入数据 */
  demoMode: boolean = false;

  /** 正文补拉状态：idle 无需补拉 / loading 补拉中 / failed 补拉失败（可重试） */
  @State bodySync: string = 'idle';
  /** 展示正文（初始取同步内联内容；补拉成功后更新） */
  @State bodyText: string = '';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  aboutToAppear(): void {
    this.bodyText = this.item.content;
    // FR-008：正文为空且非演示模式时按课程补拉一次（只读，不回写已读）
    if (this.bodyText.length === 0 && !this.demoMode) {
      this.fetchBody();
    }
  }

  /** 按 courseId 构造课程上下文重拉通知列表，按 id 匹配正文 */
  private fetchBody(): void {
    if (this.demoMode || this.item.courseId.length === 0) {
      return;
    }
    this.bodySync = 'loading';
    const service: CampusDataService = SessionManager.getCampusDataService();
    const course: CampusCourse = new CampusCourse();
    course.id = this.item.courseId;
    course.name = this.item.courseName;
    service.fetchNotifications([course]).then((list: CampusNotification[]) => {
      let matched: string = '';
      for (let i: number = 0; i < list.length; i++) {
        if (list[i].id === this.item.id && list[i].content.length > 0) {
          matched = list[i].content;
          break;
        }
      }
      if (matched.length > 0) {
        this.bodyText = matched;
        this.bodySync = 'idle';
      } else {
        // 匹配成功但正文仍为空 → 明确空态
        this.bodySync = 'idle';
      }
      Log.i('LearnAct', 'NOTIF_BODY refetch matched=%{public}s', matched.length > 0 ? 'yes' : 'no');
    }).catch((e: Object) => {
      // FR-009：补拉失败保留元信息，可重试
      this.bodySync = 'failed';
      Log.i('LearnAct', 'NOTIF_BODY refetch ex=%{public}s', e instanceof Error ? e.message : String(e));
    });
  }

  private retryFetchBody(): void {
    this.fetchBody();
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.item.title.length > 0 ? this.item.title : this.tr('learning.notification.title'), onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          Column() {
            Text(this.item.title)
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.text)
              .margin({ bottom: 12 })

            // 元信息（FR-007：所属课程 / 发布人 / 发布时间）
            Column({ space: 6 }) {
              if (this.item.courseName.length > 0) {
                Row() {
                  Text(this.tr('learning.notification.course'))
                    .fontSize(12)
                    .fontColor(Theme.textMuted)
                    .width(64)
                  Text(this.item.courseName)
                    .fontSize(13)
                    .fontColor(Theme.textSecondary)
                }
                .width('100%')
              }
              Row() {
                Text(this.tr('learning.notification.publisher'))
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
                  .width(64)
                Text(this.item.publisher.length > 0 ? this.item.publisher : '—')
                  .fontSize(13)
                  .fontColor(Theme.primary)
              }
              .width('100%')
              Row() {
                Text(this.tr('learning.notification.publishTime'))
                  .fontSize(12)
                  .fontColor(Theme.textMuted)
                  .width(64)
                Text(this.item.publishTime.length > 0 ? this.item.publishTime : '—')
                  .fontSize(13)
                  .fontColor(Theme.textSecondary)
              }
              .width('100%')
            }
            .width('100%')
            .margin({ bottom: 16 })

            Divider().color(Theme.divider).margin({ bottom: 16 })

            // 正文（FR-008/FR-009：直接展示 / 加载中 / 失败重试 / 明确空态）
            if (this.bodySync === 'loading') {
              Text(this.tr('learning.notification.loadingBody'))
                .fontSize(14)
                .fontColor(Theme.textMuted)
                .lineHeight(24)
            } else if (this.bodySync === 'failed') {
              Column({ space: 8 }) {
                Text(this.tr('learning.notification.loadFailed'))
                  .fontSize(14)
                  .fontColor(Theme.error)
                  .lineHeight(24)
                Text(this.tr('common.retry'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.primary)
                  .onClick(() => { this.retryFetchBody(); })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            } else if (this.bodyText.length > 0) {
              Text(this.bodyText)
                .fontSize(15)
                .fontColor(Theme.text)
                .lineHeight(26)
            } else {
              Text(this.tr('learning.notification.empty'))
                .fontSize(14)
                .fontColor(Theme.textMuted)
                .lineHeight(24)
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
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
