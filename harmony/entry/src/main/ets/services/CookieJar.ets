interface Cookie {
  name: string;
  value: string;
  domain: string;
  path: string;
  expires: number;
  secure: boolean;
  httpOnly: boolean;
}

export class CookieJar {
  private cookies: Cookie[] = [];

  setFromResponse(url: string, setCookieHeader: string): void {
    if (setCookieHeader.length === 0) {
      return;
    }
    const pairs: string[] = setCookieHeader.split(';');
    if (pairs.length === 0) {
      return;
    }
    const firstPair: string = pairs[0];
    const eqIdx: number = firstPair.indexOf('=');
    if (eqIdx < 0) {
      return;
    }
    const name: string = firstPair.substring(0, eqIdx).trim();
    const value: string = firstPair.substring(eqIdx + 1).trim();
    const domain: string = this.extractDomain(url);
    const cookie: Cookie = {
      name: name,
      value: value,
      domain: domain,
      path: '/',
      expires: 0,
      secure: false,
      httpOnly: false,
    };
    for (let i: number = 1; i < pairs.length; i++) {
      const attr: string = pairs[i].trim();
      if (attr.length === 0) {
        continue;
      }
      const kv: string[] = attr.split('=');
      const attrKey: string = kv[0].trim().toLowerCase();
      const attrVal: string = kv.length > 1 ? kv[1].trim() : '';
      if (attrKey === 'secure') {
        cookie.secure = true;
      } else if (attrKey === 'httponly') {
        cookie.httpOnly = true;
      } else if (attrKey === 'path' && attrVal.length > 0) {
        cookie.path = attrVal;
      } else if (attrKey === 'expires' && attrVal.length > 0) {
        cookie.expires = new Date(attrVal).getTime();
      } else if (attrKey === 'domain' && attrVal.length > 0) {
        cookie.domain = attrVal;
      }
    }
    this.removeByNameAndDomain(name, domain);
    this.cookies.push(cookie);
  }

  getCookieString(url: string): string {
    const domain: string = this.extractDomain(url);
    const matched: Cookie[] = [];
    for (let i: number = 0; i < this.cookies.length; i++) {
      const c: Cookie = this.cookies[i];
      if (c.domain === domain || domain.endsWith(c.domain)) {
        if (c.expires > 0 && c.expires < Date.now()) {
          continue;
        }
        matched.push(c);
      }
    }
    let result: string = '';
    for (let i: number = 0; i < matched.length; i++) {
      if (i > 0) {
        result = result + '; ';
      }
      result = result + matched[i].name + '=' + matched[i].value;
    }
    return result;
  }

  clear(): void {
    this.cookies = [];
  }

  clearDomain(url: string): void {
    const domain: string = this.extractDomain(url);
    const kept: Cookie[] = [];
    for (let i: number = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].domain !== domain && !domain.endsWith(this.cookies[i].domain)) {
        kept.push(this.cookies[i]);
      }
    }
    this.cookies = kept;
  }

  getAllCookies(): Cookie[] {
    return this.cookies;
  }

  serialize(): string {
    return JSON.stringify(this.cookies);
  }

  deserialize(jsonStr: string): void {
    if (jsonStr.length === 0) {
      return;
    }
    const arr: Cookie[] = JSON.parse(jsonStr) as Cookie[];
    this.cookies = arr;
  }

  private extractDomain(url: string): string {
    const tmp: string = url.replace('https://', '').replace('http://', '');
    const slashIdx: number = tmp.indexOf('/');
    if (slashIdx > 0) {
      return tmp.substring(0, slashIdx);
    }
    return tmp;
  }

  private removeByNameAndDomain(name: string, domain: string): void {
    const kept: Cookie[] = [];
    for (let i: number = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name !== name || this.cookies[i].domain !== domain) {
        kept.push(this.cookies[i]);
      }
    }
    this.cookies = kept;
  }
}
