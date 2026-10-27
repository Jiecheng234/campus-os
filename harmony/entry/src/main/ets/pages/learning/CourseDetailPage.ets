/**
 * CourseDetailPage — 课程详情（学习详情深链）
 *
 * 聚合该课程的 作业/通知/资料 三个分组（FR-001/FR-002）：
 *   - 数据优先来自 LearningPage 按 courseId 过滤后的传入数组；
 *   - 三类同时为空且非演示模式时自动补拉一次（FR-004），可重试、不重复自动拉取；
 *   - 每个分组独立空态（FR-005），条目可下钻到对应详情（FR-003）；
 *   - 课程标识失配/不存在时展示可读空态与返回入口，不崩溃。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusCourse, CampusHomework, CampusNotification, CampusFile, CampusDataService } from '../../services/campus/CampusDataService';
import { SessionManager } from '../../services/auth/SessionManager';
import { I18n } from '../../utils/I18n';
import { Log } from '../../utils/Logger';

@Component
export struct CourseDetailPage {
  onBack: () => void = () => {};
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  course: CampusCourse = new CampusCourse();
  semester: string = '';
  homework: CampusHomework[] = [];
  notifications: CampusNotification[] = [];
  files: CampusFile[] = [];
  /** 演示模式：不补拉、不发请求，直接使用传入数据（FR-023） */
  demoMode: boolean = false;
  onOpenHomework: (item: CampusHomework) => void = (item: CampusHomework) => {};
  onOpenNotification: (item: CampusNotification) => void = (item: CampusNotification) => {};
  onOpenFile: (item: CampusFile) => void = (item: CampusFile) => {};

  /** 补拉状态：idle 未拉过 / loading 拉取中 / failed 拉取失败（保留基础信息） */
  @State syncStatus: string = 'idle';
  @State fetchedHomework: CampusHomework[] = [];
  @State fetchedNotifications: CampusNotification[] = [];
  @State fetchedFiles: CampusFile[] = [];
  private fetchAttempted: boolean = false;

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  aboutToAppear(): void {
    // FR-004：本地三类全空且真实模式时自动补拉一次（演示模式零请求）
    if (!this.demoMode && this.homework.length === 0 && this.notifications.length === 0 && this.files.length === 0) {
      this.fetchCourseData();
    }
  }

  /** 课程标识失配/不存在（空 id + 空名称视为占位对象） */
  private isCourseMissing(): boolean {
    return this.course.id.length === 0 && this.course.name.length === 0;
  }

  /**
   * 补拉该课程三类数据（并发；任一失败不阻塞其余）。
   * 已尝试过自动拉取后不再自动重试，仅保留手动重试入口。
   */
  private fetchCourseData(): void {
    if (this.fetchAttempted || this.demoMode) {
      return;
    }
    this.fetchAttempted = true;
    this.syncStatus = 'loading';
    const service: CampusDataService = SessionManager.getCampusDataService();
    const courseList: CampusCourse[] = [this.course];
    let failed: boolean = false;
    let pending: number = 3;
    const finishOne: () => void = (): void => {
      pending--;
      if (pending === 0) {
        this.syncStatus = failed ? 'failed' : 'idle';
      }
    };
    service.fetchHomework(courseList).then((list: CampusHomework[]) => {
      this.fetchedHomework = list;
    }).catch((e: Object) => {
      failed = true;
      Log.i('LearnAct', 'COURSE_DETAIL fetch hw ex=%{public}s', e instanceof Error ? e.message : String(e));
    }).then((): void => { finishOne(); });
    service.fetchNotifications(courseList).then((list: CampusNotification[]) => {
      this.fetchedNotifications = list;
    }).catch((e: Object) => {
      failed = true;
      Log.i('LearnAct', 'COURSE_DETAIL fetch notif ex=%{public}s', e instanceof Error ? e.message : String(e));
    }).then((): void => { finishOne(); });
    service.fetchFiles(courseList).then((list: CampusFile[]) => {
      this.fetchedFiles = list;
    }).catch((e: Object) => {
      failed = true;
      Log.i('LearnAct', 'COURSE_DETAIL fetch files ex=%{public}s', e instanceof Error ? e.message : String(e));
    }).then((): void => { finishOne(); });
  }

  /** 手动重试：清空已尝试标记后重新补拉 */
  private retryFetch(): void {
    this.fetchAttempted = false;
    this.fetchedHomework = [];
    this.fetchedNotifications = [];
    this.fetchedFiles = [];
    this.fetchCourseData();
  }

  /** 展示数据：传入数据为空时回退补拉结果（以最后一次成功结果为准，不叠加） */
  private getDisplayHomework(): CampusHomework[] {
    if (this.homework.length > 0 || this.fetchedHomework.length === 0) {
      return this.homework;
    }
    return this.fetchedHomework;
  }

  private getDisplayNotifications(): CampusNotification[] {
    if (this.notifications.length > 0 || this.fetchedNotifications.length === 0) {
      return this.notifications;
    }
    return this.fetchedNotifications;
  }

  private getDisplayFiles(): CampusFile[] {
    if (this.files.length > 0 || this.fetchedFiles.length === 0) {
      return this.files;
    }
    return this.fetchedFiles;
  }

  @Builder
  groupTitle(label: string, count: number) {
    Row({ space: 6 }) {
      Text(label)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Text(String(count))
        .fontSize(12)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .margin({ bottom: Space.sm })
  }

  @Builder
  groupEmptyHint(text: string) {
    Text(text)
      .fontSize(13)
      .fontColor(Theme.textMuted)
      .padding({ top: Space.sm, bottom: Space.sm })
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.course.name.length > 0 ? this.course.name : this.tr('learning.tabCourses'), onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      if (this.isCourseMissing()) {
        // FR（US1 场景 5）：课程不存在或已不可用 → 可读空态 + 返回入口，不崩溃
        Column({ space: Space.md }) {
          Text(this.tr('learning.detail.courseMissingTitle'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.tr('learning.detail.courseMissingMessage'))
            .fontSize(13)
            .fontColor(Theme.textMuted)
          Button(this.tr('learning.detail.back'))
            .type(ButtonType.Normal)
            .height(40)
            .fontSize(14)
            .fontColor(Theme.textInvert)
            .backgroundColor(Theme.primary)
            .borderRadius(Radius.md)
            .padding({ left: Space.lg, right: Space.lg })
            .margin({ top: Space.sm })
            .onClick(() => { this.onBack(); })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: Space.xl, right: Space.xl })
      } else {
        Scroll() {
          Column() {
            // 基本信息卡片（FR-001）
            Column() {
              Row() {
                Text(this.tr('learning.course.code'))
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
                  .width(80)
                Text(this.course.code)
                  .fontSize(14)
                  .fontColor(Theme.text)
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Text(this.tr('learning.course.teacher'))
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
                  .width(80)
                Text(this.course.teacher)
                  .fontSize(14)
                  .fontColor(Theme.text)
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                Text(this.tr('learning.course.semester'))
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
                  .width(80)
                Text(this.semester.length > 0 ? this.semester : '—')
                  .fontSize(14)
                  .fontColor(Theme.text)
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

            // 补拉状态（FR-004：加载中 / 失败可重试；基础信息始终保留）
            if (this.syncStatus === 'loading') {
              Text(this.tr('learning.detail.loading'))
                .fontSize(13)
                .fontColor(Theme.textMuted)
                .margin({ left: 16, right: 16, bottom: 12 })
            } else if (this.syncStatus === 'failed') {
              Row({ space: Space.md }) {
                Text(this.tr('learning.detail.syncFailed'))
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
                  .layoutWeight(1)
                Text(this.tr('common.retry'))
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.primary)
                  .onClick(() => { this.retryFetch(); })
              }
              .width('100%')
              .constraintSize({ maxWidth: '100%' })
              .padding({ left: 16, right: 16, top: Space.sm, bottom: 12 })
            }

            // 作业分组
            Column() {
              this.groupTitle(this.tr('learning.detail.groupHomework'), this.getDisplayHomework().length)
              if (this.getDisplayHomework().length === 0) {
                this.groupEmptyHint(this.tr('learning.detail.emptyHomework'))
              } else {
                ForEach(this.getDisplayHomework(), (item: CampusHomework) => {
                  Row() {
                    Column({ space: 2 }) {
                      Text(item.title)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (item.deadline.length > 0) {
                        Text(item.deadline)
                          .fontSize(12)
                          .fontColor(Theme.textSecondary)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .onClick(() => { this.onOpenHomework(item); })
                }, (item: CampusHomework) => 'hw-' + item.id)
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16, bottom: 16 })

            // 通知分组
            Column() {
              this.groupTitle(this.tr('learning.detail.groupNotifications'), this.getDisplayNotifications().length)
              if (this.getDisplayNotifications().length === 0) {
                this.groupEmptyHint(this.tr('learning.detail.emptyNotifications'))
              } else {
                ForEach(this.getDisplayNotifications(), (item: CampusNotification) => {
                  Row({ space: Space.sm }) {
                    if (item.isNew) {
                      Text(this.tr('learning.badgeNew'))
                        .fontSize(10)
                        .fontColor(Theme.warning)
                        .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                        .borderRadius(4)
                        .backgroundColor('rgba(217,119,6,0.10)')
                    }
                    Column({ space: 2 }) {
                      Text(item.title)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (item.publishTime.length > 0) {
                        Text(item.publishTime)
                          .fontSize(12)
                          .fontColor(Theme.textSecondary)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                  .padding({ top: 10, bottom: 10 })
                  .onClick(() => { this.onOpenNotification(item); })
                }, (item: CampusNotification) => 'nt-' + item.id)
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16, bottom: 16 })

            // 资料分组
            Column() {
              this.groupTitle(this.tr('learning.detail.groupFiles'), this.getDisplayFiles().length)
              if (this.getDisplayFiles().length === 0) {
                this.groupEmptyHint(this.tr('learning.detail.emptyFiles'))
              } else {
                ForEach(this.getDisplayFiles(), (item: CampusFile) => {
                  Row() {
                    Column({ space: 2 }) {
                      Text(item.title)
                        .fontSize(14)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.text)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (item.size.length > 0) {
                        Text(item.size)
                          .fontSize(12)
                          .fontColor(Theme.textSecondary)
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ top: 10, bottom: 10 })
                  .onClick(() => { this.onOpenFile(item); })
                }, (item: CampusFile) => 'fl-' + item.id)
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .alignItems(HorizontalAlign.Start)
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
