/**
 * ============================================================================
 * LibraryRoomPage — 研读间查询与预约（类型 → 近 5 天 → 资源 + 我的预约 + 预约/取消）
 * ============================================================================
 *
 * 层级（页内状态切换，不走路由）：
 *   KIND（类型卡片（类型名 + "N 个房间 · 点选查看近 5 天"）—— 点击展开"近 5 天"日期项
 *         + 我的预约入口 + 使用引导）
 *     → RESOURCE（某类型某天资源：房间名（maxUser>1 附最少~最多人）、类型名、
 *                 开放时间、"可浏览/未开放"徽标；可预约房间提供"预约"入口；空态；返回回到类型）
 *       → BOOK（预约表单：时段起止 HH:mm（分钟 5 的倍数）+ 成员邀请（搜索/添加/移除）
 *               + 规则提示（开放时间/时长/人数上下限）→ 二次确认 → 提交；返回回到资源）
 *   KIND → BOOKINGS（我的预约记录：房间/类型/日期与起止/成员；可取消记录提供"取消预约"）
 *
 * 会话：进入自动完成研读间子系统登录（动态认证地址 → 重定向解析标识 →
 *   id 漫游 → 用户信息账号校验），会话失效自动重建（服务层 withCabRetry）。
 * 写操作（预约/取消/成员搜索）：二次确认后提交，提交中以 busyKey 禁用防重复；
 * 成功后刷新"我的预约"（预约再刷新资源占用）并提示。
 * 演示模式读写零网络请求（内置示例数据；写操作仅提示；成员搜索走本地示例）。
 * 新增可见文案走 i18n（libroom.*，zh/en 成对）。
 * ============================================================================
 */
import { Theme, Space, Radius, FontSize } from '../Theme';
import { EmptyHint, StateBlock, StateTone, StatusBadge, BadgeTone } from '../../components/Ui';
import { SessionManager } from '../../services/auth/SessionManager';
import {
  LibRoomKind,
  LibRoomBrief,
  LibRoomResource,
  LibRoomUsage,
  LibRoomBookRecord,
  LibRoomMember,
  LibRoomBookRequest,
  LibRoomBookResult,
  formatLibRoomDateIso,
  formatLibRoomDateYmd,
  maskLibRoomId,
} from '../../services/campus/LibraryRoomService';
import { AuthManager } from '../../state/AuthManager';
import { StateManager } from '../../state/StateManager';
import { BackDispatcher, BackOwner, BackHandler } from '../../state/BackDispatcher';
import { I18n } from '../../utils/I18n';

/** 页内层级（不走路由） */
const LEVEL_KIND: number = 0;
const LEVEL_RESOURCE: number = 1;
const LEVEL_BOOKINGS: number = 2;
/** 预约表单层（RESOURCE → BOOK） */
const LEVEL_BOOK: number = 3;
/** 近 5 天（今天起偏移 0–4，对齐参考 validDateNum） */
const VALID_DATE_NUM: number = 5;
/** 近 5 天日期偏移序列（ForEach 用） */
const DATE_OFFSETS: number[] = [0, 1, 2, 3, 4];

/** 'YYYY-MM-DD HH:mm:ss' / ISO 文本 → 毫秒；空串/不可解析返回 NaN（占用区间解析用） */
function parseRoomUsageMs(text: string): number {
  if (text.length === 0) {
    return Number.NaN;
  }
  const normalized: string = text.indexOf('T') >= 0 ? text : text.replace(' ', 'T');
  return new Date(normalized).getTime();
}

/** 'YYYY-MM-DD' + 'HH:mm' → 毫秒（表单校验用） */
function roomFormTimeMs(dateIso: string, hhmm: string): number {
  return new Date(dateIso + 'T' + hhmm + ':00').getTime();
}

// ============================================================
// 演示模式示例数据（零网络请求）
// ============================================================

function getDemoKinds(): LibRoomKind[] {
  const rows: string[][] = [
    ['1', '研读间（主馆）', '101|主馆研读间 A01', '102|主馆研读间 A02', '103|主馆研读间 A03'],
    ['2', '研讨间（文科图书馆）', '201|文科研讨间 B01', '202|文科研讨间 B02'],
    ['3', '研读间（医学图书馆）', '301|医学研读间 C01'],
  ];
  const kinds: LibRoomKind[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const kind: LibRoomKind = new LibRoomKind();
    kind.kindId = Number(rows[i][0]);
    kind.kindName = rows[i][1];
    for (let j: number = 2; j < rows[i].length; j++) {
      const parts: string[] = rows[i][j].split('|');
      const brief: LibRoomBrief = new LibRoomBrief();
      brief.devId = Number(parts[0]);
      brief.devName = parts[1];
      brief.minReserveMinute = 30;
      kind.rooms.push(brief);
    }
    kind.roomCount = kind.rooms.length;
    kinds.push(kind);
  }
  return kinds;
}

function getDemoResources(): LibRoomResource[] {
  // devId / 名称 / 类型名 / 最少人 / 最多人 / 开放起 / 开放止 / 占用起止（| 分隔，空 = 无占用）
  const rows: string[][] = [
    ['101', '主馆研读间 A01', '研读间（主馆）', '1', '1', '08:00', '22:00', '10:00|12:00'],
    ['102', '主馆研读间 A02', '研读间（主馆）', '2', '8', '08:00', '22:00', ''],
    ['103', '主馆研读间 A03', '研读间（主馆）', '4', '10', '08:00', '22:00', '14:00|16:00'],
    ['104', '主馆研读间 A04', '研读间（主馆·暂未开放）', '1', '4', '', '', ''],
  ];
  const todayIso: string = formatLibRoomDateIso(0);
  const list: LibRoomResource[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const res: LibRoomResource = new LibRoomResource();
    res.devId = Number(rows[i][0]);
    res.devName = rows[i][1];
    res.roomName = rows[i][1];
    res.kindId = 1;
    res.kindName = rows[i][2];
    res.minUser = Number(rows[i][3]);
    res.maxUser = Number(rows[i][4]);
    res.openStart = rows[i][5];
    res.openEnd = rows[i][6];
    if (rows[i][7].length > 0) {
      const times: string[] = rows[i][7].split('|');
      const usage: LibRoomUsage = new LibRoomUsage();
      usage.startText = todayIso + ' ' + times[0] + ':00';
      usage.endText = todayIso + ' ' + times[1] + ':00';
      res.usageList.push(usage);
    }
    res.minMinute = 30;
    res.maxMinute = 240;
    res.usageCount = res.usageList.length;
    list.push(res);
  }
  return list;
}

function getDemoRoomBookings(): LibRoomBookRecord[] {
  const list: LibRoomBookRecord[] = [];
  const r1: LibRoomBookRecord = new LibRoomBookRecord();
  r1.uuid = 'demo-1';
  r1.rsvId = 1001;
  r1.owner = '张同学';
  r1.ownerId = '2026010101';
  r1.date = formatLibRoomDateIso(1);
  r1.beginText = '08:00';
  r1.endText = '12:00';
  r1.beginFull = formatLibRoomDateIso(1) + ' 08:00:00';
  r1.endFull = formatLibRoomDateIso(1) + ' 12:00:00';
  r1.devName = '主馆研读间 A02';
  r1.kindName = '研读间（主馆）';
  r1.membersText = '张同学、李同学';
  list.push(r1);
  const r2: LibRoomBookRecord = new LibRoomBookRecord();
  r2.uuid = 'demo-2';
  r2.rsvId = 1002;
  r2.owner = '张同学';
  r2.ownerId = '2026010101';
  r2.date = formatLibRoomDateIso(3);
  r2.beginText = '14:00';
  r2.endText = '18:00';
  r2.beginFull = formatLibRoomDateIso(3) + ' 14:00:00';
  r2.endFull = formatLibRoomDateIso(3) + ' 18:00:00';
  r2.devName = '文科研讨间 B01';
  r2.kindName = '研讨间（文科图书馆）';
  r2.membersText = '张同学';
  list.push(r2);
  return list;
}

/** 演示成员示例（成员搜索零网络请求；label 为学号，展示时脱敏） */
function getDemoMembers(): LibRoomMember[] {
  const rows: string[][] = [
    ['1001', '2026010101', '计算机科学与技术系'],
    ['1002', '2026010102', '计算机科学与技术系'],
    ['1003', '2026010208', '自动化系'],
    ['1004', '2026010315', '电子工程系'],
    ['1005', '2026020122', '经济管理学院'],
    ['1006', '2026021011', '建筑学院'],
  ];
  const list: LibRoomMember[] = [];
  for (let i: number = 0; i < rows.length; i++) {
    const member: LibRoomMember = new LibRoomMember();
    member.accNo = Number(rows[i][0]);
    member.label = rows[i][1];
    member.department = rows[i][2];
    list.push(member);
  }
  return list;
}

// ============================================================
// 页面组件
// ============================================================

@Component
export struct LibraryRoomPage {
  onBack: () => void = () => {};

  /** 语言订阅：新增可见文案走 i18n（语言切换即时重渲染） */
  @StorageLink('locale') locale: string = 'zh';

  private tr(key: string): string {
    return I18n.t(key, this.locale);
  }

  private trp(key: string, args: Record<string, string>): string {
    return I18n.tp(key, args, this.locale);
  }

  @State level: number = LEVEL_KIND;
  @State titleText: string = '';
  @State loading: boolean = false;
  /** 加载态文案（存 i18n 键；渲染经 tr() 即时跟随语言） */
  @State loadingText: string = 'libroom.loadingSession';
  @State errorMessage: string = '';
  /** 写操作提交中标识（'book-{devId}' / 'cancel-{uuid}'；非空时禁用全部写动作防重复提交） */
  @State busyKey: string = '';

  // KIND 层
  @State kinds: LibRoomKind[] = [];
  @State expandedKindId: number = -1;

  // RESOURCE / BOOKINGS 层
  @State resources: LibRoomResource[] = [];
  @State bookings: LibRoomBookRecord[] = [];

  // BOOK（预约表单）层
  @State bookTarget: LibRoomResource = new LibRoomResource();
  @State bookStartTime: string = '';
  @State bookEndTime: string = '';
  @State bookFormError: string = '';
  @State memberKeyword: string = '';
  @State memberCandidates: LibRoomMember[] = [];
  @State memberSearching: boolean = false;
  @State selectedMembers: LibRoomMember[] = [];

  private isDemo: boolean = true;
  private currentKindId: number = 0;
  private currentKindName: string = '';
  private currentDateOffset: number = 0;

  /** 系统返回拦截：深层层级逐级 pop，KIND 层交回入口卡片 */
  private backHandler: BackHandler = (): boolean => {
    if (this.level === LEVEL_KIND) {
      this.onBack();
      return true;
    }
    this.goBackOneLevel();
    return true;
  };

  aboutToAppear(): void {
    this.isDemo = !(AuthManager.isLoggedIn() && !StateManager.isDemoMode());
    BackDispatcher.push(BackOwner.CAMPUS, this.backHandler);
    this.loadKinds();
  }

  aboutToDisappear(): void {
    BackDispatcher.remove(this.backHandler);
  }

  // ── 层级导航 ────────────────────────────────

  private goBackOneLevel(): void {
    if (this.level === LEVEL_BOOK) {
      // 表单返回资源层（保留当前类型/日期数据）
      this.level = LEVEL_RESOURCE;
      this.titleText = this.currentKindName;
      this.errorMessage = '';
      return;
    }
    this.level = LEVEL_KIND;
    this.titleText = '';
    this.errorMessage = '';
  }

  private handleHeaderBack(): void {
    if (this.level === LEVEL_KIND) {
      this.onBack();
    } else {
      this.goBackOneLevel();
    }
  }

  // ── 数据加载（演示模式零网络请求） ────────────────────────────────

  private extractError(e: Object): string {
    return e instanceof Error ? e.message : String(e);
  }

  /** KIND 层：类型列表（首次进入自动完成研读间子系统登录与账号校验） */
  private async loadKinds(): Promise<void> {
    this.level = LEVEL_KIND;
    this.titleText = '';
    this.errorMessage = '';
    this.loadingText = this.kinds.length === 0 ? 'libroom.loadingSession' : 'libroom.loadingKinds';
    if (this.isDemo) {
      this.kinds = getDemoKinds();
      return;
    }
    this.loading = true;
    try {
      this.kinds = await SessionManager.getLibraryRoomService().getRoomKindList();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  private onToggleKind(kind: LibRoomKind): void {
    if (this.expandedKindId === kind.kindId) {
      this.expandedKindId = -1;
    } else {
      this.expandedKindId = kind.kindId;
    }
  }

  /** RESOURCE 层：某类型某天资源（dateOffset 0–4 → yyyyMMdd 请求） */
  private async openResources(kind: LibRoomKind, dateOffset: number): Promise<void> {
    this.currentKindId = kind.kindId;
    this.currentKindName = kind.kindName;
    this.currentDateOffset = dateOffset;
    this.level = LEVEL_RESOURCE;
    this.titleText = kind.kindName;
    this.errorMessage = '';
    this.loadingText = 'libroom.loadingResources';
    if (this.isDemo) {
      this.resources = getDemoResources();
      return;
    }
    this.loading = true;
    try {
      this.resources = await SessionManager.getLibraryRoomService()
        .getRoomResourceList(formatLibRoomDateYmd(dateOffset), kind.kindId);
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** BOOKINGS 层：我的预约记录 */
  private async openBookings(): Promise<void> {
    this.level = LEVEL_BOOKINGS;
    this.titleText = '';
    this.errorMessage = '';
    this.loadingText = 'libroom.loadingBookings';
    if (this.isDemo) {
      this.bookings = getDemoRoomBookings();
      return;
    }
    this.loading = true;
    try {
      this.bookings = await SessionManager.getLibraryRoomService().getRoomBookingRecords();
    } catch (e) {
      this.errorMessage = this.extractError(e);
    }
    this.loading = false;
  }

  /** 右上角刷新 / 错误重试：按当前层级重拉 */
  private async refreshCurrentLevel(): Promise<void> {
    if (this.level === LEVEL_RESOURCE) {
      const kind: LibRoomKind = new LibRoomKind();
      kind.kindId = this.currentKindId;
      kind.kindName = this.currentKindName;
      await this.openResources(kind, this.currentDateOffset);
    } else if (this.level === LEVEL_BOOK) {
      // 表单层刷新：静默重拉资源占用并同步表单目标，不离开表单
      await this.reloadResourcesForBookForm();
    } else if (this.level === LEVEL_BOOKINGS) {
      await this.openBookings();
    } else {
      this.kinds = [];
      this.expandedKindId = -1;
      await this.loadKinds();
    }
  }

  /** BOOK 层刷新：重拉资源列表（占用/规则以最新为准），同步 bookTarget；失败保留原数据 */
  private async reloadResourcesForBookForm(): Promise<void> {
    if (this.isDemo) {
      return;
    }
    try {
      const list: LibRoomResource[] = await SessionManager.getLibraryRoomService()
        .getRoomResourceList(formatLibRoomDateYmd(this.currentDateOffset), this.currentKindId);
      this.resources = list;
      for (let i: number = 0; i < list.length; i++) {
        if (list[i].devId === this.bookTarget.devId) {
          this.bookTarget = list[i];
          break;
        }
      }
    } catch (e) {
      // 静默刷新失败保留原数据
    }
  }

  /** 成功预约后静默刷新"我的预约"数据（打开 BOOKINGS 层时会重新拉取，此处预取） */
  private async reloadBookingsSilently(): Promise<void> {
    if (this.isDemo) {
      return;
    }
    try {
      this.bookings = await SessionManager.getLibraryRoomService().getRoomBookingRecords();
    } catch (e) {
      // 静默刷新失败保留原列表
    }
  }

  // ── 写操作（预约 / 取消 / 成员搜索）：二次确认 + 防重复 + 成功刷新（演示模式零请求） ────────────────────────

  /** 页内头部标题（KIND/BOOKINGS 走词条；RESOURCE/BOOK 为服务数据名，存于 titleText） */
  private headerTitle(): string {
    if (this.level === LEVEL_BOOKINGS) {
      return this.tr('libroom.bookingsTitle');
    }
    if (this.level === LEVEL_KIND) {
      return this.tr('libroom.title');
    }
    return this.titleText.length > 0 ? this.titleText : this.tr('libroom.resourcesFallback');
  }

  /** 资源显示名（房间名优先，回退设备名/编号） */
  private roomDisplayName(res: LibRoomResource): string {
    const name: string = res.roomName.length > 0 ? res.roomName : res.devName;
    return name.length > 0 ? name : this.trp('libroom.roomFallback', { 'id': String(res.devId) });
  }

  /** 预约表单目标房间名（确认框/标题用） */
  private bookRoomName(): string {
    return this.roomDisplayName(this.bookTarget);
  }

  /** 打开预约表单（RESOURCE → BOOK；重置表单态） */
  private openBookForm(res: LibRoomResource): void {
    if (this.busyKey.length > 0) {
      return;
    }
    this.bookTarget = res;
    this.bookStartTime = '';
    this.bookEndTime = '';
    this.bookFormError = '';
    this.memberKeyword = '';
    this.memberCandidates = [];
    this.selectedMembers = [];
    this.level = LEVEL_BOOK;
    this.titleText = this.bookRoomName();
    this.errorMessage = '';
  }

  /** 房间规则提示（开放时间/时长/人数上下限；缺省回退兜底文案） */
  private bookRuleHint(): string {
    const res: LibRoomResource = this.bookTarget;
    const parts: string[] = [];
    if (res.openStart.length >= 5 && res.openEnd.length >= 5) {
      parts.push(this.trp('libroom.ruleOpen', {
        'start': res.openStart.substring(0, 5),
        'end': res.openEnd.substring(0, 5),
      }));
    }
    if (res.minMinute > 0 && res.maxMinute > 0) {
      parts.push(this.trp('libroom.ruleDuration', {
        'min': String(res.minMinute),
        'max': String(res.maxMinute),
      }));
    } else if (res.minMinute > 0) {
      parts.push(this.trp('libroom.ruleDurationMin', { 'min': String(res.minMinute) }));
    } else if (res.maxMinute > 0) {
      parts.push(this.trp('libroom.ruleDurationMax', { 'max': String(res.maxMinute) }));
    }
    if (res.minUser > 0 && res.maxUser > 0) {
      parts.push(this.trp('libroom.ruleUsers', {
        'min': String(res.minUser),
        'max': String(res.maxUser),
      }));
    } else if (res.minUser > 0) {
      parts.push(this.trp('libroom.ruleUsersMin', { 'min': String(res.minUser) }));
    } else if (res.maxUser > 0) {
      parts.push(this.trp('libroom.ruleUsersMax', { 'max': String(res.maxUser) }));
    }
    if (parts.length === 0) {
      return this.tr('libroom.ruleHintFallback');
    }
    return parts.join(' · ');
  }

  /** 当前人数（含本人）与上下限提示 */
  private memberCountText(): string {
    const res: LibRoomResource = this.bookTarget;
    const count: number = 1 + this.selectedMembers.length;
    if (res.minUser > 0 && res.maxUser > 0) {
      return this.trp('libroom.memberCount', {
        'n': String(count),
        'min': String(res.minUser),
        'max': String(res.maxUser),
      });
    }
    if (res.minUser > 0) {
      return this.trp('libroom.memberCountMin', {
        'n': String(count),
        'min': String(res.minUser),
      });
    }
    return this.trp('libroom.memberCountNoLimit', { 'n': String(count) });
  }

  /** 成员搜索（演示模式本地示例过滤，零网络请求；真实模式 GET getMembers） */
  private async searchMembers(): Promise<void> {
    const keyword: string = this.memberKeyword.trim();
    if (keyword.length === 0) {
      this.memberCandidates = [];
      return;
    }
    if (this.isDemo) {
      const all: LibRoomMember[] = getDemoMembers();
      const list: LibRoomMember[] = [];
      for (let i: number = 0; i < all.length; i++) {
        if (all[i].label.indexOf(keyword) >= 0 || all[i].department.indexOf(keyword) >= 0) {
          list.push(all[i]);
        }
      }
      this.memberCandidates = list;
      return;
    }
    this.memberSearching = true;
    try {
      this.memberCandidates = await SessionManager.getLibraryRoomService()
        .getRoomMemberCandidates(keyword);
    } catch (e) {
      this.memberCandidates = [];
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('libroom.memberSearchFailed', { 'msg': this.extractError(e) }),
        duration: 2500,
      });
    }
    this.memberSearching = false;
  }

  /** 添加成员（去重；超过房间人数上限时阻止并提示） */
  private addMember(member: LibRoomMember): void {
    for (let i: number = 0; i < this.selectedMembers.length; i++) {
      if (this.selectedMembers[i].accNo === member.accNo) {
        return;
      }
    }
    const maxUser: number = this.bookTarget.maxUser;
    if (maxUser > 0 && this.selectedMembers.length + 2 > maxUser) {
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('libroom.errUserMax', { 'n': String(maxUser) }),
        duration: 2000,
      });
      return;
    }
    this.selectedMembers.push(member);
    this.bookFormError = '';
  }

  /** 移除成员（按 accNo 定位） */
  private removeMember(member: LibRoomMember): void {
    for (let i: number = 0; i < this.selectedMembers.length; i++) {
      if (this.selectedMembers[i].accNo === member.accNo) {
        this.selectedMembers.splice(i, 1);
        return;
      }
    }
  }

  /** 规整 'H:mm'/'HH:mm' → 'HH:mm'（不校验合法性，供已通过校验的文本展示用） */
  private padRoomTime(text: string): string {
    const parts: string[] = text.split(':');
    if (parts.length !== 2 || parts[0].length >= 2) {
      return text;
    }
    return '0' + parts[0] + ':' + parts[1];
  }

  /**
   * 表单本地校验（提交前阻止非法输入；服务层提交时会以最新数据复核）：
   * 时间格式（HH:mm、分钟 5 的倍数）→ 先后 → 开放时间 → 时长 → 人数 → 占用重叠。
   * 返回可读错误文案，空串 = 通过。
   */
  private validateBookForm(): string {
    const res: LibRoomResource = this.bookTarget;
    const startMatch: RegExpExecArray | null = /^(\d{1,2}):(\d{2})$/.exec(this.bookStartTime.trim());
    const endMatch: RegExpExecArray | null = /^(\d{1,2}):(\d{2})$/.exec(this.bookEndTime.trim());
    if (startMatch === null || endMatch === null
      || Number(startMatch[1]) > 23 || Number(endMatch[1]) > 23
      || Number(startMatch[2]) > 59 || Number(endMatch[2]) > 59
      || Number(startMatch[2]) % 5 !== 0 || Number(endMatch[2]) % 5 !== 0) {
      return this.tr('libroom.errTimeFormat');
    }
    const startText: string = this.padRoomTime(this.bookStartTime.trim());
    const endText: string = this.padRoomTime(this.bookEndTime.trim());
    if (startText >= endText) {
      return this.tr('libroom.errEndAfterStart');
    }
    if (res.openStart.length >= 5 && res.openEnd.length >= 5) {
      const openStartText: string = res.openStart.substring(0, 5);
      const openEndText: string = res.openEnd.substring(0, 5);
      if (startText < openStartText || endText > openEndText) {
        return this.trp('libroom.errOpenTime', { 'start': openStartText, 'end': openEndText });
      }
    }
    const dateIso: string = formatLibRoomDateIso(this.currentDateOffset);
    const startMs: number = roomFormTimeMs(dateIso, startText);
    const endMs: number = roomFormTimeMs(dateIso, endText);
    if (Number.isNaN(startMs) || Number.isNaN(endMs)) {
      return this.tr('libroom.errTimeFormat');
    }
    const minutes: number = Math.round((endMs - startMs) / 60000);
    if (res.minMinute > 0 && minutes < res.minMinute) {
      return this.trp('libroom.errDurationShort', { 'min': String(res.minMinute) });
    }
    if (res.maxMinute > 0 && minutes > res.maxMinute) {
      return this.trp('libroom.errDurationLong', { 'max': String(res.maxMinute) });
    }
    const userCount: number = 1 + this.selectedMembers.length;
    if (res.minUser > 0 && userCount < res.minUser) {
      return this.trp('libroom.errUserMin', { 'n': String(res.minUser) });
    }
    if (res.maxUser > 0 && userCount > res.maxUser) {
      return this.trp('libroom.errUserMax', { 'n': String(res.maxUser) });
    }
    for (let i: number = 0; i < res.usageList.length; i++) {
      const usage: LibRoomUsage = res.usageList[i];
      const usageStartMs: number = parseRoomUsageMs(usage.startText);
      const usageEndMs: number = parseRoomUsageMs(usage.endText);
      if (!Number.isNaN(usageStartMs) && !Number.isNaN(usageEndMs)
        && startMs < usageEndMs && usageStartMs < endMs) {
        return this.tr('libroom.errOverlap');
      }
    }
    return '';
  }

  /** 预约研读间：表单校验 → 二次确认（房间/日期/时段/人数与成员）（FR-006） */
  private confirmBook(): void {
    if (this.busyKey.length > 0) {
      return;
    }
    const err: string = this.validateBookForm();
    if (err.length > 0) {
      this.bookFormError = err;
      return;
    }
    this.bookFormError = '';
    const dateText: string = formatLibRoomDateIso(this.currentDateOffset);
    const timeText: string = this.padRoomTime(this.bookStartTime.trim())
      + ' – ' + this.padRoomTime(this.bookEndTime.trim());
    const memberCount: number = 1 + this.selectedMembers.length;
    const memberText: string = memberCount > 1
      ? this.trp('libroom.confirmMembersMulti', {
        'n': String(memberCount),
        'm': String(this.selectedMembers.length),
      })
      : this.tr('libroom.confirmMembersSolo');
    const message: string = this.trp('libroom.confirmRoom', { 'name': this.bookRoomName() }) + '\n'
      + this.trp('libroom.confirmDate', { 'name': dateText }) + '\n'
      + this.trp('libroom.confirmTime', { 'name': timeText }) + '\n'
      + this.trp('libroom.confirmMembers', { 'name': memberText });
    AlertDialog.show({
      title: this.tr('libroom.bookTitle'),
      message: message,
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('libroom.confirmBook'),
        action: (): void => {
          this.doBookRoom();
        },
      },
    });
  }

  private async doBookRoom(): Promise<void> {
    if (this.busyKey.length > 0) {
      return;
    }
    if (this.isDemo) {
      // 演示模式：不发起网络请求，仅可读提示（FR-011/SC-005）
      this.getUIContext().getPromptAction()
        .showToast({ message: this.tr('libroom.demoWriteBlocked'), duration: 2000 });
      return;
    }
    const err: string = this.validateBookForm();
    if (err.length > 0) {
      this.bookFormError = err;
      return;
    }
    this.busyKey = 'book-' + String(this.bookTarget.devId);
    const req: LibRoomBookRequest = new LibRoomBookRequest();
    req.devId = this.bookTarget.devId;
    req.kindId = this.bookTarget.kindId;
    req.date = formatLibRoomDateIso(this.currentDateOffset);
    req.startTime = this.bookStartTime.trim();
    req.endTime = this.bookEndTime.trim();
    for (let i: number = 0; i < this.selectedMembers.length; i++) {
      req.memberAccNos.push(this.selectedMembers[i].accNo);
    }
    try {
      const result: LibRoomBookResult = await SessionManager.getLibraryRoomService().bookLibraryRoom(req);
      if (result.ok) {
        this.getUIContext().getPromptAction()
          .showToast({ message: this.tr('libroom.bookSuccess'), duration: 2000 });
        // 成功：回资源层刷新占用；静默刷新"我的预约"（FR-008）
        this.busyKey = '';
        const kind: LibRoomKind = new LibRoomKind();
        kind.kindId = this.currentKindId;
        kind.kindName = this.currentKindName;
        await this.openResources(kind, this.currentDateOffset);
        this.reloadBookingsSilently();
        return;
      }
      const msgText: string = result.message.length > 0
        ? result.message : this.tr('libroom.unknownError');
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('libroom.bookFailed', { 'msg': msgText }),
        duration: 2500,
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('libroom.bookFailed', { 'msg': this.extractError(e) }),
        duration: 2500,
      });
    }
    this.busyKey = '';
  }

  /** 记录是否可取消：有 uuid 且未开始/未过期（无法解析时保守提供，服务端会拒绝并给出可读原因） */
  private isRecordCancellable(rec: LibRoomBookRecord): boolean {
    if (rec.uuid.length === 0) {
      return false;
    }
    if (rec.beginFull.length > 0) {
      const beginMs: number = parseRoomUsageMs(rec.beginFull);
      if (!Number.isNaN(beginMs) && beginMs <= Date.now()) {
        return false;
      }
    }
    return true;
  }

  /** 取消预约：二次确认（房间/日期时间）→ 提交（仅可取消记录） */
  private confirmCancelBooking(rec: LibRoomBookRecord): void {
    if (this.busyKey.length > 0 || !this.isRecordCancellable(rec)) {
      return;
    }
    const roomText: string = rec.devName.length > 0
      ? rec.devName : this.trp('libroom.roomFallback', { 'id': String(rec.rsvId) });
    const timeText: string = (rec.date.length > 0 ? rec.date + ' ' : '')
      + rec.beginText + ' – ' + rec.endText;
    const message: string = this.trp('libroom.confirmRoom', { 'name': roomText }) + '\n'
      + this.trp('libroom.confirmTime', { 'name': timeText });
    AlertDialog.show({
      title: this.tr('libroom.cancelTitle'),
      message: message,
      primaryButton: {
        value: this.tr('common.cancel'),
        action: (): void => {},
      },
      secondaryButton: {
        value: this.tr('libroom.confirmCancel'),
        fontColor: Theme.error,
        action: (): void => {
          this.doCancelBooking(rec);
        },
      },
    });
  }

  private async doCancelBooking(rec: LibRoomBookRecord): Promise<void> {
    if (this.busyKey.length > 0 || !this.isRecordCancellable(rec)) {
      return;
    }
    if (this.isDemo) {
      // 演示模式：不发起网络请求，仅可读提示（FR-011/SC-005）
      this.getUIContext().getPromptAction()
        .showToast({ message: this.tr('libroom.demoWriteBlocked'), duration: 2000 });
      return;
    }
    this.busyKey = 'cancel-' + rec.uuid;
    try {
      const result: LibRoomBookResult = await SessionManager.getLibraryRoomService()
        .cancelRoomBooking(rec.uuid);
      if (result.ok) {
        this.getUIContext().getPromptAction()
          .showToast({ message: this.tr('libroom.cancelSuccess'), duration: 2000 });
        // 成功：刷新"我的预约"列表
        this.busyKey = '';
        await this.openBookings();
        return;
      }
      const msgText: string = result.message.length > 0
        ? result.message : this.tr('libroom.unknownError');
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('libroom.cancelFailed', { 'msg': msgText }),
        duration: 2500,
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({
        message: this.trp('libroom.cancelFailed', { 'msg': this.extractError(e) }),
        duration: 2500,
      });
    }
    this.busyKey = '';
  }

  // ── UI ────────────────────────────────

  /**
   * 页内头部（复刻 DetailHeader 版式）：
   * 标题直接绑定 this.titleText（自定义组件普通成员只初始化一次、不随父状态刷新，
   * 故不能经 DetailHeader 传入动态标题）。
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

      Text(this.headerTitle())
        .fontSize(FontSize.h3)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Column() {
        this.RightAction()
      }
      .width(40)
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: Space.sm, right: Space.md, top: Space.sm, bottom: Space.sm })
    .alignItems(VerticalAlign.Center)
  }

  /** 右上角刷新：加载中显示进度 */
  @Builder
  private RightAction() {
    if (this.loading) {
      LoadingProgress()
        .width(20)
        .height(20)
        .color(Theme.primary)
    } else {
      Text('↻')
        .fontSize(20)
        .fontColor(Theme.primary)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.refreshCurrentLevel();
        })
    }
  }

  @Builder
  private LoadingView() {
    Column({ space: Space.md }) {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.primary)
      Text(this.tr(this.loadingText))
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
          this.refreshCurrentLevel();
        },
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
  }

  /** KIND 层：类型卡片（类型名 + 房间数；点击展开"近 5 天"日期项） */
  @Builder
  private KindCard(kind: LibRoomKind) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text(kind.kindName.length > 0 ? kind.kindName : this.trp('libroom.kindFallback', {
            'id': String(kind.kindId)
          }))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.trp('libroom.kindCardHint', {
            'rooms': String(kind.roomCount),
            'days': String(VALID_DATE_NUM)
          }))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.expandedKindId === kind.kindId ? '⌄' : '›')
          .fontSize(FontSize.label)
          .fontColor(Theme.textMuted)
      }
      .width('100%')
      .onClick(() => {
        this.onToggleKind(kind);
      })

      if (this.expandedKindId === kind.kindId) {
        Divider()
          .color(Theme.divider)
          .margin({ top: Space.sm, bottom: Space.sm })

        ForEach(DATE_OFFSETS, (offset: number) => {
          Row() {
            Text(formatLibRoomDateIso(offset))
              .fontSize(FontSize.body)
              .fontColor(Theme.text)
              .layoutWeight(1)
            Text('›')
              .fontSize(FontSize.label)
              .fontColor(Theme.textMuted)
          }
          .width('100%')
          .padding({ top: Space.sm, bottom: Space.sm })
          .onClick(() => {
            this.openResources(kind, offset);
          })
        }, (offset: number) => String(offset))
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
  }

  @Builder
  private KindLayer() {
    Scroll() {
      Column() {
        // 我的预约入口
        Row() {
          Text('📋')
            .fontSize(20)
          Text(this.tr('libroom.bookingsTitle'))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
            .margin({ left: 12 })
            .layoutWeight(1)
          Text('>')
            .fontSize(FontSize.label)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .padding(Space.md)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })
        .onClick(() => {
          this.openBookings();
        })

        // 使用引导
        StateBlock({
          tone: StateTone.Info,
          message: this.tr('libroom.kindHint'),
        })
        .margin({ left: Space.md, right: Space.md, bottom: Space.md })

        if (this.kinds.length === 0) {
          EmptyHint({ title: this.tr('libroom.emptyKindsTitle'), message: this.tr('libroom.emptyKindsMessage') })
        } else {
          ForEach(this.kinds, (kind: LibRoomKind) => {
            this.KindCard(kind)
          }, (kind: LibRoomKind) => String(kind.kindId))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** RESOURCE 层：资源卡片（房间名（含人数区间）、类型名、开放时间、开放徽标；可预约房间提供"预约"入口） */
  @Builder
  private ResourceCard(res: LibRoomResource) {
    Column() {
      Row() {
        Column({ space: 2 }) {
          Text((res.roomName.length > 0 ? res.roomName : res.devName)
            + (res.maxUser > 1 ? this.trp('libroom.userRange', {
              'min': String(res.minUser),
              'max': String(res.maxUser)
            }) : ''))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(res.kindName)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          if (res.openStart.length > 0 && res.openEnd.length > 0) {
            Text(this.trp('libroom.ruleOpen', {
              'start': res.openStart,
              'end': res.openEnd
            }))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (res.kindName.indexOf('暂未开放') >= 0) {
          StatusBadge({ text: this.tr('libroom.closedBadge'), tone: BadgeTone.Warning })
        } else {
          StatusBadge({ text: this.tr('libroom.bookableBadge'), tone: BadgeTone.Success })
        }
      }
      .width('100%')

      // 可预约房间提供"预约"入口 → BOOK 表单层（提交中转"提交中…"防重复，FR-013）
      if (res.kindName.indexOf('暂未开放') < 0) {
        Row() {
          Text(this.busyKey === 'book-' + String(res.devId)
            ? this.tr('libroom.submitting') : this.tr('libroom.book'))
            .fontSize(FontSize.label)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textInvert)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
            .borderRadius(Radius.pill)
            .backgroundColor(Theme.primary)
            .constraintSize({ maxWidth: '100%' })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.openBookForm(res);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Space.sm })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
  }

  @Builder
  private ResourceLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: this.tr('libroom.resourceHint'),
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.resources.length === 0) {
          EmptyHint({ title: this.tr('libroom.emptyResourcesTitle'), message: this.tr('libroom.emptyResourcesMessage') })
        } else {
          ForEach(this.resources, (res: LibRoomResource) => {
            this.ResourceCard(res)
          }, (res: LibRoomResource) => String(res.devId) + '-' + String(res.roomId))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** BOOK 层：预约表单（规则提示 + 房间/日期 + 时段起止 HH:mm + 成员邀请 + 提交（二次确认）） */
  @Builder
  private BookLayer() {
    Scroll() {
      Column() {
        // 规则提示（开放时间 / 时长限制 / 人数上下限）
        StateBlock({
          tone: StateTone.Info,
          message: this.bookRuleHint(),
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        // 房间与日期
        Column({ space: Space.xs }) {
          Text(this.bookRoomName())
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.text)
          Text(this.bookTarget.kindName)
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          Text(this.trp('libroom.formDate', { 'name': formatLibRoomDateIso(this.currentDateOffset) }))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.md, right: Space.md, bottom: 12 })

        // 时段起止（HH:mm，分钟须为 5 的倍数）
        Column({ space: Space.sm }) {
          Text(this.tr('libroom.formStartTime'))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          TextInput({ placeholder: 'HH:mm', text: this.bookStartTime })
            .fontSize(FontSize.body)
            .onChange((value: string) => {
              this.bookStartTime = value;
            })
          Text(this.tr('libroom.formEndTime'))
            .fontSize(FontSize.caption)
            .fontColor(Theme.textMuted)
          TextInput({ placeholder: 'HH:mm', text: this.bookEndTime })
            .fontSize(FontSize.body)
            .onChange((value: string) => {
              this.bookEndTime = value;
            })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.md, right: Space.md, bottom: 12 })

        // 成员邀请（搜索 → 候选（学号脱敏）→ 添加/移除；显示当前人数与上下限）
        Column({ space: Space.sm }) {
          Row() {
            Text(this.tr('libroom.memberSection'))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
              .layoutWeight(1)
            Text(this.memberCountText())
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
          }
          .width('100%')

          Row({ space: Space.sm }) {
            TextInput({ placeholder: this.tr('libroom.memberSearchPlaceholder'), text: this.memberKeyword })
              .fontSize(FontSize.body)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.memberKeyword = value;
              })
            Text(this.memberSearching ? this.tr('libroom.searching') : this.tr('libroom.search'))
              .fontSize(FontSize.label)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textInvert)
              .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
              .borderRadius(Radius.pill)
              .backgroundColor(this.memberSearching ? Theme.textMuted : Theme.primary)
              .constraintSize({ maxWidth: '100%' })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                if (!this.memberSearching) {
                  this.searchMembers();
                }
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: '100%' })

          if (this.memberSearching) {
            Row({ space: Space.xs }) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(Theme.primary)
              Text(this.tr('libroom.searching'))
                .fontSize(FontSize.caption)
                .fontColor(Theme.textMuted)
            }
            .width('100%')
          }

          if (this.memberCandidates.length > 0) {
            ForEach(this.memberCandidates, (member: LibRoomMember) => {
              Row() {
                Column({ space: 2 }) {
                  Text(maskLibRoomId(member.label))
                    .fontSize(FontSize.body)
                    .fontColor(Theme.text)
                  if (member.department.length > 0) {
                    Text(member.department)
                      .fontSize(FontSize.caption)
                      .fontColor(Theme.textMuted)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.tr('libroom.add'))
                  .fontSize(FontSize.label)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.primary)
                  .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
                  .borderRadius(Radius.pill)
                  .border({ width: 1, color: Theme.primary })
                  .constraintSize({ maxWidth: '100%' })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .onClick(() => {
                    this.addMember(member);
                  })
              }
              .width('100%')
              .padding({ top: Space.sm, bottom: Space.sm })
            }, (member: LibRoomMember) => String(member.accNo))
          }

          if (this.memberCandidates.length === 0 && this.memberKeyword.trim().length > 0
            && !this.memberSearching) {
            Text(this.tr('libroom.noCandidates'))
              .fontSize(FontSize.caption)
              .fontColor(Theme.textMuted)
          }

          if (this.selectedMembers.length > 0) {
            Divider()
              .color(Theme.divider)

            ForEach(this.selectedMembers, (member: LibRoomMember) => {
              Row() {
                Column({ space: 2 }) {
                  Text(maskLibRoomId(member.label))
                    .fontSize(FontSize.body)
                    .fontColor(Theme.text)
                  if (member.department.length > 0) {
                    Text(member.department)
                      .fontSize(FontSize.caption)
                      .fontColor(Theme.textMuted)
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.tr('libroom.remove'))
                  .fontSize(FontSize.label)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.error)
                  .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
                  .borderRadius(Radius.pill)
                  .border({ width: 1, color: Theme.error })
                  .constraintSize({ maxWidth: '100%' })
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .onClick(() => {
                    this.removeMember(member);
                  })
              }
              .width('100%')
              .padding({ top: Space.sm, bottom: Space.sm })
            }, (member: LibRoomMember) => String(member.accNo))
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .alignItems(HorizontalAlign.Start)
        .padding(Space.md)
        .borderRadius(Theme.cardRadius)
        .backgroundColor(Theme.surface)
        .border({ width: 1, color: Theme.borderSubtle })
        .margin({ left: Space.md, right: Space.md, bottom: 12 })

        // 表单校验错误提示（可读原因）
        if (this.bookFormError.length > 0) {
          Text(this.bookFormError)
            .fontSize(FontSize.caption)
            .fontColor(Theme.error)
            .constraintSize({ maxWidth: '100%' })
            .margin({ left: Space.md, right: Space.md, bottom: Space.md })
        }

        // 提交（入口前已有表单校验；点击后二次确认；提交中禁用防重复，FR-013）
        Row() {
          Text(this.busyKey.length > 0
            ? this.tr('libroom.submitting') : this.tr('libroom.submit'))
            .fontSize(FontSize.body)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.textInvert)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .padding({ top: Space.sm, bottom: Space.sm })
            .borderRadius(Radius.pill)
            .backgroundColor(this.busyKey.length > 0 ? Theme.textMuted : Theme.primary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.confirmBook();
            })
        }
        .width('100%')
        .constraintSize({ maxWidth: '100%' })
        .margin({ left: Space.md, right: Space.md, bottom: Space.md })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  /** BOOKINGS 层：预约记录卡片（房间/类型/日期与起止/成员；可取消记录提供"取消预约"） */
  @Builder
  private BookingCard(rec: LibRoomBookRecord) {
    Column({ space: Space.xs }) {
      Text(rec.devName.length > 0 ? rec.devName : this.trp('libroom.roomFallback', {
        'id': String(rec.rsvId)
      }))
        .fontSize(FontSize.body)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.text)
      Text(rec.kindName)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
      Text((rec.date.length > 0 ? rec.date + ' ' : '') + rec.beginText + ' – ' + rec.endText)
        .fontSize(FontSize.caption)
        .fontColor(Theme.textMuted)
      if (rec.membersText.length > 0) {
        Text(this.trp('libroom.membersLine', { 'names': rec.membersText }))
          .fontSize(FontSize.caption)
          .fontColor(Theme.textMuted)
      }

      // 可取消记录提供"取消预约"（已过期/已开始的记录不提供）；提交中转"提交中…"防重复
      if (this.isRecordCancellable(rec)) {
        Row() {
          Text(this.busyKey === 'cancel-' + rec.uuid
            ? this.tr('libroom.submitting') : this.tr('libroom.cancelBooking'))
            .fontSize(FontSize.label)
            .fontWeight(FontWeight.Medium)
            .fontColor(Theme.error)
            .padding({ left: Space.md, right: Space.md, top: Space.sm, bottom: Space.sm })
            .borderRadius(Radius.pill)
            .border({ width: 1, color: Theme.error })
            .constraintSize({ maxWidth: '100%' })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              this.confirmCancelBooking(rec);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .margin({ top: Space.sm })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: '100%' })
    .alignItems(HorizontalAlign.Start)
    .padding(Space.md)
    .borderRadius(Theme.cardRadius)
    .backgroundColor(Theme.surface)
    .border({ width: 1, color: Theme.borderSubtle })
    .margin({ left: Space.md, right: Space.md, bottom: 12 })
  }

  @Builder
  private BookingsLayer() {
    Scroll() {
      Column() {
        StateBlock({
          tone: StateTone.Info,
          message: this.tr('libroom.bookingsHint'),
        })
        .margin({ left: Space.md, right: Space.md, top: Space.md, bottom: Space.md })

        if (this.bookings.length === 0) {
          EmptyHint({ title: this.tr('libroom.emptyBookingsTitle'), message: this.tr('libroom.bookingsEmptyMessage') })
        } else {
          ForEach(this.bookings, (rec: LibRoomBookRecord) => {
            this.BookingCard(rec)
          }, (rec: LibRoomBookRecord, index: number) => rec.uuid + '#' + String(index))
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  build() {
    Column() {
      this.HeaderBar()
      Divider().color(Theme.divider)

      if (this.loading) {
        this.LoadingView()
      } else {
        if (this.errorMessage.length > 0) {
          this.ErrorView()
        } else {
          if (this.level === LEVEL_KIND) {
            this.KindLayer()
          } else {
            if (this.level === LEVEL_RESOURCE) {
              this.ResourceLayer()
            } else {
              if (this.level === LEVEL_BOOK) {
                this.BookLayer()
              } else {
                this.BookingsLayer()
              }
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
