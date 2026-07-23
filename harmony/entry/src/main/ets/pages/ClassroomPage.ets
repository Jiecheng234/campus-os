/**
 * ClassroomPage — 空教室查询
 */
import { Theme, SafeTop } from './Theme';

const PERIODS: string[] = ['08:00', '10:10', '13:30', '15:20', '19:20'];
const BUILDINGS: string[] = ['六教', '四教', '五教', '新水', '三教'];
const DAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];

// 硬编码模拟：每个教学楼 × 时段 × 星期几 × 状态
function getMockStatus(buildingIdx: number, day: number, period: number): string {
  const seed: number = buildingIdx * 7 + day + period;
  if (seed % 7 === 0) {
    return 'teaching';    // 红
  }
  if (seed % 5 === 0) {
    return 'exam';        // 深红
  }
  if (seed % 3 === 0) {
    return 'borrowed';    // 灰
  }
  return 'available';     // 绿
}

function statusColor(status: string): string {
  if (status === 'teaching') {
    return '#DC2626';
  }
  if (status === 'exam') {
    return '#991B1B';
  }
  if (status === 'borrowed') {
    return '#9CA3AF';
  }
  return '#16A34A';
}

function statusLabel(status: string): string {
  if (status === 'teaching') {
    return '占用';
  }
  if (status === 'exam') {
    return '考试';
  }
  if (status === 'borrowed') {
    return '借用';
  }
  return '空闲';
}

@Component
export struct ClassroomPage {
  onBack: () => void = () => {};
  @State selectedBuilding: number = 0;
  @State selectedDay: number = 0;
  @State currentWeek: number = 18;

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

        Text('空教室查询')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ right: 60 })
      }
      .width('100%')
      .padding({ left: 8, right: 16, top: 8, bottom: 8 })

      Divider().color(Theme.divider)

      // 教学楼芯片
      Scroll() {
        Row() {
          ForEach(BUILDINGS, (bld: string, idx: number) => {
            Text(bld)
              .fontSize(13)
              .fontColor(this.selectedBuilding === idx ? Theme.textInvert : Theme.textSecondary)
              .padding({ left: 14, right: 14, top: 7, bottom: 7 })
              .borderRadius(999)
              .backgroundColor(this.selectedBuilding === idx ? Theme.primary : Theme.surfaceAlt)
              .margin({ right: 8 })
              .onClick(() => { this.selectedBuilding = idx; })
          })
        }
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Divider().color(Theme.divider)

      // 周选择 + 日期 tabs
      Row() {
        Text(`第 ${this.currentWeek} 周`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .margin({ right: 16 })

        Row() {
          ForEach(DAYS, (day: string, idx: number) => {
            Text(day)
              .fontSize(12)
              .fontColor(this.selectedDay === idx ? Theme.textInvert : Theme.textSecondary)
              .width(28)
              .height(28)
              .textAlign(TextAlign.Center)
              .borderRadius(14)
              .backgroundColor(this.selectedDay === idx ? Theme.primary : Theme.surfaceAlt)
              .margin({ right: 4 })
              .onClick(() => { this.selectedDay = idx; })
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 10, bottom: 6 })

      Divider().color(Theme.divider)

      // 时段网格
      Scroll() {
        Column() {
          ForEach(PERIODS, (time: string, pIdx: number) => {
            Row() {
              Column() {
                Text(time)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
              }
              .width(52)
              .height(56)
              .justifyContent(FlexAlign.Center)

              Column() {
                Text(statusLabel(getMockStatus(this.selectedBuilding, this.selectedDay, pIdx)))
                  .fontSize(13)
                  .fontColor(statusColor(getMockStatus(this.selectedBuilding, this.selectedDay, pIdx)))
                Text(BUILDINGS[this.selectedBuilding])
                  .fontSize(10)
                  .fontColor(Theme.textMuted)
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .height(56)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .border({ width: { bottom: 1, right: 1 }, color: Theme.divider })
            }
            .width('100%')
          })
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 图例
      Row() {
        LegendDot({ color: '#16A34A' }); Text('空闲').fontSize(11).fontColor(Theme.textMuted)
        Blank().width(12)
        LegendDot({ color: '#DC2626' }); Text('占用').fontSize(11).fontColor(Theme.textMuted)
        Blank().width(12)
        LegendDot({ color: '#991B1B' }); Text('考试').fontSize(11).fontColor(Theme.textMuted)
        Blank().width(12)
        LegendDot({ color: '#9CA3AF' }); Text('借用').fontSize(11).fontColor(Theme.textMuted)
      }
      .width('100%')
      .padding({ left: 16, top: 8, bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}

@Component
struct LegendDot {
  @Prop color: string = '';

  build() {
    Row()
      .width(8)
      .height(8)
      .borderRadius(4)
      .backgroundColor(this.color)
      .margin({ right: 4 })
  }
}
