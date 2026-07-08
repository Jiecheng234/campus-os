/**
 * CookieManager platform abstraction for CampusOS multi-platform support.
 *
 * On Android/iOS: uses @react-native-cookies/cookies
 * On HarmonyOS: uses manual cookie header management via fetch API
 */

type CookieManagerType = {
  get: (url: string) => Promise<Record<string, string>>;
  set: (url: string, cookie: { name: string; value: string; domain?: string; path?: string }) => Promise<void>;
  setFromResponse: (url: string, cookieString: string) => Promise<void>;
  clearAll: () => Promise<void>;
  flush: () => Promise<void>;
  getFromResponse: (url: string) => Promise<Record<string, string>>;
};

let cookieModule: CookieManagerType | null = null;

function extractDomain(url: string): string {
  try {
    const u = new URL(url);
    return u.hostname;
  } catch {
    return url;
  }
}

function parseCookieString(cookieString: string): Record<string, string> {
  const result: Record<string, string> = {};
  const parts = cookieString.split(';');
  const firstPart = parts[0]?.trim();
  if (firstPart) {
    const eqIdx = firstPart.indexOf('=');
    if (eqIdx > 0) {
      result[firstPart.substring(0, eqIdx).trim()] = firstPart.substring(eqIdx + 1).trim();
    }
  }
  return result;
}

function getCookieModule(): CookieManagerType {
  if (cookieModule) {
    return cookieModule;
  }

  try {
    const Cookie = require('@react-native-cookies/cookies');
    cookieModule = Cookie.default || Cookie;
  } catch {
    // Fallback for HarmonyOS: simple in-memory cookie store
    const fallbackStore: Record<string, string> = {};
    const getKey = (domain: string, name: string): string => `${domain}:${name}`;

    cookieModule = {
      async get(url: string): Promise<Record<string, string>> {
        const domain = extractDomain(url);
        const result: Record<string, string> = {};
        for (const key of Object.keys(fallbackStore)) {
          if (key.startsWith(domain)) {
            const cookieName = key.slice(domain.length + 1);
            result[cookieName] = fallbackStore[key];
          }
        }
        return result;
      },

      async set(
        url: string,
        cookie: { name: string; value: string; domain?: string; path?: string },
      ): Promise<void> {
        const domain = cookie.domain || extractDomain(url);
        fallbackStore[getKey(domain, cookie.name)] = cookie.value;
      },

      async setFromResponse(url: string, cookieString: string): Promise<void> {
        const domain = extractDomain(url);
        const parsed = parseCookieString(cookieString);
        for (const key of Object.keys(parsed)) {
          fallbackStore[getKey(domain, key)] = parsed[key];
        }
      },

      async clearAll(): Promise<void> {
        for (const key of Object.keys(fallbackStore)) {
          delete fallbackStore[key];
        }
      },

      async flush(): Promise<void> {
        // No-op for in-memory store
      },

      async getFromResponse(url: string): Promise<Record<string, string>> {
        return this.get(url);
      },
    };
  }

  return cookieModule;
}

export const CookieManager: CookieManagerType = {
  get(url: string): Promise<Record<string, string>> {
    return getCookieModule().get(url);
  },
  set(url: string, cookie: { name: string; value: string; domain?: string; path?: string }): Promise<void> {
    return getCookieModule().set(url, cookie);
  },
  setFromResponse(url: string, cookieString: string): Promise<void> {
    return getCookieModule().setFromResponse(url, cookieString);
  },
  clearAll(): Promise<void> {
    return getCookieModule().clearAll();
  },
  flush(): Promise<void> {
    return getCookieModule().flush();
  },
  getFromResponse(url: string): Promise<Record<string, string>> {
    return getCookieModule().getFromResponse(url);
  },
};
