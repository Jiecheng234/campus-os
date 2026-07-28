import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export class HttpResponse {
  statusCode: number = 0;
  body: string = '';
}

export class HttpError extends Error {
  statusCode: number = 0;
}

export class HttpClient {
  private timeoutMs: number = 60000;
  private session: rcp.Session;

  constructor() {
    this.session = rcp.createSession();
  }

  setTimeout(ms: number): void {
    this.timeoutMs = ms;
  }

  async get(url: string): Promise<HttpResponse> {
    return this.rcpRequest('GET', url, '');
  }

  async postForm(url: string, formData: Record<string, string>): Promise<HttpResponse> {
    const parts: string[] = [];
    const keys: string[] = Object.keys(formData);
    for (let i: number = 0; i < keys.length; i++) {
      const k: string = keys[i];
      parts.push(encodeURIComponent(k) + '=' + encodeURIComponent(formData[k]));
    }
    const body: string = parts.join('&');
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/x-www-form-urlencoded';
    return this.rcpRequest('POST', url, body, headers);
  }

  clearSession(): void {
    this.session.close();
    this.session = rcp.createSession();
  }

  getSession(): rcp.Session {
    return this.session;
  }

  private async rcpRequest(method: string, url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    const reqHeaders: Record<string, string> = {};
    if (extraHeaders !== undefined) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i: number = 0; i < keys.length; i++) {
        reqHeaders[keys[i]] = extraHeaders[keys[i]];
      }
    }

    const config: rcp.Configuration = {
      transfer: {
        autoRedirect: true,
        timeout: { connectMs: this.timeoutMs, transferMs: this.timeoutMs }
      }
    };

    const req: rcp.Request = new rcp.Request(url, method, reqHeaders, body, undefined, undefined, config);

    try {
      const resp: rcp.Response = await this.session.fetch(req);
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
