import { HttpClient, HttpResponse } from './HttpClient';
import { CookieJar } from './CookieJar';
import { WEBVPN_BASE_URL, WEBVPN_OAUTH_LOGIN_URL, SUBSYSTEM_INFO, SUBSYSTEM_LEARN, SUBSYSTEM_ID, getSubsystemUrl, CAMPUS_ENDPOINTS } from './WebvpnConstants';

export class WebvpnTransport {
  private http: HttpClient;
  private cookieJar: CookieJar;
  private roamedSystems: string[] = [];

  constructor(http: HttpClient, cookieJar: CookieJar) {
    this.http = http;
    this.cookieJar = cookieJar;
  }

  getCookieJar(): CookieJar {
    return this.cookieJar;
  }

  getHttp(): HttpClient {
    return this.http;
  }

  async getOAuthPage(): Promise<string> {
    const resp: HttpResponse = await this.http.get(WEBVPN_OAUTH_LOGIN_URL);
    return resp.body;
  }

  async postLoginForm(formData: Record<string, string>): Promise<HttpResponse> {
    const headers: Record<string, string> = {
      'Referer': WEBVPN_OAUTH_LOGIN_URL,
      'Origin': WEBVPN_BASE_URL,
    };
    return this.http.postForm(WEBVPN_OAUTH_LOGIN_URL, formData, headers);
  }

  async post2FAForm(formData: Record<string, string>): Promise<HttpResponse> {
    const headers: Record<string, string> = {
      'Referer': WEBVPN_OAUTH_LOGIN_URL,
      'Origin': WEBVPN_BASE_URL,
    };
    return this.http.postForm(WEBVPN_OAUTH_LOGIN_URL, formData, headers);
  }

  async roamToSubsystem(subsystem: string): Promise<boolean> {
    if (this.roamedSystems.indexOf(subsystem) >= 0) {
      return true;
    }
    const url: string = getSubsystemUrl(subsystem);
    if (url.length === 0) {
      return false;
    }
    const resp: HttpResponse = await this.http.get(url);
    if (resp.statusCode >= 200 && resp.statusCode < 400) {
      this.roamedSystems.push(subsystem);
      return true;
    }
    return false;
  }

  async roamToAllSubsystems(): Promise<boolean[]> {
    const results: boolean[] = [];
    const result1: boolean = await this.roamToSubsystem(SUBSYSTEM_INFO);
    results.push(result1);
    const result2: boolean = await this.roamToSubsystem(SUBSYSTEM_LEARN);
    results.push(result2);
    const result3: boolean = await this.roamToSubsystem(SUBSYSTEM_ID);
    results.push(result3);
    return results;
  }

  async fetchCampusEndpoint(endpointKey: string): Promise<string> {
    const url: string = CAMPUS_ENDPOINTS[endpointKey];
    if (url === undefined || url.length === 0) {
      return '';
    }
    const resp: HttpResponse = await this.http.get(url);
    return resp.body;
  }

  async fetchCampusEndpointPost(endpointKey: string, formData: Record<string, string>): Promise<string> {
    const url: string = CAMPUS_ENDPOINTS[endpointKey];
    if (url === undefined || url.length === 0) {
      return '';
    }
    const resp: HttpResponse = await this.http.postForm(url, formData);
    return resp.body;
  }

  clearSession(): void {
    this.cookieJar.clear();
    this.roamedSystems = [];
  }

  saveSession(): string {
    const data: Record<string, Object> = {
      'cookies': this.cookieJar.serialize(),
      'roamed': this.roamedSystems,
    };
    return JSON.stringify(data);
  }

  restoreSession(jsonStr: string): void {
    if (jsonStr.length === 0) {
      return;
    }
    const data: Record<string, Object> = JSON.parse(jsonStr) as Record<string, Object>;
    const cookiesStr: string = data['cookies'] as string;
    this.cookieJar.deserialize(cookiesStr);
    const roamed: string[] = data['roamed'] as string[];
    if (roamed !== undefined) {
      this.roamedSystems = roamed;
    }
  }
}
