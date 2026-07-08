/**
 * File system utility for CampusOS multi-platform support.
 *
 * On Android/iOS: uses react-native-fs or RNFS
 * On HarmonyOS: uses context.filesDir via ArkTS bridge
 */

import { Platform } from 'react-native';
import { isHarmonyOS } from '../app/platform';

let documentDir: string | null = null;

export async function getDocumentDir(): Promise<string> {
  if (documentDir) {
    return documentDir;
  }

  try {
    if (isHarmonyOS()) {
      // HarmonyOS filesDir path
      documentDir = '/data/storage/el2/base/haps/entry/files';
      return documentDir;
    }

    const RNFS = require('react-native-fs');
    documentDir = RNFS.DocumentDirectoryPath ?? RNFS.CachesDirectoryPath;
    return documentDir;
  } catch {
    documentDir = '.';
    return documentDir;
  }
}

export async function getCacheDir(): Promise<string> {
  try {
    if (isHarmonyOS()) {
      return '/data/storage/el2/base/haps/entry/cache';
    }

    const RNFS = require('react-native-fs');
    return RNFS.CachesDirectoryPath ?? '.';
  } catch {
    return '.';
  }
}
