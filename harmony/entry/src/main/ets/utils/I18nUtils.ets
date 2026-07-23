const DAY_NAMES_ZH: string[] = ['日', '一', '二', '三', '四', '五', '六'];
const DAY_NAMES_EN: string[] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export class I18nUtils {
  static isZh(): boolean {
    return true;
  }

  static getDayName(dayIndex: number): string {
    const idx: number = dayIndex % 7;
    if (I18nUtils.isZh()) {
      return `周${DAY_NAMES_ZH[idx]}`;
    }
    return DAY_NAMES_EN[idx];
  }

  static formatDateLong(date: Date): string {
    const year: number = date.getFullYear();
    const month: number = date.getMonth() + 1;
    const day: number = date.getDate();
    const dayOfWeek: number = date.getDay();
    if (I18nUtils.isZh()) {
      return `${year}年${month}月${day}日 周${DAY_NAMES_ZH[dayOfWeek]}`;
    }
    return `${DAY_NAMES_EN[dayOfWeek]}, ${month}/${day}/${year}`;
  }

  static formatDateShort(date: Date): string {
    const month: string = String(date.getMonth() + 1).padStart(2, '0');
    const day: string = String(date.getDate()).padStart(2, '0');
    return `${month}/${day}`;
  }

  static formatRelativeTime(dateStr: string): string {
    const date: Date = new Date(dateStr);
    if (isNaN(date.getTime())) {
      return dateStr;
    }
    const now: Date = new Date();
    const diffMs: number = now.getTime() - date.getTime();
    const minutes: number = Math.floor(diffMs / 60000);
    const hours: number = Math.floor(diffMs / 3600000);
    const days: number = Math.floor(diffMs / 86400000);
    if (I18nUtils.isZh()) {
      if (minutes < 1) { return '刚刚'; }
      if (minutes < 60) { return `${minutes}分钟前`; }
      if (hours < 24) { return `${hours}小时前`; }
      if (days < 7) { return `${days}天前`; }
      return I18nUtils.formatDateShort(date);
    }
    if (minutes < 1) { return 'just now'; }
    if (minutes < 60) { return `${minutes}m ago`; }
    if (hours < 24) { return `${hours}h ago`; }
    if (days < 7) { return `${days}d ago`; }
    return I18nUtils.formatDateShort(date);
  }
}
