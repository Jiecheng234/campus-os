/**
 * LocalNotificationTurboModule — bridges notificationManager to JS.
 * Phase 4: ArkTS native implementation.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { notificationManager } from '@kit.NotificationKit';

const TAG = 'CampusOSLocalNotification';

class NotificationOptions {
  id: number = 0;
  title: string = '';
  body: string = '';
}

export class LocalNotificationTurboModule {
  static readonly NAME: string = 'CampusOSLocalNotification';

  /**
   * Show a local basic-text notification.
   */
  async showNotification(opts: NotificationOptions): Promise<void> {
    try {
      const request: notificationManager.NotificationRequest = {
        id: opts.id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: opts.title,
            text: opts.body,
          },
        },
      };

      await notificationManager.publish(request);
      hilog.info(0xCAFE, TAG, 'Notification published: id=%{public}d', opts.id);
    } catch (err) {
      const error = err as Error;
      hilog.error(0xCAFE, TAG, 'showNotification failed: %{public}s', error.message);
    }
  }

  /**
   * Cancel a specific notification by id.
   */
  async cancelNotification(id: number): Promise<void> {
    try {
      await notificationManager.cancel(id);
      hilog.info(0xCAFE, TAG, 'Notification cancelled: id=%{public}d', id);
    } catch (err) {
      const error = err as Error;
      hilog.error(0xCAFE, TAG, 'cancelNotification failed: %{public}s', error.message);
    }
  }

  /**
   * Cancel all notifications from this app.
   */
  async cancelAllNotifications(): Promise<void> {
    try {
      await notificationManager.cancelAll();
      hilog.info(0xCAFE, TAG, 'All notifications cancelled');
    } catch (err) {
      const error = err as Error;
      hilog.error(0xCAFE, TAG, 'cancelAllNotifications failed: %{public}s', error.message);
    }
  }
}
