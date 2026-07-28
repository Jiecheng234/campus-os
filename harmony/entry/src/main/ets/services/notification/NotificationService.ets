import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';

export async function showLocalNotification(title: string, text: string, id: number): Promise<void> {
  try {
    const request: notificationManager.NotificationRequest = {
      id: id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text,
        }
      },
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
    };
    await notificationManager.publish(request);
  } catch (e) {
    // ignore
  }
}

export async function cancelNotification(id: number): Promise<void> {
  try {
    await notificationManager.cancel(id);
  } catch (e) {
    // ignore
  }
}

export async function cancelAllNotifications(): Promise<void> {
  try {
    await notificationManager.cancelAll();
  } catch (e) {
    // ignore
  }
}
