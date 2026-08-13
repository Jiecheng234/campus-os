import { hilog } from '@kit.PerformanceAnalysisKit';
import BuildProfile from 'BuildProfile';

/**
 * 全局日志开关：仅 debug 构建输出 d/i/w；error 始终输出。
 * BuildProfile.DEBUG 由 hvigor 编译期生成（debug buildMode=true，release=false）。
 */
const DOMAIN: number = 0xCAFE;
const ENABLED: boolean = BuildProfile.DEBUG;

export class Log {
  static d(tag: string, format: string, ...args: Object[]): void {
    if (ENABLED) {
      hilog.debug(DOMAIN, tag, format, ...args);
    }
  }

  static i(tag: string, format: string, ...args: Object[]): void {
    if (ENABLED) {
      hilog.info(DOMAIN, tag, format, ...args);
    }
  }

  static w(tag: string, format: string, ...args: Object[]): void {
    if (ENABLED) {
      hilog.warn(DOMAIN, tag, format, ...args);
    }
  }

  static e(tag: string, format: string, ...args: Object[]): void {
    hilog.error(DOMAIN, tag, format, ...args);
  }
}
