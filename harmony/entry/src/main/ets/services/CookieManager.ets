export class CookieEntry {
  name: string = '';
  value: string = '';
  domain: string = '';
  path: string = '/';
  expires: number = 0;
  secure: boolean = false;
  httpOnly: boolean = false;
}

export class CookieManager {
  private cookies: CookieEntry[] = [];

  setFromResponse(url: string, setCookieHeader: string): void {
    if (setCookieHeader.length === 0) {
      return;
    }
    const domain: string = this.extractDomain(url);
    const headers: string[] = setCookieHeader.split('\n');
    for (let h: number = 0; h < headers.length; h++) {
      const line: string = headers[h].trim();
      if (line.length === 0) { continue; }
      const parts: string[] = line.split(';');
      if (parts.length === 0) { continue; }
      const kv: string[] = parts[0].split('=');
      if (kv.length < 2) { continue; }
      const entry: CookieEntry = new CookieEntry();
      entry.name = kv[0].trim();
      entry.value = decodeURIComponent(kv.slice(1).join('=').trim());
      entry.domain = domain;
      for (let i: number = 1; i < parts.length; i++) {
        const attr: string = parts[i].trim().toLowerCase();
        if (attr === 'secure') { entry.secure = true; }
        else if (attr === 'httponly') { entry.httpOnly = true; }
        else if (attr.startsWith('path=')) { entry.path = attr.substring(5).trim(); }
        else if (attr.startsWith('domain=')) { entry.domain = attr.substring(7).trim(); }
        else if (attr.startsWith('expires=')) {
          const expStr: string = attr.substring(8).trim();
          const exp: number = Date.parse(expStr);
          if (!isNaN(exp)) { entry.expires = exp; }
        }
        else if (attr.startsWith('max-age=')) {
          const ma: number = parseInt(attr.substring(8).trim());
          if (!isNaN(ma)) { entry.expires = Date.now() + ma * 1000; }
        }
      }
      this.removeOld(entry.name, entry.domain);
      if (entry.value.length > 0 && entry.value !== ';') {
        this.cookies.push(entry);
      } else {
        // empty value = delete cookie
      }
    }
  }

  getCookieHeader(url: string): string {
    const domain: string = this.extractDomain(url);
    const now: number = Date.now();
    const matched: CookieEntry[] = [];
    for (let i: number = 0; i < this.cookies.length; i++) {
      const c: CookieEntry = this.cookies[i];
      if (c.expires > 0 && c.expires < now) { continue; }
      if (this.domainMatch(domain, c.domain)) {
        matched.push(c);
      }
    }
    let result: string = '';
    for (let i: number = 0; i < matched.length; i++) {
      if (i > 0) { result = result + '; '; }
      result = result + matched[i].name + '=' + matched[i].value;
    }
    return result;
  }

  clear(): void {
    this.cookies = [];
  }

  private extractDomain(url: string): string {
    let s: string = url;
    if (s.startsWith('https://')) { s = s.substring(8); }
    else if (s.startsWith('http://')) { s = s.substring(7); }
    const slash: number = s.indexOf('/');
    if (slash > 0) { s = s.substring(0, slash); }
    const colon: number = s.indexOf(':');
    if (colon > 0) { s = s.substring(0, colon); }
    return s;
  }

  private domainMatch(requestDomain: string, cookieDomain: string): boolean {
    if (requestDomain === cookieDomain) { return true; }
    if (requestDomain.endsWith('.' + cookieDomain)) { return true; }
    return false;
  }

  private removeOld(name: string, domain: string): void {
    const kept: CookieEntry[] = [];
    for (let i: number = 0; i < this.cookies.length; i++) {
      if (this.cookies[i].name !== name || this.cookies[i].domain !== domain) {
        kept.push(this.cookies[i]);
      }
    }
    this.cookies = kept;
  }
}
