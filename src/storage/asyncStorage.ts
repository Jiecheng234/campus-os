/**
 * AsyncStorage platform abstraction for CampusOS multi-platform support.
 *
 * On Android/iOS: uses @react-native-async-storage/async-storage
 * On HarmonyOS: uses @react-native-oh-tpl/async-storage
 *
 * Import this module instead of AsyncStorage directly:
 *   import Storage from '../storage/asyncStorage';
 *   // or relative path depending on location
 */

interface AsyncStorageInterface {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
  mergeItem(key: string, value: string): Promise<void>;
  clear(): Promise<void>;
  getAllKeys(): Promise<string[]>;
}

let cached: AsyncStorageInterface;

function getStorage(): AsyncStorageInterface {
  if (cached) {
    return cached;
  }

  try {
    cached = require('@react-native-async-storage/async-storage').default;
  } catch {
    try {
      cached = require('@react-native-oh-tpl/async-storage').default;
    } catch {
      throw new Error(
        'AsyncStorage is not available.',
      );
    }
  }

  return cached;
}

const Storage: AsyncStorageInterface = {
  getItem(key: string): Promise<string | null> {
    return getStorage().getItem(key);
  },
  setItem(key: string, value: string): Promise<void> {
    return getStorage().setItem(key, value);
  },
  removeItem(key: string): Promise<void> {
    return getStorage().removeItem(key);
  },
  mergeItem(key: string, value: string): Promise<void> {
    return getStorage().mergeItem(key, value);
  },
  clear(): Promise<void> {
    return getStorage().clear();
  },
  getAllKeys(): Promise<string[]> {
    return getStorage().getAllKeys();
  },
};

export default Storage;
