/**
 * PETestPage — 体测成绩（真实模式：教务 zhjw 体测 JSON；演示模式：内置示例）
 * 拆成"总览 / 单项成绩"两组展示（对齐原项目 PEtestScreen summaryKeys 拆分）。
 */
import { Theme, SafeTop, Space } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusDataService, PETestItem } from '../../services/campus/CampusDataService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';

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
  @State items: PETestItem[] = [];
  @State summary: PETestItem[] = [];
  @State details: PETestItem[] = [];
  @State loading: boolean = false;
  @State errorText: string = '';
  private isReal: boolean = false;

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
      Text('刷新')
        .fontSize(14)
        .fontColor(Theme.primary)
        .padding({ left: 12, right: 4, top: 8, bottom: 8 })
        .onClick(() => { this.refresh(); })
    }
  }

  @Builder SectionHeader(title: string) {
    Text(title)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textSecondary)
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })
  }

  @Builder ItemRow(item: PETestItem) {
    Row() {
      Text(item.label)
        .fontSize(14)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
      if (isAccentLabel(item.label)) {
        Text(item.value)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.primary)
      } else {
        Text(item.value)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.text)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({
        title: '体测成绩',
        onBack: () => { this.onBack(); },
        right: (): void => { this.RightAction(); },
      })

      Divider().color(Theme.divider)

      if (!this.isReal) {
        Text('演示数据 · 登录后显示真实成绩')
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
          Text('正在加载体测成绩...')
            .fontSize(13)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column({ space: Space.sm }) {
          Text('体测成绩加载失败')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.errorText)
            .fontSize(13)
            .fontColor(Theme.textMuted)
            .textAlign(TextAlign.Center)
          Text('重试')
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
          Text('暂无体测数据')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text('教务系统暂未返回体测记录，可以稍后刷新。')
            .fontSize(13)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          if (this.summary.length > 0) {
            ListItemGroup({ header: this.SectionHeader('总览') }) {
              ForEach(this.summary, (item: PETestItem) => {
                ListItem() {
                  this.ItemRow(item)
                }
              }, (item: PETestItem) => item.label)
            }
            .divider({ strokeWidth: 0.5, color: Theme.divider })
          }
          if (this.details.length > 0) {
            ListItemGroup({ header: this.SectionHeader('单项成绩') }) {
              ForEach(this.details, (item: PETestItem) => {
                ListItem() {
                  this.ItemRow(item)
                }
              }, (item: PETestItem) => item.label)
            }
            .divider({ strokeWidth: 0.5, color: Theme.divider })
          }
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
