/**
 * CampusNetworkService — 校园网自助服务（余额/账户信息/在线设备/设备注销/图片验证码登录）
 * 对齐原项目 src/services/campus/network.ts（thu-info-lib network 协议）：
 *   - 会话：先探测网络登录入口页（WebVPN 登录页标记 = 会话失效；验证码表单标记 =
 *     需验证码登录），整体包 withSessionRecovery 两层恢复（对齐原项目 withNetworkRetry）。
 *   - 解析：正则复刻 DOM 选择语义——设备表 `#w1-container table tbody tr`（行 data-key
 *     + 5 个 td）、余额表 `#w3-container table tbody tr td`（<5 列视为结构异常）、
 *     账户表 `#w0 td`（按序 0/1/2/3/5/6/7）、状态 `.glyphicon-info-sign` 父节点文本、
 *     允许设备数 `.glyphicon-exclamation-sign` 父节点文本首个数字。
 *   - 注销：从首页提取 CSRF（input[name=_csrf-8800]）→ postForm 携带至删除端点
 *     （id/user_mac 查询参数百分号编码）→ 按成功标记判定，失败提取错误文本。
 *   - 验证码登录：`?refresh=1` 预热 + 一次性随机参数取图（getBytes 原始字节 → Base64
 *     data URI）；登录页解析 meta[csrf-token]/隐藏域 CSRF/#public 公开密钥 →
 *     漫游信息门户用户信息子系统取邮箱账号名 → RSA PKCS#1 v1.5 加密密码 →
 *     带自定义头校验用户（X-CSRF-Token/X-Requested-With）→ 提交登录表单 → 复探测确认。
 *     NetworkCaptchaRequiredError 短路直抛（恢复链不重试）。
 */
import { HttpClient, HttpResponse } from '../HttpClient';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { CampusDataService } from './CampusDataService';
import { Log } from '../../utils/Logger';
import { rsaEncryptPkcs1 } from '../../utils/CryptoUtils';
import { util } from '@kit.ArkTS';
import { SecureStorage, SecureCredentials } from '../../storage/SecureStorage';

const WEBVPN_BASE: string = 'https://webvpn.tsinghua.edu.cn';
/** 校园网自助服务 webvpn token（对齐原项目 NETWORK_TOKEN） */
const NETWORK_TOKEN: string =
  '77726476706e69737468656265737421e5e4448e223726446d0187ab9040227b54b6c80fcd73';
/** 会话探测端点（网络登录入口页） */
const NETWORK_LOGIN_URL: string = WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/login';
/** 验证码图片端点（"换一张"以一次性随机查询参数规避缓存） */
const NETWORK_CAPTCHA_URL: string = WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/site/captcha';
/** 校验用户端点（要求 X-CSRF-Token / X-Requested-With 头） */
const NETWORK_VALIDATE_USER_URL: string = WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/site/validate-user';
/** 网络首页（余额表 + 设备表 + 状态图标 + 注销 CSRF） */
const NETWORK_HOME_URL: string = WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/home';
/** 注销设备端点（{id}/{mac} 占位，提交前百分号编码） */
const NETWORK_HOME_DELETE_URL: string =
  WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/home/delete?id={id}&user_mac={mac}';
/** 账户信息页（`#w0` 账户表） */
const NETWORK_USER_INFO_URL: string = WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/users';
/** 允许在线设备数页（`.glyphicon-exclamation-sign` 父文本） */
const NETWORK_ALLOWED_DEVICES_URL: string =
  WEBVPN_BASE + '/https/' + NETWORK_TOKEN + '/user/online-num';
/** 信息门户用户信息子系统 yyfwid（漫游取邮箱账号名，对齐参考实现 USER_INFO_YYFWID） */
const USER_INFO_YYFWID: string = 'F315577F5BF20E1B1668EDD594B2C04F';

/** WebVPN 统一登录页标记（命中即会话失效，对齐原项目 WEBVPN_TITLE） */
const WEBVPN_TITLE_MARK: string = '<title>清华大学WebVPN</title>';
/** 校园网验证码登录表单标记（命中即需要验证码登录） */
const CAPTCHA_FORM_MARK: string = 'loginform-verifycode';

// ============================================================
// 模型（全部字段非可选默认值，空值由 UI 以 '—' 兜底）
// ============================================================

export class NetworkBalance {
  productName: string = '';
  usedBytes: string = '';
  usedSeconds: string = '';
  accountBalance: string = '';
  settlementDate: string = '';
}

export class NetworkAccountInfo {
  username: string = '';
  contactEmail: string = '';
  contactPhone: string = '';
  contactLandline: string = '';
  realName: string = '';
  status: string = '';
  userGroup: string = '';
  location: string = '';
  allowedDevices: number = 0;
}

export class NetworkDevice {
  key: number = 0;
  ip4: string = '';
  ip6: string = '';
  loggedAt: string = '';
  authPermission: string = '';
  mac: string = '';
}

export class NetworkSnapshot {
  balance: NetworkBalance = new NetworkBalance();
  account: NetworkAccountInfo = new NetworkAccountInfo();
  devices: NetworkDevice[] = [];
}

export class NetworkLogoutResult {
  ok: boolean = false;
  message: string = '';
}

// ============================================================
// 验证码专用错误类型（稳定 code 供判别；本阶段不接入验证码登录）
// ============================================================

export class NetworkCaptchaRequiredError extends Error {
  readonly code: string = 'NETWORK_CAPTCHA_REQUIRED';

  constructor() {
    super('校园网需要验证码登录');
  }
}

/** 验证码错误判别（供页面分支：instanceof 或稳定 code 兜底） */
export function isNetworkCaptchaRequiredError(error: Object): boolean {
  if (error instanceof NetworkCaptchaRequiredError) {
    return true;
  }
  if (error instanceof Error) {
    const coded: NetworkCaptchaRequiredError = error as NetworkCaptchaRequiredError;
    return coded.code === 'NETWORK_CAPTCHA_REQUIRED';
  }
  return false;
}

// ============================================================
// 正则解析辅助（复刻参考 DOM 选择语义）
// ============================================================

/** 空白归一（对齐参考 elementText 的 replace(/\s+/g,' ').trim()） */
function collapseSpace(value: string): string {
  return value.replace(/\s+/g, ' ').trim();
}

function isLetter(ch: string): boolean {
  return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z');
}

/** 常用 HTML 实体解码（数值 + 命名，&amp; 最后） */
function decodeEntities(value: string): string {
  let out: string = value.replace(/&#x([0-9a-fA-F]+);/g, (m: string, hex: string): string => {
    return String.fromCharCode(parseInt(hex, 16));
  });
  out = out.replace(/&#(\d+);/g, (m: string, dec: string): string => {
    return String.fromCharCode(parseInt(dec, 10));
  });
  out = out.replace(/&nbsp;/g, ' ');
  out = out.replace(/&lt;/g, '<');
  out = out.replace(/&gt;/g, '>');
  out = out.replace(/&quot;/g, '"');
  out = out.replace(/&#39;/g, "'");
  out = out.replace(/&amp;/g, '&');
  return out;
}

/** HTML 片段 → 纯文本（去标签 + 实体解码 + 空白归一，对齐参考 elementText 语义并加固实体解码） */
function elementText(fragment: string): string {
  return collapseSpace(decodeEntities(fragment.replace(/<[^>]+>/g, '')));
}

/** 标签名提取（`<td ...>` / `</td>` → 'td'；非法返回 ''） */
function tagNameOf(tagText: string): string {
  let s: string = tagText.startsWith('</') ? tagText.substring(2) : tagText.substring(1);
  const m: RegExpExecArray | null = /^([a-zA-Z][a-zA-Z0-9]*)/.exec(s);
  return m !== null ? m[1].toLowerCase() : '';
}

/** 定位 id 属性（精确匹配，避免 w1 命中 w1-container）首次出现位置；找不到返回 -1 */
function findIdIndex(html: string, id: string): number {
  const re: RegExp = new RegExp('\\sid=["\']' + id + '["\']');
  const m: RegExpExecArray | null = re.exec(html);
  return m !== null ? m.index : -1;
}

/** 从 `<table` 开标签位置取该 table 内部 HTML（同名嵌套计数） */
function innerOfTableAt(html: string, tableStart: number): string {
  const openGt: number = html.indexOf('>', tableStart);
  if (openGt < 0) {
    return '';
  }
  const tagRe: RegExp = /<\/?table[^>]*>/gi;
  tagRe.lastIndex = openGt + 1;
  let depth: number = 1;
  let m: RegExpExecArray | null = tagRe.exec(html);
  while (m !== null) {
    if (m[0].charAt(1) === '/') {
      depth--;
      if (depth === 0) {
        return html.substring(openGt + 1, m.index);
      }
    } else {
      depth++;
    }
    m = tagRe.exec(html);
  }
  return '';
}

/**
 * 取 id 所标识 table 的内部 HTML，兼容两种形态：
 *   - id 直接在 `<table id="w0">` 上（Yii DetailView，如 `#w0 td`）；
 *   - id 在外层容器上（GridView，如 `#w1-container` / `#w3-container`，取其后第一个 table）。
 */
function tableInnerById(html: string, id: string): string {
  const idIdx: number = findIdIndex(html, id);
  if (idIdx < 0) {
    return '';
  }
  const tagStart: number = html.lastIndexOf('<', idIdx);
  if (tagStart >= 0) {
    const gt: number = html.indexOf('>', idIdx);
    if (gt >= 0) {
      const openTag: string = html.substring(tagStart, gt + 1).toLowerCase();
      if (openTag.startsWith('<table')) {
        return innerOfTableAt(html, tagStart);
      }
    }
  }
  const afterRe: RegExpExecArray | null = /<table[^>]*>/i.exec(html.substring(idIdx));
  if (afterRe === null) {
    return '';
  }
  return innerOfTableAt(html, idIdx + afterRe.index);
}

/** 提取片段内全部 `<td>` 单元格文本 */
function parseTdCells(fragment: string): string[] {
  const cells: string[] = [];
  const tdRe: RegExp = /<td[^>]*>([\s\S]*?)<\/td>/gi;
  let m: RegExpExecArray | null = tdRe.exec(fragment);
  while (m !== null) {
    cells.push(elementText(m[1]));
    m = tdRe.exec(fragment);
  }
  return cells;
}

/**
 * 图标 class 所在元素的**父元素文本**（复刻参考 nodeText(icon.parentNode)）：
 * 向前栈式扫描找直接包裹图标的开标签（跳过完整闭合的兄弟元素），
 * 再向后按同名嵌套计数找匹配闭标签，取其间文本。
 */
function iconParentText(html: string, iconClass: string): string {
  const iconIdx: number = html.indexOf(iconClass);
  if (iconIdx < 0) {
    return '';
  }
  const iconTagStart: number = html.lastIndexOf('<', iconIdx);
  if (iconTagStart < 0) {
    return '';
  }
  const closeStack: string[] = [];
  let parentStart: number = -1;
  let pos: number = iconTagStart;
  while (pos > 0) {
    const lt: number = html.lastIndexOf('<', pos - 1);
    if (lt < 0) {
      break;
    }
    const afterChar: string = html.charAt(lt + 1);
    if (afterChar !== '/' && !isLetter(afterChar)) {
      pos = lt;
      continue;
    }
    const gt: number = html.indexOf('>', lt);
    if (gt < 0 || gt >= pos) {
      pos = lt;
      continue;
    }
    const tagText: string = html.substring(lt, gt + 1);
    const name: string = tagNameOf(tagText);
    if (name.length === 0) {
      pos = lt;
      continue;
    }
    if (tagText.startsWith('</')) {
      closeStack.push(name);
    } else if (closeStack.length > 0 && closeStack[closeStack.length - 1] === name) {
      closeStack.pop();
    } else {
      parentStart = lt;
      break;
    }
    pos = lt;
  }
  if (parentStart < 0) {
    return '';
  }
  const parentName: string = tagNameOf(html.substring(parentStart));
  const closeTag: string = '</' + parentName;
  const openTag: string = '<' + parentName;
  let depth: number = 1;
  let scan: number = html.indexOf('>', parentStart) + 1;
  while (scan < html.length) {
    const nextLt: number = html.indexOf('<', scan);
    if (nextLt < 0) {
      break;
    }
    const nextGt: number = html.indexOf('>', nextLt);
    if (nextGt < 0) {
      break;
    }
    const tag: string = html.substring(nextLt, nextGt + 1).toLowerCase();
    if (tag.startsWith(closeTag)) {
      depth--;
      if (depth === 0) {
        return elementText(html.substring(scan, nextLt));
      }
    } else if (tag.startsWith(openTag)) {
      depth++;
    }
    scan = nextGt + 1;
  }
  return '';
}

/** 设备表解析：`#w1-container table tbody tr`（行 data-key + 5 列；key≤0 的行丢弃） */
function parseDevices(homeHtml: string): NetworkDevice[] {
  const devices: NetworkDevice[] = [];
  const tableInner: string = tableInnerById(homeHtml, 'w1-container');
  if (tableInner.length === 0) {
    return devices;
  }
  const tbodyMatch: RegExpExecArray | null = /<tbody[^>]*>([\s\S]*?)<\/tbody>/i.exec(tableInner);
  const rowsHtml: string = tbodyMatch !== null ? tbodyMatch[1] : tableInner;
  const trRe: RegExp = /<tr([^>]*)>([\s\S]*?)<\/tr>/gi;
  let trMatch: RegExpExecArray | null = trRe.exec(rowsHtml);
  while (trMatch !== null) {
    const attrs: string = trMatch[1];
    const keyMatch: RegExpExecArray | null = /data-key\s*=\s*["']([^"']*)["']/i.exec(attrs);
    const key: number = keyMatch !== null ? (Number(keyMatch[1]) || 0) : 0;
    if (key > 0) {
      const cells: string[] = parseTdCells(trMatch[2]);
      const device: NetworkDevice = new NetworkDevice();
      device.key = key;
      device.ip4 = cells.length > 0 ? cells[0] : '';
      device.ip6 = cells.length > 1 ? cells[1] : '';
      device.loggedAt = cells.length > 2 ? cells[2] : '';
      device.authPermission = cells.length > 3 ? cells[3] : '';
      device.mac = cells.length > 4 ? cells[4] : '';
      devices.push(device);
    }
    trMatch = trRe.exec(rowsHtml);
  }
  return devices;
}

/** 余额表解析：`#w3-container table tbody tr` 的全部 td（<5 列视为结构异常） */
function parseBalance(homeHtml: string): NetworkBalance {
  const tableInner: string = tableInnerById(homeHtml, 'w3-container');
  const tbodyMatch: RegExpExecArray | null = /<tbody[^>]*>([\s\S]*?)<\/tbody>/i.exec(tableInner);
  const rowsHtml: string = tbodyMatch !== null ? tbodyMatch[1] : tableInner;
  const cells: string[] = parseTdCells(rowsHtml);
  if (cells.length < 5) {
    throw new Error('校园网余额页面结构异常，请刷新后重试');
  }
  const balance: NetworkBalance = new NetworkBalance();
  balance.productName = cells[0];
  balance.usedBytes = cells[1];
  balance.usedSeconds = cells[2];
  balance.accountBalance = cells[3];
  balance.settlementDate = cells[4];
  return balance;
}

/** 从账户信息页解析 `#w0 td` 全部单元格文本 */
function parseAccountCells(usersHtml: string): string[] {
  return parseTdCells(tableInnerById(usersHtml, 'w0'));
}

/** 首页提取 CSRF（`input[name=_csrf-8800]` 的 value，兼容属性顺序） */
function extractCsrf8800(homeHtml: string): string {
  const inputRe: RegExp = /<input[^>]*>/gi;
  let m: RegExpExecArray | null = inputRe.exec(homeHtml);
  while (m !== null) {
    const tag: string = m[0];
    if (/name=["']_csrf-8800["']/i.test(tag)) {
      const v: RegExpExecArray | null = /value=["']([^"']*)["']/i.exec(tag);
      if (v !== null) {
        return v[1];
      }
    }
    m = inputRe.exec(homeHtml);
  }
  return '';
}

/** 提取 id 告警容器（如 w5-danger-0）开标签到首个闭标签之间的文本 */
function alertTextById(html: string, alertId: string): string {
  const re: RegExp = new RegExp('id=["\']' + alertId + '["\'][^>]*>');
  const m: RegExpExecArray | null = re.exec(html);
  if (m === null) {
    return '';
  }
  const start: number = m.index + m[0].length;
  const close: number = html.indexOf('</', start);
  const fragment: string = close >= 0 ? html.substring(start, close) : html.substring(start);
  return elementText(fragment);
}

/** 登录页提取 meta[name=csrf-token] 的 content（validate-user 的 X-CSRF-Token） */
function extractMetaCsrfToken(html: string): string {
  const metaRe: RegExp = /<meta[^>]*>/gi;
  let m: RegExpExecArray | null = metaRe.exec(html);
  while (m !== null) {
    const tag: string = m[0];
    if (/name=["']csrf-token["']/i.test(tag)) {
      const c: RegExpExecArray | null = /content=["']([^"']*)["']/i.exec(tag);
      if (c !== null) {
        return c[1];
      }
    }
    m = metaRe.exec(html);
  }
  return '';
}

/** 登录页提取 `#public` 隐藏域 value（RSA 公钥 PEM；属性值内换行为实体，需先解码） */
function extractPublicInput(html: string): string {
  const inputRe: RegExp = /<input[^>]*>/gi;
  let m: RegExpExecArray | null = inputRe.exec(html);
  while (m !== null) {
    const tag: string = m[0];
    if (/\sid=["']public["']/i.test(tag)) {
      const v: RegExpExecArray | null = /value=["']([^"']*)["']/i.exec(tag);
      if (v !== null) {
        return decodeEntities(v[1]);
      }
    }
    m = inputRe.exec(html);
  }
  return '';
}

// ============================================================
// 服务
// ============================================================

export class CampusNetworkService {
  private http: HttpClient;
  private auth: TsinghuaAuthService;

  constructor(http: HttpClient, auth: TsinghuaAuthService) {
    this.http = http;
    this.auth = auth;
  }

  /**
   * 会话探测：请求网络登录入口页——
   * 命中 WebVPN 登录页标记 → 会话失效；命中验证码表单标记 → 抛 NetworkCaptchaRequiredError。
   */
  private async ensureNetworkLoggedIn(): Promise<void> {
    const resp: HttpResponse = await this.http.get(NETWORK_LOGIN_URL);
    const html: string = resp.body;
    Log.i('CampusNetwork', 'PROBE code=%{public}d len=%{public}d', resp.statusCode, html.length);
    if (html.indexOf(WEBVPN_TITLE_MARK) >= 0) {
      throw new Error('校园网 WebVPN 会话失效，请重新登录后再试');
    }
    if (html.indexOf(CAPTCHA_FORM_MARK) >= 0) {
      throw new NetworkCaptchaRequiredError();
    }
  }

  /**
   * 两层兜底（对齐原项目 withNetworkRetry）：探测 + 操作；
   * 验证码错误直接抛出（恢复无意义），其余交 withSessionRecovery
   * （默认 reroam info 门户，仍失败则完整重登录）。
   */
  private async withNetworkRetry<T>(operation: () => Promise<T>): Promise<T> {
    const run = async (): Promise<T> => {
      await this.ensureNetworkLoggedIn();
      return operation();
    };
    try {
      return await run();
    } catch (e) {
      if (e instanceof NetworkCaptchaRequiredError) {
        throw e;
      }
      return this.auth.withSessionRecovery<T>(run, undefined, 'campus-network');
    }
  }

  /** 校园网快照：探测 → 首页（余额 + 设备 + 状态）→ 账户信息 → 允许设备数 → 组装 */
  async getNetworkSnapshot(): Promise<NetworkSnapshot> {
    return this.withNetworkRetry<NetworkSnapshot>(async (): Promise<NetworkSnapshot> => {
      const homeResp: HttpResponse = await this.http.get(NETWORK_HOME_URL);
      const homeHtml: string = homeResp.body;
      const balance: NetworkBalance = parseBalance(homeHtml);
      const devices: NetworkDevice[] = parseDevices(homeHtml);
      const status: string = iconParentText(homeHtml, 'glyphicon-info-sign');

      const usersResp: HttpResponse = await this.http.get(NETWORK_USER_INFO_URL);
      const users: string[] = parseAccountCells(usersResp.body);

      const allowedResp: HttpResponse = await this.http.get(NETWORK_ALLOWED_DEVICES_URL);
      const allowedText: string = iconParentText(allowedResp.body, 'glyphicon-exclamation-sign');
      const allowedMatch: RegExpExecArray | null = /(\d+)/.exec(allowedText);
      const allowedDevices: number = allowedMatch !== null ? (Number(allowedMatch[1]) || 0) : 0;

      const account: NetworkAccountInfo = new NetworkAccountInfo();
      account.username = users.length > 0 ? users[0] : '';
      account.contactEmail = users.length > 1 ? users[1] : '';
      account.contactPhone = users.length > 2 ? users[2] : '';
      account.location = users.length > 3 ? users[3] : '';
      account.contactLandline = users.length > 5 ? users[5] : '';
      account.realName = users.length > 6 ? users[6] : '';
      account.userGroup = users.length > 7 ? users[7] : '';
      account.status = status;
      account.allowedDevices = allowedDevices;

      const snapshot: NetworkSnapshot = new NetworkSnapshot();
      snapshot.balance = balance;
      snapshot.account = account;
      snapshot.devices = devices;
      Log.i('CampusNetwork', 'SNAPSHOT devices=%{public}d allowed=%{public}d',
        devices.length, allowedDevices);
      return snapshot;
    });
  }

  /**
   * 注销在线设备（唯一写操作）：探测 → 首页提取 CSRF → postForm 携带 CSRF
   * 至删除端点（id/user_mac 百分号编码）→ 按成功标记判定，失败提取服务端错误文本。
   */
  async logoutNetworkDevice(key: number, mac: string): Promise<NetworkLogoutResult> {
    return this.withNetworkRetry<NetworkLogoutResult>(async (): Promise<NetworkLogoutResult> => {
      const homeResp: HttpResponse = await this.http.get(NETWORK_HOME_URL);
      const homeHtml: string = homeResp.body;
      const csrf: string = extractCsrf8800(homeHtml);
      if (csrf.length === 0) {
        throw new Error('校园网注销缺少必要令牌，请刷新后重试');
      }
      const url: string = NETWORK_HOME_DELETE_URL
        .replace('{id}', encodeURIComponent(String(key)))
        .replace('{mac}', encodeURIComponent(mac));
      const form: Record<string, string> = {};
      form['_csrf-8800'] = csrf;
      const resp: HttpResponse = await this.http.postForm(url, form);
      const resultHtml: string = resp.body;
      Log.i('CampusNetwork', 'LOGOUT key=%{public}d code=%{public}d len=%{public}d',
        key, resp.statusCode, resultHtml.length);

      const result: NetworkLogoutResult = new NetworkLogoutResult();
      if (resultHtml.indexOf('w5-success-0') >= 0) {
        result.ok = true;
        result.message = '设备已注销';
        return result;
      }
      const errorText: string = alertTextById(resultHtml, 'w5-danger-0');
      result.ok = false;
      result.message = errorText.length > 0 ? errorText : '设备注销失败';
      return result;
    });
  }

  /**
   * 获取验证码图片（data URI，供 Image 直接渲染）：
   * `?refresh=1` 预热触发新验证码并落 Cookie，再以一次性随机参数取图规避缓存；
   * getBytes 取响应原始字节（不走文本解码——图片二进制经文本解码会损坏）。
   * 单发不套探测/恢复链（探测在验证码态必抛 NetworkCaptchaRequiredError）。
   */
  async fetchCaptchaImage(): Promise<string> {
    await this.http.getBytes(NETWORK_CAPTCHA_URL + '?refresh=1');
    const bytes: Uint8Array = await this.http.getBytes(
      NETWORK_CAPTCHA_URL + '?_=' + Date.now().toString());
    if (bytes.length === 0) {
      throw new Error('验证码图片获取失败，请重试');
    }
    const helper: util.Base64Helper = new util.Base64Helper();
    const base64: string = helper.encodeToStringSync(bytes);
    Log.i('CampusNetwork', 'CAPTCHA_IMG bytes=%{public}d b64=%{public}d', bytes.length, base64.length);
    return 'data:image/png;base64,' + base64;
  }

  /**
   * 验证码登录（单发，不套 withNetworkRetry——探测在验证码态必抛验证码错误，
   * 会话恢复重试则可能重复提交登录表单；调用方捕获后展示错误并刷新验证码）：
   * ① 校验输入 → ② 登录页取参（meta csrf / 表单 csrf / RSA 公钥，缺一即失败）→
   * ③ 漫游信息门户用户信息子系统，从 HTML 提取邮箱前缀为账号名 →
   * ④ RSA PKCS#1 v1.5 加密密码（对齐参考 JSEncrypt 默认填充）→
   * ⑤ validate-user 校验（X-CSRF-Token / X-Requested-With 头）→
   * ⑥ 提交登录表单 → ⑦ 复探测确认（仍见验证码表单 = 登录未生效）。
   */
  async loginNetworkWithCaptcha(code: string): Promise<void> {
    const verifyCode: string = code.trim();
    if (verifyCode.length === 0) {
      throw new Error('请输入验证码');
    }

    // ② 登录页参数（会话失效时该页为 WebVPN 登录页，取不到参数 → 引导重试）
    const loginResp: HttpResponse = await this.http.get(NETWORK_LOGIN_URL);
    const loginHtml: string = loginResp.body;
    const metaCsrf: string = extractMetaCsrfToken(loginHtml);
    const formCsrf: string = extractCsrf8800(loginHtml);
    const publicKey: string = extractPublicInput(loginHtml);
    Log.i('CampusNetwork', 'CAPTCHA_LOGIN params meta=%{public}d form=%{public}d pub=%{public}d',
      metaCsrf.length, formCsrf.length, publicKey.length);
    if (metaCsrf.length === 0 || formCsrf.length === 0 || publicKey.length === 0) {
      throw new Error('校园网登录页缺少必要参数，请刷新后重试');
    }

    // ③ 漫游信息门户用户信息子系统，从页面脚本提取邮箱账号名
    const dataService: CampusDataService = new CampusDataService(this.http);
    const userInfoHtml: string = await dataService.roamByYyfwidHtml(USER_INFO_YYFWID);
    const addrMatch: RegExpExecArray | null = /'addr':'(.+?)@mails\.tsinghua\.edu\.cn'/.exec(userInfoHtml);
    const username: string = addrMatch !== null ? addrMatch[1] : '';
    if (username.length === 0) {
      throw new Error('无法获取校园网账号名，请稍后重试');
    }

    // ④ 密码加密（PKCS#1 v1.5）
    const creds: SecureCredentials | undefined = await SecureStorage.getCredentials();
    const password: string = creds !== undefined ? creds.password : '';
    let encrypted: string = '';
    try {
      encrypted = rsaEncryptPkcs1(password, publicKey);
    } catch (e) {
      Log.i('CampusNetwork', 'CAPTCHA_LOGIN rsa_ex=%{public}s', e instanceof Error ? e.message : String(e));
      throw new Error('校园网密码加密失败，请重试');
    }

    // ⑤ validate-user 校验（Ajax 头 + JSON 响应）
    const validateHeaders: Record<string, string> = {};
    validateHeaders['X-CSRF-Token'] = metaCsrf;
    validateHeaders['X-Requested-With'] = 'XMLHttpRequest';
    validateHeaders['Content-Type'] = 'application/x-www-form-urlencoded; charset=UTF-8';
    const validateForm: Record<string, string> = {};
    validateForm['LoginForm[username]'] = username;
    validateForm['LoginForm[password]'] = encrypted;
    validateForm['LoginForm[verifyCode]'] = verifyCode;
    const validateResp: HttpResponse =
      await this.http.postFormWithHeaders(NETWORK_VALIDATE_USER_URL, validateForm, validateHeaders);
    let validateJson: Record<string, Object>;
    try {
      validateJson = JSON.parse(validateResp.body) as Record<string, Object>;
    } catch (e) {
      Log.i('CampusNetwork', 'CAPTCHA_LOGIN validate_non_json head=%{public}s',
        validateResp.body.substring(0, 120));
      throw new Error('校园网验证码登录失败');
    }
    if (String(validateJson['success'] ?? '') !== 'true') {
      const message: string = String(validateJson['message'] ?? '');
      throw new Error(message.length > 0 ? message : '校园网验证码登录失败');
    }

    // ⑥ 提交登录表单
    const loginForm: Record<string, string> = {};
    loginForm['_csrf-8800'] = formCsrf;
    loginForm['LoginForm[username]'] = username;
    loginForm['LoginForm[password]'] = encrypted;
    loginForm['LoginForm[verifyCode]'] = verifyCode;
    loginForm['LoginForm[smsCode]'] = '';
    const submitResp: HttpResponse = await this.http.postForm(NETWORK_LOGIN_URL, loginForm);
    Log.i('CampusNetwork', 'CAPTCHA_LOGIN submit code=%{public}d len=%{public}d',
      submitResp.statusCode, submitResp.body.length);

    // ⑦ 复探测确认（仍见验证码表单 = 登录未生效）
    try {
      await this.ensureNetworkLoggedIn();
    } catch (e) {
      if (e instanceof NetworkCaptchaRequiredError) {
        throw new Error('校园网验证码登录失败，请稍后重试');
      }
      if (e instanceof Error) {
        throw e;
      }
      throw new Error(String(e));
    }
    Log.i('CampusNetwork', 'CAPTCHA_LOGIN ok user=%{public}s', username);
  }
}
