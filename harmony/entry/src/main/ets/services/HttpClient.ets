/**
 * ============================================================================
 * HttpClient — 基于 RCP 的 HTTP 客户端封装（认证/数据链路的网络底座）
 * ============================================================================
 *
 * 职责：
 *   - 手动 Cookie 管理（CookieManager）：RCP 原生 cookie 与跨域重定向处理不符合
 *     清华 SSO 链需求，故禁用 RCP autoRedirect + 自带 CookieManager 手动同步。
 *   - 手动重定向（manualRedirect）：3xx 时 follow Location，重写 method 为 GET、清空 body。
 *   - GBK 解码：响应头 charset 优先；头无声明时按 URL 标记（isGbkUrl）回退 GBK，
 *     并做严格 UTF-8 嗅探兜底（webvpn 会把部分 zhjw 响应重编码为 UTF-8）。
 *   - POST urlencoded：postForm 自动拼 Content-Type: application/x-www-form-urlencoded
 *     【关键】缺了这个头会导致清华 ID 登录失败（响应异常短）。
 *   - getBytes：GET 响应体原始字节（验证码图片等二进制，不做文本解码）；
 *     postFormWithHeaders：urlencoded POST + 自定义请求头（X-CSRF-Token 等）。
 *
 * 注意：
 *   - lastSetCookies 暴露最近一次响应的原始 Set-Cookie（用于诊断，如 cookieSync 排查）。
 *   - 307/308 语义上应保留 method+body，当前统一转 GET（清华主要用 302，影响小）。
 *   - callback 类一次性 SSO URL 只能 follow 一次（重复消费会清 WebVPN 会话）。
 * ============================================================================
 */
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CookieManager } from './CookieManager';
import { decodeGBK, isGBKContentType } from '../utils/EncodingUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** JSON 请求体标量值（ArkTS 禁止原始类型装箱，Record 值域用原始类型联合） */
export type JsonBodyValue = string | number | boolean;

export class HttpResponse {
  statusCode: number = 0;
  body: string = '';
}

export class HttpError extends Error {
  statusCode: number = 0;
}

/** 原始字节响应（getBytes 用；响应体不经字符集解码，二进制安全） */
class HttpBytesResponse {
  statusCode: number = 0;
  bytes: Uint8Array = new Uint8Array(0);
}

/** 统一 User-Agent（既有 rcpRequest 同款） */
const USER_AGENT: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.88 Safari/537.36';

function getLocationFromHeaders(headers: Record<string, string | string[] | undefined>): string {
  const v = headers['Location'] || headers['location'];
  if (typeof v === 'string') { return v; }
  if (Array.isArray(v) && v.length > 0) { return v[0]; }
  return '';
}

function getSetCookieFromHeaders(headers: Record<string, string | string[] | undefined>): string[] {
  const results: string[] = [];
  const keys: string[] = Object.keys(headers);
  for (let i: number = 0; i < keys.length; i++) {
    if (keys[i].toLowerCase() === 'set-cookie') {
      const v = headers[keys[i]];
      if (typeof v === 'string') { results.push(v); }
      else if (Array.isArray(v)) {
        for (let j: number = 0; j < v.length; j++) { results.push(v[j]); }
      }
    }
  }
  return results;
}

function resolveUrl(baseUrl: string, relative: string): string {
  if (relative.startsWith('http://') || relative.startsWith('https://')) {
    return relative;
  }
  if (relative.startsWith('/')) {
    let base: string = baseUrl;
    const protoEnd: number = base.indexOf('://');
    if (protoEnd > 0) {
      const afterProto: string = base.substring(protoEnd + 3);
      const slash: number = afterProto.indexOf('/');
      if (slash > 0) {
        base = base.substring(0, protoEnd + 3 + slash);
      }
    }
    return base + relative;
  }
  return baseUrl + '/' + relative;
}

/**
 * 这些 webvpn token 对应的清华子系统后端默认 GBK 编码（对齐原项目 GBK_WEBVPN_TOKENS）。
 * 命中其中之一时即便响应头没声明 charset 也按 GBK 解码。
 */
const GBK_URL_MARKERS: string[] = [
  'eaff4b8b69336153301c9aa596522b20bc86e6e559a9b290', // zhjw 教务（成绩/课表/教室/培养方案/学籍）
  'fdee49932a3526446d0187ab9040227bca90a6e14cc9',     // yhdf 电费充值
  'eaff4b8b3f3b2653770bc7b88b5c2d320506b1aec738590a49ba', // cr_xk 选课系统
  'a5a70f8834396657761d88e29d51367b6a00',             // gymbook 体育场馆预约
  'zhjw.cic.tsinghua.edu.cn',                          // 直连教务系统
];

function isGbkUrl(url: string): boolean {
  for (let i: number = 0; i < GBK_URL_MARKERS.length; i++) {
    if (url.indexOf(GBK_URL_MARKERS[i]) >= 0) {
      return true;
    }
  }
  return false;
}

/** 从 Content-Type 解析已声明的 charset（无声明返回空串） */
function charsetFromContentType(contentType: string): string {
  const m: RegExpExecArray | null = /charset=([^;\s'"]+)/i.exec(contentType);
  if (m !== null && m.length >= 2 && m[1].length > 0) {
    return m[1].toLowerCase().replace(/['"]/g, '');
  }
  return '';
}

function hasNonAsciiByte(bytes: Uint8Array): boolean {
  for (let i: number = 0; i < bytes.length; i++) {
    if (bytes[i] >= 0x80) {
      return true;
    }
  }
  return false;
}

/** 严格 UTF-8 字节级校验——GBK 中文响应体几乎不可能整段通过（对齐原项目 header 优先 + 标记回退策略的加固） */
function isValidUtf8(bytes: Uint8Array): boolean {
  let i: number = 0;
  while (i < bytes.length) {
    const b: number = bytes[i];
    if (b < 0x80) {
      i++;
      continue;
    }
    let seqLen: number = 0;
    if (b >= 0xC2 && b <= 0xDF) {
      seqLen = 2;
    } else if (b >= 0xE0 && b <= 0xEF) {
      seqLen = 3;
    } else if (b >= 0xF0 && b <= 0xF4) {
      seqLen = 4;
    } else {
      return false;
    }
    if (i + seqLen > bytes.length) {
      return false;
    }
    for (let j: number = 1; j < seqLen; j++) {
      const c: number = bytes[i + j];
      if (c < 0x80 || c > 0xBF) {
        return false;
      }
    }
    i += seqLen;
  }
  return true;
}

export class HttpClient {
  private cookieManager: CookieManager;
  private timeoutMs: number = 60000;
  private maxRedirects: number = 30;
  private session: rcp.Session;
  public lastSetCookies: string[] = [];

  constructor(cookieManager: CookieManager) {
    this.cookieManager = cookieManager;
    this.session = rcp.createSession();
  }

  setTimeout(ms: number): void {
    this.timeoutMs = ms;
  }

  async get(url: string): Promise<HttpResponse> {
    return this.manualRedirect('GET', url, '');
  }

  async postForm(url: string, formData: Record<string, string>): Promise<HttpResponse> {
    const parts: string[] = [];
    const keys: string[] = Object.keys(formData);
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i];
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(formData[k]));
    }
    const body: string = parts.join('&');
    const extraHeaders: Record<string, string> = {};
    extraHeaders['Content-Type'] = 'application/x-www-form-urlencoded';
    return this.manualRedirect('POST', url, body, extraHeaders);
  }

  /** POST application/json（校园卡等 JSON API） */
  async postJson(url: string, jsonBody: Record<string, JsonBodyValue>): Promise<HttpResponse> {
    const body: string = JSON.stringify(jsonBody);
    const extraHeaders: Record<string, string> = {};
    extraHeaders['Content-Type'] = 'application/json';
    return this.manualRedirect('POST', url, body, extraHeaders);
  }

  /**
   * GET 响应体原始字节（验证码图片等二进制内容用）：
   * 复用既有会话（Cookie 注入 + 手动重定向跟随 Location），但**不做文本解码**——
   * 既有 get() 返回按字符集解码的文本，直接用于图片会损坏内容。
   */
  async getBytes(url: string): Promise<Uint8Array> {
    let currentUrl: string = url;
    for (let hop: number = 0; hop < this.maxRedirects; hop++) {
      const resp: HttpBytesResponse = await this.rcpRequestBytes(currentUrl);
      if (resp.statusCode < 300 || resp.statusCode >= 400) {
        return resp.bytes;
      }
      const location: string = getLocationFromHeaders(this.lastResponseHeaders);
      if (location.length === 0) {
        return resp.bytes;
      }
      currentUrl = resolveUrl(currentUrl, location);
    }
    const err: HttpError = new HttpError();
    err.message = 'Too many redirects';
    throw err;
  }

  /**
   * GET 跟随重定向返回最终落点地址（研读间 cab 登录用，等价 XHR responseURL）：
   * 复用既有请求头/Cookie 注入与手动重定向循环（manualRedirect 同款语义），
   * 但不返回响应体，而是返回最终请求落点的完整地址。
   * 不改动既有 get/postForm/postJson/manualRedirect 的签名与行为。
   */
  async resolveFinalUrl(url: string): Promise<string> {
    let currentUrl: string = url;
    for (let hop: number = 0; hop < this.maxRedirects; hop++) {
      const resp: HttpResponse = await this.rcpRequest('GET', currentUrl, '');
      const status: number = resp.statusCode;
      if (status < 300 || status >= 400) {
        return currentUrl;
      }
      const location: string = getLocationFromHeaders(this.lastResponseHeaders);
      if (location.length === 0) {
        return currentUrl;
      }
      currentUrl = resolveUrl(currentUrl, location);
    }
    const err: HttpError = new HttpError();
    err.message = 'Too many redirects';
    throw err;
  }

  /**
   * POST urlencoded + 自定义请求头：请求体编码与既有 postForm 完全一致，
   * 另将 extraHeaders（X-CSRF-Token / X-Requested-With / 带 charset 的 Content-Type 等）
   * 并入请求头；不改动既有 postForm 的签名与行为。
   */
  async postFormWithHeaders(url: string, formData: Record<string, string>, extraHeaders: Record<string, string>): Promise<HttpResponse> {
    const parts: string[] = [];
    const keys: string[] = Object.keys(formData);
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i];
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(formData[k]));
    }
    const body: string = parts.join('&');
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    const extraKeys: string[] = Object.keys(extraHeaders);
    for (let i: number = 0; i < extraKeys.length; i++) {
      headers[extraKeys[i]] = extraHeaders[extraKeys[i]];
    }
    return this.manualRedirect('POST', url, body, headers);
  }

  clearSession(): void {
    this.cookieManager.clear();
    this.session.close();
    this.session = rcp.createSession();
  }

  getCookieManager(): CookieManager {
    return this.cookieManager;
  }

  private async manualRedirect(method: string, url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    let currentMethod: string = method;
    let currentUrl: string = url;
    let currentBody: string = body;
    let currentHeaders: Record<string, string> = {};
    if (extraHeaders !== undefined) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i: number = 0; i < keys.length; i++) {
        currentHeaders[keys[i]] = extraHeaders[keys[i]];
      }
    }

    for (let hop: number = 0; hop < this.maxRedirects; hop++) {
      const resp: HttpResponse = await this.rcpRequest(currentMethod, currentUrl, currentBody, currentHeaders);
      const status: number = resp.statusCode;

      if (status < 300 || status >= 400) {
        return resp;
      }

      const location: string = getLocationFromHeaders(this.lastResponseHeaders);
      if (location.length === 0) {
        return resp;
      }

      currentMethod = 'GET';
      currentUrl = resolveUrl(currentUrl, location);
      currentBody = '';
      currentHeaders = {};
    }

    const err: HttpError = new HttpError();
    err.message = 'Too many redirects';
    throw err;
  }

  private lastResponseHeaders: Record<string, string | string[] | undefined> = {};

  /** 与 rcpRequest 同款请求装配（Cookie 注入 / Set-Cookie 回写 / 头结构），但保留响应体原始字节 */
  private async rcpRequestBytes(url: string): Promise<HttpBytesResponse> {
    const cookieHeader: string = this.cookieManager.getCookieHeader(url);

    const reqHeaders: Record<string, string> = {};
    reqHeaders['User-Agent'] = USER_AGENT;
    if (cookieHeader.length > 0) {
      reqHeaders['Cookie'] = cookieHeader;
    }

    const config: rcp.Configuration = {
      transfer: {
        autoRedirect: false,
        timeout: { connectMs: this.timeoutMs, transferMs: this.timeoutMs }
      }
    };

    const req: rcp.Request = new rcp.Request(url, 'GET', reqHeaders, '', undefined, undefined, config);

    try {
      const resp: rcp.Response = await this.session.fetch(req);
      this.lastResponseHeaders = resp.headers;

      const setCookies: string[] = getSetCookieFromHeaders(resp.headers);
      this.lastSetCookies = setCookies;
      for (let i: number = 0; i < setCookies.length; i++) {
        this.cookieManager.setFromResponse(url, setCookies[i]);
      }

      const result: HttpBytesResponse = new HttpBytesResponse();
      result.statusCode = resp.statusCode;
      // RCP 响应体本身就是原始 ArrayBuffer（本 SDK 版本无 toArrayBuffer()），
      // 直接包装为 Uint8Array 即为未解码字节
      const buf: ArrayBuffer | undefined = resp.body;
      result.bytes = buf !== undefined ? new Uint8Array(buf) : new Uint8Array(0);
      return result;
    } catch (e) {
      const err: HttpError = new HttpError();
      if (e instanceof Error) {
        err.message = e.message;
      }
      throw err;
    }
  }

  private async rcpRequest(method: string, url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    const cookieHeader: string = this.cookieManager.getCookieHeader(url);

    const reqHeaders: Record<string, string> = {};
    reqHeaders['User-Agent'] = USER_AGENT;
    if (cookieHeader.length > 0) {
      reqHeaders['Cookie'] = cookieHeader;
    }
    if (extraHeaders !== undefined) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i: number = 0; i < keys.length; i++) {
        reqHeaders[keys[i]] = extraHeaders[keys[i]];
      }
    }

    const config: rcp.Configuration = {
      transfer: {
        autoRedirect: false,
        timeout: { connectMs: this.timeoutMs, transferMs: this.timeoutMs }
      }
    };

    const isGet: boolean = method === 'GET';
    const content: string = isGet ? '' : body;
    const req: rcp.Request = new rcp.Request(url, method, reqHeaders, content, undefined, undefined, config);

    try {
      const resp: rcp.Response = await this.session.fetch(req);
      this.lastResponseHeaders = resp.headers;

      const setCookies: string[] = getSetCookieFromHeaders(resp.headers);
      this.lastSetCookies = setCookies;
      for (let i: number = 0; i < setCookies.length; i++) {
        this.cookieManager.setFromResponse(url, setCookies[i]);
      }

      const httpResp: HttpResponse = new HttpResponse();
      httpResp.statusCode = resp.statusCode;

      let contentType: string = '';
      const ctVal = resp.headers['Content-Type'] || resp.headers['content-type'];
      if (typeof ctVal === 'string') { contentType = ctVal; }
      else if (Array.isArray(ctVal) && ctVal.length > 0) { contentType = ctVal[0]; }

      // 字符集判定（对齐原项目 transport.inferResponseCharset 的优先级）：
      //   1) 响应头已声明 charset → 头优先（webvpn 会把部分 zhjw 响应重编码为 UTF-8，
      //      例如课表 jxmh_out.do JSONP；此时再强制 GBK 就会把中文解成乱码）
      //   2) 头无声明 → 按 URL 标记回退 GBK，但先做 UTF-8 嗅探：
      //      响应体含非 ASCII 且整段通过严格 UTF-8 校验 → 实际是 UTF-8
      let bodyText: string = resp.toString() ?? '';
      const buf: ArrayBuffer | undefined = resp.body;
      if (buf !== undefined) {
        const bytes: Uint8Array = new Uint8Array(buf);
        const declared: string = charsetFromContentType(contentType);
        let useGbk: boolean = false;
        if (declared.length > 0) {
          useGbk = isGBKContentType(declared);
        } else if (isGbkUrl(url)) {
          useGbk = hasNonAsciiByte(bytes) && !isValidUtf8(bytes);
        }
        if (useGbk) {
          try {
            bodyText = decodeGBK(bytes);
            hilog.info(0x0000, 'HttpClient', 'GBK decode ct=%{public}s len=%{public}d url=%{public}s',
              contentType, bytes.length, url);
          } catch (e) {
            // 解码失败保留默认解码结果
          }
        }
      }
      httpResp.body = bodyText;
      return httpResp;
    } catch (e) {
      const err: HttpError = new HttpError();
      if (e instanceof Error) {
        err.message = e.message;
      }
      throw err;
    }
  }
}
