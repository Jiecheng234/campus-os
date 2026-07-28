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

function getHeaderValue(headerObj: Record<string, Object>, key: string): string {
  if (key.length === 0) {
    return '';
  }
  const val: Object = headerObj[key];
  if (val === undefined || val === null) {
    return '';
  }
  return String(val);
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
        headers[k] = extraHeaders[k];
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
    const isPost: boolean = method === 'POST';
    const existingCookies: string = this.cookieJar.getCookieString(url);

    const headerObj: Record<string, Object> = {};
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

    return this.manualRedirectRequest(url, requestOptions, 0);
  }

  private async manualRedirectRequest(url: string, requestOptions: http.HttpRequestOptions, depth: number): Promise<HttpResponse> {
    const MAX_REDIRECTS: number = 20;
    if (depth > MAX_REDIRECTS) {
      const err: HttpError = new HttpError();
      err.message = 'Too many redirects';
      err.statusCode = -1;
      throw err;
    }

    const innerReq: http.HttpRequest = http.createHttp();
    return new Promise<HttpResponse>((resolve: (value: HttpResponse) => void, reject: (reason: HttpError) => void) => {
      innerReq.request(url, requestOptions).then((resp: http.HttpResponse) => {
        innerReq.destroy();
        const status: number = resp.responseCode;
        const respHeaderObj: Record<string, Object> = {};
        if (resp.header !== undefined) {
          respHeaderObj['Location'] = resp.header['Location'];
        }
        const location: string = getHeaderValue(respHeaderObj, 'Location');

        if (status >= 300 && status < 400 && location.length > 0) {
          const followOptions: http.HttpRequestOptions = {
            method: http.RequestMethod.GET,
            header: requestOptions.header,
            extraData: '',
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: requestOptions.connectTimeout,
            readTimeout: requestOptions.readTimeout,
          };
          this.manualRedirectRequest(location, followOptions, depth + 1).then((result: HttpResponse) => {
            resolve(result);
          }).catch((err: HttpError) => {
            reject(err);
          });
          return;
        }

        const response: HttpResponse = new HttpResponse();
        response.statusCode = status;
        if (typeof resp.result === 'string') {
          response.body = resp.result;
        }
        resolve(response);
      }).catch((error: BusinessError) => {
        innerReq.destroy();
        const httpError: HttpError = new HttpError();
        httpError.message = error.message;
        httpError.statusCode = error.code;
        reject(httpError);
      });
    });
  }
}
