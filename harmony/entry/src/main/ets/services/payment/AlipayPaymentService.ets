/**
 * AlipayPaymentService — 电费 / 校园卡 / 体育共用的支付宝支付基础设施。
 *
 * 能力边界：
 *  - payCode → 与 RN 基线一致的支付宝 Deep Link（纯内存，无网络）；
 *  - 探测支付宝 scheme → 系统 openLink 外跳；
 *  - 外跳成功后在内存登记“待回读”上下文，EntryAbility.onForeground 投递一次事件；
 *  - 服务层只返回状态码与 i18n 键，不返回支付结果结论；
 *  - 不持久化支付码、二维码 URL、金额；日志不输出任何凭据。
 */
import { bundleManager, common, OpenLinkOptions } from '@kit.AbilityKit';
import { BusinessError, emitter } from '@kit.BasicServicesKit';
import { Log } from '../../utils/Logger';

const PAYMENT_SCHEME_ALIPAYQR: string = 'alipayqr';
const PAYMENT_SCHEME_ALIPAYS: string = 'alipays';
const PAYMENT_PROBE_ALIPAYQR: string = 'alipayqr://platformapi/startapp';
const PAYMENT_PROBE_ALIPAYS: string = 'alipays://platformapi/startapp';
const PAYMENT_LINK_PATH: string = '://platformapi/startapp?saId=10000007&qrcode=';
const PAYMENT_QR_ENCODED_PREFIX: string = 'https%3A%2F%2Fqr.alipay.com%2F';
const PAYMENT_MAX_CODE_LENGTH: number = 256;
const PAYMENT_WHITESPACE: RegExp = /\s/;
const PAYMENT_LOG_TAG: string = 'Payment';

/** 待回读上下文有效期：30 分钟 */
export const CAMPUS_PAYMENT_PENDING_TTL_MS: number = 30 * 60 * 1000;

/** 支付回读事件 ID（与 UiEvents 的 10001 不冲突） */
export const CAMPUS_PAYMENT_RETURN_EVENT_ID: number = 11001;

/** 支付自检专用事件 ID：隔离测试事件，生产订阅方不会收到 */
export const CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID: number = 11002;

/** 支付子系统标识（服务层稳定值，不用于展示） */
export class CampusPaymentSubsystem {
  static readonly ELECTRICITY: string = 'electricity';
  static readonly CAMPUS_CARD: string = 'campusCard';
  static readonly SPORTS: string = 'sports';
  static readonly DIAGNOSTICS: string = 'diagnostics';
}

/** 链接构建 / 外跳稳定状态码 */
export class CampusPaymentStatus {
  static readonly BUILD_READY: string = 'build_ready';
  static readonly LAUNCHED: string = 'launched';
  static readonly INVALID_CODE: string = 'invalid_code';
  static readonly NOT_INSTALLED: string = 'not_installed';
  static readonly LAUNCH_FAILED: string = 'launch_failed';
}

/** 支付相关 i18n 键（页面交给 I18n.t() 本地化） */
export class CampusPaymentI18n {
  static readonly ERROR_INVALID_CODE: string = 'payment.error.invalidCode';
  static readonly ERROR_ALIPAY_NOT_INSTALLED: string = 'payment.error.alipayNotInstalled';
  static readonly ERROR_LAUNCH_FAILED: string = 'payment.error.launchFailed';
  static readonly ERROR_UNSUPPORTED: string = 'payment.error.unsupported';
  static readonly LINK_READY: string = 'payment.link.ready';
  static readonly LAUNCH_OPENED: string = 'payment.launch.opened';
  static readonly RETURN_REFRESHING: string = 'payment.return.refreshing';
  static readonly RETURN_UNCONFIRMED: string = 'payment.return.unconfirmed';
  static readonly DIAG_SECTION: string = 'payment.diag.section';
  static readonly DIAG_PROBE: string = 'payment.diag.probe';
  static readonly DIAG_OPEN_TEST: string = 'payment.diag.openTest';
  static readonly DIAG_AVAILABLE: string = 'payment.diag.available';
  static readonly DIAG_NOT_INSTALLED: string = 'payment.diag.notInstalled';
  static readonly DIAG_NO_PAYMENT: string = 'payment.diag.noPayment';
  static readonly DIAG_RETURNED: string = 'payment.diag.returned';
}

/** 待回读支付意图（仅内存，不序列化） */
export class CampusPaymentIntent {
  subsystem: string = '';
  amount: number = 0;
  startedAt: number = 0;

  constructor(subsystem: string = '', amount: number = 0, startedAt: number = 0) {
    this.subsystem = subsystem;
    this.amount = amount;
    this.startedAt = startedAt;
  }
}

/** 链接构建 / 外跳结果 */
export class CampusPaymentLaunchResult {
  status: string = '';
  messageKey: string = '';
  errorCode: number = 0;
  /** 仅构建成功时返回；页面不得写入日志 */
  url: string = '';

  constructor(status: string = '', messageKey: string = '', errorCode: number = 0, url: string = '') {
    this.status = status;
    this.messageKey = messageKey;
    this.errorCode = errorCode;
    this.url = url;
  }
}

/** 回读事件：只表示“用户已返回 CampusOS”，不表示用户已完成支付 */
export class CampusPaymentReturnEvent {
  intent: CampusPaymentIntent = new CampusPaymentIntent();
  elapsedMs: number = 0;

  constructor(intent: CampusPaymentIntent = new CampusPaymentIntent(), elapsedMs: number = 0) {
    this.intent = intent;
    this.elapsedMs = elapsedMs;
  }
}

/** 支付宝可用性探测结果 */
export class CampusPaymentProbeResult {
  available: boolean = false;
  scheme: string = '';
  messageKey: string = '';

  constructor(available: boolean = false, scheme: string = '', messageKey: string = '') {
    this.available = available;
    this.scheme = scheme;
    this.messageKey = messageKey;
  }
}

/** 回读订阅句柄（消费者只透传给 unsubscribeReturn） */
export class CampusPaymentReturnSubscription {
  eventId: number = 0;
  cb: (event: emitter.EventData) => void = (event: emitter.EventData): void => {};
}

export class AlipayPaymentService {
  static readonly PENDING_TTL_MS: number = CAMPUS_PAYMENT_PENDING_TTL_MS;
  static readonly EVT_PAYMENT_RETURN: number = CAMPUS_PAYMENT_RETURN_EVENT_ID;

  /** 待回读上下文仅保存在进程内存；同一时刻最多一条，新值覆盖旧值。 */
  private static pending: CampusPaymentIntent | null = null;

  /** 探测支付宝可访问性（先 alipayqr，再回退 alipays）。 */
  static probe(): CampusPaymentProbeResult {
    const scheme: string = AlipayPaymentService.currentScheme();
    if (scheme.length > 0) {
      return new CampusPaymentProbeResult(true, scheme, CampusPaymentI18n.DIAG_AVAILABLE);
    }
    return new CampusPaymentProbeResult(false, '', CampusPaymentI18n.DIAG_NOT_INSTALLED);
  }

  /** 至少一个支付宝 scheme 可访问时返回 true；异常按不可访问处理。 */
  static isAlipayAvailable(): boolean {
    return AlipayPaymentService.currentScheme().length > 0;
  }

  /** 返回实际可用的 scheme；都不可用返回空串。 */
  static currentScheme(): string {
    if (AlipayPaymentService.canOpen(PAYMENT_PROBE_ALIPAYQR)) {
      return PAYMENT_SCHEME_ALIPAYQR;
    }
    if (AlipayPaymentService.canOpen(PAYMENT_PROBE_ALIPAYS)) {
      return PAYMENT_SCHEME_ALIPAYS;
    }
    return '';
  }

  /**
   * 外跳支付宝。成功只表示“已请求打开支付宝”，不表示支付结果。
   * 发起外跳前登记待回读；失败清除待回读并返回可读状态码。
   */
  static async launch(
    context: common.UIAbilityContext,
    payCode: string,
    subsystem: string,
    amount: number
  ): Promise<CampusPaymentLaunchResult> {
    const built: CampusPaymentLaunchResult = AlipayPaymentService.tryBuildDeepLink(payCode);
    if (built.status === CampusPaymentStatus.INVALID_CODE) {
      AlipayPaymentService.clearPending();
      Log.w(PAYMENT_LOG_TAG, 'PAYMENT launch rejected status=%{public}s', built.status);
      return built;
    }

    const scheme: string = AlipayPaymentService.currentScheme();
    if (scheme.length === 0) {
      AlipayPaymentService.clearPending();
      Log.w(PAYMENT_LOG_TAG, 'PAYMENT launch rejected status=%{public}s', CampusPaymentStatus.NOT_INSTALLED);
      return new CampusPaymentLaunchResult(
        CampusPaymentStatus.NOT_INSTALLED,
        CampusPaymentI18n.ERROR_ALIPAY_NOT_INSTALLED,
        0,
        ''
      );
    }

    const code: string = AlipayPaymentService.normalizePayCode(AlipayPaymentService.extractPayCode(payCode));
    if (code.length === 0) {
      AlipayPaymentService.clearPending();
      return new CampusPaymentLaunchResult(
        CampusPaymentStatus.INVALID_CODE,
        CampusPaymentI18n.ERROR_INVALID_CODE,
        0,
        ''
      );
    }
    const url: string = AlipayPaymentService.buildDeepLinkForScheme(code, scheme);
    const options: OpenLinkOptions = { appLinkingOnly: false };
    try {
      // 必须在 openLink 之前登记：避免用户已返回前台但 Promise 尚未 resolve 时漏发回读。
      AlipayPaymentService.beginPending(subsystem, amount, Date.now());
      await context.openLink(url, options);
      Log.i(
        PAYMENT_LOG_TAG,
        'PAYMENT launch requested subsystem=%{public}s status=%{public}s',
        subsystem,
        CampusPaymentStatus.LAUNCHED
      );
      return new CampusPaymentLaunchResult(
        CampusPaymentStatus.LAUNCHED,
        CampusPaymentI18n.LAUNCH_OPENED,
        0,
        url
      );
    } catch (error) {
      AlipayPaymentService.clearPending();
      const err: BusinessError = error as BusinessError;
      const errorCode: number = typeof err.code === 'number' ? err.code : 0;
      let status: string = CampusPaymentStatus.LAUNCH_FAILED;
      let messageKey: string = CampusPaymentI18n.ERROR_LAUNCH_FAILED;
      if (errorCode === 16000001 || errorCode === 16000019) {
        status = CampusPaymentStatus.NOT_INSTALLED;
        messageKey = CampusPaymentI18n.ERROR_ALIPAY_NOT_INSTALLED;
      } else if (errorCode === 17700056) {
        messageKey = CampusPaymentI18n.ERROR_UNSUPPORTED;
      }
      Log.w(
        PAYMENT_LOG_TAG,
        'PAYMENT launch failed subsystem=%{public}s status=%{public}s code=%{public}d',
        subsystem,
        status,
        errorCode
      );
      return new CampusPaymentLaunchResult(status, messageKey, errorCode, '');
    }
  }

  /** 登记待回读上下文；新支付覆盖旧支付。 */
  static beginPending(subsystem: string, amount: number, startedAt: number): void {
    AlipayPaymentService.pending = new CampusPaymentIntent(subsystem, amount, startedAt);
  }

  /** 查询待回读上下文（返回副本，不修改状态）。 */
  static peekPending(): CampusPaymentIntent | null {
    const current: CampusPaymentIntent | null = AlipayPaymentService.pending;
    if (current === null) {
      return null;
    }
    return new CampusPaymentIntent(current.subsystem, current.amount, current.startedAt);
  }

  /** 清除待回读上下文。 */
  static clearPending(): void {
    AlipayPaymentService.pending = null;
  }

  /**
   * 应用回到前台时调用：存在未过期 pending 时投递恰好一次回读事件并清除。
   * 无 pending、已过期或已清除时不投递。
   */
  static notifyForeground(
    eventId: number = CAMPUS_PAYMENT_RETURN_EVENT_ID,
    logTag: string = PAYMENT_LOG_TAG
  ): void {
    const current: CampusPaymentIntent | null = AlipayPaymentService.pending;
    if (current === null) {
      return;
    }
    const elapsedMs: number = Date.now() - current.startedAt;
    if (elapsedMs < 0 || elapsedMs > AlipayPaymentService.PENDING_TTL_MS) {
      AlipayPaymentService.clearPending();
      Log.i(
        logTag,
        'PAYMENT pending expired subsystem=%{public}s elapsedMs=%{public}d',
        current.subsystem,
        elapsedMs
      );
      return;
    }

    // 先清除再投递：即使订阅回调内再次触发前台通知，也不会重复投递。
    AlipayPaymentService.clearPending();
    const payload: Record<string, Object> = {
      'subsystem': current.subsystem,
      'amount': current.amount,
      'startedAt': current.startedAt,
      'elapsedMs': elapsedMs
    };
    try {
      emitter.emit({ eventId: eventId }, { data: payload });
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      const errorCode: number = typeof err.code === 'number' ? err.code : 0;
      Log.e(logTag, 'PAYMENT return emit failed code=%{public}d', errorCode);
      return;
    }
    Log.i(
      logTag,
      'PAYMENT return delivered subsystem=%{public}s elapsedMs=%{public}d',
      current.subsystem,
      elapsedMs
    );
  }

  /** 订阅支付回读事件；返回句柄供 unsubscribeReturn 使用。 */
  static subscribeReturn(
    handler: (event: CampusPaymentReturnEvent) => void,
    eventId: number = CAMPUS_PAYMENT_RETURN_EVENT_ID
  ): CampusPaymentReturnSubscription {
    const sub: CampusPaymentReturnSubscription = new CampusPaymentReturnSubscription();
    sub.eventId = eventId;
    sub.cb = (event: emitter.EventData): void => {
      const data: Record<string, Object> = event.data ?? {};
      try {
        handler(AlipayPaymentService.readReturnEvent(data));
      } catch (error) {
        const err: BusinessError = error as BusinessError;
        const errorCode: number = typeof err.code === 'number' ? err.code : 0;
        Log.w(PAYMENT_LOG_TAG, 'PAYMENT return handler failed code=%{public}d', errorCode);
      }
    };
    emitter.on({ eventId: eventId }, sub.cb);
    return sub;
  }

  /** 取消回读订阅；重复取消不抛异常。 */
  static unsubscribeReturn(sub: CampusPaymentReturnSubscription): void {
    try {
      emitter.off(sub.eventId, sub.cb);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      const errorCode: number = typeof err.code === 'number' ? err.code : 0;
      Log.w(PAYMENT_LOG_TAG, 'PAYMENT unsubscribe failed code=%{public}d', errorCode);
    }
  }

  private static readReturnEvent(data: Record<string, Object>): CampusPaymentReturnEvent {
    const intent: CampusPaymentIntent = new CampusPaymentIntent();
    const subsystem: Object | undefined = data['subsystem'];
    if (typeof subsystem === 'string') {
      intent.subsystem = subsystem;
    }
    const amount: Object | undefined = data['amount'];
    if (typeof amount === 'number') {
      intent.amount = amount;
    }
    const startedAt: Object | undefined = data['startedAt'];
    if (typeof startedAt === 'number') {
      intent.startedAt = startedAt;
    }
    const event: CampusPaymentReturnEvent = new CampusPaymentReturnEvent(intent, 0);
    const elapsedMs: Object | undefined = data['elapsedMs'];
    if (typeof elapsedMs === 'number') {
      event.elapsedMs = elapsedMs;
    }
    return event;
  }

  private static canOpen(link: string): boolean {
    try {
      return bundleManager.canOpenLink(link);
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      const errorCode: number = typeof err.code === 'number' ? err.code : 0;
      Log.w(PAYMENT_LOG_TAG, 'PAYMENT probe failed code=%{public}d', errorCode);
      return false;
    }
  }

  /**
   * 构建 RN 基线 Deep Link（主 scheme：alipayqr）。
   * 非法支付码抛出不带敏感信息的 Error；日志与异常均不含支付码。
   */
  static buildDeepLink(payCode: string): string {
    const code: string = AlipayPaymentService.normalizePayCode(payCode);
    if (code.length === 0) {
      throw new Error('invalid payment code');
    }
    return AlipayPaymentService.buildDeepLinkForScheme(code, PAYMENT_SCHEME_ALIPAYQR);
  }

  /** 安全构建：非法支付码返回 invalid_code，不抛异常。 */
  static tryBuildDeepLink(payCode: string): CampusPaymentLaunchResult {
    const extracted: string = AlipayPaymentService.extractPayCode(payCode);
    const code: string = AlipayPaymentService.normalizePayCode(extracted);
    if (code.length === 0) {
      return new CampusPaymentLaunchResult(
        CampusPaymentStatus.INVALID_CODE,
        CampusPaymentI18n.ERROR_INVALID_CODE,
        0,
        ''
      );
    }
    return new CampusPaymentLaunchResult(
      CampusPaymentStatus.BUILD_READY,
      CampusPaymentI18n.LINK_READY,
      0,
      AlipayPaymentService.buildDeepLinkForScheme(code, PAYMENT_SCHEME_ALIPAYQR)
    );
  }

  /**
   * 从完整二维码 URL 提取最后一个路径段（去除查询参数、片段与末尾斜杠）。
   * 裸支付码原样返回；无法提取时返回空串。
   */
  static extractPayCode(input: string): string {
    const value: string = input.trim();
    if (value.length === 0) {
      return '';
    }
    const schemeIndex: number = value.indexOf('://');
    if (schemeIndex <= 0) {
      return value;
    }

    let withoutQuery: string = value;
    const queryIndex: number = value.indexOf('?');
    const fragmentIndex: number = value.indexOf('#');
    let cutIndex: number = -1;
    if (queryIndex >= 0 && fragmentIndex >= 0) {
      cutIndex = Math.min(queryIndex, fragmentIndex);
    } else if (queryIndex >= 0) {
      cutIndex = queryIndex;
    } else if (fragmentIndex >= 0) {
      cutIndex = fragmentIndex;
    }
    if (cutIndex >= 0) {
      withoutQuery = value.substring(0, cutIndex);
    }

    const authorityStart: number = schemeIndex + 3;
    const pathIndex: number = withoutQuery.indexOf('/', authorityStart);
    if (pathIndex < 0) {
      return '';
    }
    let path: string = withoutQuery.substring(pathIndex + 1);
    while (path.length > 0 && path.charAt(path.length - 1) === '/') {
      path = path.substring(0, path.length - 1);
    }
    if (path.length === 0) {
      return '';
    }
    const lastSlash: number = path.lastIndexOf('/');
    if (lastSlash >= 0) {
      path = path.substring(lastSlash + 1);
    }
    return path.trim();
  }

  private static buildDeepLinkForScheme(payCode: string, scheme: string): string {
    // 与 RN 基线逐字符一致：固定编码前缀 + 原始 payCode（保留 + 等字符）。
    return scheme + PAYMENT_LINK_PATH + PAYMENT_QR_ENCODED_PREFIX + payCode;
  }

  /**
   * 支付码严格校验：trim 后非空、长度 ≤ 256；
   * 拒绝空白、控制字符与会破坏 URL 结构的 & ? # / %。
   */
  private static normalizePayCode(input: string): string {
    const code: string = input.trim();
    if (code.length === 0 || code.length > PAYMENT_MAX_CODE_LENGTH) {
      return '';
    }
    for (let i: number = 0; i < code.length; i += 1) {
      const ch: string = code.charAt(i);
      const charCode: number = code.charCodeAt(i);
      if (charCode < 0x20 || charCode === 0x7f) {
        return '';
      }
      if (PAYMENT_WHITESPACE.test(ch)) {
        return '';
      }
      if (ch === '&' || ch === '?' || ch === '#' || ch === '/' || ch === '%') {
        return '';
      }
    }
    return code;
  }
}
