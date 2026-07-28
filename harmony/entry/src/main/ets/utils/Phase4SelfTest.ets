import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  encodeBase64, decodeBase64, sha256, md5, generateUUID,
  bytesToHex, stringToUint8Array, uint8ArrayToString
} from './CryptoUtils';
import { decodeURLEncodedGBK } from './EncodingUtils';
import { I18nUtils } from './I18nUtils';
import { CookieJar } from '../services/CookieJar';
import { StateManager } from '../state/StateManager';
import { AuthManager } from '../state/AuthManager';
import { LearningManager } from '../state/LearningManager';
import { ScheduleManager } from '../state/ScheduleManager';
import { AIChatManager } from '../state/AIChatManager';
import { SettingsManager } from '../state/SettingsManager';

const DOMAIN: number = 0xCAFE;
const TAG: string = 'Phase4Test';

class TestRunner {
  static passed: number = 0;
  static failed: number = 0;

  static log(msg: string): void {
    hilog.info(DOMAIN, TAG, '%{public}s', msg);
  }

  static test(name: string, fn: () => boolean): void {
    let result: boolean = false;
    try {
      result = fn();
    } catch (e) {
      TestRunner.logFail(name, 'Exception: ' + (e instanceof Error ? e.message : 'unknown'));
      return;
    }
    if (result) {
      hilog.info(DOMAIN, TAG, 'PASS: %{public}s', name);
      TestRunner.passed = TestRunner.passed + 1;
    } else {
      TestRunner.logFail(name, 'Assertion failed');
    }
  }

  static logFail(name: string, detail: string): void {
    hilog.error(DOMAIN, TAG, 'FAIL: %{public}s — %{public}s', name, detail);
    TestRunner.failed = TestRunner.failed + 1;
  }
}

export function runPhase4SelfTest(): number {
  TestRunner.passed = 0;
  TestRunner.failed = 0;

  TestRunner.log('===== Phase4 Self-Test Start =====');

  runCryptoTests();
  runEncodingTests();
  runI18nTests();
  runCookieTests();
  runStateTests();

  const total: number = TestRunner.passed + TestRunner.failed;
  TestRunner.log(`===== Phase4 Self-Test Done: ${TestRunner.passed}/${total} passed, ${TestRunner.failed} failed =====`);
  return TestRunner.failed;
}

function runCryptoTests(): void {
  TestRunner.test('Base64 round-trip', () => {
    const input: string = 'Hello CampusOS 2025!';
    const encoded: string = encodeBase64(input);
    const decoded: string = decodeBase64(encoded);
    return decoded === input;
  });

  TestRunner.test('Base64 empty string', () => {
    const encoded: string = encodeBase64('');
    const decoded: string = decodeBase64(encoded);
    return decoded === '';
  });

  TestRunner.test('SHA256 hash length', () => {
    const hash: string = sha256('test');
    return hash.length === 64;
  });

  TestRunner.test('MD5 hash length', () => {
    const hash: string = md5('test');
    return hash.length === 32;
  });

  TestRunner.test('UUID generation', () => {
    const id1: string = generateUUID();
    const id2: string = generateUUID();
    return id1.length >= 36 && id1 !== id2;
  });

  TestRunner.test('BytesToHex round-trip', () => {
    const input: Uint8Array = new Uint8Array([0x48, 0x65, 0x6C, 0x6C, 0x6F]);
    const hex: string = bytesToHex(input);
    return hex === '48656c6c6f';
  });

  TestRunner.test('String/Uint8 conversion', () => {
    const input: string = 'CampusOS';
    const bytes: Uint8Array = stringToUint8Array(input);
    const back: string = uint8ArrayToString(bytes);
    return back === input;
  });
}

function runEncodingTests(): void {
  TestRunner.test('Decode URL-encoded ASCII', () => {
    const result: string = decodeURLEncodedGBK('hello%20world');
    return result.indexOf('hello') >= 0;
  });

  TestRunner.test('Decode plain text passthrough', () => {
    const input: string = 'Hello World 2025';
    const result: string = decodeURLEncodedGBK(input);
    return result === input;
  });
}

function runI18nTests(): void {
  TestRunner.test('I18n format date short', () => {
    const date: Date = new Date(2025, 0, 15);
    const result: string = I18nUtils.formatDateShort(date);
    return result === '01/15';
  });

  TestRunner.test('I18n format relative time', () => {
    const result: string = I18nUtils.formatRelativeTime(new Date().toISOString());
    return result.length > 0;
  });

  TestRunner.test('I18n isZh default', () => {
    return I18nUtils.isZh() === true;
  });
}

function runCookieTests(): void {
  TestRunner.test('CookieJar set and get', () => {
    const jar: CookieJar = new CookieJar();
    jar.setFromResponse('https://tsinghua.edu.cn', 'session=abc123; Path=/; Domain=tsinghua.edu.cn');
    const cookieStr: string = jar.getCookieString('https://tsinghua.edu.cn/index');
    return cookieStr.indexOf('session=abc123') >= 0;
  });

  TestRunner.test('CookieJar clear', () => {
    const jar: CookieJar = new CookieJar();
    jar.setFromResponse('https://tsinghua.edu.cn', 'token=xyz');
    jar.clear();
    const cookieStr: string = jar.getCookieString('https://tsinghua.edu.cn');
    return cookieStr.length === 0;
  });

  TestRunner.test('CookieJar serialize/deserialize', () => {
    const jar: CookieJar = new CookieJar();
    jar.setFromResponse('https://tsinghua.edu.cn', 'session=s1');
    jar.setFromResponse('https://tsinghua.edu.cn', 'token=t1');
    const serialized: string = jar.serialize();
    const jar2: CookieJar = new CookieJar();
    jar2.deserialize(serialized);
    const cs: string = jar2.getCookieString('https://tsinghua.edu.cn');
    return cs.indexOf('session=s1') >= 0 && cs.indexOf('token=t1') >= 0;
  });
}

function runStateTests(): void {
  TestRunner.test('AuthManager reset', () => {
    AuthManager.reset();
    return AuthManager.isLoggedIn() === false;
  });

  TestRunner.test('AuthManager login flow', () => {
    AuthManager.startLogin();
    AuthManager.loginSuccess();
    const isLogged: boolean = AuthManager.isLoggedIn();
    AuthManager.reset();
    return isLogged === true;
  });

  TestRunner.test('LearningManager empty state', () => {
    const courses = LearningManager.getCourses();
    return courses.length === 0;
  });

  TestRunner.test('ScheduleManager add personal event', () => {
    const event = ScheduleManager.addPersonalEvent('Test', 1, 3, 5, 'Room 101', 'Test notes');
    const events = ScheduleManager.getPersonalEvents();
    const found: boolean = events[0].id === event.id;
    ScheduleManager.removePersonalEvent(event.id);
    return found;
  });

  TestRunner.test('AIChatManager create conversation', () => {
    const conv = AIChatManager.createConversation();
    const convId: string = conv.id;
    AIChatManager.deleteConversation(convId);
    return convId.length > 0;
  });

  TestRunner.test('SettingsManager locale', () => {
    SettingsManager.setLocale('zh');
    const locale: string = SettingsManager.getLocale();
    return locale === 'zh';
  });

  TestRunner.test('StateManager demo default', () => {
    return StateManager.settings.demoMode === false;
  });
}
