/**
 * FileDetailPage — 资料详情（学习详情深链 US3，FR-013 ~ FR-017）
 *
 *   - 预览：调用 onPreview(previewUrl, title) 由父页面打开内嵌浏览器（WebViewerPage）；
 *   - 下载：idle / downloading / done / failed 四态（页面内状态，不持久化）；
 *     done 判定 = LearningFileStore 已下载探测命中或本次下载成功；
 *   - 打开：LearningFileStore.openDownloaded（系统预览优先、startAbility 回退）；
 *   - 演示模式（FR-023 / FR-031）：预览/下载按钮不发任何请求，
 *     提示「演示模式不可用」，不进入 WebViewerPage。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Theme, SafeTop } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { CampusFile } from '../../services/campus/CampusDataService';
import { LearningFileStore } from '../../services/learning/LearningFileStore';
import { I18n } from '../../utils/I18n';
import { Log } from '../../utils/Logger';

@Component
export struct FileDetailPage {
  onBack: () => void = () => {};
  /** 预览回调：父页面打开内嵌浏览器并停留在文件详情（返回后） */
  onPreview: (url: string, title: string) => void = () => {};
  /** 演示模式：预览/下载按钮不发请求，提示不可用 */
  demoMode: boolean = false;
  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';
  item: CampusFile = new CampusFile();
  /** 下载四态：idle / downloading / done / failed */
  @State downloadState: string = 'idle';
  /** 已下载本地路径（探测命中或本次下载成功后非空） */
  @State localPath: string = '';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  aboutToAppear(): void {
    // 进入页面即探测已下载（演示模式不落盘，跳过）
    if (!this.demoMode) {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const path: string = LearningFileStore.downloadedPath(context, this.item);
      if (path.length > 0) {
        this.localPath = path;
        this.downloadState = 'done';
      }
    }
  }

  private getExtension(title: string): string {
    const dot: number = title.lastIndexOf('.');
    if (dot < 0 || dot === title.length - 1) { return ''; }
    return title.substring(dot + 1).toLowerCase();
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 2500 });
  }

  /** 预览：非演示且 URL 可用时交给父页面打开 WebViewerPage */
  private startPreview(): void {
    if (this.demoMode) {
      this.showToast(this.tr('learning.file.demoUnavailable'));
      return;
    }
    const url: string = this.item.previewUrl.length > 0 ? this.item.previewUrl : this.item.downloadUrl;
    if (url.length === 0) {
      this.showToast(this.tr('learning.file.previewFailed'));
      return;
    }
    this.onPreview(url, this.item.title);
  }

  /** 下载：四态流转；失败可重试 */
  private startDownload(): void {
    if (this.demoMode) {
      this.showToast(this.tr('learning.file.demoUnavailable'));
      return;
    }
    if (this.downloadState === 'downloading') {
      return;
    }
    this.downloadState = 'downloading';
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    LearningFileStore.download(context, this.item).then((path: string) => {
      this.localPath = path;
      this.downloadState = 'done';
      this.showToast(this.trp('learning.file.downloadSuccess', { 'name': this.displayName() }));
    }).catch((e: BusinessError) => {
      this.downloadState = 'failed';
      Log.i('FileDetail', 'FILE_DOWNLOAD_FAILED code=%{public}d msg_len=%{public}d',
        e.code, e.message.length);
      this.showToast(this.tr('learning.file.downloadFailed'));
    });
  }

  /** 打开已下载文件：系统预览优先、startAbility 回退 */
  private openDownloaded(): void {
    if (this.localPath.length === 0) {
      return;
    }
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    LearningFileStore.openDownloaded(context, this.localPath, this.item).then((ok: boolean) => {
      if (!ok) {
        this.showToast(this.tr('learning.file.openFailed'));
      }
    });
  }

  /** 展示名（toast 用）：标题去扩展名，空则回退 i18n「文件」 */
  private displayName(): string {
    let name: string = this.item.title;
    const dot: number = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    if (name.trim().length === 0) {
      return this.tr('learning.file.nameFallback');
    }
    return name;
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: this.tr('learning.file.title'), onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      Scroll() {
        Column() {
          // 文件图标预览
          Column() {
            Text(this.getFileIcon(this.getExtension(this.item.title)))
              .fontSize(56)
              .margin({ bottom: 12 })
            Text(this.item.title)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Center)
          .padding({ top: 32, bottom: 24 })

          // 文件信息
          Column() {
            InfoRow({ label: this.tr('learning.file.course'), value: this.item.courseName })
            InfoRow({ label: this.tr('learning.file.size'), value: this.item.size.length > 0 ? this.item.size : '—' })
            InfoRow({ label: this.tr('learning.file.type'), value: this.getExtension(this.item.title).toUpperCase() })
            InfoRow({ label: this.tr('learning.file.uploadTime'), value: this.item.uploadTime.length > 0 ? this.item.uploadTime : '—' })
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 描述
          Column() {
            Text(this.tr('learning.file.descriptionTitle'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            Text(this.item.description.length > 0 ? this.item.description : this.tr('learning.file.emptyDescription'))
              .fontSize(14)
              .fontColor(Theme.textSecondary)
              .lineHeight(22)
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 20 })

          // 预览按钮（打开内嵌浏览器）
          Button(this.tr('learning.file.preview'))
            .type(ButtonType.Normal)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .height(48)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.primary)
            .backgroundColor(Theme.surface)
            .borderRadius(16)
            .border({ width: 1, color: Theme.primaryMuted })
            .margin({ left: 16, right: 16, bottom: 12 })
            .onClick(() => { this.startPreview(); })

          // 下载四态
          if (this.downloadState === 'downloading') {
            Button(this.tr('learning.file.downloading'))
              .type(ButtonType.Normal)
              .width('100%')
              .constraintSize({ maxWidth: '100%' })
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textMuted)
              .backgroundColor(Theme.surfaceAlt)
              .borderRadius(16)
              .margin({ left: 16, right: 16 })
              .enabled(false)
          } else if (this.downloadState === 'done') {
            Column({ space: 8 }) {
              Text(this.tr('learning.file.downloaded'))
                .fontSize(13)
                .fontColor(Theme.primary)
              Button(this.tr('learning.file.open'))
                .type(ButtonType.Normal)
                .width('100%')
                .constraintSize({ maxWidth: '100%' })
                .height(52)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textInvert)
                .backgroundColor(Theme.primary)
                .borderRadius(16)
                .margin({ left: 16, right: 16 })
                .onClick(() => { this.openDownloaded(); })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          } else if (this.downloadState === 'failed') {
            Column({ space: 8 }) {
              Button(this.tr('common.retry'))
                .type(ButtonType.Normal)
                .width('100%')
                .constraintSize({ maxWidth: '100%' })
                .height(52)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textInvert)
                .backgroundColor(Theme.primary)
                .borderRadius(16)
                .margin({ left: 16, right: 16 })
                .onClick(() => { this.startDownload(); })
              Text(this.tr('learning.file.downloadFailed'))
                .fontSize(13)
                .fontColor(Theme.error)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          } else {
            Button(this.item.size.length > 0
              ? this.trp('learning.file.downloadWithSize', { 'size': this.item.size })
              : this.tr('learning.file.download'))
              .type(ButtonType.Normal)
              .width('100%')
              .constraintSize({ maxWidth: '100%' })
              .height(52)
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textInvert)
              .backgroundColor(Theme.primary)
              .borderRadius(16)
              .margin({ left: 16, right: 16 })
              .onClick(() => { this.startDownload(); })
          }

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

  private getFileIcon(ext: string): string {
    if (ext === 'pdf') { return '📕'; }
    if (ext === 'pptx' || ext === 'ppt') { return '📊'; }
    if (ext === 'docx' || ext === 'doc') { return '📝'; }
    if (ext === 'xlsx' || ext === 'xls') { return '📈'; }
    if (ext === 'zip' || ext === 'rar') { return '📦'; }
    return '📄';
  }
}

@Component
struct InfoRow {
  @Prop label: string = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor(Theme.textMuted)
        .width(80)
      Text(this.value)
        .fontSize(14)
        .fontColor(Theme.text)
    }
    .width('100%')
    .margin({ bottom: 10 })
  }
}
