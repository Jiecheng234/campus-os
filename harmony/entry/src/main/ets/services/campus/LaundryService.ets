/**
 * ============================================================================
 * LaundryService — 宿舍洗衣机只读查询（洁力 / 海乐生活）
 * ============================================================================
 *
 * 对齐原项目 src/services/campus/laundry.ts：
 *   - 数据来源为第三方洗衣平台公开接口，无鉴权、无 Cookie、不依赖登录态
 *     （FR-009）；经统一 HttpClient 直连（get / postJson）。
 *   - 楼宇列表：洁力（tower）与海乐（nearPosition 固定坐标）并发请求，
 *     "部分成功"语义合并——任一平台失败仍返回另一平台；两侧均失败才抛
 *     可读错误（FR-006）。
 *   - 分组：洁力按名称含 紫荆/南区/双清 归入 紫荆公寓/南区宿舍/双清公寓，
 *     其余归"其他位置"；海乐仅保留名称含"清华"者，组名"海乐生活"；
 *     仅保留非空分组；组内楼宇按"数字优先 + 名称"排序。
 *   - 状态：洁力由状态文本映射（待机/空闲→空闲；工作/运转/运行→使用中；
 *     其余→异常），剩余分钟取"剩余…数字"，更新时间取"更新…时间"；
 *     位置映射接口（按楼宇）尽力而为，失败降级不展示位置。
 *     海乐由 state 数值映射（1→空闲、2→使用中、其余→异常），无剩余时间。
 *   - 异常（HTTP 非 2xx / 非 JSON / 平台错误码 / 结构不符）一律转为可读
 *     中文错误（FR-011），不暴露原始异常文本。
 * ============================================================================
 */
import { HttpClient, HttpResponse, JsonBodyValue } from '../HttpClient';
import { Log } from '../../utils/Logger';

// ============================================================
// 端点常量（对齐参考实现 src/services/campus/laundry.ts，逐字移植）
// ============================================================

/** 洁力楼宇列表 */
const JIELI_TOWER_URL: string = 'https://api.cleverschool.cn/washapi4/device/tower';
/** 洁力机台状态（按楼宇） */
const JIELI_STATUS_URL: string = 'https://api.cleverschool.cn/washapi4/device/status';
/** 洁力位置映射（按楼宇查询，返回 名称→位置） */
const JIELI_LOCATION_URL: string = 'https://app.cs.tsinghua.edu.cn/Api/JieliWashers';
/** 海乐生活楼宇（固定坐标检索） */
const HAILE_POSITIONS_URL: string = 'https://yshz-user.haier-ioc.com/position/nearPosition';
/** 海乐生活设备（按位置 + 类目） */
const HAILE_DEVICES_URL: string = 'https://yshz-user.haier-ioc.com/position/deviceDetailPage';

/** 海乐设备类目（code 逐字对齐参考实现 HAILE_CATEGORIES） */
class HaileCategory {
  code: string = '';
  label: string = '';
}

function haileCategoryOf(code: string, label: string): HaileCategory {
  const c: HaileCategory = new HaileCategory();
  c.code = code;
  c.label = label;
  return c;
}

const HAILE_CATEGORIES: HaileCategory[] = [
  haileCategoryOf('00', '洗衣机'),
  haileCategoryOf('01', '洗鞋机'),
  haileCategoryOf('02', '烘干机'),
];

/** 海乐楼宇检索固定坐标（对齐参考实现） */
const HAILE_SEARCH_LNG: number = 116.32697;
const HAILE_SEARCH_LAT: number = 40.00281;

// ============================================================
// 数据模型（全字段非可选默认值）
// ============================================================

/** 洗衣平台：'jieli'（洁力）/ 'haile'（海乐生活） */
export type LaundryPlatform = 'jieli' | 'haile';

/** 机台状态：'idle'（空闲）/ 'working'（使用中）/ 'error'（异常） */
export type LaundryMachineStatus = 'idle' | 'working' | 'error';

/** 楼宇 */
export class LaundryBuilding {
  id: string = '';
  name: string = '';
  platform: LaundryPlatform = 'jieli';
}

/** 楼宇分组（紫荆公寓/南区宿舍/双清公寓/其他位置/海乐生活） */
export class LaundryBuildingGroup {
  name: string = '';
  buildings: LaundryBuilding[] = [];
}

/** 机台（etaMinutes 为 -1 表示无/不适用） */
export class LaundryMachine {
  type: string = '';
  name: string = '';
  floor: string = '';
  status: LaundryMachineStatus = 'error';
  etaMinutes: number = -1;
  updatedAt: string = '';
  location: string = '';
}

/** 楼层 */
export class LaundryFloor {
  name: string = '';
  machines: LaundryMachine[] = [];
}

// ============================================================
// 模块级辅助
// ============================================================

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

/** JSON 字段 → 字符串（null/undefined → ''） */
function asString(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  return String(value);
}

/** JSON 字段 → 数字（缺失/非法 → 0） */
function numOf(value: Object | undefined): number {
  if (value === undefined || value === null) {
    return 0;
  }
  const n: number = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/** 中文数字字符表（对齐参考实现 CHINESE_DIGITS） */
const CHINESE_DIGITS: Record<string, number> = {
  '零': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

/** 单个中文数字字符 → 数值（未命中返回 -1） */
function numOfChineseDigit(ch: string): number {
  const v: number | undefined = CHINESE_DIGITS[ch];
  return v !== undefined ? v : -1;
}

/** 中文数字串 → 整数（'十' 组合支持；无法解析返回 -1；对齐参考实现 chineseNumberToInt） */
function chineseNumberToInt(raw: string): number {
  if (raw.length === 0) {
    return -1;
  }
  if (raw === '十') {
    return 10;
  }
  const tenIndex: number = raw.indexOf('十');
  if (tenIndex >= 0) {
    const left: string = raw.substring(0, tenIndex);
    const right: string = raw.substring(tenIndex + 1);
    const tens: number = left.length > 0 ? numOfChineseDigit(left) : 1;
    const ones: number = right.length > 0 ? numOfChineseDigit(right) : 0;
    if (tens < 0 || ones < 0) {
      return -1;
    }
    return tens * 10 + ones;
  }
  return numOfChineseDigit(raw);
}

/** 提取字符串中的数字序列（阿拉伯与中文数字；对齐参考实现 sortNumbers） */
function sortNumbers(value: string): number[] {
  const result: number[] = [];
  const pattern: RegExp = /\d+|[零一二两三四五六七八九十]+/g;
  const matches: RegExpMatchArray | null = value.match(pattern);
  if (matches === null) {
    return result;
  }
  for (let i: number = 0; i < matches.length; i++) {
    const token: string = matches[i];
    const parsed: number = /^\d+$/.test(token) ? Number(token) : chineseNumberToInt(token);
    if (parsed >= 0) {
      result.push(parsed);
    }
  }
  return result;
}

/** "数字优先 + 名称"排序比较（对齐参考实现 compareByNumberThenName） */
function compareByNumberThenName(a: string, b: string): number {
  const aNums: number[] = sortNumbers(a);
  const bNums: number[] = sortNumbers(b);
  const len: number = Math.min(aNums.length, bNums.length);
  for (let i: number = 0; i < len; i++) {
    const diff: number = aNums[i] - bNums[i];
    if (diff !== 0) {
      return diff;
    }
  }
  if (aNums.length !== bNums.length) {
    return aNums.length - bNums.length;
  }
  if (a === b) {
    return 0;
  }
  return a < b ? -1 : 1;
}

/** 机台比较：位置（或名称）优先，其次类型（对齐参考实现 compareMachines） */
function compareMachines(a: LaundryMachine, b: LaundryMachine): number {
  const left: string = a.location.length > 0 ? a.location : a.name;
  const right: string = b.location.length > 0 ? b.location : b.name;
  const byLocation: number = compareByNumberThenName(left, right);
  if (byLocation !== 0) {
    return byLocation;
  }
  return compareByNumberThenName(a.type, b.type);
}

/** 当前时间 HH:mm:ss（海乐机台更新时间用，避免依赖 Intl） */
function pad2(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

function nowTimeText(): string {
  const d: Date = new Date();
  return pad2(d.getHours()) + ':' + pad2(d.getMinutes()) + ':' + pad2(d.getSeconds());
}

/** 洁力状态文本解析结果（status + 剩余分钟 + 更新时间） */
class JieliStatusParse {
  status: LaundryMachineStatus = 'error';
  etaMinutes: number = -1;
  updatedAt: string = '';
}

/** 洁力状态文本解析（对齐参考实现 parseJieliStatus） */
function parseJieliStatus(rawStatus: string): JieliStatusParse {
  const result: JieliStatusParse = new JieliStatusParse();
  if (/待机|空闲/.test(rawStatus)) {
    result.status = 'idle';
  } else if (/工作|运转|运行/.test(rawStatus)) {
    result.status = 'working';
  } else {
    result.status = 'error';
  }
  const eta: RegExpMatchArray | null = rawStatus.match(/剩余\D*(\d+)/);
  if (eta !== null && eta.length >= 2) {
    result.etaMinutes = Number(eta[1]);
  }
  let updated: RegExpMatchArray | null = rawStatus.match(/更新[:：]?\s*([0-9./-]+\s+[0-9:]+)/);
  if (updated === null || updated.length < 2) {
    updated = rawStatus.match(/更新[:：]?\s*([0-9:]+)/);
  }
  if (updated !== null && updated.length >= 2) {
    result.updatedAt = updated[1];
  }
  return result;
}

// ============================================================
// 服务（只读）
// ============================================================

/** 单平台楼宇拉取结果（部分成功语义用） */
class PlatformFetchResult {
  groups: LaundryBuildingGroup[] = [];
  errorMessage: string = '';
}

/** 海乐单类目拉取结果（单类目失败容错用） */
class HaileCategoryResult {
  machines: LaundryMachine[] = [];
  errorMessage: string = '';
}

export class LaundryService {
  private http: HttpClient;

  constructor(http: HttpClient) {
    this.http = http;
  }

  // ── 通用请求（统一可读中文错误） ────────────────────────

  /** POST JSON 并校验：HTTP 非 2xx / 非 JSON → 可读中文错误 */
  private async postJsonChecked(url: string, jsonBody: Record<string, JsonBodyValue>,
    errorLabel: string): Promise<Record<string, Object>> {
    const resp: HttpResponse = await this.http.postJson(url, jsonBody);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(errorLabel + '（HTTP ' + String(resp.statusCode) + '）');
    }
    try {
      return JSON.parse(resp.body) as Record<string, Object>;
    } catch (e) {
      throw new Error(errorLabel + '：接口响应不是有效的 JSON');
    }
  }

  /** GET 并校验：HTTP 非 2xx / 非 JSON → 可读中文错误 */
  private async getJsonChecked(url: string, errorLabel: string): Promise<Record<string, Object>> {
    const resp: HttpResponse = await this.http.get(url);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw new Error(errorLabel + '（HTTP ' + String(resp.statusCode) + '）');
    }
    try {
      return JSON.parse(resp.body) as Record<string, Object>;
    } catch (e) {
      throw new Error(errorLabel + '：接口响应不是有效的 JSON');
    }
  }

  /** 洁力平台错误码检查（errorCode 存在即失败；对齐参考实现） */
  private assertJieliOk(parsed: Record<string, Object>, fallbackMessage: string): void {
    const errorCode: Object | undefined = parsed['errorCode'];
    if (errorCode !== undefined && errorCode !== null) {
      const errorMsg: Object | undefined = parsed['errorMsg'];
      const msg: string = errorMsg !== undefined && errorMsg !== null && String(errorMsg).length > 0
        ? String(errorMsg) : fallbackMessage;
      throw new Error(msg);
    }
  }

  // ── 楼宇列表（US1） ────────────────────────

  /** 洁力楼宇归组索引（紫荆/南区/双清/其他；对齐参考实现 groupJieliBuilding） */
  private groupJieliIndex(building: LaundryBuilding): number {
    if (building.name.indexOf('紫荆') >= 0) {
      return 0;
    }
    if (building.name.indexOf('南区') >= 0) {
      return 1;
    }
    if (building.name.indexOf('双清') >= 0) {
      return 2;
    }
    return 3;
  }

  /** 洁力楼宇分组（tower 接口 + 分组 + 排序 + 仅保留非空组） */
  private async fetchJieliBuildings(): Promise<LaundryBuildingGroup[]> {
    const body: Record<string, JsonBodyValue> = {};
    const parsed: Record<string, Object> = await this.postJsonChecked(JIELI_TOWER_URL, body, '洁力洗衣机楼宇加载失败');
    this.assertJieliOk(parsed, '洁力洗衣机接口返回失败');

    const groupNames: string[] = ['紫荆公寓', '南区宿舍', '双清公寓', '其他位置'];
    const buckets: LaundryBuilding[][] = [[], [], [], []];
    const rows: Record<string, Object>[] = asObjectArray(parsed['data']);
    for (let i: number = 0; i < rows.length; i++) {
      const row: Record<string, Object> = rows[i];
      const id: string = asString(row['value']);
      const name: string = asString(row['text']);
      if (id.length === 0 || id === '0' || name.length === 0) {
        continue;
      }
      const building: LaundryBuilding = new LaundryBuilding();
      building.id = id;
      building.name = name;
      building.platform = 'jieli';
      buckets[this.groupJieliIndex(building)].push(building);
    }

    const groups: LaundryBuildingGroup[] = [];
    for (let i: number = 0; i < buckets.length; i++) {
      if (buckets[i].length === 0) {
        continue;
      }
      buckets[i].sort((a: LaundryBuilding, b: LaundryBuilding): number =>
        compareByNumberThenName(a.name, b.name));
      const group: LaundryBuildingGroup = new LaundryBuildingGroup();
      group.name = groupNames[i];
      group.buildings = buckets[i];
      groups.push(group);
    }
    return groups;
  }

  /** 海乐楼宇分组（nearPosition 固定坐标 + 仅保留含"清华"者 + 组名"海乐生活"） */
  private async fetchHaileBuildings(): Promise<LaundryBuildingGroup[]> {
    const body: Record<string, JsonBodyValue> = {
      'lng': HAILE_SEARCH_LNG,
      'lat': HAILE_SEARCH_LAT,
      'page': 1,
      'pageSize': 30,
    };
    const parsed: Record<string, Object> = await this.postJsonChecked(HAILE_POSITIONS_URL, body, '海乐生活楼宇加载失败');
    if (numOf(parsed['code']) !== 0) {
      return [];
    }
    const data: Record<string, Object> = asRecord(parsed['data']);
    const rows: Record<string, Object>[] = asObjectArray(data['items']);
    const buildings: LaundryBuilding[] = [];
    for (let i: number = 0; i < rows.length; i++) {
      const row: Record<string, Object> = rows[i];
      const id: string = asString(row['id']);
      const name: string = asString(row['name']);
      if (id.length === 0 || name.indexOf('清华') < 0) {
        continue;
      }
      const building: LaundryBuilding = new LaundryBuilding();
      building.id = id;
      building.name = name;
      building.platform = 'haile';
      buildings.push(building);
    }
    if (buildings.length === 0) {
      return [];
    }
    buildings.sort((a: LaundryBuilding, b: LaundryBuilding): number =>
      compareByNumberThenName(a.name, b.name));
    const group: LaundryBuildingGroup = new LaundryBuildingGroup();
    group.name = '海乐生活';
    group.buildings = buildings;
    return [group];
  }

  /** 单平台楼宇拉取（失败转 errorMessage，不抛） */
  private async fetchJieliBuildingsSafe(): Promise<PlatformFetchResult> {
    const result: PlatformFetchResult = new PlatformFetchResult();
    try {
      result.groups = await this.fetchJieliBuildings();
    } catch (e) {
      result.errorMessage = e instanceof Error ? e.message : '洁力洗衣机楼宇加载失败';
    }
    return result;
  }

  /** 单平台楼宇拉取（失败转 errorMessage，不抛） */
  private async fetchHaileBuildingsSafe(): Promise<PlatformFetchResult> {
    const result: PlatformFetchResult = new PlatformFetchResult();
    try {
      result.groups = await this.fetchHaileBuildings();
    } catch (e) {
      result.errorMessage = e instanceof Error ? e.message : '海乐生活楼宇加载失败';
    }
    return result;
  }

  /**
   * 洗衣机楼宇分组列表：两平台并发 + 部分成功合并（任一平台失败仍返回另一
   * 平台）；全部失败抛可读错误（FR-006）。
   */
  async getLaundryBuildings(): Promise<LaundryBuildingGroup[]> {
    // 并发启动两平台请求（Promise 构造即执行，await 前已发出）
    const jieliTask: Promise<PlatformFetchResult> = this.fetchJieliBuildingsSafe();
    const haileTask: Promise<PlatformFetchResult> = this.fetchHaileBuildingsSafe();
    const jieli: PlatformFetchResult = await jieliTask;
    const haile: PlatformFetchResult = await haileTask;

    const groups: LaundryBuildingGroup[] = [];
    for (let i: number = 0; i < jieli.groups.length; i++) {
      groups.push(jieli.groups[i]);
    }
    for (let i: number = 0; i < haile.groups.length; i++) {
      groups.push(haile.groups[i]);
    }
    if (groups.length === 0) {
      if (jieli.errorMessage.length > 0) {
        throw new Error(jieli.errorMessage);
      }
      if (haile.errorMessage.length > 0) {
        throw new Error(haile.errorMessage);
      }
      throw new Error('洗衣机楼宇加载失败');
    }
    Log.i('Laundry', 'BUILDINGS groups=%{public}d jieliErr=%{public}s haileErr=%{public}s',
      groups.length, jieli.errorMessage.length > 0 ? '1' : '0', haile.errorMessage.length > 0 ? '1' : '0');
    return groups;
  }

  // ── 楼层与机台（US2） ────────────────────────

  /** 洁力机台解析（macUnionCode 首词为类型、余下为名称；位置映射尽力而为） */
  private parseJieliMachine(row: Record<string, Object>, locations: Record<string, Object>): LaundryMachine {
    const machine: LaundryMachine = new LaundryMachine();
    machine.floor = asString(row['floorName']);
    if (machine.floor.length === 0) {
      machine.floor = '未知楼层';
    }
    const unionCode: string = asString(row['macUnionCode']);
    const tokens: string[] = unionCode.split(/\s+/);
    let typePart: string = '';
    const nameTokens: string[] = [];
    for (let i: number = 0; i < tokens.length; i++) {
      if (tokens[i].length === 0) {
        continue;
      }
      if (typePart.length === 0) {
        typePart = tokens[i];
      } else {
        nameTokens.push(tokens[i]);
      }
    }
    machine.type = typePart.length > 0 ? typePart : '洗衣机';
    machine.name = nameTokens.length > 0 ? nameTokens.join(' ')
      : (unionCode.length > 0 ? unionCode : '洗衣机');

    const parsedStatus: JieliStatusParse = parseJieliStatus(asString(row['status']));
    machine.status = parsedStatus.status;
    machine.etaMinutes = parsedStatus.etaMinutes;
    machine.updatedAt = parsedStatus.updatedAt;

    const located: Object | undefined = locations[machine.name];
    machine.location = located !== undefined && located !== null ? String(located) : '';
    return machine;
  }

  /** 洁力楼层与机台：状态接口（关键）+ 位置映射接口（尽力而为）+ 按楼层聚合排序 */
  private async getJieliFloors(building: LaundryBuilding): Promise<LaundryFloor[]> {
    const statusBody: Record<string, JsonBodyValue> = {
      'towerKey': building.id,
    };
    // 并发启动状态与位置请求（Promise 构造即执行）
    const statusTask: Promise<Record<string, Object>> = this.postJsonChecked(
      JIELI_STATUS_URL, statusBody, '洁力洗衣机状态加载失败');
    const locationTask: Promise<Record<string, Object>> = this.getJsonChecked(
      JIELI_LOCATION_URL + '?building=' + encodeURIComponent(building.id), '洁力洗衣机位置加载失败');

    const parsed: Record<string, Object> = await statusTask;
    this.assertJieliOk(parsed, '洁力洗衣机接口返回失败');

    // 位置映射尽力而为：失败降级为空表（位置缺失不展示，不阻塞状态展示）
    let locations: Record<string, Object> = {};
    try {
      locations = await locationTask;
    } catch (e) {
      Log.i('Laundry', 'JIELI_LOCATION fallback building=%{public}s', building.id);
    }

    const floorNames: string[] = [];
    const floorMachines: LaundryMachine[][] = [];
    const rows: Record<string, Object>[] = asObjectArray(parsed['data']);
    for (let i: number = 0; i < rows.length; i++) {
      const machine: LaundryMachine = this.parseJieliMachine(rows[i], locations);
      const idx: number = floorNames.indexOf(machine.floor);
      if (idx >= 0) {
        floorMachines[idx].push(machine);
      } else {
        floorNames.push(machine.floor);
        const list: LaundryMachine[] = [];
        list.push(machine);
        floorMachines.push(list);
      }
    }

    // 楼层按"数字优先 + 名称"排序
    const order: number[] = [];
    for (let i: number = 0; i < floorNames.length; i++) {
      order.push(i);
    }
    order.sort((a: number, b: number): number => compareByNumberThenName(floorNames[a], floorNames[b]));

    const floors: LaundryFloor[] = [];
    for (let i: number = 0; i < order.length; i++) {
      const machines: LaundryMachine[] = floorMachines[order[i]];
      machines.sort(compareMachines);
      const floor: LaundryFloor = new LaundryFloor();
      floor.name = floorNames[order[i]];
      floor.machines = machines;
      floors.push(floor);
    }
    return floors;
  }

  /** 海乐机台状态数值映射（1→空闲 2→使用中 其余→异常；对齐参考实现 haileStatus） */
  private haileStatus(state: number): LaundryMachineStatus {
    if (state === 1) {
      return 'idle';
    }
    if (state === 2) {
      return 'working';
    }
    return 'error';
  }

  /** 海乐单类目设备拉取（失败容错为空列表 + errorMessage，不抛） */
  private async fetchHaileCategory(building: LaundryBuilding, category: HaileCategory):
    Promise<HaileCategoryResult> {
    const result: HaileCategoryResult = new HaileCategoryResult();
    try {
      const body: Record<string, JsonBodyValue> = {
        'positionId': building.id,
        'categoryCode': category.code,
        'page': 1,
        'floorCode': '',
        'pageSize': 100,
      };
      const parsed: Record<string, Object> = await this.postJsonChecked(
        HAILE_DEVICES_URL, body, '海乐生活设备状态加载失败');
      if (numOf(parsed['code']) !== 0) {
        return result;
      }
      const data: Record<string, Object> = asRecord(parsed['data']);
      const rows: Record<string, Object>[] = asObjectArray(data['items']);
      const machines: LaundryMachine[] = [];
      for (let i: number = 0; i < rows.length; i++) {
        const row: Record<string, Object> = rows[i];
        const name: string = asString(row['name']);
        const machine: LaundryMachine = new LaundryMachine();
        machine.type = category.label;
        machine.name = name.length > 0 ? name : category.label;
        machine.floor = '海乐生活';
        machine.status = this.haileStatus(numOf(row['state']));
        machine.etaMinutes = -1;
        machine.updatedAt = nowTimeText();
        machines.push(machine);
      }
      result.machines = machines;
    } catch (e) {
      result.errorMessage = e instanceof Error ? e.message : '海乐生活设备状态加载失败';
    }
    return result;
  }

  /** 海乐楼层与机台：三类目并发拉取后合并；全部类目失败抛可读错误 */
  private async getHaileFloors(building: LaundryBuilding): Promise<LaundryFloor[]> {
    // 三类目并发启动（Promise 构造即执行）
    const taskWasher: Promise<HaileCategoryResult> = this.fetchHaileCategory(building, HAILE_CATEGORIES[0]);
    const taskShoes: Promise<HaileCategoryResult> = this.fetchHaileCategory(building, HAILE_CATEGORIES[1]);
    const taskDryer: Promise<HaileCategoryResult> = this.fetchHaileCategory(building, HAILE_CATEGORIES[2]);
    const washerResult: HaileCategoryResult = await taskWasher;
    const shoesResult: HaileCategoryResult = await taskShoes;
    const dryerResult: HaileCategoryResult = await taskDryer;

    const machines: LaundryMachine[] = [];
    let failCount: number = 0;
    let firstError: string = '';
    const results: HaileCategoryResult[] = [washerResult, shoesResult, dryerResult];
    for (let i: number = 0; i < results.length; i++) {
      if (results[i].errorMessage.length > 0) {
        failCount++;
        if (firstError.length === 0) {
          firstError = results[i].errorMessage;
        }
        continue;
      }
      for (let j: number = 0; j < results[i].machines.length; j++) {
        machines.push(results[i].machines[j]);
      }
    }
    if (machines.length === 0) {
      if (failCount === results.length) {
        throw new Error(firstError.length > 0 ? firstError : '海乐生活设备状态加载失败');
      }
      return [];
    }
    machines.sort(compareMachines);
    const floor: LaundryFloor = new LaundryFloor();
    floor.name = '海乐生活';
    floor.machines = machines;
    return [floor];
  }

  /**
   * 楼层与机台列表（按平台分支）：
   *   - 洁力：状态接口（关键，失败抛可读错误）+ 位置映射接口（尽力而为）
   *     + 状态文本解析（空闲/使用中/异常 + 剩余分钟 + 更新时间）；
   *   - 海乐：三类目并发拉取合并 + state 数值映射（无剩余时间）。
   */
  async getLaundryFloors(building: LaundryBuilding): Promise<LaundryFloor[]> {
    if (building.platform === 'haile') {
      return this.getHaileFloors(building);
    }
    return this.getJieliFloors(building);
  }
}
