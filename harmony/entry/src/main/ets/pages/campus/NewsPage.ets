/**
 * NewsPage — 校园资讯（真实模式：info 门户新闻 JSON；演示模式：内置示例）
 */
import { Theme, SafeTop, Space, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusNews } from '../../services/campus/CampusDataService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';

class NewsItem {
  id: string = '';
  title: string = '';
  summary: string = '';
  publishTime: string = '';
  channel: string = '';
  isNew: boolean = false;
}

function getMockNews(): NewsItem[] {
  const list: NewsItem[] = [];
  const rows: string[][] = [
    ['1', '清华大学2025届本科生毕业典礼举行', '7月6日上午，清华大学2025届本科生毕业典礼在东大操场举行。', '7月6日', '头条', '1'],
    ['2', '关于2025-2026学年秋季学期选课的通知', '2025-2026学年秋季学期选课将于8月15日9:00正式开始。', '7月15日', '教务', ''],
    ['3', '图书馆暑期开放时间安排', '暑期期间各图书馆开放时间调整为8:00-18:00。', '7月1日', '校园服务', ''],
    ['4', '校园一卡通升级通知', '校园一卡通系统将于本周末进行升级维护。', '7月20日', '信息化', ''],
    ['5', '暑期社会实践出征仪式举行', '2025年暑期社会实践出征仪式近日在蒙民伟音乐厅举行。', '7月18日', '学生活动', ''],
  ];
  for (let i: number = 0; i < rows.length; i++) {
    const n: NewsItem = new NewsItem();
    n.id = rows[i][0];
    n.title = rows[i][1];
    n.summary = rows[i][2];
    n.publishTime = rows[i][3];
    n.channel = rows[i][4];
    n.isNew = rows[i][5].length > 0;
    list.push(n);
  }
  return list;
}

@Component
export struct NewsPage {
  onBack: () => void = () => {};
  @State news: NewsItem[] = getMockNews();
  @State isDemo: boolean = true;
  @State loading: boolean = false;
  @State errorText: string = '';

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    if (!this.isDemo) {
      this.loadNews();
    } else {
      this.news = getMockNews();
    }
  }

  private async loadNews(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const list: CampusNews[] = await SessionManager.getCampusDataService().fetchNewsList(1, 20);
      const items: NewsItem[] = [];
      for (let i: number = 0; i < list.length; i++) {
        const item: NewsItem = new NewsItem();
        item.id = list[i].id;
        item.title = list[i].title;
        item.summary = list[i].source;
        item.publishTime = list[i].date;
        item.channel = list[i].channel;
        item.isNew = list[i].topped;
        items.push(item);
      }
      this.news = items;
    } catch (e) {
      this.errorText = e instanceof Error ? e.message : String(e);
    }
    this.loading = false;
  }

  build() {
    Column() {
      SafeTop()

      DetailHeader({ title: '校园新闻', onBack: () => { this.onBack(); } })

      Divider().color(Theme.divider)

      if (this.isDemo) {
        Text('演示数据 · 登录后显示真实资讯')
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: Space.sm, bottom: Space.sm })
      } else if (this.loading || this.errorText.length > 0) {
        Row({ space: Space.sm }) {
          if (this.loading) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(Theme.primary)
          }
          Text(this.loading ? '加载中...' : this.errorText)
            .fontSize(FontSize.caption)
            .fontColor(this.errorText.length > 0 ? Theme.warning : Theme.textMuted)
          if (!this.loading && this.errorText.length > 0) {
            Text('重试')
              .fontSize(FontSize.caption)
              .fontColor(Theme.primary)
              .padding({ left: Space.sm, right: Space.sm, top: 2, bottom: 2 })
              .borderRadius(8)
              .border({ width: 1, color: Theme.primary })
              .onClick(() => { this.loadNews(); })
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: Space.sm, bottom: Space.sm })
      }

      List() {
        ForEach(this.news, (item: NewsItem) => {
          ListItem() {
            Column() {
              Row() {
                if (item.isNew) {
                  Text('置顶')
                    .fontSize(10)
                    .fontColor(Theme.warning)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .borderRadius(4)
                    .backgroundColor('rgba(217,119,6,0.10)')
                    .margin({ right: 6 })
                }
                Text(item.channel)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor(Theme.surfaceAlt)
              }
              .width('100%')
              .margin({ bottom: 6 })

              Text(item.title)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.text)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ bottom: 6 })

              Row() {
                Text(item.summary)
                  .fontSize(13)
                  .fontColor(Theme.textMuted)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                Text(item.publishTime)
                  .fontSize(11)
                  .fontColor(Theme.textMuted)
                  .margin({ left: 12 })
              }
              .width('100%')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
            .alignItems(HorizontalAlign.Start)
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0.5, color: Theme.divider })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
