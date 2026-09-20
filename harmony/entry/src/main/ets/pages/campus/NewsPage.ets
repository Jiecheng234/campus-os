/**
 * NewsPage — 校园资讯（真实模式：info 门户新闻 JSON；演示模式：内置示例）
 */
import { Theme, SafeTop, Space, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import { CampusNews, CampusNewsDetail } from '../../services/campus/CampusDataService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';
import { webview } from '@kit.ArkWeb';
import { Log } from '../../utils/Logger';

class NewsItem {
  id: string = '';
  title: string = '';
  summary: string = '';
  publishTime: string = '';
  channel: string = '';
  isNew: boolean = false;
  url: string = '';
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
  /** 详情子视图状态（页内切换，不走路由） */
  @State showDetail: boolean = false;
  @State detail: CampusNewsDetail = new CampusNewsDetail();
  @State detailLoading: boolean = false;
  @State detailError: string = '';
  private currentNews: NewsItem | undefined = undefined;
  private webController: webview.WebviewController = new webview.WebviewController();
  /** 系统返回拦截：详情打开时消费返回事件只关闭详情（链式回退到子页 → 校园主页） */
  private detailBackHandler: BackHandler = () => {
    if (this.showDetail) {
      this.closeDetail();
      return true;
    }
    return false;
  };

  aboutToDisappear(): void {
    BackDispatcher.remove(this.detailBackHandler);
  }

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
        item.url = list[i].url;
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

  private async openDetail(item: NewsItem): Promise<void> {
    this.currentNews = item;
    this.showDetail = true;
    this.detailError = '';
    BackDispatcher.push(BackOwner.CAMPUS, this.detailBackHandler);
    if (this.isDemo) {
      const demoDetail: CampusNewsDetail = new CampusNewsDetail();
      demoDetail.title = item.title;
      demoDetail.content = item.summary + (item.publishTime.length > 0 ? '\n' + item.publishTime : '');
      this.detail = demoDetail;
      return;
    }
    if (item.url.length === 0) {
      this.detail = new CampusNewsDetail();
      this.detailError = '该资讯缺少详情链接';
      return;
    }
    this.detailLoading = true;
    this.detail = new CampusNewsDetail();
    try {
      this.detail = await SessionManager.getCampusDataService().fetchNewsDetail(item.url);
    } catch (e) {
      this.detailError = e instanceof Error ? e.message : String(e);
    }
    this.detailLoading = false;
  }

  private closeDetail(): void {
    this.showDetail = false;
    BackDispatcher.remove(this.detailBackHandler);
  }

  /**
   * 富文本正文 → 完整 HTML 文档（对齐原项目 utils/html wrapAsDocument 亮色基线）：
   * viewport + CSP（禁脚本、图片放行）+ 移动端中文排版。
   */
  private buildDetailDocument(): string {
    const body: string = this.detail.contentHtml;
    return '<!DOCTYPE html><html lang="zh-cmn-Hans"><head>'
      + '<meta charset="utf-8"/>'
      + '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>'
      + '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; img-src * data:; upgrade-insecure-requests"/>'
      + '<style>'
      + 'html,body{margin:0;padding:16px;background:rgb(255,255,255);color:rgb(26,26,46);'
      + 'font-family:"HarmonyOS Sans SC","PingFang SC","Microsoft YaHei",sans-serif;'
      + 'font-size:15px;line-height:1.7;word-break:break-word;-webkit-text-size-adjust:100%;}'
      + 'img,video{max-width:100%;height:auto;border-radius:8px;margin:8px 0;}'
      + 'a{color:rgb(124,92,250);}'
      + 'table{border-collapse:collapse;max-width:100%;margin:12px 0;}'
      + 'table,th,td{border:1px solid rgb(226,232,240);}'
      + 'th,td{padding:6px 10px;}'
      + 'pre,code{background:rgb(241,245,249);padding:2px 6px;border-radius:4px;}'
      + 'pre{padding:12px;overflow-x:auto;}'
      + 'p{margin:0 0 0.8em;}p:first-child{margin-top:0;}p:last-child{margin-bottom:0;}'
      + '[style*="line-height"]{line-height:1.7 !important;}'
      + '</style></head><body>' + body + '</body></html>';
  }

  @Builder DetailView() {
    DetailHeader({ title: '新闻详情', onBack: () => { this.closeDetail(); } })
    Divider().color(Theme.divider)
    if (this.detailLoading) {
      Column({ space: Space.sm }) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(Theme.primary)
        Text('加载中...')
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else if (this.detailError.length > 0) {
      Column({ space: Space.md }) {
        Text(this.detailError)
          .fontSize(FontSize.body)
          .fontColor(Theme.error)
          .textAlign(TextAlign.Center)
          .padding({ left: Space.lg, right: Space.lg })
        Text('重试')
          .fontSize(FontSize.label)
          .fontColor(Theme.primary)
          .padding({ left: Space.md, right: Space.md, top: 6, bottom: 6 })
          .borderRadius(8)
          .border({ width: 1, color: Theme.primary })
          .onClick(() => {
            if (this.currentNews !== undefined) {
              this.openDetail(this.currentNews);
            }
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Text(this.detail.title)
          .fontSize(FontSize.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .width('100%')
          .padding({ left: Space.md, right: Space.md, top: Space.md })
        if (this.currentNews !== undefined) {
          Text(this.currentNews.channel + ' · ' + this.currentNews.summary + ' · ' + this.currentNews.publishTime)
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
            .width('100%')
            .padding({ left: Space.md, right: Space.md })
            .margin({ top: Space.sm, bottom: Space.md })
        } else {
          Column().height(Space.md)
        }
        if (this.detail.contentHtml.length > 0) {
          // 富文本正文：Web 组件渲染（对齐原项目 HtmlContent/WebView 方案），
          // 同步 webvpn 会话 Cookie 后加载，图片/附件才可鉴权访问
          Web({ src: '', controller: this.webController })
            .onControllerAttached(() => {
              try {
                SessionManager.getCampusDataService().syncWebvpnCookiesForWebView();
                // 实测约束：http baseUrl 下 data 为原始 HTML 直通渲染（'base64' 编码不会
                // 被解码，会整段显示成 base64 文本）；historyUrl 必传，缺省触发 401
                this.webController.loadData(
                  this.buildDetailDocument(), 'text/html', 'utf-8',
                  'https://webvpn.tsinghua.edu.cn/', 'https://webvpn.tsinghua.edu.cn/');
              } catch (e) {
                Log.e('LearnAct', 'NEWS_WEB loadData failed: %{public}s',
                  e instanceof Error ? e.message : String(e));
              }
            })
            .javaScriptAccess(false)
            .zoomAccess(false)
            .fileAccess(false)
            .darkMode(WebDarkMode.Off)
            .width('100%')
            .layoutWeight(1)
            .backgroundColor('#FFFFFF')
        } else {
          Scroll() {
            Column() {
              if (this.detail.content.length > 0) {
                Text(this.detail.content)
                  .fontSize(FontSize.body)
                  .fontColor(Theme.text)
                  .lineHeight(26)
                  .width('100%')
                  .textAlign(TextAlign.Start)
              } else {
                Text('暂无内容')
                  .fontSize(FontSize.body)
                  .fontColor(Theme.textMuted)
                  .width('100%')
              }
              ForEach(this.detail.attachments, (name: string) => {
                Text('附件：' + name)
                  .fontSize(FontSize.caption)
                  .fontColor(Theme.primary)
                  .width('100%')
                  .margin({ top: Space.sm })
              }, (name: string) => name)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.xl })
          }
          .width('100%')
          .layoutWeight(1)
          .align(Alignment.Top)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    Column() {
      SafeTop()

      if (this.showDetail) {
        this.DetailView()
      } else {
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
              .onClick(() => { this.openDetail(item); })
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: Theme.divider })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
