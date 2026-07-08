/**
 * SecureStorage platform abstraction for CampusOS multi-platform support.
 *
 * On Android/iOS: uses react-native-keychain (iOS Keychain / Android Keystore)
 * On HarmonyOS: uses @ohos.security.huks (HarmonyOS Universal KeyStore)
 *
 * For Phase 3-4 migration: currently delegates to react-native-keychain.
 * Phase 4 will add ArkTS HUKS TurboModule bridge for HarmonyOS.
 */

type Credentials = {
  studentId: string;
  password: string;
  fingerprint: string;
};

type KeychainType = {
  setGenericPassword(
    username: string,
    password: string,
    options?: { service: string },
  ): Promise<boolean | { service: string; storage: string }>;

  getGenericPassword(options?: {
    service: string;
  }): Promise<false | { username: string; password: string; service: string; storage: string }>;

  resetGenericPassword(options?: { service: string }): Promise<boolean>;
};

let keychainModule: KeychainType | null = null;

function getKeychainModule(): KeychainType {
  if (keychainModule) {
    return keychainModule;
  }

  try {
    keychainModule = require('react-native-keychain');
  } catch {
    // HarmonyOS fallback: will be implemented in Phase 4 via TurboModule
    keychainModule = {
      async setGenericPassword(): Promise<boolean> {
        throw new Error('Secure storage not available on HarmonyOS (Phase 4 pending)');
      },
      async getGenericPassword(): Promise<false> {
        return false;
      },
      async resetGenericPassword(): Promise<boolean> {
        return true;
      },
    };
  }

  return keychainModule;
}

export const Keychain = {
  setGenericPassword(
    username: string,
    password: string,
    options?: { service: string },
  ): Promise<boolean | { service: string; storage: string }> {
    return getKeychainModule().setGenericPassword(username, password, options);
  },

  getGenericPassword(options?: {
    service: string;
  }): Promise<false | { username: string; password: string; service: string; storage: string }> {
    return getKeychainModule().getGenericPassword(options);
  },

  resetGenericPassword(options?: { service: string }): Promise<boolean> {
    return getKeychainModule().resetGenericPassword(options);
  },
};
