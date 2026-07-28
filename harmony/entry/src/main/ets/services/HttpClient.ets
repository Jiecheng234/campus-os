import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CookieManager } from './CookieManager';

export class HttpResponse {
  statusCode: number = 0;
  body: string = '';
}

export class HttpError extends Error {
  statusCode: number = 0;
}

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

export class HttpClient {
  private cookieManager: CookieManager;
  private timeoutMs: number = 60000;
  private maxRedirects: number = 30;
  private session: rcp.Session;

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

    for (let hop: number = 0; hop < this.maxRedirects; hop++) {
      const resp: HttpResponse = await this.rcpRequest(currentMethod, currentUrl, currentBody);
      const status: number = resp.statusCode;

      if (status < 300 || status >= 400) {
        return resp;
      }

      const location: string = getLocationFromHeaders(this.lastResponseHeaders);
      if (location.length === 0) {
        return resp;
      }

      currentMethod = 'GET';
      currentUrl = location;
      currentBody = '';
    }

    const err: HttpError = new HttpError();
    err.message = 'Too many redirects';
    throw err;
  }

  private lastResponseHeaders: Record<string, string | string[] | undefined> = {};

  private async rcpRequest(method: string, url: string, body: string): Promise<HttpResponse> {
    const cookieHeader: string = this.cookieManager.getCookieHeader(url);

    const reqHeaders: Record<string, string> = {};
    if (cookieHeader.length > 0) {
      reqHeaders['Cookie'] = cookieHeader;
    }

    const config: rcp.Configuration = {
      transfer: {
        autoRedirect: false,
        timeout: { connectMs: this.timeoutMs, transferMs: this.timeoutMs }
      }
    };

    const req: rcp.Request = new rcp.Request(url, method, reqHeaders, body, undefined, undefined, config);

    try {
      const resp: rcp.Response = await this.session.fetch(req);
      this.lastResponseHeaders = resp.headers;

      const setCookies: string[] = getSetCookieFromHeaders(resp.headers);
      for (let i: number = 0; i < setCookies.length; i++) {
        this.cookieManager.setFromResponse(url, setCookies[i]);
      }

      const httpResp: HttpResponse = new HttpResponse();
      httpResp.statusCode = resp.statusCode;
      httpResp.body = resp.toString() ?? '';
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
