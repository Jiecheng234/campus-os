/**
 * ============================================================================
 * SportsService — 体育场馆只读查询（场馆 → 近 7 天资源 + 限额/联系电话 + 预约记录）
 * ============================================================================
 *
 * 对齐原项目 src/services/campus/sports.ts（thu-info-lib sports.ts 协议）：
 *   - 会话：通用漫游 CampusDataService.roamByYyfwidHtml(yyfwid '5539ECF8…')，
 *     对齐参考 ensureSportsSession（roamDefault 同一门户端点）；
 *     读取统一包 withSportsRetry（withSessionRecovery，reroam = 标记复位 + 强制重漫游，
 *     label 'sports'）。roamingurl 为原始主机地址（50.tsinghua.edu.cn）时由
 *     CampusDataService.parseToWebVPN 的体育场馆主机映射（加法式）包装为 WebVPN 前缀。
 *   - 编码：gymbook 子系统 token 已在 HttpClient.GBK_URL_MARKERS（a5a70f88…），
 *     响应头无 charset 时回退 GBK + 严格 UTF-8 嗅探（中文零乱码）。
 *   - 资源页（GBK HTML 脚本驱动，非 JSON）四类脚本调用合并（键 = 资源标识）：
 *     resourceArray.push + resourcesm.put（资源主体）、addCost（费用）、
 *     markResStatus（预约标识/锁定）、markStatusColor（用户类型/支付状态）。
 *   - 限额：资源首页脚本变量多形态匹配（var x='n' / "n" / 裸数字 / 不带 var）。
 *   - 记录：未支付订单 tbody 行按 **td 计数**列序 1/3/5/7/9 取名称/场地/时间/价格/支付方式
 *     （参考 sports.ts 本地 cellText 按 td 计数，非 cheerio 子节点序）；行内脚本
 *     payNow/unsubscribeOnline/unsubscribe 提取支付/预约标识；span[time] 取时间戳；
 *     已支付订单 tr[style="display:none"] 内嵌行（列序 2/3/4/5）合并；逐行容错。
 *
 * 只读浏览；下单/支付/退订不迁移（官方渠道引导）。
 * ============================================================================
 */
import { HttpClient, HttpResponse } from '../HttpClient';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { SessionManager } from '../auth/SessionManager';
import { Log } from '../../utils/Logger';

const WEBVPN_BASE: string = 'https://webvpn.tsinghua.edu.cn';
/** 体育场馆 webvpn token（对齐参考 SPORTS_* 端点中的子系统 token） */
const SPORTS_TOKEN: string = '77726476706e69737468656265737421a5a70f8834396657761d88e29d51367b6a00';
/** 体育场馆子系统通用漫游 payload（对齐参考 SPORTS_ROAM_PAYLOAD / thu-info-lib roamingWrapper default） */
const SPORTS_ROAM_PAYLOAD: string = '5539ECF8CD815C7D3F5A8EE0A2D72441';

/** 资源首页（含限额变量） */
const SPORTS_BASE_URL: string = WEBVPN_BASE + '/http/' + SPORTS_TOKEN
  + '/gymbook/gymBookAction.do?ms=viewGymBook&viewType=m';
/** 资源明细（脚本驱动） */
const SPORTS_DETAIL_URL: string = WEBVPN_BASE + '/http/' + SPORTS_TOKEN
  + '/gymsite/cacheAction.do?ms=viewBook&userType=1';
/** 联系电话（约定值 do_not → 无） */
const SPORTS_PHONE_URL: string = WEBVPN_BASE + '/http/' + SPORTS_TOKEN
  + '/gymbook/gymBookAction.do?ms=hadContactOrNot';
/** 未支付订单页 */
const SPORTS_UNPAID_URL: string = WEBVPN_BASE + '/http/' + SPORTS_TOKEN
  + '/pay/payAction.do?ms=getOrdersForNopay';
/** 已支付订单页 */
const SPORTS_PAID_URL: string = WEBVPN_BASE + '/http/' + SPORTS_TOKEN
  + '/pay/payAction.do?ms=getOrdersForUnpay';

/** 会话失效 / 落回登录页的标记（对齐参考 WEBVPN_LOGIN_MARKERS） */
const WEBVPN_LOGIN_MARKERS: string[] = [
  '<title>清华大学WebVPN</title>',
  'user login',
  '用户登陆超时',
  '登录超时',
];

// ============================================================
// 数据模型（全字段非可选默认值）
// ============================================================

/** 体育场馆（固定清单项） */
export class SportsVenue {
  name: string = '';
  /** 场馆标识 */
  gymId: string = '';
  /** 项目标识 */
  itemId: string = '';
}

/** 场馆资源（一个时段 × 一块场地） */
export class SportsResource {
  resId: string = '';
  resHash: string = '';
  timeSession: string = '';
  fieldName: string = '';
  overlaySize: number = 0;
  canNetBook: boolean = false;
  cost: number = 0;
  bookId: string = '';
  locked: boolean = false;
  userType: string = '';
  paymentStatus: boolean = false;
}

/** 资源总量信息（count=已用 init=上限，对齐 spec 语义） */
export class SportsResourceInfo {
  count: number = 0;
  init: number = 0;
  phone: string = '';
  data: SportsResource[] = [];
}

/** 预约记录（bookId=可取消标识 payId=可支付标识，仅标注不提供操作） */
export class SportsRecord {
  name: string = '';
  field: string = '';
  time: string = '';
  price: string = '';
  method: string = '';
  bookTimestamp: number = 0;
  bookId: string = '';
  payId: string = '';
}

/** 限额页解析结果（内部使用） */
class SportsLimit {
  count: number = -1;
  init: number = -1;
}

/**
 * 固定场馆清单（对齐参考 sportsIdInfoList 的 8 个场馆：名称/场馆标识/项目标识）。
 * 不提供自定义场馆/项目标识。
 */
export const SPORTS_VENUES: SportsVenue[] = [
  { name: '气膜馆羽毛球场', gymId: '3998000', itemId: '4045681' },
  { name: '气膜馆乒乓球场', gymId: '3998000', itemId: '4037036' },
  { name: '综体篮球场', gymId: '4797914', itemId: '4797898' },
  { name: '综体羽毛球场', gymId: '4797914', itemId: '4797899' },
  { name: '西体羽毛球场', gymId: '4836273', itemId: '4836196' },
  { name: '西体台球', gymId: '4836273', itemId: '14567218' },
  { name: '紫荆网球场', gymId: '5843934', itemId: '5845263' },
  { name: '西网球场', gymId: '5843934', itemId: '10120539' },
];

// ============================================================
// 模块级辅助
// ============================================================

function pad(n: number): string {
  return n < 10 ? '0' + String(n) : String(n);
}

/** 日期偏移 → YYYY-MM-DD（近 7 天：偏移 0–6） */
export function sportsDateString(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate());
}

/** 登录页 / 会话失效标记检测（命中抛可读中文错误） */
function assertSportsHtml(html: string): void {
  for (let i: number = 0; i < WEBVPN_LOGIN_MARKERS.length; i++) {
    if (html.indexOf(WEBVPN_LOGIN_MARKERS[i]) >= 0) {
      throw new Error('体育场馆会话未登录，请刷新重试');
    }
  }
}

/**
 * 限额变量多形态匹配（对齐参考 matchSportsLimitVar）：
 * var x='n' / var x="n" / var x=n / 不带 var 的 x='n'；未命中返回 -1。
 */
function matchSportsLimitVar(html: string, name: string): number {
  const patterns: RegExp[] = [
    new RegExp('var\\s+' + name + '\\s*=\\s*\'(\\d+)\'', 'i'),
    new RegExp('var\\s+' + name + '\\s*=\\s*"(\\d+)"', 'i'),
    new RegExp('var\\s+' + name + '\\s*=\\s*(\\d+)', 'i'),
    new RegExp(name + '\\s*=\\s*\'(\\d+)\'', 'i'),
  ];
  for (let i: number = 0; i < patterns.length; i++) {
    const m: RegExpExecArray | null = patterns[i].exec(html);
    if (m !== null && m.length >= 2 && m[1].length > 0) {
      const n: number = Number(m[1]);
      return Number.isFinite(n) ? n : -1;
    }
  }
  return -1;
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
 * 提取 <tr> 内全部 <td> 单元格文本。
 * 【关键】参考 sports.ts 的本地 cellText 按 **td 计数**（querySelectorAll('td')[index]），
 * 与 cheerio 子节点序（htmlSelect.childText）不同——勿混用。
 */
function parseRowTds(trHtml: string): string[] {
  const cells: string[] = [];
  const tdRe: RegExp = /<td[^>]*>([\s\S]*?)<\/td>/gi;
  let m: RegExpExecArray | null = tdRe.exec(trHtml);
  while (m !== null) {
    cells.push(cellText(m[1]));
    m = tdRe.exec(trHtml);
  }
  return cells;
}

/**
 * 资源页脚本解析（四类调用合并，键 = 资源标识，对齐参考 getSportsResourceData）：
 *   ① resourceArray.push({…});…resourcesm.put(id,hash) → 资源主体（push.id 与 put 键一致才收录）
 *   ② addCost(id,cost) → 费用
 *   ③ markResStatus(bookId,id,locked) → 预约标识 / 是否锁定
 *   ④ markStatusColor(id,userType,paid) → 用户类型 / 支付状态
 */
function parseSportsResourceScripts(html: string): SportsResource[] {
  const map: Map<string, SportsResource> = new Map<string, SportsResource>();
  const order: SportsResource[] = [];

  const p1: RegExp = /resourceArray\.push\({id:'(.*?)',time_session:'(.*?)',field_name:'(.*?)',overlaySize:'(.*?)',can_net_book:'(.*?)'}\);[\s\S]+?resourcesm\.put\('(.*?)', '(.*?)'\)/gm;
  let m1: RegExpExecArray | null = p1.exec(html);
  while (m1 !== null) {
    if (m1[1] === m1[6] && !map.has(m1[1])) {
      const res: SportsResource = new SportsResource();
      res.resId = m1[1];
      res.resHash = m1[7];
      res.timeSession = m1[2];
      res.fieldName = m1[3];
      const overlay: number = Number(m1[4]);
      res.overlaySize = Number.isFinite(overlay) ? overlay : 0;
      res.canNetBook = m1[5] === '1';
      map.set(res.resId, res);
      order.push(res);
    }
    m1 = p1.exec(html);
  }

  const p2: RegExp = /addCost\('(.*?)','(.*?)'\);/g;
  let m2: RegExpExecArray | null = p2.exec(html);
  while (m2 !== null) {
    const res: SportsResource | undefined = map.get(m2[1]);
    if (res !== undefined) {
      const cost: number = Number(m2[2]);
      res.cost = Number.isFinite(cost) ? cost : 0;
    }
    m2 = p2.exec(html);
  }

  const p3: RegExp = /markResStatus\('(.*?)','(.*?)','(.*?)'\);/g;
  let m3: RegExpExecArray | null = p3.exec(html);
  while (m3 !== null) {
    const res: SportsResource | undefined = map.get(m3[2]);
    if (res !== undefined) {
      res.bookId = m3[1];
      res.locked = m3[3] === '1';
    }
    m3 = p3.exec(html);
  }

  const p4: RegExp = /markStatusColor\('(.*?)','(.*?)','(.*?)','(.*?)'\);/g;
  let m4: RegExpExecArray | null = p4.exec(html);
  while (m4 !== null) {
    const res: SportsResource | undefined = map.get(m4[1]);
    if (res !== undefined) {
      res.userType = m4[2];
      res.paymentStatus = m4[3] === '1';
    }
    m4 = p4.exec(html);
  }

  return order;
}

/** 未支付订单行解析（列序按 td 计数：1=名称 3=场地 5=时间 7=价格 9=支付方式）；逐行容错 */
function parseSportsUnpaidRecords(html: string): SportsRecord[] {
  const records: SportsRecord[] = [];
  let firstRowLogged: boolean = false;
  const tbodyRe: RegExp = /<tbody[^>]*>([\s\S]*?)<\/tbody>/gi;
  let tbm: RegExpExecArray | null = tbodyRe.exec(html);
  while (tbm !== null) {
    const trRe: RegExp = /<tr([^>]*)>([\s\S]*?)<\/tr>/gi;
    let trm: RegExpExecArray | null = trRe.exec(tbm[1]);
    while (trm !== null) {
      const trAttrs: string = trm[1];
      const trInner: string = trm[2];
      const rowFull: string = trm[0];
      // 隐藏模板行跳过（参考只取展示行语义；display:none 行为 jQuery 模板）
      if (trAttrs.indexOf('display:none') < 0) {
        try {
          const tds: string[] = parseRowTds(trInner);
          // 首行诊断日志（列数组），核对列序（项目曾因子节点索引语义踩坑）
          if (!firstRowLogged && tds.length > 0) {
            Log.i('Sports', 'UNPAID row0 tds=%{public}d cells=[%{public}s]',
              tds.length, tds.join('|').substring(0, 200));
            firstRowLogged = true;
          }
          if (tds.length >= 10) {
            const rec: SportsRecord = new SportsRecord();
            rec.name = tds[1];
            rec.field = tds[3];
            rec.time = tds[5];
            rec.price = tds[7];
            rec.method = tds[9];
            if (rec.name.length > 0 || rec.field.length > 0 || rec.time.length > 0) {
              // 行内脚本调用提取支付标识（网上支付）与预约标识（网上/现场退订）
              if (rec.method === '网上支付') {
                const pm: RegExpExecArray | null = /payNow\('(.+?)'/.exec(rowFull);
                if (pm !== null) {
                  rec.payId = pm[1];
                }
                const um: RegExpExecArray | null = /unsubscribeOnline\('(.+?)'/.exec(rowFull);
                if (um !== null) {
                  rec.bookId = um[1];
                }
              } else if (rec.method === '现场支付') {
                const um: RegExpExecArray | null = /unsubscribe\('(.+?)'/.exec(rowFull);
                if (um !== null) {
                  rec.bookId = um[1];
                }
              }
              // span[time] 属性取预约时间戳
              const sm: RegExpExecArray | null = /<span[^>]*\stime\s*=\s*"([^"]*)"/i.exec(rowFull);
              if (sm !== null && sm[1].length > 0) {
                const ts: number = Number(sm[1]);
                rec.bookTimestamp = Number.isFinite(ts) ? ts : 0;
              }
              records.push(rec);
            }
          }
        } catch (e) {
          // 逐行容错：单行失败跳过
        }
      }
      trm = trRe.exec(tbm[1]);
    }
    tbm = tbodyRe.exec(html);
  }
  return records;
}

/**
 * 已支付订单行解析（对齐参考 getSportsReservationPaidRecords）：
 * tr[style="display:none"] 内嵌表格的首个数据行，按 td 计数列序 2/3/4/5 取
 * 名称/场地/时间/价格，method 固定"已支付"；逐行容错。
 */
function parseSportsPaidRecords(html: string): SportsRecord[] {
  const records: SportsRecord[] = [];
  const hiddenRe: RegExp = /<tr[^>]*style=(?:"display:none"|'display:none')[^>]*>([\s\S]*?)<\/tr>/gi;
  let hm: RegExpExecArray | null = hiddenRe.exec(html);
  while (hm !== null) {
    try {
      const frag: string = hm[1];
      // 隐藏行内嵌套表格：片段在首个 </tr>（内层行闭合）处截断，
      // 取最后一个 <tr…> 开标签之后的内层行内容（等价参考 querySelector('tbody tr') 首行）
      const trOpenRe: RegExp = /<tr[^>]*>/gi;
      let lastOpen: RegExpExecArray | null = null;
      let om: RegExpExecArray | null = trOpenRe.exec(frag);
      while (om !== null) {
        lastOpen = om;
        om = trOpenRe.exec(frag);
      }
      if (lastOpen !== null) {
        const rowHtml: string = frag.substring(lastOpen.index + lastOpen[0].length);
        const tds: string[] = parseRowTds(rowHtml);
        if (tds.length >= 6) {
          const rec: SportsRecord = new SportsRecord();
          rec.name = tds[2];
          rec.field = tds[3];
          rec.time = tds[4];
          rec.price = tds[5];
          rec.method = '已支付';
          if (rec.name.length > 0 || rec.field.length > 0 || rec.time.length > 0) {
            records.push(rec);
          }
        }
      }
    } catch (e) {
      // 逐行容错：单行失败跳过
    }
    hm = hiddenRe.exec(html);
  }
  return records;
}

// ============================================================
// 服务
// ============================================================

export class SportsService {
  private http: HttpClient;
  private auth: TsinghuaAuthService;
  /** 体育场馆子系统会话是否已通过通用漫游建立 */
  private sportsSessionEnsured: boolean = false;

  constructor(http: HttpClient, auth: TsinghuaAuthService) {
    this.http = http;
    this.auth = auth;
  }

  /** 建立体育场馆子系统会话（通用漫游，对齐参考 ensureSportsSession） */
  private async ensureSportsSession(force: boolean): Promise<void> {
    if (this.sportsSessionEnsured && !force) {
      return;
    }
    const landingHtml: string = await SessionManager.getCampusDataService()
      .roamByYyfwidHtml(SPORTS_ROAM_PAYLOAD);
    if (landingHtml.length === 0) {
      // roamByYyfwidHtml 失败返回空串不抛；此处转为可读错误交由 withSessionRecovery 恢复重试
      throw new Error('体育场馆会话建立失败，请稍后重试');
    }
    this.sportsSessionEnsured = true;
    Log.i('Sports', 'SPORTS_SESSION ensured force=%{public}s', force ? '1' : '0');
  }

  /** 体育场馆读取统一会话兜底（reroam = 标记复位 + 强制重漫游；label 'sports'） */
  private async withSportsRetry<T>(operation: () => Promise<T>): Promise<T> {
    return this.auth.withSessionRecovery<T>(operation, async (): Promise<void> => {
      this.sportsSessionEnsured = false;
      await this.ensureSportsSession(true);
    }, 'sports');
  }

  /** 限额（资源首页脚本变量；缺失抛可读错误） */
  private async fetchSportsLimit(gymId: string, itemId: string, date: string): Promise<SportsLimit> {
    const url: string = SPORTS_BASE_URL + '&gymnasium_id=' + gymId
      + '&item_id=' + itemId + '&time_date=' + date;
    const resp: HttpResponse = await this.http.get(url);
    assertSportsHtml(resp.body);
    const limit: SportsLimit = new SportsLimit();
    limit.count = matchSportsLimitVar(resp.body, 'limitBookCount');
    limit.init = matchSportsLimitVar(resp.body, 'limitBookInit');
    Log.i('Sports', 'LIMIT code=%{public}d len=%{public}d used=%{public}d cap=%{public}d',
      resp.statusCode, resp.body.length, limit.count, limit.init);
    // 诊断：限额页缺失变量时打印响应体头部，用于核对落点是否为错误/登录页
    if (limit.count < 0 || limit.init < 0) {
      Log.i('Sports', 'LIMIT_RAW head=%{public}s',
        resp.body.substring(0, 300).replace(/[\r\n\t]+/g, ' '));
    }
    if (limit.count < 0 || limit.init < 0) {
      throw new Error('无法获取体育场馆预约限额');
    }
    return limit;
  }

  /** 联系电话（约定值 do_not → 空串；接口失败不阻塞资源加载 → 空串） */
  private async fetchSportsPhone(): Promise<string> {
    try {
      const resp: HttpResponse = await this.http.get(SPORTS_PHONE_URL);
      const msg: string = resp.body.trim();
      if (msg.length === 0 || msg === 'do_not' || msg.charAt(0) === '<') {
        return '';
      }
      return msg;
    } catch (e) {
      // 联系电话为非必需项，失败置空不阻塞
      return '';
    }
  }

  /** 资源明细（四类脚本调用合并解析） */
  private async fetchSportsResourceData(gymId: string, itemId: string, date: string): Promise<SportsResource[]> {
    const url: string = SPORTS_DETAIL_URL + '&gymnasium_id=' + gymId
      + '&item_id=' + itemId + '&time_date=' + date;
    const resp: HttpResponse = await this.http.get(url);
    assertSportsHtml(resp.body);
    const data: SportsResource[] = parseSportsResourceScripts(resp.body);
    Log.i('Sports', 'RES_DATA code=%{public}d len=%{public}d count=%{public}d',
      resp.statusCode, resp.body.length, data.length);
    if (data.length === 0) {
      Log.i('Sports', 'RES_RAW head=%{public}s',
        resp.body.substring(0, 300).replace(/[\r\n\t]+/g, ' '));
    }
    return data;
  }

  /**
   * 场馆某日资源（只读）：并发取"限额 + 联系电话 + 资源列表"并组装
   * {count, init, phone, data}；限额/资源失败抛可读错误（联系电话失败置空不阻塞）。
   */
  async getSportsResources(venue: SportsVenue, dateYmd: string): Promise<SportsResourceInfo> {
    return this.withSportsRetry((): Promise<SportsResourceInfo> => {
      return this.doGetSportsResources(venue, dateYmd);
    });
  }

  private async doGetSportsResources(venue: SportsVenue, dateYmd: string): Promise<SportsResourceInfo> {
    await this.ensureSportsSession(false);
    // 并发取数：任务先发起（不逐个 await 发起），后逐个收取（对齐项目并发范式）
    const limitTask: Promise<SportsLimit> = this.fetchSportsLimit(venue.gymId, venue.itemId, dateYmd);
    const phoneTask: Promise<string> = this.fetchSportsPhone();
    const dataTask: Promise<SportsResource[]> = this.fetchSportsResourceData(venue.gymId, venue.itemId, dateYmd);
    const limit: SportsLimit = await limitTask;
    const data: SportsResource[] = await dataTask;
    const phone: string = await phoneTask;
    const info: SportsResourceInfo = new SportsResourceInfo();
    info.count = limit.count;
    info.init = limit.init;
    info.phone = phone;
    info.data = data;
    Log.i('Sports', 'RESOURCES gym=%{public}s item=%{public}s date=%{public}s used=%{public}d cap=%{public}d res=%{public}d phone=%{public}s',
      venue.gymId, venue.itemId, dateYmd, info.count, info.init, info.data.length,
      info.phone.length > 0 ? 'y' : 'n');
    return info;
  }

  /**
   * 我的预约记录（只读）：未支付订单页 + 已支付订单页合并；
   * 逐行容错（单行失败跳过）；页面无订单表抛可读错误。
   */
  async getSportsRecords(): Promise<SportsRecord[]> {
    return this.withSportsRetry((): Promise<SportsRecord[]> => {
      return this.doGetSportsRecords();
    });
  }

  private async doGetSportsRecords(): Promise<SportsRecord[]> {
    await this.ensureSportsSession(false);
    const unpaidResp: HttpResponse = await this.http.get(SPORTS_UNPAID_URL);
    assertSportsHtml(unpaidResp.body);
    if (unpaidResp.body.indexOf('<table') < 0) {
      throw new Error('无法加载体育场馆预约订单');
    }
    const unpaid: SportsRecord[] = parseSportsUnpaidRecords(unpaidResp.body);
    const paidResp: HttpResponse = await this.http.get(SPORTS_PAID_URL);
    assertSportsHtml(paidResp.body);
    const paid: SportsRecord[] = parseSportsPaidRecords(paidResp.body);
    Log.i('Sports', 'RECORDS code=%{public}d/%{public}d unpaid=%{public}d paid=%{public}d',
      unpaidResp.statusCode, paidResp.statusCode, unpaid.length, paid.length);
    return unpaid.concat(paid);
  }
}
