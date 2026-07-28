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

interface PendingRequest {
  resolve: (value: HttpResponse) => void;
  reject: (reason: HttpError) => void;
  url: string;
  requestOptions: http.HttpRequestOptions;
  depth: number;
}

export class HttpClient {
  private cookieJar: CookieJar;
  private timeoutMs: number = 30000;
  private maxRedirects: number = 30;

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

    return this.interceptedRequest(url, requestOptions, 0);
  }

  private interceptedRequest(url: string, requestOptions: http.HttpRequestOptions, depth: number): Promise<HttpResponse> {
    return new Promise<HttpResponse>((resolve: (value: HttpResponse) => void, reject: (reason: HttpError) => void) => {
      if (depth >= this.maxRedirects) {
        const err: HttpError = new HttpError();
        err.message = 'Too many redirects';
        reject(err);
        return;
      }

      const innerReq: http.HttpRequest = http.createHttp();
      let redirectUrl: string = '';
      let responseHeaders: Record<string, string> = {};

      innerReq.on('headersReceive', (header: Object) => {
        if (header === undefined || header === null) {
          return;
        }
        const headerRecord: Record<string, Object> = header as Record<string, Object>;
        const location: string = String(headerRecord['Location'] || '');
        if (location.length > 0) {
          redirectUrl = location;
          innerReq.destroy();
        }
        responseHeaders['Location'] = location;
      });

      innerReq.request(url, requestOptions).then((resp: http.HttpResponse) => {
        innerReq.destroy();

        if (redirectUrl.length > 0) {
          const followOptions: http.HttpRequestOptions = {
            method: http.RequestMethod.GET,
            header: requestOptions.header,
            extraData: '',
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: requestOptions.connectTimeout,
            readTimeout: requestOptions.readTimeout,
          };
          this.interceptedRequest(redirectUrl, followOptions, depth + 1).then((result: HttpResponse) => {
            resolve(result);
          }).catch((err: HttpError) => {
            reject(err);
          });
          return;
        }

        const response: HttpResponse = new HttpResponse();
        response.statusCode = resp.responseCode;
        if (typeof resp.result === 'string') {
          response.body = resp.result;
        }
        response.headers = responseHeaders;
        resolve(response);
      }).catch((error: BusinessError) => {
        innerReq.destroy();

        if (redirectUrl.length > 0) {
          const followOptions: http.HttpRequestOptions = {
            method: http.RequestMethod.GET,
            header: requestOptions.header,
            extraData: '',
            expectDataType: http.HttpDataType.STRING,
            connectTimeout: requestOptions.connectTimeout,
            readTimeout: requestOptions.readTimeout,
          };
          this.interceptedRequest(redirectUrl, followOptions, depth + 1).then((result: HttpResponse) => {
            resolve(result);
          }).catch((err: HttpError) => {
            reject(err);
          });
          return;
        }

        const httpError: HttpError = new HttpError();
        httpError.message = error.message;
        httpError.statusCode = error.code;
        reject(httpError);
      });
    });
  }
}
