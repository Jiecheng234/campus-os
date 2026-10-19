/**
 * PaymentSelfTest — 支付基础设施启动自检。
 *
 * 只测试纯逻辑与事件总线：不发起网络请求、不调用 openLink、不修改业务数据。
 * 日志标签 PaymentTest；PASS/FAIL 只包含用例名，不输出支付码或二维码 URL。
 */
import { Log } from '../../utils/Logger';
import {
  AlipayPaymentService,
  CampusPaymentI18n,
  CampusPaymentIntent,
  CampusPaymentLaunchResult,
  CampusPaymentReturnEvent,
  CampusPaymentReturnSubscription,
  CampusPaymentStatus,
  CampusPaymentSubsystem,
  CAMPUS_PAYMENT_PENDING_TTL_MS,
  CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID
} from './AlipayPaymentService';

const TAG: string = 'PaymentTest';
const EXPECTED_BAX123_URL: string =
  'alipayqr://platformapi/startapp?saId=10000007&qrcode=https%3A%2F%2Fqr.alipay.com%2Fbax123';
const EXPECTED_BAX_PLUS_URL: string =
  'alipayqr://platformapi/startapp?saId=10000007&qrcode=https%3A%2F%2Fqr.alipay.com%2Fbax+123';

class PaymentTestRunner {
  static passed: number = 0;
  static failed: number = 0;
  static ran: boolean = false;
  static lastFailures: number = 0;

  static test(name: string, fn: () => boolean): void {
    let result: boolean = false;
    try {
      result = fn();
    } catch (error) {
      // 异常文本不可控，可能包含敏感输入；自检只记录用例失败，不输出异常正文。
      PaymentTestRunner.logFail(name, 'Exception');
      return;
    }
    if (result) {
      Log.i(TAG, 'PASS: %{public}s', name);
      PaymentTestRunner.passed += 1;
    } else {
      PaymentTestRunner.logFail(name, 'Assertion failed');
    }
  }

  static async testAsync(name: string, fn: () => Promise<boolean>): Promise<void> {
    let result: boolean = false;
    try {
      result = await fn();
    } catch (error) {
      PaymentTestRunner.logFail(name, 'Exception');
      return;
    }
    if (result) {
      Log.i(TAG, 'PASS: %{public}s', name);
      PaymentTestRunner.passed += 1;
    } else {
      PaymentTestRunner.logFail(name, 'Assertion failed');
    }
  }

  static logFail(name: string, detail: string): void {
    Log.e(TAG, 'FAIL: %{public}s — %{public}s', name, detail);
    PaymentTestRunner.failed += 1;
  }
}

class PaymentReturnCapture {
  count: number = 0;
  subsystem: string = '';
  amount: number = -1;
  startedAt: number = 0;
  elapsedMs: number = -1;
}

export async function runPaymentSelfTest(): Promise<number> {
  // 一次性运行：窗口重建导致重复调用时，不得清理真实 pending 或重复 emit。
  if (PaymentTestRunner.ran) {
    Log.i(
      TAG,
      '===== Payment Self-Test Skipped (already ran): %{public}d failed =====',
      PaymentTestRunner.lastFailures
    );
    return PaymentTestRunner.lastFailures;
  }
  PaymentTestRunner.ran = true;
  PaymentTestRunner.passed = 0;
  PaymentTestRunner.failed = 0;

  Log.i(TAG, '===== Payment Self-Test Start =====');

  runLinkBuildTests();
  // emitter 通过事件队列异步投递，回读用例必须等待回调到达后再断言。
  await runReturnEventTests();

  const total: number = PaymentTestRunner.passed + PaymentTestRunner.failed;
  Log.i(
    TAG,
    '===== Payment Self-Test Done: %{public}d/%{public}d passed, %{public}d failed =====',
    PaymentTestRunner.passed,
    total,
    PaymentTestRunner.failed
  );
  PaymentTestRunner.lastFailures = PaymentTestRunner.failed;
  return PaymentTestRunner.failed;
}

function isInvalid(result: CampusPaymentLaunchResult): boolean {
  return result.status === CampusPaymentStatus.INVALID_CODE && result.url.length === 0;
}

function runLinkBuildTests(): void {
  PaymentTestRunner.test('Deep link matches RN baseline', (): boolean => {
    return AlipayPaymentService.buildDeepLink('bax123') === EXPECTED_BAX123_URL;
  });

  PaymentTestRunner.test('Safe build returns baseline url', (): boolean => {
    const result: CampusPaymentLaunchResult = AlipayPaymentService.tryBuildDeepLink('bax+123');
    return result.status === CampusPaymentStatus.BUILD_READY &&
      result.messageKey === CampusPaymentI18n.LINK_READY &&
      result.url === EXPECTED_BAX_PLUS_URL;
  });

  PaymentTestRunner.test('Build is deterministic', (): boolean => {
    const first: string = AlipayPaymentService.buildDeepLink('bax123');
    const second: string = AlipayPaymentService.buildDeepLink('bax123');
    return first === second;
  });

  PaymentTestRunner.test('Extract pay code from full qr url', (): boolean => {
    return AlipayPaymentService.extractPayCode('https://qr.alipay.com/bax123') === 'bax123';
  });

  PaymentTestRunner.test('Extract pay code ignores query and fragment', (): boolean => {
    return AlipayPaymentService.extractPayCode('https://qr.alipay.com/bax123/?from=app#frag') === 'bax123';
  });

  PaymentTestRunner.test('Extract pay code rejects empty path', (): boolean => {
    return AlipayPaymentService.extractPayCode('https://qr.alipay.com/') === '';
  });

  PaymentTestRunner.test('Full qr url builds baseline url', (): boolean => {
    const result: CampusPaymentLaunchResult =
      AlipayPaymentService.tryBuildDeepLink('https://qr.alipay.com/bax123?from=app');
    return result.status === CampusPaymentStatus.BUILD_READY && result.url === EXPECTED_BAX123_URL;
  });

  PaymentTestRunner.test('Empty pay code rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink(''));
  });

  PaymentTestRunner.test('Whitespace-only pay code rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('   '));
  });

  PaymentTestRunner.test('Internal whitespace rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax 123'));
  });

  PaymentTestRunner.test('Control character rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax' + String.fromCharCode(1) + '123'));
  });

  PaymentTestRunner.test('Ampersand rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax&123'));
  });

  PaymentTestRunner.test('Question mark rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax?123'));
  });

  PaymentTestRunner.test('Hash rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax#123'));
  });

  PaymentTestRunner.test('Slash rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax/123'));
  });

  PaymentTestRunner.test('Percent rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('bax%20123'));
  });

  PaymentTestRunner.test('Overlong pay code rejected', (): boolean => {
    return isInvalid(AlipayPaymentService.tryBuildDeepLink('a'.repeat(257)));
  });

  PaymentTestRunner.test('Maximum length pay code accepted', (): boolean => {
    const result: CampusPaymentLaunchResult = AlipayPaymentService.tryBuildDeepLink('a'.repeat(256));
    return result.status === CampusPaymentStatus.BUILD_READY && result.url.length > 0;
  });

  PaymentTestRunner.test('Raw build throws on invalid code', (): boolean => {
    let threw: boolean = false;
    try {
      AlipayPaymentService.buildDeepLink('');
    } catch (error) {
      threw = true;
    }
    return threw;
  });
}

function subscribeCapture(capture: PaymentReturnCapture): CampusPaymentReturnSubscription {
  return AlipayPaymentService.subscribeReturn(
    (event: CampusPaymentReturnEvent): void => {
      capture.count += 1;
      capture.subsystem = event.intent.subsystem;
      capture.amount = event.intent.amount;
      capture.startedAt = event.intent.startedAt;
      capture.elapsedMs = event.elapsedMs;
    },
    CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID
  );
}

function pollReturnCapture(
  capture: PaymentReturnCapture,
  expected: number,
  startedAt: number,
  timeoutMs: number,
  resolve: (value: boolean) => void
): void {
  if (capture.count >= expected) {
    resolve(true);
    return;
  }
  if (Date.now() - startedAt >= timeoutMs) {
    resolve(false);
    return;
  }
  setTimeout((): void => {
    pollReturnCapture(capture, expected, startedAt, timeoutMs, resolve);
  }, 10);
}

/** 等待 emitter 队列投递回调；超时返回 false（不阻塞首页加载，仅自检内部等待）。 */
function waitForReturnCount(
  capture: PaymentReturnCapture,
  expected: number,
  timeoutMs: number
): Promise<boolean> {
  return new Promise<boolean>((resolve: (value: boolean) => void): void => {
    pollReturnCapture(capture, expected, Date.now(), timeoutMs, resolve);
  });
}

async function runReturnEventTests(): Promise<void> {
  await PaymentTestRunner.testAsync('Pending return delivered exactly once', async (): Promise<boolean> => {
    AlipayPaymentService.clearPending();
    const capture: PaymentReturnCapture = new PaymentReturnCapture();
    const sub: CampusPaymentReturnSubscription = subscribeCapture(capture);
    try {
      AlipayPaymentService.beginPending(
        CampusPaymentSubsystem.ELECTRICITY,
        12.5,
        Date.now() - 1000
      );
      AlipayPaymentService.notifyForeground(CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID, TAG);
      AlipayPaymentService.notifyForeground(CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID, TAG);
      const delivered: boolean = await waitForReturnCount(capture, 1, 500);
      return delivered && capture.count === 1 && AlipayPaymentService.peekPending() === null;
    } finally {
      AlipayPaymentService.unsubscribeReturn(sub);
      AlipayPaymentService.clearPending();
    }
  });

  PaymentTestRunner.test('No pending does not emit', (): boolean => {
    AlipayPaymentService.clearPending();
    const capture: PaymentReturnCapture = new PaymentReturnCapture();
    const sub: CampusPaymentReturnSubscription = subscribeCapture(capture);
    try {
      AlipayPaymentService.notifyForeground(CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID, TAG);
      return capture.count === 0;
    } finally {
      AlipayPaymentService.unsubscribeReturn(sub);
      AlipayPaymentService.clearPending();
    }
  });

  PaymentTestRunner.test('Expired pending does not emit and is cleared', (): boolean => {
    AlipayPaymentService.clearPending();
    const capture: PaymentReturnCapture = new PaymentReturnCapture();
    const sub: CampusPaymentReturnSubscription = subscribeCapture(capture);
    try {
      AlipayPaymentService.beginPending(
        CampusPaymentSubsystem.SPORTS,
        0,
        Date.now() - CAMPUS_PAYMENT_PENDING_TTL_MS - 1000
      );
      AlipayPaymentService.notifyForeground(CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID, TAG);
      return capture.count === 0 && AlipayPaymentService.peekPending() === null;
    } finally {
      AlipayPaymentService.unsubscribeReturn(sub);
      AlipayPaymentService.clearPending();
    }
  });

  PaymentTestRunner.test('Latest pending overwrites previous', (): boolean => {
    AlipayPaymentService.clearPending();
    try {
      const now: number = Date.now();
      AlipayPaymentService.beginPending(CampusPaymentSubsystem.ELECTRICITY, 1, now - 2000);
      AlipayPaymentService.beginPending(CampusPaymentSubsystem.CAMPUS_CARD, 2, now);
      const pending: CampusPaymentIntent | null = AlipayPaymentService.peekPending();
      if (pending === null) {
        return false;
      }
      return pending.subsystem === CampusPaymentSubsystem.CAMPUS_CARD && pending.amount === 2;
    } finally {
      AlipayPaymentService.clearPending();
    }
  });

  await PaymentTestRunner.testAsync('Return payload has four fields', async (): Promise<boolean> => {
    AlipayPaymentService.clearPending();
    const capture: PaymentReturnCapture = new PaymentReturnCapture();
    const sub: CampusPaymentReturnSubscription = subscribeCapture(capture);
    try {
      const startedAt: number = Date.now() - 500;
      AlipayPaymentService.beginPending(CampusPaymentSubsystem.SPORTS, 7.5, startedAt);
      AlipayPaymentService.notifyForeground(CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID, TAG);
      const delivered: boolean = await waitForReturnCount(capture, 1, 500);
      return delivered &&
        capture.count === 1 &&
        capture.subsystem === CampusPaymentSubsystem.SPORTS &&
        capture.amount === 7.5 &&
        capture.startedAt === startedAt &&
        capture.elapsedMs >= 0;
    } finally {
      AlipayPaymentService.unsubscribeReturn(sub);
      AlipayPaymentService.clearPending();
    }
  });

  PaymentTestRunner.test('Unsubscribed handler is not called', (): boolean => {
    AlipayPaymentService.clearPending();
    const capture: PaymentReturnCapture = new PaymentReturnCapture();
    const sub: CampusPaymentReturnSubscription = subscribeCapture(capture);
    try {
      AlipayPaymentService.unsubscribeReturn(sub);
      AlipayPaymentService.beginPending(CampusPaymentSubsystem.ELECTRICITY, 0, Date.now());
      AlipayPaymentService.notifyForeground(CAMPUS_PAYMENT_TEST_RETURN_EVENT_ID, TAG);
      return capture.count === 0;
    } finally {
      AlipayPaymentService.unsubscribeReturn(sub);
      AlipayPaymentService.clearPending();
    }
  });
}
