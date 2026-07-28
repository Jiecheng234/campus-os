/**
 * LearningPage — 学习页（4 子标签 + DDL 弹窗）
 */
import { Theme, SafeTop } from './Theme';
import {
  getCourses, getHomeworkList, getNotifications, getFiles, getTodayDateStr,
  CourseItem, HomeworkItem, NotificationItem, FileItem, DeadlineForm
} from './LearningData';
import { promptAction } from '@kit.ArkUI';
import { CourseDetailPage } from './learning/CourseDetailPage';
import { HomeworkDetailPage } from './learning/HomeworkDetailPage';
import { NotificationDetailPage } from './learning/NotificationDetailPage';
import { FileDetailPage } from './learning/FileDetailPage';

@Component
struct SegmentBar {
  @Link activeTab: string;
  @Prop tabs: string[] = [];
  @Prop counts: number[] = [];

  build() {
    Row() {
      ForEach(this.tabs, (tab: string, index: number) => {
        Text(`${tab} ${this.counts[index]}`)
          .fontSize(13)
          .fontColor(this.activeTab === tab ? Theme.textInvert : Theme.textSecondary)
          .padding({ left: 14, right: 14, top: 7, bottom: 7 })
          .borderRadius(999)
          .backgroundColor(this.activeTab === tab ? Theme.primary : Theme.surfaceAlt)
          .margin({ right: 8 })
          .onClick(() => {
            this.activeTab = tab;
          })
      })
    }
  }
}

@Component
struct DDLCard {
  @Prop item: HomeworkItem = new HomeworkItem();
  onCardClick: () => void = () => {};

  build() {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(this.item.status === '即将截止' ? Theme.warning : Theme.primary)

      Column() {
        Text(this.item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.item.course}  ·  ${this.item.deadline}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      Text(this.item.status)
        .fontSize(11)
        .fontColor(Theme.warning)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(8)
        .backgroundColor('rgba(217,119,6,0.10)')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
struct CourseCard {
  @Prop item: CourseItem = new CourseItem();
  onCardClick: () => void = () => {};

  build() {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(Theme.primary)

      Column() {
        Text(this.item.name)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.item.teacher}  ·  ${this.item.code}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
struct NotificationCard {
  @Prop item: NotificationItem = new NotificationItem();
  onCardClick: () => void = () => {};

  build() {
    Row() {
      Column()
        .width(3)
        .height('100%')
        .borderRadius(2)
        .backgroundColor(this.item.isNew ? Theme.warning : Theme.divider)

      Column() {
        Text(this.item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
        Text(`${this.item.publisher}  ·  ${this.item.time}`)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      if (this.item.isNew) {
        Text('NEW')
          .fontSize(11)
          .fontColor(Theme.warning)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('rgba(217,119,6,0.10)')
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => {
      this.onCardClick();
    })
  }
}

@Component
export struct LearningPage {
  @State activeTab: string = '课程';
  @State showDialog: boolean = false;
  @State ddls: HomeworkItem[] = getHomeworkList();
  @State form: DeadlineForm = new DeadlineForm();
  @State subScreen: string = '';
  private tabs: string[] = ['课程', '作业', '通知', '文件'];

  private getTabCounts(): number[] {
    return [getCourses().length, this.ddls.length, getNotifications().length, getFiles().length];
  }

  private getTabCountsSnippet(): string {
    const c: number[] = this.getTabCounts();
    return `${c[0]} 门课程 · ${c[1]} 项作业 · ${c[2]} 通知 · ${c[3]} 文件`;
  }

  build() {
    if (this.subScreen === 'course') {
      CourseDetailPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'homework') {
      HomeworkDetailPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'notification') {
      NotificationDetailPage({ onBack: () => { this.subScreen = ''; } })
    } else if (this.subScreen === 'file') {
      FileDetailPage({ onBack: () => { this.subScreen = ''; } })
    } else {
    Stack() {
      Scroll() {
        Column() {
          SafeTop()

          Row() {
            Column() {
              Text('学习')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
              Text(this.getTabCountsSnippet())
                .fontSize(12)
                .fontColor(Theme.textMuted)
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('+')
              .type(ButtonType.Circle)
              .width(36)
              .height(36)
              .fontSize(20)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
              .onClick(() => {
                this.form = new DeadlineForm();
                this.form.date = getTodayDateStr();
                this.form.time = '23:59';
                this.showDialog = true;
              })
          }
          .width('100%')
          .padding({ left: 20, right: 16, top: 12, bottom: 8 })

          SegmentBar({ activeTab: $activeTab, tabs: this.tabs, counts: this.getTabCounts() })
            .margin({ left: 20, right: 20, bottom: 16 })

          Divider().color(Theme.divider)

          if (this.activeTab === '课程') {
            Column() {
              ForEach(getCourses(), (item: CourseItem, index: number) => {
                CourseCard({ item: item, onCardClick: () => { this.subScreen = 'course'; } })
                if (index < getCourses().length - 1) {
                  Divider().color(Theme.divider).margin({ left: 15 })
                }
              })
            }
            .width('100%')
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          } else if (this.activeTab === '作业') {
            Column() {
              ForEach(this.ddls, (item: HomeworkItem, index: number) => {
                DDLCard({ item: item, onCardClick: () => { this.subScreen = 'homework'; } })
                if (index < this.ddls.length - 1) {
                  Divider().color(Theme.divider).margin({ left: 15 })
                }
              })
              if (this.ddls.length === 0) {
                Text('暂无作业')
                  .fontSize(14)
                  .fontColor(Theme.textMuted)
                  .padding({ top: 16, bottom: 16 })
              }
            }
            .width('100%')
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          } else if (this.activeTab === '通知') {
            Column() {
              ForEach(getNotifications(), (item: NotificationItem) => {
                NotificationCard({ item: item, onCardClick: () => { this.subScreen = 'notification'; } })
              })
            }
            .width('100%')
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          } else {
            Column() {
              Text('暂无文件')
                .fontSize(14)
                .fontColor(Theme.textMuted)
                .padding({ top: 16, bottom: 16 })
            }
            .width('100%')
            .padding(16)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
            .margin({ left: 16, right: 16 })
          }

          Blank().height(32)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Theme.background)
      .scrollBar(BarState.Off)

      if (this.showDialog) {
        // 半透明遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.4)')
          .onClick(() => { this.showDialog = false; })
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showDialog, this.buildDDLSheet(), {
      height: 420,
      showClose: true,
      dragBar: true,
    })
    }
  }

  @Builder
  buildDDLSheet() {
    Column() {
      Text('添加 DDL')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .margin({ bottom: 16 })

      TextInput({ placeholder: '标题（必填）', text: this.form.title })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .padding({ left: 12 })
        .margin({ bottom: 10 })
        .onChange((v: string) => { this.form.title = v; })

      Row() {
        TextInput({ placeholder: '日期', text: this.form.date })
          .width('48%')
          .height(44)
          .fontSize(14)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
          .padding({ left: 12 })
          .onChange((v: string) => { this.form.date = v; })

        Blank()

        TextInput({ placeholder: '时间', text: this.form.time })
          .width('48%')
          .height(44)
          .fontSize(14)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.border })
          .borderRadius(10)
          .padding({ left: 12 })
          .onChange((v: string) => { this.form.time = v; })
      }
      .width('100%')
      .margin({ bottom: 10 })

      TextInput({ placeholder: '课程（选填）', text: this.form.course })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .padding({ left: 12 })
        .margin({ bottom: 10 })
        .onChange((v: string) => { this.form.course = v; })

      TextInput({ placeholder: '备注（选填）', text: this.form.note })
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.border })
        .borderRadius(10)
        .padding({ left: 12 })
        .margin({ bottom: 16 })
        .onChange((v: string) => { this.form.note = v; })

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .width('48%')
          .height(44)
          .fontSize(14)
          .fontColor(Theme.text)
          .backgroundColor(Theme.surfaceAlt)
          .borderRadius(10)
          .onClick(() => { this.showDialog = false; })

        Blank()

        Button('保存')
          .type(ButtonType.Normal)
          .width('48%')
          .height(44)
          .fontSize(14)
          .fontColor(Theme.textInvert)
          .backgroundColor(Theme.primary)
          .borderRadius(10)
          .onClick(() => {
            if (this.form.title.trim() === '') {
              promptAction.showToast({ message: '请输入标题', duration: 2000 });
              return;
            }
            const hw: HomeworkItem = new HomeworkItem();
            hw.title = this.form.title;
            hw.course = this.form.course || '自定义';
            hw.deadline = `${this.form.date} ${this.form.time}`;
            hw.status = '即将截止';
            this.ddls = [hw].concat(this.ddls);
            this.showDialog = false;
            this.activeTab = '作业';
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(20)
    .alignItems(HorizontalAlign.Start)
  }
}
