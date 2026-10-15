/**
 * PETestPage — 体测成绩（真实模式：教务 zhjw 体测 JSON；演示模式：内置示例）
 * 拆成"总览 / 单项成绩"两组展示（对齐原项目 PEtestScreen summaryKeys 拆分）。
 * 视觉层级（对齐参考实现 styles.section/row）：总览 = 独立卡片 + 主色分组标题 +
 * 更强字号/配色（总分/参考成绩 h2 主色强调）；单项 = 次级底色列表行 + 分隔线 +
 * 次要文字色。数据流（请求/解析/分组键）不变。
 */
import { Theme, SafeTop, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusDataService, PETestItem } from '../../services/campus/CampusDataService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { I18n } from '../../utils/I18n';

/** 总览组标签（对齐原项目 summaryKeys） */
const SUMMARY_LABELS: string[] = [
  '是否免测', '免测原因', '总分', '标准分', '附加分', '长跑附加分', '参考成绩（自动结算）', '体育课成绩',
];

function isSummaryLabel(label: string): boolean {
  for (let i: number = 0; i < SUMMARY_LABELS.length; i++) {
    if (SUMMARY_LABELS[i] === label) {
      return true;
    }
  }
  return false;
}

/** 总分/参考成绩做主色强调（对齐原项目 isNumericScore） */
function isAccentLabel(label: string): boolean {
  return label === '总分' || label === '参考成绩（自动结算）';
}

function getMockPETest(): PETestItem[] {
  const rows: string[][] = [
    ['是否免测', '否'],
    ['总分', '472'],
    ['标准分', '468'],
    ['附加分', '4'],
    ['参考成绩（自动结算）', '82.60'],
    ['体育课成绩', '92'],
    ['身高', '178'],
    ['体重', '68'],
    ['身高体重分数', '78'],
    ['肺活量', '4350'],
    ['肺活量分数', '82'],
    ['1000M 跑', "3'45\""],
    ['1000M 跑分数', '85'],
    ['50M 跑', '7.1'],
    ['50M 跑分数', '78'],
    ['立定跳远', '2.45'],
    ['立定跳远分数', '72'],
    ['引体向上', '12'],
    ['引体向上分数', '65'],
    ['坐位体前屈', '14.2'],
    ['坐位体前屈分数', '90'],
  ];
  const list: PETestItem[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const it: PETestItem = new PETestItem();
    it.label = rows[i][0];
    it.value = rows[i][1];
    list.push(it);
  }
  return list;
}

@Component
export struct PETestPage {
  onBack: () => void = () => {};
  /** 语言订阅：语言切换即时重渲染 */
  @StorageLink('locale') locale: string = 'zh';
  @State items: PETestItem[] = [];
  @State summary: PETestItem[] = [];
  @State details: PETestItem[] = [];
  @State loading: boolean = false;
  @State errorText: string = '';
  private isReal: boolean = false;

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  aboutToAppear(): void {
    this.isReal = AuthManager.isLoggedIn() && !StateManager.isDemoMode();
    if (this.isReal) {
      this.load();
    } else {
      this.applyItems(getMockPETest());
    }
  }

  private applyItems(items: PETestItem[]): void {
    this.items = items;
    const summary: PETestItem[] = [];
    const details: PETestItem[] = [];
    for (let i: number = 0; i < items.length; i++) {
      if (isSummaryLabel(items[i].label)) {
        summary.push(items[i]);
      } else {
        details.push(items[i]);
      }
    }
    this.summary = summary;
    this.details = details;
  }

  private async load(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const service: CampusDataService = SessionManager.getCampusDataService();
      const rows: PETestItem[] = await service.fetchPEResult();
      this.applyItems(rows);
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
      this.applyItems([]);
    }
    this.loading = false;
  }

  private refresh(): void {
    if (this.isReal) {
      this.load();
    } else {
      this.applyItems(getMockPETest());
    }
  }

  @Builder RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
      Text(this.tr('pe.refresh'))
        .fontSize(14)
        .fontColor(Theme.primary)
        .padding({ left: 12, right: 4, top: 8, bottom: 8 })
        .onClick(() => { this.refresh(); })
    }
  }

  /** 总览行：label 次要色 + value 主层级（总分/参考成绩 h2 主色加粗强调） */
  @Builder SummaryRow(item: PETestItem) {
    Row({ space: Space.md }) {
      Text(item.label)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (isAccentLabel(item.label)) {
        Text(item.value)
          .fontSize(FontSize.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '60%' })
      } else {
        Text(item.value)
          .fontSize(FontSize.body)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: '60%' })
      }
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: 13, bottom: 13 })
    .alignItems(VerticalAlign.Center)
  }

  /** 单项行：次要文字色 + 更紧凑行距（对齐参考实现 styles.label/value 次级层） */
  @Builder DetailRow(item: PETestItem) {
    Row({ space: Space.md }) {
      Text(item.label)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(item.value)
        .fontSize(FontSize.caption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({
        title: this.tr('pe.title'),
        onBack: () => { this.onBack(); },
        right: (): void => { this.RightAction(); },
      })

      Divider().color(Theme.divider)

      if (!this.isReal) {
        Text(this.tr('pe.demoHint'))
          .fontSize(12)
          .fontColor(Theme.textMuted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 8, bottom: 0 })
      }

      if (this.loading && this.items.length === 0) {
        Column({ space: Space.sm }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(Theme.primary)
          Text(this.tr('pe.loading'))
            .fontSize(13)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column({ space: Space.sm }) {
          Text(this.tr('pe.errorTitle'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.errorText)
            .fontSize(13)
            .fontColor(Theme.textMuted)
            .textAlign(TextAlign.Center)
          Text(this.tr('pe.retry'))
            .fontSize(13)
            .fontColor(Theme.primary)
            .padding({ left: Space.md, right: Space.md, top: Space.xs, bottom: Space.xs })
            .borderRadius(8)
            .border({ width: 1, color: Theme.primary })
            .onClick(() => { this.load(); })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: Space.lg, right: Space.lg })
      } else if (this.items.length === 0) {
        Column({ space: Space.sm }) {
          Text(this.tr('pe.emptyTitle'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.tr('pe.emptyMessage'))
            .fontSize(13)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Column() {
            // ── 总览：独立卡片（主色竖条分组标题 + 更强字号/配色层级）──
            if (this.summary.length > 0) {
              Column() {
                Row({ space: Space.sm }) {
                  Column()
                    .width(4)
                    .height(16)
                    .borderRadius(2)
                    .backgroundColor(Theme.primary)
                  Text(this.tr('pe.groupSummary'))
                    .fontSize(FontSize.h3)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(Theme.text)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
                .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.sm })

                ForEach(this.summary, (item: PETestItem, index: number) => {
                  if (index > 0) {
                    Divider()
                      .color(Theme.divider)
                      .margin({ left: Space.md, right: Space.md })
                  }
                  this.SummaryRow(item)
                }, (item: PETestItem) => item.label)
              }
              .width('100%')
              .constraintSize({ maxWidth: '100%' })
              .alignItems(HorizontalAlign.Start)
              .borderRadius(Radius.lg)
              .backgroundColor(Theme.surface)
              .border({ width: 1, color: Theme.borderSubtle })
              .margin({ left: Space.lg, right: Space.lg, top: Space.md })
            }

            // ── 单项成绩：次级底色列表卡（分隔线 + 次要文字色）──
            if (this.details.length > 0) {
              Column() {
                Text(this.tr('pe.groupDetails'))
                  .fontSize(FontSize.h3)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textSecondary)
                  .width('100%')
                  .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.xs })

                ForEach(this.details, (item: PETestItem, index: number) => {
                  if (index > 0) {
                    Divider()
                      .color(Theme.divider)
                      .margin({ left: Space.md, right: Space.md })
                  }
                  this.DetailRow(item)
                }, (item: PETestItem) => item.label)
              }
              .width('100%')
              .constraintSize({ maxWidth: '100%' })
              .alignItems(HorizontalAlign.Start)
              .borderRadius(Radius.lg)
              .backgroundColor(Theme.surfaceAlt)
              .border({ width: 1, color: Theme.borderSubtle })
              .margin({ left: Space.lg, right: Space.lg, top: Space.md })
            }

            Blank().height(Space.lg)
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })
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
