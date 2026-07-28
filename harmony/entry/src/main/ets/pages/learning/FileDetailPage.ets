import { Theme, SafeTop } from '../Theme';

class FileInfo {
  title: string = '';
  course: string = '';
  size: string = '';
  extension: string = '';
  uploadTime: string = '';
  downloads: number = 0;
  description: string = '';
}

@Component
export struct FileDetailPage {
  onBack: () => void = () => {};
  @State file: FileInfo = new FileInfo();

  aboutToAppear(): void {
    const f: FileInfo = new FileInfo();
    f.title = '高等数学第5章课件.pptx';
    f.course = '高等数学(1)';
    f.size = '12.5 MB';
    f.extension = 'pptx';
    f.uploadTime = '2025年7月15日 14:30';
    f.downloads = 42;
    f.description = '第5章：定积分的应用\n\n内容包括：微元法、平面图形的面积、旋转体的体积、平面曲线的弧长、定积分在物理中的应用等。';
    this.file = f;
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

        Text('文件详情')
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
          // 文件图标预览
          Column() {
            Text(this.getFileIcon(this.file.extension))
              .fontSize(56)
              .margin({ bottom: 12 })
            Text(this.file.title)
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
            InfoRow({ label: '所属课程', value: this.file.course })
            InfoRow({ label: '文件大小', value: this.file.size })
            InfoRow({ label: '文件类型', value: this.file.extension.toUpperCase() })
            InfoRow({ label: '上传时间', value: this.file.uploadTime })
            InfoRow({ label: '下载次数', value: String(this.file.downloads) + ' 次' })
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 16 })

          // 描述
          Column() {
            Text('文件说明')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.text)
              .margin({ bottom: 8 })

            Text(this.file.description)
              .fontSize(14)
              .fontColor(Theme.textSecondary)
              .lineHeight(22)
          }
          .width('100%')
          .padding(16)
          .borderRadius(Theme.cardRadius)
          .backgroundColor(Theme.surface)
          .border({ width: 1, color: Theme.borderSubtle })
          .margin({ left: 16, right: 16, bottom: 20 })

          // 下载按钮
          Button('下载文件 (' + this.file.size + ')')
            .type(ButtonType.Normal)
            .width('100%')
            .height(52)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textInvert)
            .backgroundColor(Theme.primary)
            .borderRadius(16)
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
