import { Theme } from '../../Theme';

@Component
export struct MarkdownText {
  @Prop content: string = '';

  build() {
    Column() {
      ForEach(this.parseLines(this.content), (line: string) => {
        Row() {
          Text(line)
            .fontSize(14)
            .fontColor(Theme.text)
            .width('100%')
        }
        .width('100%')
        .margin({ top: 4 })
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  private parseLines(text: string): string[] {
    const lines: string[] = text.split('\n');
    const result: string[] = [];
    for (let i: number = 0; i < lines.length; i++) {
      result.push(lines[i]);
    }
    return result;
  }
}
