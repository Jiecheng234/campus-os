/**
 * ============================================================================
 * LibrarySeatService — 图书馆座位只读查询（馆 → 楼层使用率 → 区域 → 座位 + 我的预约）
 * ============================================================================
 *
 * 对齐原项目 src/services/campus/library.ts（thu-info-lib library.ts 协议）：
 *   - 会话：id-roam 图书馆座院子系统（yyfwid 'ef84f6…/0?/api/id_tsinghua_callback'，
 *     对齐原项目 SUBSYSTEM_YYFWID.librarySeat）+ 首个 home 请求失败忽略
 *     + withLibRetry 两层恢复（reroam = 重置标记 + 强制重漫游，label 'lib'）。
 *   - 接口：api.php/areas|areadays|spaces_old 纯 JSON（失败标记 status=false → 抛服务端
 *     msg；data.list 缺失 → 可读错误）。
 *   - 楼层使用率：楼层自身无总数，由其开放子区域的 TotalCount/UnavailableSpace 聚合；
 *     并发拉取、单层失败容错为 0；未开放层不发请求。
 *   - 座位查询：先 areadays/{sectionId} 命中目标日期拿时段 id 与起止时间
 *     （今天把起始时间钳制为"当前时刻或更晚"），再 spaces_old 查座位状态。
 *   - 我的预约：user/index/book HTML 表格正则解析（cheerio 语义：tr 子节点含文本节点）；
 *     行内 menuDel('…') onclick 解析出可取消标识 cancelId（无则不可取消）。
 *   - 写操作（预约/取消，对齐原项目 getLibraryAccessToken/bookLibrarySeat/
 *     cancelLibraryBooking）：访问令牌自图书馆主页 HTML 抓取（access_token 后
 *     第一对引号内字符串），内存缓存约 5 分钟；预约 POST api.php/spaces/{seatId}/book
 *     （表单 access_token/userid/segment/type/operateChannel=2）；取消 POST
 *     api.php/profile/books/{bookingId}（表单 _method=delete/id/userid/
 *     access_token/operateChannel=2）；响应 JSON status===0 视为成功；失败文本
 *     命中令牌关键字则强制刷新令牌重试一次；日志/错误不得输出令牌明文（FR-019）。
 * ============================================================================
 */
import { HttpClient, HttpResponse } from '../HttpClient';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { CampusCredentials } from '../../domain/AuthTypes';
import { Log } from '../../utils/Logger';

const WEBVPN_BASE: string = 'https://webvpn.tsinghua.edu.cn';
/** 图书馆座位 webvpn token（对齐原项目 LIB_TOKEN） */
const LIB_TOKEN: string = '77726476706e69737468656265737421e3f24088693c6152301c9aa596522b204c02212b859d0a19';
/** 图书馆座位子系统 id-roam payload（对齐原项目 SUBSYSTEM_YYFWID.librarySeat） */
const LIB_SEAT_YYFWID: string = 'ef84f6d6784f6b834e5214f432d6173f/0?/api/id_tsinghua_callback';

/** 子系统首页（激活后 GET 一次，偶发 500 忽略） */
const LIB_HOME_URL: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/home/web/f_second';
/** 馆树（顶层图书馆列表） */
const LIBRARY_LIST_URL: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/api.php/areas/1/tree/1';
/** 楼层（areas/{libraryId}）与区域（areas/{floorId}/date/{date}）共用前缀 */
const LIBRARY_AREAS_URL_PREFIX: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/api.php/areas/';
/** 区域可预约日/时段（areadays/{sectionId}） */
const LIBRARY_DAYS_URL_PREFIX: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/api.php/areadays/';
/** 座位列表（query string：area/segment/day/startTime/endTime） */
const LIBRARY_SEATS_URL: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/api.php/spaces_old';
/** 我的预约记录页（HTML 表格） */
const LIBRARY_BOOKING_RECORDS_URL: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/user/index/book';
/** 预约座位（POST 表单：api.php/spaces/{seatId}/book） */
const LIBRARY_BOOK_URL_PREFIX: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/api.php/spaces/';
const LIBRARY_BOOK_URL_SUFFIX: string = '/book';
/** 取消预约（POST 表单：api.php/profile/books/{bookingId}；表单含 _method=delete） */
const LIBRARY_CANCEL_URL_PREFIX: string = WEBVPN_BASE + '/https/' + LIB_TOKEN + '/api.php/profile/books/';
/** 访问令牌内存缓存有效期（约 5 分钟；对齐参考实现） */
const ACCESS_TOKEN_CACHE_MS: number = 5 * 60 * 1000;

// ============================================================
// 模块级辅助
// ============================================================

function pad(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

/** 日期路径格式 YYYY-MM-DD（choice：0=今天 1=明天；路径带横杠，非 YYYYMMDD） */
export function dateForChoice(choice: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + choice);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** 今天场景起始时间取"当前时刻或更晚"（避免请求已过去的时段） */
function currentTimeOrLater(coerce: string): string {
  const d: Date = new Date();
  const now: string = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  return coerce > now ? coerce : now;
}

/** query string 拼接（键值均 percent-encode） */
function qs(params: Record<string, string | number>): string {
  const parts: string[] = [];
  const keys: string[] = Object.keys(params);
  for (let i: number = 0; i < keys.length; i++) {
    parts.push(encodeURIComponent(keys[i]) + '=' + encodeURIComponent(String(params[keys[i]])));
  }
  return parts.join('&');
}

/** Object → Record（非对象返回空表，调用方各自兜底） */
function asRecord(value: Object | undefined): Record<string, Object> {
  if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, Object>;
  }
  const empty: Record<string, Object> = {};
  return empty;
}

/** Object → 对象数组（非数组返回空数组） */
function asObjectArray(value: Object | undefined): Record<string, Object>[] {
  if (value !== undefined && value !== null && Array.isArray(value)) {
    return value as Record<string, Object>[];
  }
  const empty: Record<string, Object>[] = [];
  return empty;
}

/** JSON 字段 → 数字（null/undefined/非法 → 0） */
function numOf(value: Object | undefined): number {
  if (value === undefined || value === null) {
    return 0;
  }
  const n: number = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/** JSON 字段 → 字符串（null/undefined → ''） */
function strOf(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

/** 写接口 status 字段 → 数字（缺失/非法 → -1，对齐参考实现 ?? -1；status===0 才视为成功） */
function numOfOrMinusOne(value: Object | undefined): number {
  if (value === undefined || value === null) {
    return -1;
  }
  const n: number = Number(value);
  return Number.isFinite(n) ? n : -1;
}

/** 失败文本是否命中令牌失效关键字（token/令牌/过期/invalid，忽略大小写；对齐参考实现） */
function isTokenFailureText(msg: string): boolean {
  return /token|令牌|过期|invalid/i.test(msg);
}

/** 座位状态 → 中文标签（1=可用 6=已预约 7=已被占用 其他=不可用；未知值安全回退） */
export function seatStatusLabel(status: number): string {
  if (status === 1) {
    return '可用';
  }
  if (status === 6) {
    return '已预约';
  }
  if (status === 7) {
    return '已被占用';
  }
  return '不可用';
}

/** areadays 的 startTime/endTime 字段可能是 {date: 'YYYY-MM-DD HH:MM:SS'} 或字符串 */
function extractSegmentTime(field: Object | undefined): string {
  if (field === undefined || field === null) {
    return '';
  }
  if (typeof field === 'object' && !Array.isArray(field)) {
    const rec: Record<string, Object> = field as Record<string, Object>;
    return strOf(rec['date']);
  }
  return String(field);
}

/** 'YYYY-MM-DD HH:MM:SS' → 'HH:MM'；短串原样返回（对齐原项目 transform） */
function toHHmm(value: string): string {
  return value.length >= 16 ? value.substring(11, 16) : value;
}

/** 预约记录单元格常用 HTML 实体解码（&amp; 最后，避免二次解码） */
function decodeBasicEntities(value: string): string {
  let out: string = value.replace(/&nbsp;/g, ' ');
  out = out.replace(/&lt;/g, '<');
  out = out.replace(/&gt;/g, '>');
  out = out.replace(/&quot;/g, '"');
  out = out.replace(/&#39;/g, "'");
  out = out.replace(/&amp;/g, '&');
  return out;
}

/** 去 HTML 标签 + 实体解码 + 空白压缩 */
function cellText(html: string): string {
  return decodeBasicEntities(html.replace(/<[^>]+>/g, '')).replace(/\s+/g, ' ').trim();
}

/**
 * <tr> 子节点序列解析（对齐 cheerio children 语义：标签间文本节点占一席，
 * 与 CampusDataService.parseGradeRowChildren 同构）。
 */
function parseTrChildren(trHtml: string): string[] {
  const children: string[] = [];
  const cleaned: string = trHtml.replace(/<!--[\s\S]*?-->/g, '');
  const tagRe: RegExp = /<(t[dh])[^>]*>([\s\S]*?)<\/\1>/gi;
  let lastEnd: number = 0;
  let m: RegExpExecArray | null = tagRe.exec(cleaned);
  while (m !== null) {
    if (m.index > lastEnd) {
      children.push(cellText(cleaned.substring(lastEnd, m.index)));
    }
    children.push(cellText(m[2]));
    lastEnd = m.index + m[0].length;
    m = tagRe.exec(cleaned);
  }
  return children;
}

/**
 * 解析预约记录页 <tbody><tr> 行（对齐原项目 childText(row, 3/5/7/11)）：
 * id=编号 pos=位置 time=时间 status=状态；空行（无编号/位置/时间）过滤。
 * 取消标识：行内 menuDel('…') onclick 提取取消 id（对齐参考 delMatch）；无则不可取消。
 */
function parseBookingRecords(html: string): LibraryBookingRecord[] {
  const records: LibraryBookingRecord[] = [];
  const tbodyMatch: RegExpExecArray | null = /<tbody[^>]*>([\s\S]*?)<\/tbody>/i.exec(html);
  if (tbodyMatch === null) {
    return records;
  }
  const trRe: RegExp = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
  let trm: RegExpExecArray | null = trRe.exec(tbodyMatch[1]);
  while (trm !== null) {
    const children: string[] = parseTrChildren(trm[1]);
    if (children.length >= 4) {
      const rec: LibraryBookingRecord = new LibraryBookingRecord();
      rec.id = children.length > 3 ? children[3] : '';
      rec.pos = children.length > 5 ? children[5] : '';
      rec.time = children.length > 7 ? children[7] : '';
      rec.status = children.length > 11 ? children[11] : '';
      // 可取消标识：行内 menuDel('…') onclick 的第一个引号参数（无该标识 → 不可取消）
      const delMatch: RegExpExecArray | null = /menuDel\('(.+?)'/.exec(trm[1]);
      rec.cancelId = delMatch !== null ? delMatch[1] : '';
      if (rec.id.length > 0 || rec.pos.length > 0 || rec.time.length > 0) {
        records.push(rec);
      }
    }
    trm = trRe.exec(tbodyMatch[1]);
  }
  return records;
}

// ============================================================
// 数据模型（全字段非可选默认值）
// ============================================================

/** 图书馆（顶层） */
export class LibraryInfo {
  id: number = 0;
  zhName: string = '';
  enName: string = '';
  /** 是否开放（isValid === 1） */
  valid: boolean = false;
}

/** 楼层：自身无总数，total/available 由下属开放区域聚合 */
export class LibraryFloorInfo {
  id: number = 0;
  parentId: number = 0;
  zhName: string = '';
  enName: string = '';
  valid: boolean = false;
  total: number = 0;
  available: number = 0;
}

/** 区域：有座位、可下单的最小单位 */
export class LibrarySectionInfo {
  id: number = 0;
  zhName: string = '';
  enName: string = '';
  valid: boolean = false;
  total: number = 0;
  available: number = 0;
  reservedCount: number = 0;
}

/** 座位（status：1=可用 6=已预约 7=已被占用 其他=不可用） */
export class LibrarySeatInfo {
  id: number = 0;
  name: string = '';
  status: number = 0;
  type: number = 0;
}

/** 我的预约记录（cancelId 非空 → 可发起取消；空串 → 不可取消，不提供取消动作） */
export class LibraryBookingRecord {
  id: string = '';
  pos: string = '';
  time: string = '';
  status: string = '';
  /** 取消标识（行内 menuDel('…') 解析；空串表示不可取消） */
  cancelId: string = '';
}

/** 区域可预约日时段（areadays 命中目标日期的那天；读写共用） */
export class LibraryDaySegment {
  day: string = '';
  startTime: string = '';
  endTime: string = '';
  segmentId: string = '';
  today: boolean = false;
}

/** 预约/取消写接口结果（status === 0 视为成功；失败文本命中令牌关键字 → tokenExpired） */
export class LibraryBookResult {
  status: number = -1;
  msg: string = '';
  /** 仅服务内部重试用；调用方以 status === 0 判定成功 */
  tokenExpired: boolean = false;
}

// ============================================================
// 服务
// ============================================================

export class LibrarySeatService {
  private http: HttpClient;
  private auth: TsinghuaAuthService;
  /** 图书馆座院子系统会话是否已通过 id-roam 建立 */
  private libAccessEnsured: boolean = false;
  /** 访问令牌内存缓存值（禁止输出到日志/错误文本，FR-019） */
  private accessTokenValue: string = '';
  /** 访问令牌缓存时间戳（有效期约 5 分钟） */
  private accessTokenTs: number = 0;
  /** 最近一次座位查询解析到的目标日时段（预约确认框展示时段用） */
  private lastDaySegment: LibraryDaySegment | undefined = undefined;

  constructor(http: HttpClient, auth: TsinghuaAuthService) {
    this.http = http;
    this.auth = auth;
  }

  /**
   * 会话瞬态复位（SessionManager.resetSessionState() 统一扇出调用）：
   * 清图书馆座院子系统"已确保"标志、访问令牌缓存（值/时间戳）与最近
   * 时段缓存，避免进程内"退出→再登录"复用上一会话的陈旧令牌/时段。
   * 契约：无参、同步、幂等、不抛；仅清本服务进程内瞬态态，
   * 不触及 Cookie/凭证/网络。
   */
  resetSessionState(): void {
    this.libAccessEnsured = false;
    this.accessTokenValue = '';
    this.accessTokenTs = 0;
    this.lastDaySegment = undefined;
  }

  /** 建立图书馆座院子系统会话（id-roam + 子系统首页 GET 失败忽略）；force 强制重漫游 */
  private async ensureLibraryAccess(force: boolean): Promise<void> {
    if (this.libAccessEnsured && !force) {
      return;
    }
    await this.auth.roamIdSubsystem(LIB_SEAT_YYFWID);
    try {
      await this.http.get(LIB_HOME_URL);
    } catch (e) {
      // home 偶发 500，忽略（对齐原项目）
    }
    this.libAccessEnsured = true;
    Log.i('LibrarySeat', 'LIB_ACCESS ensured force=%{public}s', force ? '1' : '0');
  }

  /** 图书馆接口统一两层会话兜底（reroam = 标记复位 + 强制重漫游；label 'lib'） */
  private async withLibRetry<T>(operation: () => Promise<T>): Promise<T> {
    return this.auth.withSessionRecovery<T>(operation, async (): Promise<void> => {
      this.libAccessEnsured = false;
      await this.ensureLibraryAccess(true);
    }, 'lib');
  }

  /** 统一 JSON 解析：非 JSON → 可读错误；失败标记（status 为 false/'false'）→ 抛服务端 msg */
  private async libFetchJson(url: string): Promise<Record<string, Object>> {
    const resp: HttpResponse = await this.http.get(url);
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(resp.body) as Record<string, Object>;
    } catch (e) {
      throw new Error('图书馆接口响应非 JSON: ' + resp.body.substring(0, 80));
    }
    const statusVal: Object | undefined = parsed['status'];
    if (statusVal !== undefined && String(statusVal) === 'false') {
      const msg: Object | undefined = parsed['msg'];
      throw new Error(msg !== undefined && msg !== null && String(msg).length > 0
        ? String(msg) : '图书馆接口返回失败');
    }
    return parsed;
  }

  /** 统一列表解析：取 data.list（缺失抛可读错误）；list 形状（对象含 childArea / 数组）由调用方各自归一 */
  private async libFetchList(url: string): Promise<Object> {
    const parsed: Record<string, Object> = await this.libFetchJson(url);
    const data: Record<string, Object> = asRecord(parsed['data']);
    const list: Object | undefined = data['list'];
    if (list === undefined || list === null) {
      throw new Error('图书馆接口缺少列表数据（URL: ' + url.substring(url.length - 60) + '）');
    }
    return list;
  }

  /** 图书馆列表（顶层） */
  async getLibraryList(): Promise<LibraryInfo[]> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibraryInfo[]> => {
      return this.doGetLibraryList();
    });
  }

  private async doGetLibraryList(): Promise<LibraryInfo[]> {
    const list: Object = await this.libFetchList(LIBRARY_LIST_URL);
    const rows: Record<string, Object>[] = asObjectArray(list);
    const result: LibraryInfo[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const n: Record<string, Object> = rows[i];
      const lib: LibraryInfo = new LibraryInfo();
      lib.id = numOf(n['id']);
      lib.zhName = strOf(n['name']);
      lib.enName = strOf(n['enname']);
      lib.valid = numOf(n['isValid']) === 1;
      result.push(lib);
    }
    Log.i('LibrarySeat', 'LIB_LIST count=%{public}d', result.length);
    return result;
  }

  /**
   * 楼层列表 + 使用率聚合：
   *   1. 取馆下楼层（areas/{libraryId} 的 childArea）；
   *   2. 仅对开放（isValid===1）楼层**并发**拉取其区域并聚合 total/available；
   *   3. 单层失败容错为 0 不阻塞其余；未开放层不发请求。
   */
  async getLibraryFloorList(libraryId: number, dateChoice: number): Promise<LibraryFloorInfo[]> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibraryFloorInfo[]> => {
      return this.doGetLibraryFloorList(libraryId, dateChoice);
    });
  }

  private async doGetLibraryFloorList(libraryId: number, dateChoice: number): Promise<LibraryFloorInfo[]> {
    const root: Record<string, Object> = asRecord(await this.libFetchList(
      LIBRARY_AREAS_URL_PREFIX + String(libraryId)));
    const rawFloors: Record<string, Object>[] = asObjectArray(root['childArea']);
    const floors: LibraryFloorInfo[] = [];
    const tasks: Promise<void>[] = [];
    for (let i: number = 0; i < rawFloors.length; i++) {
      const n: Record<string, Object> = rawFloors[i];
      const floor: LibraryFloorInfo = new LibraryFloorInfo();
      floor.id = numOf(n['id']);
      floor.parentId = libraryId;
      floor.zhName = strOf(n['name']);
      floor.enName = strOf(n['enname']);
      floor.valid = numOf(n['isValid']) === 1;
      floors.push(floor);
      if (floor.valid) {
        // 并发启动（不逐个 await）；aggregateFloorUsage 内部容错不抛
        tasks.push(this.aggregateFloorUsage(floor, dateChoice));
      }
    }
    for (let i: number = 0; i < tasks.length; i++) {
      await tasks[i];
    }
    Log.i('LibrarySeat', 'FLOOR_LIST lib=%{public}d floors=%{public}d', libraryId, floors.length);
    return floors;
  }

  /** 单楼层使用率聚合：开放区域求和 total/available；失败置 0 不阻塞其余楼层 */
  private async aggregateFloorUsage(floor: LibraryFloorInfo, dateChoice: number): Promise<void> {
    try {
      const sections: LibrarySectionInfo[] = await this.getLibrarySectionList(floor.id, dateChoice);
      let total: number = 0;
      let available: number = 0;
      for (let i: number = 0; i < sections.length; i++) {
        if (sections[i].valid) {
          total += sections[i].total;
          available += sections[i].available;
        }
      }
      floor.total = total;
      floor.available = available;
    } catch (e) {
      // 单层失败容错为 0（对齐原项目）
    }
  }

  /** 区域列表（楼层下）：available = max(0, TotalCount - UnavailableSpace) */
  async getLibrarySectionList(floorId: number, dateChoice: number): Promise<LibrarySectionInfo[]> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibrarySectionInfo[]> => {
      return this.doGetLibrarySectionList(floorId, dateChoice);
    });
  }

  private async doGetLibrarySectionList(floorId: number, dateChoice: number): Promise<LibrarySectionInfo[]> {
    const date: string = dateForChoice(dateChoice);
    const url: string = LIBRARY_AREAS_URL_PREFIX + String(floorId) + '/date/' + date;
    const root: Record<string, Object> = asRecord(await this.libFetchList(url));
    const raw: Record<string, Object>[] = asObjectArray(root['childArea']);
    const result: LibrarySectionInfo[] = [];
    for (let i: number = 0; i < raw.length; i++) {
      const n: Record<string, Object> = raw[i];
      const section: LibrarySectionInfo = new LibrarySectionInfo();
      section.id = numOf(n['id']);
      section.zhName = strOf(n['name']);
      section.enName = strOf(n['enname']);
      section.valid = numOf(n['isValid']) === 1;
      section.total = numOf(n['TotalCount']);
      const unavail: number = numOf(n['UnavailableSpace']);
      section.available = Math.max(0, section.total - unavail);
      section.reservedCount = numOf(n['area_reserve_count']);
      result.push(section);
    }
    Log.i('LibrarySeat', 'SECTION_LIST floor=%{public}d count=%{public}d', floorId, result.length);
    return result;
  }

  /**
   * 取目标日时段（areadays/{sectionId} 命中 dateForChoice(dateChoice) 的那天）：
   * 得到时段 id（segment）与起止时间；startTime/endTime 兼容 {date} 对象或字符串。
   */
  private async getLibraryDay(sectionId: number, dateChoice: number): Promise<LibraryDaySegment> {
    const list: Object = await this.libFetchList(LIBRARY_DAYS_URL_PREFIX + String(sectionId));
    const rows: Record<string, Object>[] = asObjectArray(list);
    const target: string = dateForChoice(dateChoice);
    let hit: Record<string, Object> | undefined = undefined;
    for (let i: number = 0; i < rows.length; i++) {
      if (strOf(rows[i]['day']) === target) {
        hit = rows[i];
        break;
      }
    }
    if (hit === undefined) {
      throw new Error('未找到 ' + target + ' 的预约时段');
    }
    const day: LibraryDaySegment = new LibraryDaySegment();
    day.day = strOf(hit['day']);
    day.startTime = toHHmm(extractSegmentTime(hit['startTime']));
    day.endTime = toHHmm(extractSegmentTime(hit['endTime']));
    day.segmentId = strOf(hit['id']);
    day.today = dateChoice === 0;
    return day;
  }

  /**
   * 座位列表 + 状态：先取目标日时段（今天起始时间钳制为"当前时刻或更晚"），
   * 再 spaces_old?area&segment&day&startTime&endTime 查座位（id/name/status/area_type）。
   */
  async getLibrarySeatList(sectionId: number, dateChoice: number): Promise<LibrarySeatInfo[]> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibrarySeatInfo[]> => {
      return this.doGetLibrarySeatList(sectionId, dateChoice);
    });
  }

  private async doGetLibrarySeatList(sectionId: number, dateChoice: number): Promise<LibrarySeatInfo[]> {
    const dayInfo: LibraryDaySegment = await this.getLibraryDay(sectionId, dateChoice);
    this.lastDaySegment = dayInfo;
    const params: Record<string, string | number> = {
      'area': sectionId,
      'segment': dayInfo.segmentId,
      'day': dayInfo.day,
      'startTime': dayInfo.today ? currentTimeOrLater(dayInfo.startTime) : dayInfo.startTime,
      'endTime': dayInfo.endTime,
    };
    const list: Object = await this.libFetchList(LIBRARY_SEATS_URL + '?' + qs(params));
    const rows: Record<string, Object>[] = asObjectArray(list);
    const result: LibrarySeatInfo[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const n: Record<string, Object> = rows[i];
      const seat: LibrarySeatInfo = new LibrarySeatInfo();
      seat.id = numOf(n['id']);
      const name: string = strOf(n['name']);
      seat.name = name.length > 0 ? name : '#' + String(seat.id);
      seat.status = numOf(n['status']);
      seat.type = numOf(n['area_type']);
      result.push(seat);
    }
    Log.i('LibrarySeat', 'SEAT_LIST section=%{public}d count=%{public}d', sectionId, result.length);
    return result;
  }

  /** 我的预约记录（user/index/book HTML 表格解析；整体包 withLibRetry，会话失效自动恢复） */
  async getLibraryBookingRecords(): Promise<LibraryBookingRecord[]> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibraryBookingRecord[]> => {
      return this.doGetLibraryBookingRecords();
    });
  }

  private async doGetLibraryBookingRecords(): Promise<LibraryBookingRecord[]> {
    const resp: HttpResponse = await this.http.get(LIBRARY_BOOKING_RECORDS_URL);
    Log.i('LibrarySeat', 'BOOKING_RECORDS code=%{public}d len=%{public}d', resp.statusCode, resp.body.length);
    const records: LibraryBookingRecord[] = parseBookingRecords(resp.body);
    if (records.length === 0 && resp.body.indexOf('tbody') < 0) {
      throw new Error('未能加载图书馆预约记录');
    }
    return records;
  }

  // ============================================================
  // 写操作（预约 / 取消；对齐参考实现 getLibraryAccessToken / bookLibrarySeat / cancelLibraryBooking）
  // ============================================================

  /**
   * 最近一次座位查询的目标日时段（供预约确认框展示时段；尚未查询过返回 undefined）。
   * 仅供展示；预约提交以 bookLibrarySeat 内部重新解析的时段为准。
   */
  getLastDaySegment(): LibraryDaySegment | undefined {
    return this.lastDaySegment;
  }

  /**
   * 访问令牌：自图书馆主页 HTML 中 "access_token" 后第一对引号内字符串抓取；
   * 内存缓存约 5 分钟（force=true 跳过缓存强制刷新）。
   * 令牌禁止输出到日志/错误文本（FR-019）。
   */
  async getLibraryAccessToken(force?: boolean): Promise<string> {
    const now: number = Date.now();
    const skipCache: boolean = force === undefined ? false : force;
    if (!skipCache && this.accessTokenValue.length > 0
      && now - this.accessTokenTs < ACCESS_TOKEN_CACHE_MS) {
      return this.accessTokenValue;
    }
    await this.ensureLibraryAccess(false);
    const resp: HttpResponse = await this.http.get(LIB_HOME_URL);
    const html: string = resp.body;
    const left: number = html.indexOf('access_token');
    if (left < 0) {
      throw new Error('图书馆主页未包含访问令牌字段');
    }
    const quoteStart: number = html.indexOf('"', left);
    if (quoteStart < 0) {
      throw new Error('图书馆主页访问令牌格式异常');
    }
    const quoteEnd: number = html.indexOf('"', quoteStart + 1);
    if (quoteEnd < 0) {
      throw new Error('图书馆主页访问令牌格式异常');
    }
    const token: string = html.substring(quoteStart + 1, quoteEnd).trim();
    if (token.length === 0) {
      throw new Error('图书馆主页访问令牌为空');
    }
    this.accessTokenValue = token;
    this.accessTokenTs = now;
    // 仅记录长度，禁止输出令牌明文（FR-019）
    Log.i('LibrarySeat', 'ACCESS_TOKEN refreshed len=%{public}d force=%{public}s',
      token.length, skipCache ? '1' : '0');
    return token;
  }

  /**
   * 预约座位：取目标日时段 → POST 表单 {access_token, userid, segment, type, operateChannel='2'}；
   * 响应 JSON status===0 视为成功；失败文本命中令牌关键字 → 强制刷新令牌重试一次；
   * 整体包 withLibRetry（两层会话恢复，label 'lib'）。
   */
  async bookLibrarySeat(sectionId: number, seatId: number, seatType: number, dateChoice: number):
    Promise<LibraryBookResult> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibraryBookResult> => {
      return this.doBookLibrarySeat(sectionId, seatId, seatType, dateChoice);
    });
  }

  private async doBookLibrarySeat(sectionId: number, seatId: number, seatType: number,
    dateChoice: number): Promise<LibraryBookResult> {
    const creds: CampusCredentials = await this.auth.getRoamCredentials();
    const dayInfo: LibraryDaySegment = await this.getLibraryDay(sectionId, dateChoice);
    const token: string = await this.getLibraryAccessToken();
    const first: LibraryBookResult = await this.postBook(seatId, seatType, creds.studentId,
      dayInfo.segmentId, token);
    if (first.tokenExpired) {
      // 令牌失效自愈：强制刷新令牌后重试一次（SC-011）
      const freshToken: string = await this.getLibraryAccessToken(true);
      return this.postBook(seatId, seatType, creds.studentId, dayInfo.segmentId, freshToken);
    }
    return first;
  }

  /** 单次预约提交（POST 表单；不重试） */
  private async postBook(seatId: number, seatType: number, userid: string, segment: string,
    token: string): Promise<LibraryBookResult> {
    const form: Record<string, string> = {
      'access_token': token,
      'userid': userid,
      'segment': segment,
      'type': String(seatType),
      'operateChannel': '2',
    };
    const url: string = LIBRARY_BOOK_URL_PREFIX + String(seatId) + LIBRARY_BOOK_URL_SUFFIX;
    const resp: HttpResponse = await this.http.postForm(url, form);
    const result: LibraryBookResult = this.parseWriteResult(resp.body, '预约');
    // 日志只记录座位与状态码，禁止输出表单（含令牌）与服务端原始文本（FR-019）
    Log.i('LibrarySeat', 'LIB_BOOK seat=%{public}d status=%{public}d', seatId, result.status);
    return result;
  }

  /**
   * 取消预约：POST 表单 {_method='delete', id, userid, access_token, operateChannel='2'}；
   * 令牌失效自动刷新重试一次；整体包 withLibRetry（两层会话恢复，label 'lib'）。
   */
  async cancelLibraryBooking(bookingId: string): Promise<LibraryBookResult> {
    await this.ensureLibraryAccess(false);
    return this.withLibRetry((): Promise<LibraryBookResult> => {
      return this.doCancelLibraryBooking(bookingId);
    });
  }

  private async doCancelLibraryBooking(bookingId: string): Promise<LibraryBookResult> {
    const creds: CampusCredentials = await this.auth.getRoamCredentials();
    const token: string = await this.getLibraryAccessToken();
    const first: LibraryBookResult = await this.postCancel(bookingId, creds.studentId, token);
    if (first.tokenExpired) {
      // 令牌失效自愈：强制刷新令牌后重试一次（SC-011）
      const freshToken: string = await this.getLibraryAccessToken(true);
      return this.postCancel(bookingId, creds.studentId, freshToken);
    }
    return first;
  }

  /** 单次取消提交（POST 表单；不重试） */
  private async postCancel(bookingId: string, userid: string, token: string): Promise<LibraryBookResult> {
    const form: Record<string, string> = {
      '_method': 'delete',
      'id': bookingId,
      'userid': userid,
      'access_token': token,
      'operateChannel': '2',
    };
    const url: string = LIBRARY_CANCEL_URL_PREFIX + bookingId;
    const resp: HttpResponse = await this.http.postForm(url, form);
    const result: LibraryBookResult = this.parseWriteResult(resp.body, '取消');
    // 日志只记录结果状态码，禁止输出表单（含令牌）与服务端原始文本（FR-019）
    Log.i('LibrarySeat', 'LIB_CANCEL status=%{public}d', result.status);
    return result;
  }

  /** 写接口响应解析：非 JSON → 可读错误；status===0 成功；失败文本命中令牌关键字 → tokenExpired */
  private parseWriteResult(body: string, opLabel: string): LibraryBookResult {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(body) as Record<string, Object>;
    } catch (e) {
      throw new Error(opLabel + '接口响应非 JSON: ' + body.substring(0, 80));
    }
    const result: LibraryBookResult = new LibraryBookResult();
    result.status = numOfOrMinusOne(parsed['status']);
    result.msg = strOf(parsed['msg']);
    if (result.status !== 0 && isTokenFailureText(result.msg)) {
      result.tokenExpired = true;
    }
    return result;
  }
}
