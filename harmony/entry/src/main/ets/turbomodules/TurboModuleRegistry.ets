/**
 * TurboModule registry — registers all CampusOS native modules.
 *
 * Phase 4: Registers native modules for the RN-OH runtime.
 */

import { SecureStorageTurboModule } from './SecureStorageTurboModule';
import { LocalNotificationTurboModule } from './LocalNotificationTurboModule';

class TurboModuleEntry {
  name: string = '';
  className: string = '';
}

export function getTurboModuleList(): TurboModuleEntry[] {
  const entries: TurboModuleEntry[] = [
    {
      name: SecureStorageTurboModule.NAME,
      className: 'SecureStorageTurboModule',
    },
    {
      name: LocalNotificationTurboModule.NAME,
      className: 'LocalNotificationTurboModule',
    },
  ];
  return entries;
}
