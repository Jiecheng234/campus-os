/**
 * ============================================================================
 * LibraryRoomService — 研读间只读查询（类型 → 近 5 天 → 资源 + 我的预约）
 * ============================================================================
 *
 * 对齐原项目 src/services/campus/library.ts（thu-info-lib library.ts cab 部分）：
 *   - 会话：研读间专用登录 cabLogin（认证服务）+ cabLoginEnsured 标记 + accNo 缓存
 *     + assureCabSession 两轮复查（失败强制重登后再查，仍失败抛可读错误）
 *     + withCabRetry 两层恢复（reroam = 标记复位 + 强制 cabLogin，label 'cab'）。
 *   - 接口：ic-web 纯 JSON（业务码非 0 → 抛服务端 message；非 JSON → 可读错误附截断片段）。
 *   - 日期：近 5 天（今天起偏移 0–4）；展示 YYYY-MM-DD、请求 yyyyMMdd；
 *     "我的预约"查询窗口"今天 → +6 天"（YYYY-MM-DD 查询参数）。
 *
 * 只读浏览；预约/取消不迁移（完整下单走清华师生大厅小程序）。
 * ============================================================================
 */
import { HttpClient, HttpResponse } from '../HttpClient';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { Log } from '../../utils/Logger';

const WEBVPN_BASE: string = 'https://webvpn.tsinghua.edu.cn';
/** 研读间 webvpn token（对齐原项目 LIB_ROOM_TOKEN / ROOM_BOOKING_TOKEN） */
const ROOM_BOOKING_TOKEN: string = '77726476706e69737468656265737421f3f643d22b396a1e6a1b80a29f5d363409e413829737d1';
/** 房间类型（对齐原项目 LIBRARY_ROOM_BOOKING_ROOM_INFO_URL） */
const ROOM_KIND_URL: string = WEBVPN_BASE + '/https/' + ROOM_BOOKING_TOKEN + '/ic-web/roomDevice/roomInfos';
/** 资源列表（对齐原项目 LIBRARY_ROOM_BOOKING_RESOURCE_LIST_URL，追加 resvDates/kindIds 查询参数） */
const ROOM_RESOURCE_URL: string = WEBVPN_BASE + '/https/' + ROOM_BOOKING_TOKEN + '/ic-web/reserve?sysKind=1';
/** 我的预约（对齐原项目 LIBRARY_ROOM_BOOKING_RECORD_URL，追加 beginDate/endDate 查询参数） */
const ROOM_RECORD_URL: string = WEBVPN_BASE + '/https/' + ROOM_BOOKING_TOKEN
  + '/ic-web/reserve/resvInfo?needStatus=8454&orderKey=gmt_create&orderModel=desc';
/** 用户信息（对齐原项目 LIBRARY_ROOM_BOOKING_USER_INFO_URL；会话复查比对学号用） */
const ROOM_USER_INFO_URL: string = WEBVPN_BASE + '/https/' + ROOM_BOOKING_TOKEN + '/ic-web/auth/userInfo';

// ============================================================
// 模块级辅助
// ============================================================

function pad(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

/** 展示用日期 YYYY-MM-DD（offsetDays：0=今天） */
export function formatLibRoomDateIso(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
}

/** 请求用日期 yyyyMMdd（offsetDays：0=今天） */
export function formatLibRoomDateYmd(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  return String(d.getFullYear()) + pad(d.getMonth() + 1) + pad(d.getDate());
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

/** 学号打码（前 2 + *** + 后 2；空值 → (empty)） */
function maskId(value: string): string {
  return value.length > 0 ? value.substring(0, 2) + '***' + value.substring(value.length - 2) : '(empty)';
}

/** 'YYYY-MM-DD HH:MM:SS' → 'MM-DD HH:MM'；短串原样返回 */
function formatRoomTimeText(value: string): string {
  if (value.length >= 16 && value.charAt(4) === '-') {
    return value.substring(5, 16);
  }
  return value;
}

// ============================================================
// 数据模型（全字段非可选默认值）
// ============================================================

/** 类型下房间简述 */
export class LibRoomBrief {
  devId: number = 0;
  devName: string = '';
  minReserveMinute: number = 0;
}

/** 研读间类型（含房间数与房间简述） */
export class LibRoomKind {
  kindId: number = 0;
  kindName: string = '';
  roomCount: number = 0;
  rooms: LibRoomBrief[] = [];
}

/** 某类型某天的可预约资源 */
export class LibRoomResource {
  devId: number = 0;
  devName: string = '';
  kindId: number = 0;
  kindName: string = '';
  labId: number = 0;
  labName: string = '';
  roomId: number = 0;
  roomName: string = '';
  limitCount: number = 0;
  maxMinute: number = 0;
  minMinute: number = 0;
  cancelMinute: number = 0;
  maxUser: number = 0;
  minUser: number = 0;
  openStart: string = '';
  openEnd: string = '';
  /** 当日占用条数（明细不展示） */
  usageCount: number = 0;
}

/** 我的预约记录（只读展示；不支持取消） */
export class LibRoomBookRecord {
  uuid: string = '';
  rsvId: number = 0;
  owner: string = '';
  ownerId: string = '';
  date: string = '';
  beginText: string = '';
  endText: string = '';
  devName: string = '';
  kindName: string = '';
  /** 成员名拼接（顿号分隔） */
  membersText: string = '';
}

/** 研读间用户信息（会话复查：pid 与学号比对） */
export class LibRoomUserInfo {
  pid: string = '';
  accNo: number = 0;
}

// ============================================================
// 服务
// ============================================================

export class LibraryRoomService {
  private http: HttpClient;
  private auth: TsinghuaAuthService;
  /** 研读间 cab 会话是否已建立（cabLogin + 账号校验通过） */
  private cabLoginEnsured: boolean = false;
  /** 研读间账号号缓存（-1 = 未取得） */
  private cabAccNo: number = -1;

  constructor(http: HttpClient, auth: TsinghuaAuthService) {
    this.http = http;
    this.auth = auth;
  }

  /** 建立研读间 cab 会话（认证服务 cabLogin + 标记）；force 强制重登 */
  private async ensureCabLogin(force: boolean): Promise<void> {
    if (this.cabLoginEnsured && !force) {
      return;
    }
    await this.auth.cabLogin();
    this.cabLoginEnsured = true;
    Log.i('LibraryRoom', 'CAB_LOGIN ensured force=%{public}s', force ? '1' : '0');
  }

  /** 研读间读取统一两层会话兜底（reroam = 标记复位 + 强制 cabLogin；label 'cab'） */
  private async withCabRetry<T>(operation: () => Promise<T>): Promise<T> {
    return this.auth.withSessionRecovery<T>(operation, async (): Promise<void> => {
      this.cabLoginEnsured = false;
      this.cabAccNo = -1;
      await this.ensureCabLogin(true);
    }, 'cab');
  }

  /**
   * 会话复查（对齐参考 assureCabSession）：标记 + 账号号缓存命中则直接返回；
   * 否则最多两轮——每轮 ensureCabLogin（第二轮强制）→ 读用户信息比对学号；
   * 成功缓存 accNo；失败重置标记再来一轮；仍失败抛可读错误。
   */
  private async assureCabSession(): Promise<void> {
    const studentId: string = (await this.auth.getRoamCredentials()).studentId;
    if (this.cabLoginEnsured && this.cabAccNo !== -1) {
      return;
    }
    let lastError: Error | undefined = undefined;
    for (let attempt: number = 0; attempt < 2; attempt++) {
      try {
        await this.ensureCabLogin(attempt > 0);
        const info: LibRoomUserInfo = await this.fetchUserInfo();
        if (info.pid === studentId) {
          this.cabAccNo = info.accNo;
          return;
        }
        throw new Error('研读间账号不匹配：期望 ' + maskId(studentId)
          + '，实际 ' + maskId(info.pid));
      } catch (e) {
        lastError = e instanceof Error ? e : new Error(String(e));
      }
      this.cabLoginEnsured = false;
      this.cabAccNo = -1;
    }
    const reason: string = lastError !== undefined ? '：' + lastError.message : '';
    throw new Error('研读间会话校验失败' + reason);
  }

  /** 统一 JSON 解析（对齐参考 cabFetch）：非 JSON → 可读错误附截断片段；业务码非 0 → 抛服务端 message */
  private async cabFetch(url: string): Promise<Object | undefined> {
    const resp: HttpResponse = await this.http.get(url);
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(resp.body) as Record<string, Object>;
    } catch (e) {
      throw new Error('研读间接口响应非 JSON: ' + resp.body.substring(0, 80));
    }
    const codeVal: Object | undefined = parsed['code'];
    if (codeVal === undefined || Number(codeVal) !== 0) {
      const msgVal: Object | undefined = parsed['message'];
      const msg: string = msgVal !== undefined && msgVal !== null ? String(msgVal) : '';
      throw new Error(msg.length > 0 ? msg : '研读间接口返回失败');
    }
    return parsed['data'];
  }

  /** 用户信息（pid + accNo；会话复查与账号校验用） */
  private async fetchUserInfo(): Promise<LibRoomUserInfo> {
    const data: Object | undefined = await this.cabFetch(ROOM_USER_INFO_URL);
    const rec: Record<string, Object> = asRecord(data);
    const info: LibRoomUserInfo = new LibRoomUserInfo();
    info.pid = strOf(rec['pid']);
    info.accNo = numOf(rec['accNo']);
    return info;
  }

  /** 研读间类型与下属房间（对齐参考 getLibraryRoomBookingInfoList） */
  async getRoomKindList(): Promise<LibRoomKind[]> {
    return this.withCabRetry((): Promise<LibRoomKind[]> => {
      return this.doGetRoomKindList();
    });
  }

  private async doGetRoomKindList(): Promise<LibRoomKind[]> {
    await this.assureCabSession();
    const data: Object | undefined = await this.cabFetch(ROOM_KIND_URL);
    const rows: Record<string, Object>[] = asObjectArray(data);
    const result: LibRoomKind[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const n: Record<string, Object> = rows[i];
      const kind: LibRoomKind = new LibRoomKind();
      kind.kindId = numOf(n['kindId']);
      kind.kindName = strOf(n['kindName']);
      const roomRows: Record<string, Object>[] = asObjectArray(n['roomInfos']);
      for (let j: number = 0; j < roomRows.length; j++) {
        const r: Record<string, Object> = roomRows[j];
        const brief: LibRoomBrief = new LibRoomBrief();
        brief.devId = numOf(r['devId']);
        brief.devName = strOf(r['devName']);
        brief.minReserveMinute = numOf(r['minResvTime']);
        kind.rooms.push(brief);
      }
      kind.roomCount = kind.rooms.length;
      result.push(kind);
    }
    Log.i('LibraryRoom', 'KIND_LIST count=%{public}d', result.length);
    return result;
  }

  /** 某类型某天的可预约资源（dateYmd：yyyyMMdd；对齐参考 getLibraryRoomBookingResourceList） */
  async getRoomResourceList(dateYmd: string, kindId: number): Promise<LibRoomResource[]> {
    return this.withCabRetry((): Promise<LibRoomResource[]> => {
      return this.doGetRoomResourceList(dateYmd, kindId);
    });
  }

  private async doGetRoomResourceList(dateYmd: string, kindId: number): Promise<LibRoomResource[]> {
    await this.assureCabSession();
    const url: string = ROOM_RESOURCE_URL + '&resvDates=' + dateYmd + '&kindIds=' + String(kindId);
    const data: Object | undefined = await this.cabFetch(url);
    const rows: Record<string, Object>[] = asObjectArray(data);
    const result: LibRoomResource[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const n: Record<string, Object> = rows[i];
      const res: LibRoomResource = new LibRoomResource();
      res.devId = numOf(n['devId']);
      res.devName = strOf(n['devName']);
      res.kindId = numOf(n['kindId']);
      res.kindName = strOf(n['kindName']);
      res.labId = numOf(n['labId']);
      res.labName = strOf(n['labName']);
      res.roomId = numOf(n['roomId']);
      res.roomName = strOf(n['roomName']);
      const rule: Record<string, Object> = asRecord(n['resvRule']);
      res.limitCount = numOf(rule['limit']);
      res.maxMinute = numOf(rule['maxResvTime']);
      res.minMinute = numOf(rule['minResvTime']);
      res.cancelMinute = numOf(rule['cancelTime']);
      res.maxUser = numOf(n['maxUser']);
      res.minUser = numOf(n['minUser']);
      res.openStart = strOf(n['openStart']);
      res.openEnd = strOf(n['openEnd']);
      res.usageCount = asObjectArray(n['resvInfo']).length;
      result.push(res);
    }
    Log.i('LibraryRoom', 'RESOURCE_LIST kind=%{public}d date=%{public}s count=%{public}d',
      kindId, dateYmd, result.length);
    return result;
  }

  /** 我的预约记录（查询窗口"今天 → +6 天"；对齐参考 getLibraryRoomBookingRecord） */
  async getRoomBookingRecords(): Promise<LibRoomBookRecord[]> {
    return this.withCabRetry((): Promise<LibRoomBookRecord[]> => {
      return this.doGetRoomBookingRecords();
    });
  }

  private async doGetRoomBookingRecords(): Promise<LibRoomBookRecord[]> {
    await this.assureCabSession();
    const begin: Date = new Date();
    const end: Date = new Date();
    end.setDate(begin.getDate() + 6);
    const beginDate: string = begin.getFullYear() + '-' + pad(begin.getMonth() + 1) + '-' + pad(begin.getDate());
    const endDate: string = end.getFullYear() + '-' + pad(end.getMonth() + 1) + '-' + pad(end.getDate());
    const url: string = ROOM_RECORD_URL + '&beginDate=' + beginDate + '&endDate=' + endDate;
    const data: Object | undefined = await this.cabFetch(url);
    const rows: Record<string, Object>[] = asObjectArray(data);
    const result: LibRoomBookRecord[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const n: Record<string, Object> = rows[i];
      const rec: LibRoomBookRecord = new LibRoomBookRecord();
      rec.uuid = strOf(n['uuid']);
      rec.rsvId = numOf(n['resvId']);
      rec.owner = strOf(n['resvName']);
      rec.ownerId = strOf(n['logonName']);
      rec.date = strOf(n['resvDate']);
      rec.beginText = formatRoomTimeText(strOf(n['resvBeginTime']));
      rec.endText = formatRoomTimeText(strOf(n['resvEndTime']));
      const devRows: Record<string, Object>[] = asObjectArray(n['resvDevInfoList']);
      if (devRows.length > 0) {
        rec.devName = strOf(devRows[0]['devName']);
        rec.kindName = strOf(devRows[0]['kindName']);
      }
      const memberRows: Record<string, Object>[] = asObjectArray(n['resvMemberInfoList']);
      const names: string[] = [];
      for (let j: number = 0; j < memberRows.length; j++) {
        const name: string = strOf(memberRows[j]['trueName']);
        if (name.length > 0) {
          names.push(name);
        }
      }
      rec.membersText = names.join('、');
      result.push(rec);
    }
    Log.i('LibraryRoom', 'BOOK_RECORDS count=%{public}d', result.length);
    return result;
  }
}
