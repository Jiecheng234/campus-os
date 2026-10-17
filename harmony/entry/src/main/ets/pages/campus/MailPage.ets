/**
 * ============================================================================
 * MailPage — 校园邮件（清华邮箱 Coremail 读写）
 * ============================================================================
 *
 * 层级（页内状态切换，不走路由）：
 *   LIST（文件夹 chips + 未读计数 + 邮件列表 + 加载更多）
 *     → DETAIL（邮件详情：MailDetailView 内联渲染）
 *     → COMPOSE（写邮件：MailComposeView 内联渲染）
 *
 * 模式：
 *   - 真实模式（已登录且非演示）：MailService（Coremail 会话自愈 + 多形态回退）。
 *   - 演示模式：内置示例数据，零网络请求。
 * ============================================================================
 */
import { Theme, SafeTop, Space, FontSize } from '../Theme';
import { EmptyHint, StateBlock, StateTone } from '../../components/Ui';
import { MailDetailView } from './MailDetailView';
import { MailComposeView } from './MailComposeView';
import { SessionManager } from '../../services/auth/SessionManager';
import {
  MailService,
  MailFolder,
  MailContact,
  MailAttachment,
  MailMessageSummary,
  MailMessageDetail,
  MailListResult,
  ComposeDraft,
  MAIL_FOLDERS,
} from '../../services/campus/MailService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';
import { Log } from '../../utils/Logger';
import { I18n } from '../../utils/I18n';

/** 页内层级（不走路由） */
const LEVEL_LIST: number = 0;
const LEVEL_DETAIL: number = 1;
const LEVEL_COMPOSE: number = 2;

/** 列表分页大小 */
const MAIL_PAGE_SIZE: number = 20;

// ============================================================
// 展示辅助（模块级）
// ============================================================

/** 联系人列表 → 一行文本（优先名字，其次地址；"；"分隔） */
function contactLabel(contacts: MailContact[]): string {
  const parts: string[] = [];
  for (let i: number = 0; i < contacts.length; i++) {
    const c: MailContact = contacts[i];
    const label: string = c.name.length > 0 ? c.name : c.address;
    if (label.length > 0) {
      parts.push(label);
    }
  }
  return parts.join('；');
}

/** ISO/常见日期串 → "MM-DD HH:mm"（无法解析时截断展示） */
function formatMailDate(raw: string): string {
  const s: string = raw.trim();
  if (s.length === 0) {
    return '';
  }
  const m: RegExpExecArray | null = /(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/.exec(s);
  if (m !== null) {
    return m[2] + '-' + m[3] + ' ' + m[4] + ':' + m[5];
  }
  return s.length > 16 ? s.substring(0, 16) : s;
}

// ============================================================
// 演示模式示例数据（零网络请求）
// ============================================================

function getDemoMailSummaries(): MailMessageSummary[] {
  // id / 发件人名 / 发件人地址 / 主题 / 摘要 / 时间 / 未读 / 附件
  const rows: string[][] = [
    ['1001', '教务处', 'jwc@mails.tsinghua.edu.cn', '关于2025-2026学年选课通知',
      '各位同学：2025-2026学年秋季学期选课将于8月15日9:00开始，请在规定时间内完成选课……',
      '2026-10-10 09:30:00', '1', '1'],
    ['1002', '图书馆', 'lib@mails.tsinghua.edu.cn', '图书到期提醒',
      '您借阅的《高等数学（第七版）》将于3天后到期，请及时归还或在线续借。',
      '2026-10-09 16:20:00', '1', ''],
    ['1003', '信息中心', 'its@mails.tsinghua.edu.cn', '校园网络维护通知',
      '定于10月13日凌晨0:00-6:00进行网络设备升级，期间校园网可能出现短暂中断……',
      '2026-10-08 10:00:00', '', ''],
    ['1004', '课程助教', 'ta_math@mails.tsinghua.edu.cn', '高等数学(1) 作业反馈',
      '同学们好，第5章作业已批改完毕，请在教学门户查看批注并及时订正。',
      '2026-10-07 20:45:00', '', '1'],
    ['1005', '学生资助中心', 'zizhu@mails.tsinghua.edu.cn', '2026年助学金申请通知',
      '本学年助学金申请现已开放，符合条件的同学请于10月20日前提交申请材料……',
      '2026-10-06 09:00:00', '1', ''],
    ['1006', '校医院', 'hospital@mails.tsinghua.edu.cn', '流感疫苗接种安排',
      '秋季流感疫苗接种将于下周一开始，师生可凭校园卡到校医院免费接种。',
      '2026-10-05 14:30:00', '', ''],
    ['1007', '团委', 'youth@mails.tsinghua.edu.cn', '暑期社会实践总结评比通知',
      '各实践支队请于10月15日前提交实践总结材料，参与本年度评比表彰。',
      '2026-10-03 18:00:00', '', ''],
    ['1008', '信息化技术中心', 'its@mails.tsinghua.edu.cn', '邮箱安全提醒：请开启双重验证',
      '近期发现部分钓鱼邮件冒充管理员索取账号密码，请勿点击可疑链接……',
      '2026-10-01 08:30:00', '', ''],
  ];
  const list: MailMessageSummary[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const m: MailMessageSummary = new MailMessageSummary();
    m.id = rows[i][0];
    const sender: MailContact = new MailContact();
    sender.name = rows[i][1];
    sender.address = rows[i][2];
    m.from = [sender];
    m.subject = rows[i][3];
    m.brief = rows[i][4];
    m.date = rows[i][5];
    m.unread = rows[i][6].length > 0;
    m.hasAttachment = rows[i][7].length > 0;
    m.fid = 1;
    list.push(m);
  }
  return list;
}

/** 演示搜索：按关键词过滤摘要/主题/发件人（零网络请求） */
function filterDemoMailSummaries(base: MailMessageSummary[], keyword: string): MailMessageSummary[] {
  const lower: string = keyword.toLowerCase();
  const result: MailMessageSummary[] = [];
  for (let i: number = 0; i < base.length; i++) {
    const m: MailMessageSummary = base[i];
    const haystack: string = (m.subject + ' ' + m.brief + ' ' + contactLabel(m.from)).toLowerCase();
    if (haystack.indexOf(lower) >= 0) {
      result.push(m);
    }
  }
  return result;
}

/** 演示详情：由列表摘要构造（零网络请求） */
function getDemoMailDetail(item: MailMessageSummary): MailMessageDetail {
  const d: MailMessageDetail = new MailMessageDetail();
  d.loadSummary(item);
  const to: MailContact = new MailContact();
  to.name = '我';
  to.address = 'student@mails.tsinghua.edu.cn';
  d.to = [to];
  d.cc = [];
  d.contentText = item.brief + '\n\n（演示数据 · 登录后查看真实邮件正文）';
  d.contentHtml = '';
  if (item.hasAttachment) {
    const att: MailAttachment = new MailAttachment();
    att.id = 'demo-att-1';
    att.name = '通知附件.pdf';
    att.size = 245760;
    d.attachments = [att];
  }
  return d;
}

// ============================================================
// 列表行组件
// ============================================================

@Component
struct MailRow {
  @Prop item: MailMessageSummary = new MailMessageSummary();
  @Prop isUnread: boolean = false;
  /** 语言订阅：行内兜底文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  build() {
    Row() {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.isUnread ? Theme.primary : 'transparent')
        .border({ width: this.isUnread ? 0 : 1, color: Theme.border })
        .margin({ right: 12 })

      Column() {
        Row() {
          Text(contactLabel(this.item.from).length > 0 ? contactLabel(this.item.from) : this.tr('mail.unknownSender'))
            .fontSize(FontSize.label)
            .fontWeight(this.isUnread ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(Theme.text)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(formatMailDate(this.item.date))
            .fontSize(FontSize.micro)
            .fontColor(Theme.textMuted)
            .margin({ left: 8 })
        }
        .width('100%')

        Text(this.item.subject)
          .fontSize(FontSize.label)
          .fontWeight(this.isUnread ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(Theme.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
          .width('100%')

        Row() {
          Text(this.item.brief)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.item.hasAttachment) {
            Text('📎')
              .fontSize(FontSize.caption)
              .margin({ left: 4 })
          }
        }
        .width('100%')
        .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

// ============================================================
// 页面
// ============================================================

@Component
export struct MailPage {
  onBack: () => void = () => {};

  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  /** 系统文件夹展示名（服务层 name 为中文常量，按 system 标识走词典） */
  private folderLabel(folder: MailFolder): string {
    if (folder.system.length === 0) {
      return folder.name;
    }
    const label: string = this.tr('mail.folder.' + folder.system);
    return label;
  }

  @State level: number = LEVEL_LIST;
  @State titleText: string = 'mail.title';
  @State loading: boolean = false;
  @State errorMessage: string = '';

  // LIST 层
  @State selectedFid: number = 1;
  @State messages: MailMessageSummary[] = [];
  @State total: number = 0;
  @State loadingMore: boolean = false;
  /** 已打开并成功标记已读的邮件 id（未读展示与计数据此修正） */
  @State markedReadIds: string[] = [];

  // 搜索（US3）
  @State searchMode: boolean = false;
  @State searchInput: string = '';
  @State hasSearched: boolean = false;
  private searchKeyword: string = '';

  // DETAIL 层
  @State detail: MailMessageDetail = new MailMessageDetail();
  @State detailLoading: boolean = false;
  @State detailError: string = '';
  private currentMessage: MailMessageSummary | undefined = undefined;

  private isDemo: boolean = true;
  private backHandler: BackHandler = (): boolean => {
    if (this.level === LEVEL_LIST) {
      this.onBack();
      return true;
    }
    this.goBackOneLevel();
    return true;
  };

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    this.loadFolderMessages(true);
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
  }

  // ── 层级导航 ────────────────────────────────

  private goBackOneLevel(): void {
    this.level = LEVEL_LIST;
    this.titleText = 'mail.title';
  }

  private handleHeaderBack(): void {
    if (this.level === LEVEL_LIST) {
      this.onBack();
    } else {
      this.goBackOneLevel();
    }
  }

  // ── 数据加载（演示模式零网络请求） ────────────────────────────────

  private extractError(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  /** 合并分页结果（按 id 去重，保持顺序） */
  private mergeMessages(base: MailMessageSummary[], more: MailMessageSummary[]): MailMessageSummary[] {
    const seenIds: string[] = [];
    for (let i: number = 0; i < base.length; i++) {
      seenIds.push(base[i].id);
    }
    const merged: MailMessageSummary[] = [];
    for (let i: number = 0; i < base.length; i++) {
      merged.push(base[i]);
    }
    for (let i: number = 0; i < more.length; i++) {
      if (seenIds.indexOf(more[i].id) < 0) {
        merged.push(more[i]);
        seenIds.push(more[i].id);
      }
    }
    return merged;
  }

  /** 当前文件夹邮件列表（reset=true 重置到第一页） */
  private async loadFolderMessages(reset: boolean): Promise<void> {
    this.errorMessage = '';
    if (this.isDemo) {
      this.messages = getDemoMailSummaries();
      this.total = this.messages.length;
      return;
    }
    const start: number = reset ? 0 : this.messages.length;
    this.loading = true;
    try {
      const service: MailService = SessionManager.getMailService();
      const result: MailListResult = await service.listMessages(this.selectedFid, start, MAIL_PAGE_SIZE);
      this.messages = reset ? result.messages : this.mergeMessages(this.messages, result.messages);
      this.total = result.total;
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private onSelectFolder(folder: MailFolder): void {
    if (folder.id === this.selectedFid) {
      return;
    }
    this.selectedFid = folder.id;
    this.markedReadIds = [];
    this.loadFolderMessages(true);
  }

  /** 加载更多（追加去重；失败仅提示，不影响已展示内容） */
  private async loadMore(): Promise<void> {
    if (this.loadingMore || this.loading || this.messages.length >= this.total) {
      return;
    }
    if (this.isDemo) {
      return;
    }
    this.loadingMore = true;
    try {
      const service: MailService = SessionManager.getMailService();
      const result: MailListResult = this.searchMode && this.searchKeyword.length > 0
        ? await service.searchMessages(this.searchKeyword, this.messages.length, MAIL_PAGE_SIZE)
        : await service.listMessages(this.selectedFid, this.messages.length, MAIL_PAGE_SIZE);
      this.messages = this.mergeMessages(this.messages, result.messages);
      this.total = result.total > 0 ? result.total : this.messages.length;
    } catch (e) {
      this.getUIContext().getPromptAction()
        .showToast({ message: this.trp('mail.loadMoreFailed', { 'msg': this.extractError(e) }), duration: 2000 });
    }
    this.loadingMore = false;
  }

  // ── 搜索（US3） ────────────────────────────────

  /** 关键词搜索（空关键词 = 清除搜索恢复文件夹视图） */
  private async doSearch(): Promise<void> {
    const keyword: string = this.searchInput.trim();
    if (keyword.length === 0) {
      await this.clearSearch();
      return;
    }
    this.searchKeyword = keyword;
    this.searchMode = true;
    this.hasSearched = true;
    this.errorMessage = '';
    if (this.isDemo) {
      this.messages = filterDemoMailSummaries(getDemoMailSummaries(), keyword);
      this.total = this.messages.length;
      this.markedReadIds = [];
      return;
    }
    this.loading = true;
    try {
      const service: MailService = SessionManager.getMailService();
      const result: MailListResult = await service.searchMessages(keyword, 0, MAIL_PAGE_SIZE);
      this.messages = result.messages;
      this.total = result.total > 0 ? result.total : result.messages.length;
      this.markedReadIds = [];
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 清除搜索，恢复文件夹视图 */
  private async clearSearch(): Promise<void> {
    this.searchMode = false;
    this.hasSearched = false;
    this.searchInput = '';
    this.searchKeyword = '';
    await this.loadFolderMessages(true);
  }

  /** 右上角刷新 / 错误重试：按当前层级重拉 */
  private refreshCurrentView(): void {
    if (this.level === LEVEL_DETAIL) {
      this.retryDetail();
      return;
    }
    if (this.level === LEVEL_LIST) {
      if (this.searchMode && this.hasSearched) {
        this.doSearch();
      } else {
        this.loadFolderMessages(true);
      }
    }
  }

  // ── 详情（US2） ────────────────────────────────

  /** 打开邮件详情（真实：先同步 Coremail Cookie 再拉详情；演示：本地构造） */
  private async openMessage(item: MailMessageSummary): Promise<void> {
    this.currentMessage = item;
    this.level = LEVEL_DETAIL;
    this.detailError = '';
    this.detail = new MailMessageDetail();
    if (this.isDemo) {
      this.detail = getDemoMailDetail(item);
      // 演示模式同样演示"打开未读 → 计数减一"（零网络请求）
      this.markOpenedRead(item, true);
      return;
    }
    this.detailLoading = true;
    try {
      const service: MailService = SessionManager.getMailService();
      // 受控 Web 内嵌图片鉴权：先同步 Coremail 会话 Cookie 到 ArkWeb
      service.syncCoremailCookiesForWebView();
      this.detail = await service.readMessage(item.id);
    } catch (e) {
      this.detailError = this.extractError(e);
    }
    this.detailLoading = false;
    // 打开即标记已读（失败不阻塞阅读）
    this.markOpenedRead(item, false);
  }

  /**
   * 打开未读邮件后标记已读（US4）：
   *   - demoLocal=true：演示模式本地置已读（零网络请求）。
   *   - 真实模式调用服务置已读；失败仅记日志 + 轻提示，不阻塞阅读；
   *     成功后记录 id（返回列表时未读标记与计数随之更新）。
   */
  private async markOpenedRead(item: MailMessageSummary, demoLocal: boolean): Promise<void> {
    if (!item.unread || this.markedReadIds.indexOf(item.id) >= 0) {
      return;
    }
    if (!demoLocal) {
      try {
        await SessionManager.getMailService().markRead([item.id], true);
      } catch (e) {
        Log.i('CampusMail', 'MARK_READ fail (ignore): %{public}s',
          e instanceof Error ? e.message : String(e));
        this.getUIContext().getPromptAction()
          .showToast({ message: this.tr('mail.markReadFailed'), duration: 2000 });
        return;
      }
    }
    const updated: string[] = [];
    for (let i: number = 0; i < this.markedReadIds.length; i++) {
      updated.push(this.markedReadIds[i]);
    }
    updated.push(item.id);
    this.markedReadIds = updated;
  }

  private retryDetail(): void {
    if (this.currentMessage !== undefined) {
      this.openMessage(this.currentMessage);
    }
  }

  // ── 删除 / 移动（US5，均二次确认） ────────────────────────────────

  /** 写操作后刷新当前列表（搜索模式重搜索，否则重拉文件夹） */
  private async refreshListAfterWrite(): Promise<void> {
    if (this.searchMode && this.hasSearched) {
      await this.doSearch();
    } else {
      await this.loadFolderMessages(true);
    }
  }

  /** 演示模式本地移除（零网络请求） */
  private removeLocalMessages(ids: string[]): void {
    const rest: MailMessageSummary[] = [];
    for (let i: number = 0; i < this.messages.length; i++) {
      if (ids.indexOf(this.messages[i].id) < 0) {
        rest.push(this.messages[i]);
      }
    }
    this.messages = rest;
    this.total = rest.length;
  }

  /** 列表长按：邮件操作（删除 / 移动） */
  private showRowActions(item: MailMessageSummary): void {
    const ids: string[] = [item.id];
    const sheets: SheetInfo[] = [];
    sheets.push({
      title: this.tr('mail.delete'),
      action: (): void => {
        this.confirmDeleteMessages(ids);
      },
    });
    sheets.push({
      title: this.tr('mail.move'),
      action: (): void => {
        this.pickMoveFolder(ids);
      },
    });
    ActionSheet.show({
      title: item.subject,
      message: this.tr('mail.rowActionsMessage'),
      confirm: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      sheets: sheets,
    });
  }

  /** 删除二次确认（AlertDialog） */
  private confirmDeleteMessages(ids: string[]): void {
    AlertDialog.show({
      title: this.tr('mail.delete'),
      message: this.tr('mail.deleteConfirmMessage'),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('mail.deleteConfirmOk'),
        fontColor: Theme.error,
        action: (): void => {
          this.doDeleteMessages(ids);
        },
      },
    });
  }

  private async doDeleteMessages(ids: string[]): Promise<void> {
    const fromDetail: boolean = this.level === LEVEL_DETAIL;
    if (this.isDemo) {
      this.removeLocalMessages(ids);
      if (fromDetail) {
        this.goBackOneLevel();
      }
      this.getUIContext().getPromptAction().showToast({ message: this.tr('mail.deletedToast'), duration: 2000 });
      return;
    }
    try {
      await SessionManager.getMailService().deleteMessages(ids);
      if (fromDetail) {
        this.goBackOneLevel();
      }
      this.getUIContext().getPromptAction().showToast({ message: this.tr('mail.deletedToast'), duration: 2000 });
      await this.refreshListAfterWrite();
    } catch (e) {
      this.getUIContext().getPromptAction()
        .showToast({ message: this.trp('mail.deleteFailed', { 'msg': this.extractError(e) }), duration: 2500 });
    }
  }

  /** 移动：先选目标文件夹（ActionSheet），再二次确认（AlertDialog） */
  private pickMoveFolder(ids: string[]): void {
    const sheets: SheetInfo[] = [];
    for (let i: number = 0; i < MAIL_FOLDERS.length; i++) {
      const folder: MailFolder = MAIL_FOLDERS[i];
      if (folder.id === this.selectedFid) {
        continue;
      }
      const targetFid: number = folder.id;
      const targetName: string = this.folderLabel(folder);
      sheets.push({
        title: targetName,
        action: (): void => {
          this.confirmMoveMessages(ids, targetFid, targetName);
        },
      });
    }
    ActionSheet.show({
      title: this.tr('mail.move'),
      message: this.tr('mail.pickFolderMessage'),
      confirm: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      sheets: sheets,
    });
  }

  private confirmMoveMessages(ids: string[], fid: number, name: string): void {
    AlertDialog.show({
      title: this.tr('mail.move'),
      message: this.trp('mail.moveConfirmMessage', { 'name': name }),
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('mail.moveConfirmOk'),
        action: (): void => {
          this.doMoveMessages(ids, fid, name);
        },
      },
    });
  }

  private async doMoveMessages(ids: string[], fid: number, name: string): Promise<void> {
    const fromDetail: boolean = this.level === LEVEL_DETAIL;
    if (this.isDemo) {
      this.removeLocalMessages(ids);
      if (fromDetail) {
        this.goBackOneLevel();
      }
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('mail.movedToast', { 'name': name }),
        duration: 2000,
      });
      return;
    }
    try {
      await SessionManager.getMailService().moveMessages(ids, fid);
      if (fromDetail) {
        this.goBackOneLevel();
      }
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('mail.movedToast', { 'name': name }),
        duration: 2000,
      });
      await this.refreshListAfterWrite();
    } catch (e) {
      this.getUIContext().getPromptAction()
        .showToast({ message: this.trp('mail.moveFailed', { 'msg': this.extractError(e) }), duration: 2500 });
    }
  }

  /** 未读展示：服务端未读标记 − 已成功置已读的修正集 */
  private displayUnread(item: MailMessageSummary): boolean {
    return item.unread && this.markedReadIds.indexOf(item.id) < 0;
  }

  private countUnread(): number {
    let count: number = 0;
    for (let i: number = 0; i < this.messages.length; i++) {
      if (this.displayUnread(this.messages[i])) {
        count = count + 1;
      }
    }
    return count;
  }

  // ── UI ────────────────────────────────

  /**
   * 页内头部（标题绑定 this.titleText：自定义组件普通成员只初始化一次，
   * 故按 LibrarySeatPage 范式自绘头部）。
   */
  @Builder
  private HeaderBar() {
    Row() {
      Text('‹')
        .fontSize(32)
        .fontWeight(FontWeight.Lighter)
        .fontColor(Theme.text)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.handleHeaderBack();
        })

      Text(this.tr(this.titleText))
        .fontSize(FontSize.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)

      if (this.level === LEVEL_LIST) {
        Row() {
          Text('✏️')
            .fontSize(18)
            .width(36)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.openCompose();
            })
          Text('↻')
            .fontSize(20)
            .fontColor(Theme.primary)
            .width(36)
            .height(40)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.refreshCurrentView();
            })
        }
        .alignItems(VerticalAlign.Center)
      } else {
        Column()
          .width(72)
          .height(40)
      }
    }
    .width('100%')
    .padding({ left: Space.sm, right: Space.sm, top: Space.sm, bottom: Space.sm })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private LoadingView() {
    Column({ space: Space.md }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.primary)
      Text(this.tr('status.loading'))
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private ErrorView() {
    Column() {
      StateBlock({
        tone: StateTone.Error,
        title: this.tr('status.failed'),
        message: this.errorMessage,
        actionText: this.tr('status.retry'),
        onAction: () => {
          this.refreshCurrentView();
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
  }

  @Builder
  private FolderChip(folder: MailFolder) {
    Text(this.folderLabel(folder))
      .fontSize(FontSize.label)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.selectedFid === folder.id ? Theme.textInvert : Theme.textSecondary)
      .padding({ left: 14, right: 14, top: Space.sm, bottom: Space.sm })
      .borderRadius(999)
      .backgroundColor(this.selectedFid === folder.id ? Theme.primary : Theme.surfaceAlt)
      .onClick(() => {
        this.onSelectFolder(folder);
      })
  }

  @Builder
  private ListLayer() {
    Column() {
      if (this.isDemo) {
        Text(this.tr('mail.demoHint'))
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: Space.sm, bottom: Space.sm })
      }

      // 搜索框（空关键词搜索 = 清除，恢复文件夹视图）
      Row({ space: Space.sm }) {
        TextInput({ placeholder: this.tr('mail.searchPlaceholder'), text: this.searchInput })
          .fontSize(FontSize.caption)
          .fontColor(Theme.text)
          .height(40)
          .layoutWeight(1)
          .backgroundColor(Theme.surfaceAlt)
          .borderRadius(999)
          .padding({ left: Space.md, right: Space.md })
          .onChange((value: string) => {
            this.searchInput = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })

        if (this.searchMode) {
          Text(this.tr('common.clear'))
            .fontSize(FontSize.label)
            .fontColor(Theme.primary)
            .height(40)
            .padding({ left: Space.sm, right: Space.sm })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.clearSearch();
            })
        } else {
          Text(this.tr('common.search'))
            .fontSize(FontSize.label)
            .fontColor(Theme.primary)
            .height(40)
            .padding({ left: Space.sm, right: Space.sm })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.doSearch();
            })
        }
      }
      .width('100%')
      .padding({ left: Space.md, right: Space.md, top: Space.sm })

      // 文件夹 chips（横向滚动；搜索模式隐藏）
      if (!this.searchMode) {
        Scroll() {
          Row({ space: Space.sm }) {
            ForEach(MAIL_FOLDERS, (folder: MailFolder) => {
              this.FolderChip(folder)
            }, (folder: MailFolder) => String(folder.id))
          }
          .padding({ left: Space.md, right: Space.md })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: Space.sm, bottom: Space.sm })

        // 未读计数 / 总数
        Row() {
          Text(this.countUnread() > 0
            ? this.trp('mail.unreadCount', { 'n': String(this.countUnread()) })
            : this.tr('mail.noUnread'))
            .fontSize(FontSize.caption)
            .fontColor(this.countUnread() > 0 ? Theme.primary : Theme.textMuted)
          Blank()
          Text(this.trp('mail.totalCount', { 'n': String(this.total) }))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md, bottom: Space.xs })
      } else {
        // 搜索结果计数
        Row() {
          Text(this.trp('mail.searchResult', {
            'k': this.searchKeyword,
            'n': String(this.total),
          }))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          Blank()
        }
        .width('100%')
        .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.xs })
      }

      // 邮件列表
      if (this.messages.length === 0) {
        Column() {
          if (this.searchMode && this.hasSearched) {
            EmptyHint({ title: this.tr('mail.searchEmptyTitle'), message: this.tr('mail.searchEmptyMessage') })
          } else {
            EmptyHint({ title: this.tr('mail.emptyTitle'), message: this.tr('mail.emptyMessage') })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.messages, (item: MailMessageSummary) => {
            ListItem() {
              MailRow({ item: item, isUnread: this.displayUnread(item) })
            }
            .onClick(() => {
              this.openMessage(item);
            })
            .gesture(LongPressGesture()
              .onAction(() => {
                this.showRowActions(item);
              }))
          }, (item: MailMessageSummary) => item.id)
          if (this.messages.length < this.total) {
            ListItem() {
              Text(this.loadingMore ? this.tr('status.loading') : this.tr('mail.loadMore'))
                .fontSize(FontSize.caption)
                .fontColor(Theme.primary)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: Space.md, bottom: Space.md })
                .onClick(() => {
                  this.loadMore();
                })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: Theme.divider })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  private ComposeLayer() {
    MailComposeView({
      onSend: (draft: ComposeDraft): Promise<void> => this.handleSendMail(draft),
      onSent: () => {
        this.onComposeSent();
      },
      onBack: () => {
        this.goBackOneLevel();
      },
    })
  }

  @Builder
  private DetailLayer() {
    MailDetailView({
      detail: this.detail,
      loading: this.detailLoading,
      errorText: this.detailError,
      onBack: () => {
        this.goBackOneLevel();
      },
      onRetry: () => {
        this.retryDetail();
      },
      onDelete: () => {
        if (this.currentMessage !== undefined) {
          this.confirmDeleteMessages([this.currentMessage.id]);
        }
      },
      onMove: () => {
        if (this.currentMessage !== undefined) {
          this.pickMoveFolder([this.currentMessage.id]);
        }
      },
    })
  }

  /** 撰写入口（US6）：整页切换到 MailComposeView（自带 DetailHeader） */
  private openCompose(): void {
    this.level = LEVEL_COMPOSE;
  }

  // ── 撰写与发送（US6） ────────────────────────────────

  /** 发送（真实：MailService.sendMail；演示：模拟成功，零网络请求） */
  private async handleSendMail(draft: ComposeDraft): Promise<void> {
    if (this.isDemo) {
      return;
    }
    await SessionManager.getMailService().sendMail(draft);
  }

  /** 发送成功：返回列表 + 提示；停留在"已发送"文件夹时刷新列表 */
  private onComposeSent(): void {
    this.goBackOneLevel();
    this.getUIContext().getPromptAction().showToast({ message: this.tr('mail.sentToast'), duration: 2000 });
    if (!this.searchMode && this.selectedFid === 3) {
      this.loadFolderMessages(true);
    }
  }

  build() {
    Column() {
      SafeTop()

      if (this.level === LEVEL_DETAIL) {
        // 详情整页切换（自带 DetailHeader，对齐 NewsPage 详情形态）
        this.DetailLayer()
      } else {
        if (this.level === LEVEL_COMPOSE) {
          // 撰写整页切换（自带 DetailHeader）
          this.ComposeLayer()
        } else {
          this.HeaderBar()
          Divider().color(Theme.divider)

          if (this.loading) {
            this.LoadingView()
          } else {
            if (this.errorMessage.length > 0) {
              this.ErrorView()
            } else {
              this.ListLayer()
            }
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.background)
  }
}
