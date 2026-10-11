/**
 * ============================================================================
 * MailDetailView — 邮件详情（发件人/收件人/抄送/主题/时间/正文/附件元信息）
 * ============================================================================
 *
 * 正文渲染策略：
 *   - 纯文本：原生 Text 直显（整体随 Scroll 滚动）。
 *   - 富文本（HTML）：受控 Web —— CSP 禁脚本 + 禁文件访问 + 禁缩放 + 关暗色 +
 *     loadData 五参（baseUrl/historyUrl 指向 mails.tsinghua.edu.cn，
 *     配合父级同步的 Coremail Cookie 内嵌图片才可鉴权加载）。
 *
 * 父组件负责：拉取详情（readMessage）、同步 Coremail Cookie、返回层级管理。
 * ============================================================================
 */
import { Theme, Space, Radius, FontSize } from '../Theme';
import { DetailHeader } from '../../components/Ui';
import {
  MailMessageDetail,
  MailContact,
  MailAttachment,
  mailFolderName,
} from '../../services/campus/MailService';
import { webview } from '@kit.ArkWeb';
import { Log } from '../../utils/Logger';

// ============================================================
// 展示辅助（模块级）
// ============================================================

/** 联系人列表 → 详情行文本（"名字 <地址>" 形态） */
function contactDetailLine(contacts: MailContact[]): string {
  const parts: string[] = [];
  for (let i: number = 0; i < contacts.length; i++) {
    const c: MailContact = contacts[i];
    if (c.name.length > 0 && c.address.length > 0) {
      parts.push(c.name + ' <' + c.address + '>');
    } else if (c.address.length > 0) {
      parts.push(c.address);
    } else if (c.name.length > 0) {
      parts.push(c.name);
    }
  }
  return parts.join('；');
}

/** ISO/常见日期串 → "YYYY-MM-DD HH:mm"（无法解析时原样截断展示） */
function formatMailFullDate(raw: string): string {
  const s: string = raw.trim();
  if (s.length === 0) {
    return '';
  }
  const m: RegExpExecArray | null = /(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/.exec(s);
  if (m !== null) {
    return m[1] + '-' + m[2] + '-' + m[3] + ' ' + m[4] + ':' + m[5];
  }
  return s.length > 19 ? s.substring(0, 19) : s;
}

/** 字节数 → 可读大小（B/KB/MB） */
function formatFileSize(size: number): string {
  if (size <= 0) {
    return '';
  }
  if (size < 1024) {
    return String(size) + ' B';
  }
  if (size < 1024 * 1024) {
    return (size / 1024).toFixed(1) + ' KB';
  }
  return (size / (1024 * 1024)).toFixed(1) + ' MB';
}

/** 正文是否为富文本（含 HTML 标签） */
function isRichHtml(html: string): boolean {
  return /<[a-zA-Z][^>]*>/.test(html);
}

/** 文本注入 HTML 前转义（正文 contentHtml 为服务端 HTML，不转义） */
function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ============================================================
// 组件
// ============================================================

@Component
export struct MailDetailView {
  /** @Prop：父组件 @State 变化时同步刷新（@Watch 触发富文本重载） */
  @Prop @Watch('onDetailChanged') detail: MailMessageDetail = new MailMessageDetail();
  @Prop loading: boolean = false;
  @Prop errorText: string = '';
  onBack: () => void = () => {};
  onRetry: () => void = () => {};
  /** 删除当前邮件（父组件负责二次确认与服务调用） */
  onDelete: () => void = () => {};
  /** 移动当前邮件（父组件负责选择目标文件夹与二次确认） */
  onMove: () => void = () => {};

  private webController: webview.WebviewController = new webview.WebviewController();

  private isRichBody(): boolean {
    return isRichHtml(this.detail.contentHtml);
  }

  /** 父组件更新 detail 后触发富文本重载（重试/重新打开） */
  private onDetailChanged(): void {
    this.loadWebContent();
  }

  private loadWebContent(): void {
    if (!this.isRichBody()) {
      return;
    }
    try {
      // 实测约束（对齐 NewsPage）：http baseUrl 下 data 为原始 HTML 直通渲染；
      // historyUrl 必传，缺省触发 401。baseUrl 指向 Coremail 域，
      // 配合父级同步的会话 Cookie，内嵌图片可鉴权加载。
      this.webController.loadData(
        this.buildMailDocument(), 'text/html', 'utf-8',
        'https://mails.tsinghua.edu.cn/', 'https://mails.tsinghua.edu.cn/');
    } catch (e) {
      Log.e('CampusMail', 'MAIL_WEB loadData failed: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }

  /**
   * 富文本完整 HTML 文档（对齐 NewsPage 版式）：
   * 主题 + 元信息行 + 白卡正文；viewport + CSP（禁脚本、图片放行）+ 中文排版。
   */
  private buildMailDocument(): string {
    let bodyHtml: string = this.detail.contentHtml;
    if (bodyHtml.length === 0 && this.detail.contentText.length > 0) {
      bodyHtml = '<p>' + escapeHtml(this.detail.contentText).replace(/\n/g, '<br/>') + '</p>';
    }
    if (bodyHtml.length === 0) {
      bodyHtml = '<p class="empty">暂无正文</p>';
    }
    return '<!DOCTYPE html><html lang="zh-cmn-Hans"><head>'
      + '<meta charset="utf-8"/>'
      + '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>'
      + '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'; img-src * data:; upgrade-insecure-requests"/>'
      + '<style>'
      + 'html,body{margin:0;padding:0 16px 32px;background:#FAFAFB;color:#0A0A0B;'
      + 'font-family:"HarmonyOS Sans SC","PingFang SC","Microsoft YaHei",sans-serif;'
      + 'font-size:15px;line-height:1.7;word-break:break-word;-webkit-text-size-adjust:100%;}'
      + '.subject{font-size:20px;font-weight:700;line-height:28px;margin:16px 0 0;}'
      + '.meta{margin:12px 0 16px;padding:12px;background:#FFFFFF;border-radius:14px;'
      + 'border:1px solid rgba(10,10,11,0.08);font-size:12px;color:#5C5C61;}'
      + '.meta div{margin:2px 0;}'
      + '.meta .k{display:inline-block;width:52px;color:#8E8E93;}'
      + '.card{background:#FFFFFF;border-radius:20px;border:1px solid rgba(10,10,11,0.08);'
      + 'padding:16px;overflow:hidden;}'
      + 'img,video{max-width:100%;height:auto;border-radius:8px;margin:8px 0;}'
      + 'a{color:#7C5CFA;}'
      + 'table{border-collapse:collapse;max-width:100%;margin:12px 0;}'
      + 'table,th,td{border:1px solid #E2E2E5;}'
      + 'th,td{padding:6px 10px;}'
      + 'pre,code{background:#F2F2F4;padding:2px 6px;border-radius:4px;}'
      + 'pre{padding:12px;overflow-x:auto;}'
      + 'p{margin:0 0 0.8em;}p:first-child{margin-top:0;}p:last-child{margin-bottom:0;}'
      + '.empty{color:#8E8E93;}'
      + '[style*="line-height"]{line-height:1.7 !important;}'
      + '</style></head><body>'
      + '<div class="subject">' + escapeHtml(this.detail.subject) + '</div>'
      + '<div class="meta">'
      + '<div><span class="k">发件人</span>' + escapeHtml(contactDetailLine(this.detail.from)) + '</div>'
      + '<div><span class="k">收件人</span>' + escapeHtml(contactDetailLine(this.detail.to)) + '</div>'
      + (this.detail.cc.length > 0
        ? '<div><span class="k">抄送</span>' + escapeHtml(contactDetailLine(this.detail.cc)) + '</div>'
        : '')
      + '<div><span class="k">时间</span>' + escapeHtml(formatMailFullDate(this.detail.date)) + '</div>'
      + (mailFolderName(this.detail.fid).length > 0
        ? '<div><span class="k">文件夹</span>' + escapeHtml(mailFolderName(this.detail.fid)) + '</div>'
        : '')
      + '</div>'
      + '<div class="card">' + bodyHtml + '</div>'
      + '</body></html>';
  }

  // ── UI ────────────────────────────────

  @Builder
  private LoadingView() {
    Column({ space: Space.md }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.primary)
      Text('正在加载邮件…')
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column({ space: Space.md }) {
      Text(this.errorText)
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
          this.onRetry();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private MetaRow(label: string, value: string) {
    Row({ space: Space.sm }) {
      Text(label)
        .fontSize(FontSize.micro)
        .fontColor(Theme.textMuted)
        .width(52)
      Text(value.length > 0 ? value : '—')
        .fontSize(FontSize.caption)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private PlainBodyView() {
    Scroll() {
      Column() {
        Text(this.detail.subject)
          .fontSize(FontSize.h2)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.text)
          .lineHeight(28)
          .width('100%')
          .padding({ left: Space.md, right: Space.md, top: Space.md })

        Column({ space: Space.xs }) {
          this.MetaRow('发件人', contactDetailLine(this.detail.from))
          this.MetaRow('收件人', contactDetailLine(this.detail.to))
          if (this.detail.cc.length > 0) {
            this.MetaRow('抄送', contactDetailLine(this.detail.cc))
          }
          this.MetaRow('时间', formatMailFullDate(this.detail.date))
          if (mailFolderName(this.detail.fid).length > 0) {
            this.MetaRow('文件夹', mailFolderName(this.detail.fid))
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        // 正文白卡（外层 padding 防右缘溢出）
        Column() {
          Text(this.detail.contentText.length > 0 ? this.detail.contentText : '暂无正文')
            .fontSize(FontSize.body)
            .fontColor(this.detail.contentText.length > 0 ? Theme.text : Theme.textMuted)
            .lineHeight(24)
            .width('100%')
            .constraintSize({ maxWidth: '100%' })
            .padding(Space.md)
            .borderRadius(Theme.cardRadius)
            .backgroundColor(Theme.surface)
            .border({ width: 1, color: Theme.borderSubtle })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: Space.md, right: Space.md, bottom: Space.md })

        if (this.detail.attachments.length > 0) {
          // 附件元信息白卡（外层 padding 防右缘溢出）
          Column() {
            this.AttachmentSection()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: Space.md, right: Space.md, bottom: Space.md })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .backgroundColor(Theme.background)
  }

  @Builder
  private AttachmentSection() {
    Column() {
      Text('附件（' + String(this.detail.attachments.length) + '）')
        .fontSize(FontSize.label)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .width('100%')

      ForEach(this.detail.attachments, (att: MailAttachment) => {
        Row({ space: Space.sm }) {
          Text('📎')
            .fontSize(FontSize.caption)
          Column({ space: 2 }) {
            Text(att.name)
              .fontSize(FontSize.caption)
              .fontColor(Theme.text)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (formatFileSize(att.size).length > 0) {
              Text(formatFileSize(att.size))
                .fontSize(FontSize.micro)
                .fontColor(Theme.textMuted)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .padding({ top: Space.sm, bottom: Space.sm })
      }, (att: MailAttachment) => att.id + '#' + att.name)
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
  }

  /** 底部操作条：删除 / 移动（具体确认流程与写操作由父组件执行） */
  @Builder
  private ActionBar() {
    Row({ space: Space.md }) {
      Text('删除')
        .fontSize(FontSize.label)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.error)
        .layoutWeight(1)
        .height(40)
        .textAlign(TextAlign.Center)
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.errorMuted)
        .border({ width: 1, color: Theme.errorMuted })
        .onClick(() => {
          this.onDelete();
        })

      Text('移动')
        .fontSize(FontSize.label)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .layoutWeight(1)
        .height(40)
        .textAlign(TextAlign.Center)
        .borderRadius(Radius.pill)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .onClick(() => {
          this.onMove();
        })
    }
    .width('100%')
    .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
  }

  build() {
    Column() {
      DetailHeader({ title: '邮件详情', onBack: () => { this.onBack(); } })
      Divider().color(Theme.divider)

      if (this.loading) {
        this.LoadingView()
      } else {
        if (this.errorText.length > 0) {
          this.ErrorView()
        } else {
          Column() {
            if (this.isRichBody()) {
              Web({ src: '', controller: this.webController })
                .onControllerAttached(() => {
                  this.loadWebContent();
                })
                .javaScriptAccess(false)
                .zoomAccess(false)
                .fileAccess(false)
                .darkMode(WebDarkMode.Off)
                .width('100%')
                .layoutWeight(1)
                .backgroundColor('#FAFAFB')
            } else {
              this.PlainBodyView()
            }
            this.ActionBar()
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
