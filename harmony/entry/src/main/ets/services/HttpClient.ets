import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CookieJar } from './CookieJar';

export class HttpResponse {
  statusCode: number = 0;
  body: string = '';
  headers: Record<string, string> = {};
}

export class HttpError extends Error {
  statusCode: number = 0;
  body: string = '';
}

function getSetCookieFromHeaders(headers: Record<string, string | string[] | undefined>): string {
  let val = headers['Set-Cookie'];
  if (val === undefined) {
    val = headers['set-cookie'];
  }
  if (val === undefined) {
    return '';
  }
  if (typeof val === 'string') {
    return val;
  }
  if (Array.isArray(val) && val.length > 0) {
    return val[0];
  }
  return '';
}

export class HttpClient {
  private cookieJar: CookieJar;
  private timeoutMs: number = 60000;
  private maxRedirects: number = 30;
  private session: rcp.Session;

  constructor(cookieJar: CookieJar) {
    this.cookieJar = cookieJar;
    this.session = rcp.createSession();
  }

  setTimeout(ms: number): void {
    this.timeoutMs = ms;
  }

  async get(url: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    return this.autoFollow('GET', url, '', extraHeaders);
  }

  async post(url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    return this.autoFollow('POST', url, body, extraHeaders);
  }

  async postForm(url: string, formData: Record<string, string>, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    const parts: string[] = [];
    const keys: string[] = Object.keys(formData);
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i];
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(formData[k]));
    }
    const body: string = parts.join('&');
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    if (extraHeaders !== undefined) {
      const extraKeys: string[] = Object.keys(extraHeaders);
      for (let i: number = 0; i < extraKeys.length; i++) {
        const k: string = extraKeys[i];
        headers[k] = extraKeys[k];
      }
    }
    return this.autoFollow('POST', url, body, headers);
  }

  getCookieString(url: string): string {
    return this.cookieJar.getCookieString(url);
  }

  clearCookies(): void {
    this.cookieJar.clear();
    this.session.close();
    this.session = rcp.createSession();
  }

  private async autoFollow(method: string, url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    let currentMethod: string = method;
    let currentUrl: string = url;
    let currentBody: string = body;

    for (let hop: number = 0; hop < this.maxRedirects; hop++) {
      const resp: HttpResponse = await this.rcpRequest(currentMethod, currentUrl, currentBody, extraHeaders);
      const status: number = resp.statusCode;

      if (status < 300 || status >= 400) {
        return resp;
      }

      const location: string = resp.headers['Location'] || resp.headers['location'] || '';
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

  private async rcpRequest(method: string, url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    const existingCookies: string = this.cookieJar.getCookieString(url);

    const reqHeaders: Record<string, string> = {};
    if (existingCookies.length > 0) {
      reqHeaders['Cookie'] = existingCookies;
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

    const req: rcp.Request = new rcp.Request(url, method, reqHeaders, body, undefined, undefined, config);

    try {
      const resp: rcp.Response = await this.session.fetch(req);
      const httpResp: HttpResponse = new HttpResponse();
      httpResp.statusCode = resp.statusCode;
      httpResp.body = resp.toString() ?? '';

      const setCookie: string = getSetCookieFromHeaders(resp.headers);
      if (setCookie.length > 0) {
        this.cookieJar.setFromResponse(url, setCookie);
      }

      const locationValue = resp.headers['Location'];
      if (typeof locationValue === 'string') {
        httpResp.headers['Location'] = locationValue;
      } else if (Array.isArray(locationValue) && locationValue.length > 0) {
        httpResp.headers['Location'] = locationValue[0];
      } else if (locationValue === undefined) {
        httpResp.headers['Location'] = '';
      } else {
        httpResp.headers['Location'] = String(locationValue);
      }

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
