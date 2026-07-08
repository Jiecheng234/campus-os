/**
 * Platform detection and compatibility layer for CampusOS multi-platform support.
 *
 * Currently supports: Android, iOS (via React Native) and HarmonyOS (via RN-OH).
 *
 * Usage:
 *   import { PlatformOS, isHarmonyOS } from '@/app/platform';
 *   if (isHarmonyOS()) { /* HarmonyOS-specific code * / }
 */

export type PlatformOS = 'android' | 'ios' | 'ohos';

let cachedPlatform: PlatformOS | null = null;

export function getPlatformOS(): PlatformOS {
  if (cachedPlatform !== null) {
    return cachedPlatform;
  }

  try {
    const RN = require('react-native') as { Platform: { OS: string } };
    const os = RN.Platform.OS;

    if (os === 'android') {
      cachedPlatform = 'android';
    } else if (os === 'ios') {
      cachedPlatform = 'ios';
    } else if (os === 'ohos') {
      cachedPlatform = 'ohos';
    } else {
      cachedPlatform = 'android';
    }
  } catch {
    cachedPlatform = 'android';
  }

  return cachedPlatform;
}

export function isHarmonyOS(): boolean {
  return getPlatformOS() === 'ohos';
}

export function isAndroid(): boolean {
  return getPlatformOS() === 'android';
}

export function isIOS(): boolean {
  return getPlatformOS() === 'ios';
}

/**
 * Select a value based on the current platform.
 */
export function platformSelect<T>(opts: {
  android?: T;
  ios?: T;
  ohos?: T;
  default: T;
}): T {
  const os = getPlatformOS();
  if (os === 'ohos' && opts.ohos !== undefined) {
    return opts.ohos;
  }
  if (os === 'android' && opts.android !== undefined) {
    return opts.android;
  }
  if (os === 'ios' && opts.ios !== undefined) {
    return opts.ios;
  }
  return opts.default;
}
