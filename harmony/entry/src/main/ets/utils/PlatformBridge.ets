/**
 * ArkTS Platform Bridge — stubs for native modules that need TurboModule bridge.
 *
 * This file defines the interface contracts for native modules that will be
 * bridged from ArkTS to JS via React Native TurboModule system in Phase 4.
 */

export interface SecureStorageBridge {
  saveCredentials(studentId: string, password: string, fingerprint: string): Promise<void>;
  loadCredentials(): Promise<StudentCredentials | null>;
  clearCredentials(): Promise<void>;
  saveApiKey(providerId: string, apiKey: string): Promise<void>;
  loadApiKey(providerId: string): Promise<string | null>;
  clearAllApiKeys(): Promise<void>;
}

export interface StudentCredentials {
  studentId: string;
  password: string;
  fingerprint: string;
}

export interface LocalNotificationBridge {
  showNotification(title: string, body: string, id: number): Promise<void>;
  cancelNotification(id: number): Promise<void>;
  cancelAllNotifications(): Promise<void>;
  requestPermission(): Promise<boolean>;
}

export interface WebViewBridge {
  createWebView(url: string, options: WebViewOptions): void;
}

export interface WebViewOptions {
  javaScriptEnabled: boolean;
  domStorageEnabled: boolean;
  onNavigationStateChange?: (url: string) => void;
  onMessage?: (message: string) => void;
}

/**
 * Native module names for TurboModule registration.
 * These must match the names registered on the ArkTS side.
 */
export const NATIVE_MODULE_NAMES = {
  SECURE_STORAGE: 'CampusOSSecureStorage',
  LOCAL_NOTIFICATION: 'CampusOSLocalNotification',
  WEB_VIEW: 'CampusOSWebView',
} as const;
