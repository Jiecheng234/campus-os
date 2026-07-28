import { http } from '@kit.NetworkKit';
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

export class HttpClient {
  private cookieJar: CookieJar;
  private timeoutMs: number = 30000;

  constructor(cookieJar: CookieJar) {
    this.cookieJar = cookieJar;
  }

  setTimeout(ms: number): void {
    this.timeoutMs = ms;
  }

  async get(url: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    return this.request('GET', url, '', extraHeaders);
  }

  async post(url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    return this.request('POST', url, body, extraHeaders);
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
    return this.request('POST', url, body, headers);
  }

  getCookieString(url: string): string {
    return this.cookieJar.getCookieString(url);
  }

  clearCookies(): void {
    this.cookieJar.clear();
  }

  private async request(method: string, url: string, body: string, extraHeaders?: Record<string, string>): Promise<HttpResponse> {
    const req: http.HttpRequest = http.createHttp();

    const isPost: boolean = method === 'POST';
    let headerObj: Record<string, Object> = {};
    const existingCookies: string = this.cookieJar.getCookieString(url);
    if (existingCookies.length > 0) {
      headerObj['Cookie'] = existingCookies;
    }
    if (extraHeaders !== undefined) {
      const keys: string[] = Object.keys(extraHeaders);
      for (let i: number = 0; i < keys.length; i++) {
        headerObj[keys[i]] = extraHeaders[keys[i]];
      }
    }

    const requestOptions: http.HttpRequestOptions = {
      method: isPost ? http.RequestMethod.POST : http.RequestMethod.GET,
      header: headerObj,
      extraData: isPost ? body : body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: this.timeoutMs,
      readTimeout: this.timeoutMs,
    };

    return new Promise<HttpResponse>((resolve: (value: HttpResponse) => void, reject: (reason: HttpError) => void) => {
      req.request(url, requestOptions).then((resp: http.HttpResponse) => {
        const response: HttpResponse = new HttpResponse();
        response.statusCode = resp.responseCode;
        if (typeof resp.result === 'string') {
          response.body = resp.result;
        }
        response.headers = {};
        resolve(response);
      }).catch((error: BusinessError) => {
        const httpError: HttpError = new HttpError();
        httpError.message = error.message;
        httpError.statusCode = error.code;
        reject(httpError);
      });
    });
  }
}
