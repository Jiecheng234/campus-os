/**
 * Network utility for CampusOS multi-platform support.
 *
 * On Android/iOS: uses NetInfo from @react-native-community/netinfo or fallback
 * On HarmonyOS: uses connection.getNetCapabilitiesSync via ArkTS bridge
 */

import { Platform } from 'react-native';
import { isHarmonyOS } from '../app/platform';

export type NetworkState = {
  isConnected: boolean;
  isWifi: boolean;
  isCellular: boolean;
};

let cachedState: NetworkState = { isConnected: true, isWifi: true, isCellular: false };

export async function getNetworkState(): Promise<NetworkState> {
  try {
    if (isHarmonyOS()) {
      return getHarmonyOSNetworkState();
    }

    // Try RN NetInfo
    const NetInfo = require('@react-native-community/netinfo');
    const state = await NetInfo.default.fetch();
    cachedState = {
      isConnected: state.isConnected ?? true,
      isWifi: state.type === 'wifi',
      isCellular: state.type === 'cellular',
    };
    return cachedState;
  } catch {
    return cachedState;
  }
}

async function getHarmonyOSNetworkState(): Promise<NetworkState> {
  try {
    // In RN-OH, this will call into the ArkTS network bridge
    const connection = (global as Record<string, unknown>).harmonyConnection;
    if (connection) {
      return (connection as () => Promise<NetworkState>)();
    }
  } catch {
    // Fallback
  }
  return { isConnected: true, isWifi: false, isCellular: false };
}

export function addNetworkListener(
  _callback: (state: NetworkState) => void,
): () => void {
  // TODO: Implement HarmonyOS network listener via connection.on('netChange')
  return () => {};
}
