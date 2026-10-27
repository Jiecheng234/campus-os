import { Log } from '../utils/Logger';
import { AuditRecord } from '../domain/ActionTypes';
import { PreferencesStorage } from './PreferencesStorage';
import { StorageKeys } from './StorageKeys';

const AUDIT_TAG: string = 'ActionAuditStore';
/** 持久化记录上限（对齐 RN actionAuditStorage.MAX_RECORDS） */
const MAX_RECORDS: number = 200;
/** 参数字符串截断长度 */
const MAX_STRING_LENGTH: number = 500;
/** 结果 JSON 字符串截断长度 */
const RESULT_MAX_STRING_LENGTH: number = 2000;
/** 数组元素上限 */
const MAX_ARRAY_LENGTH: number = 20;
/** 递归深度上限 */
const MAX_DEPTH: number = 5;
/** 审计面板监听的刷新信号（AppStorage 键） */
export const AUDIT_TICK_KEY: string = 'auditTick';

/** 加载状态常量：idle=未加载 ok=成功 failed=失败（可重试） */
const LOAD_IDLE: string = 'idle';
const LOAD_OK: string = 'ok';
const LOAD_FAILED: string = 'failed';

/** 单调递增 tick 序列（避免同毫秒多次写入不触发 @Watch） */
let auditTickSeq: number = 0;

/** 向面板投递刷新信号（单调递增，必定驱动 @Watch） */
function notifyAuditTick(): void {
  auditTickSeq += 1;
  AppStorage.setOrCreate<number>(AUDIT_TICK_KEY, auditTickSeq);
}

/** 敏感键正则（对齐 RN SENSITIVE_KEY_PATTERN） */
const SENSITIVE_KEY_PATTERN: RegExp =
  /(password|passwd|pwd|secret|token|cookie|captcha|verification|api.?key|credential|fingerprint|trade.?password|transaction.?password|phone|mobile|email|student.?id|owner.?id|user.?id|member.*id|idserial|card.?id|account|acc.?no|identity|idcard|mac|ip4|ip6)/i;

/** 11 位手机号/证件号检测 */
const ELEVEN_DIGIT_PATTERN: RegExp = /^\d{11}$/;

/** 文本级兜底打码：连续 11 位数字（词边界防误吞更长数字串） */
const ELEVEN_DIGIT_TEXT_PATTERN: RegExp = /\b\d{11}\b/g;

/** 文本级兜底打码：邮箱（本地部分保留前 2 位 + *** + @域名） */
const EMAIL_TEXT_PATTERN: RegExp = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;

/** 文本级兜底打码：敏感键 key=value / key: value 形态（值整体替换为 ***） */
const SENSITIVE_KV_TEXT_PATTERN: RegExp =
  /(password|passwd|pwd|secret|token|cookie|captcha|credential|apikey)(\s*[=:]\s*)([^\s,;&"']+)/gi;

/**
 * AI 行为审计持久化仓库（ai-governance 特性）。
 * - 内存缓存 + PreferencesStorage 持久化（StorageKeys.ACTION_AUDIT）
 * - load / append / clear 全部串到同一串行队列，避免并发读写相互覆盖
 * - 读取失败标记 failed 且不写盘（防止空集覆盖最多 200 条历史），ensureLoaded 可重试
 * - 写入前统一脱敏（敏感键遮蔽、邮箱/手机号文本兜底打码、长度截断、深度/数组截断）
 */
export class ActionAuditStore {
  private static records: AuditRecord[] = [];
  private static loadState: string = LOAD_IDLE;
  /** 串行队列：load / append / clear 全部串行 */
  private static writeChain: Promise<void> = Promise.resolve();

  /**
   * 幂等加载：成功后直接复用；失败可重试（面板据失败态提示）。
   * 排入串行队列执行，与写入互不并发。
   */
  static ensureLoaded(): Promise<void> {
    if (ActionAuditStore.loadState === LOAD_OK) {
      return Promise.resolve();
    }
    const next: Promise<void> = ActionAuditStore.writeChain.then((): Promise<void> => {
      return ActionAuditStore.loadInternal();
    });
    ActionAuditStore.writeChain = next.catch((): void => {
    });
    return next;
  }

  /** 同步读取内存缓存（页面展示用；先 ensureLoaded） */
  static getRecords(): AuditRecord[] {
    return ActionAuditStore.records;
  }

  /** 是否已成功加载 */
  static isLoaded(): boolean {
    return ActionAuditStore.loadState === LOAD_OK;
  }

  /** 追加一条审计记录（脱敏后持久化，最新在前，超限裁剪） */
  static append(record: AuditRecord): Promise<void> {
    const next: Promise<void> = ActionAuditStore.writeChain.then((): Promise<void> => {
      return ActionAuditStore.appendInternal(record);
    });
    ActionAuditStore.writeChain = next.catch((): void => {
    });
    return next;
  }

  /** 清空全部审计记录（内存 + 持久化，走串行队列；失败上抛由面板提示） */
  static clear(): Promise<void> {
    const next: Promise<void> = ActionAuditStore.writeChain.then((): Promise<void> => {
      return ActionAuditStore.clearInternal();
    });
    ActionAuditStore.writeChain = next.catch((): void => {
    });
    return next;
  }

  /** 参数 JSON 脱敏：递归遮蔽敏感键 + 文本兜底打码 + 500 字符截断 */
  static sanitizeParamsJson(paramsJson: string): string {
    return ActionAuditStore.sanitizeJsonString(paramsJson, MAX_STRING_LENGTH);
  }

  /** 结果 JSON 脱敏：递归遮蔽敏感键 + 文本兜底打码 + 2000 字符截断 */
  static sanitizeResultJson(resultJson: string): string {
    return ActionAuditStore.sanitizeJsonString(resultJson, RESULT_MAX_STRING_LENGTH);
  }

  /**
   * 普通文本脱敏（FR-003 / plan D7：摘要类纯文本兜底打码后再截断）：
   * 1. 敏感键 key=value / key: value → 值替换为 ***
   * 2. 连续 11 位数字 → 前3****后4
   * 3. 邮箱 → 前2***@域名
   * 4. 长度截断（默认 500）
   */
  static sanitizeText(text: string): string {
    const redacted: string = ActionAuditStore.redactText(text);
    return ActionAuditStore.truncateString(redacted, MAX_STRING_LENGTH);
  }

  /** 从持久化读入内存缓存；失败标记 failed 并上抛（不以空集合覆盖历史） */
  private static async loadInternal(): Promise<void> {
    try {
      const raw: string = await PreferencesStorage.getString(StorageKeys.ACTION_AUDIT, '');
      const out: AuditRecord[] = [];
      if (raw.length > 0) {
        const parsed: Object | null = JSON.parse(raw) as Object | null;
        if (parsed !== null && parsed instanceof Array) {
          const items: Object[] = parsed as Object[];
          for (const item of items) {
            out.push(ActionAuditStore.toRecord(item));
          }
        }
      }
      ActionAuditStore.records = out;
      ActionAuditStore.loadState = LOAD_OK;
    } catch (error) {
      // 读取失败：保留内存现状并标记 failed——append 不写盘，
      // 避免以空集落盘覆盖最多 200 条历史记录；ensureLoaded 可重试
      ActionAuditStore.loadState = LOAD_FAILED;
      Log.w(AUDIT_TAG, 'audit load failed');
      throw new Error(`ActionAuditStore load failed: ${String(error)}`);
    }
  }

  private static async appendInternal(record: AuditRecord): Promise<void> {
    if (ActionAuditStore.loadState !== LOAD_OK) {
      // 首次加载 / 读取失败后重试；再失败则上抛中止本次写入（调用方 fire-and-forget catch）
      await ActionAuditStore.loadInternal();
    }
    const clean: AuditRecord = ActionAuditStore.sanitizeRecord(record);
    const records: AuditRecord[] = ActionAuditStore.records.slice();
    records.unshift(clean);
    if (records.length > MAX_RECORDS) {
      records.splice(MAX_RECORDS);
    }
    ActionAuditStore.records = records;
    await PreferencesStorage.setJson<AuditRecord[]>(StorageKeys.ACTION_AUDIT, records);
    notifyAuditTick();
  }

  /** 先清盘再清内存：清盘失败时内存仍保留旧记录（与磁盘一致），便于面板发现 */
  private static async clearInternal(): Promise<void> {
    try {
      await PreferencesStorage.remove(StorageKeys.ACTION_AUDIT);
      ActionAuditStore.records = [];
    } finally {
      // 成功/失败都发 tick（失败时面板读到的仍是旧记录）
      notifyAuditTick();
    }
  }

  /** 复制并脱敏一条记录（不修改调用方传入对象） */
  private static sanitizeRecord(record: AuditRecord): AuditRecord {
    const clean: AuditRecord = new AuditRecord();
    clean.id = record.id.length > 0 ? record.id : ActionAuditStore.makeAuditId();
    clean.timestamp = record.timestamp;
    clean.toolName = record.toolName;
    clean.parameters = ActionAuditStore.sanitizeText(record.parameters);
    clean.result = ActionAuditStore.sanitizeResultJson(record.result);
    clean.success = record.success;
    clean.confirmed = record.confirmed;
    clean.toolTitle = record.toolTitle;
    clean.risk = record.risk;
    clean.status = record.status;
    clean.confirmation = record.confirmation;
    clean.resultSummary = ActionAuditStore.sanitizeText(record.resultSummary);
    clean.errorMessage = ActionAuditStore.sanitizeText(record.errorMessage);
    clean.permission = record.permission;
    clean.paramsJson = ActionAuditStore.sanitizeParamsJson(record.paramsJson);
    clean.previewAffectedResource = ActionAuditStore.sanitizeText(record.previewAffectedResource);
    clean.verificationOk = record.verificationOk;
    clean.verificationMessage = ActionAuditStore.sanitizeText(record.verificationMessage);
    return clean;
  }

  private static makeAuditId(): string {
    return `audit_${Date.now()}_${Math.floor(Math.random() * 0xffffffff).toString(36)}`;
  }

  /** JSON 字符串递归脱敏；解析失败则退化为文本打码 + 截断。序列化结果再做长度上限兜底 */
  private static sanitizeJsonString(raw: string, maxLen: number): string {
    const trimmed: string = raw.trim();
    if (trimmed.length === 0) {
      return '';
    }
    try {
      const parsed: Object | null = JSON.parse(trimmed) as Object | null;
      const clean: Object | null = ActionAuditStore.sanitizeValue(parsed, '', 0, maxLen);
      const serialized: string = JSON.stringify(clean);
      return ActionAuditStore.truncateString(serialized, maxLen);
    } catch (error) {
      // 解析失败（截断过的 JSON / 非法 JSON）：仍做文本级打码，不能只截断
      return ActionAuditStore.truncateString(ActionAuditStore.redactText(trimmed), maxLen);
    }
  }

  /** 递归脱敏任意 JSON 值（敏感键遮蔽 / 文本兜底打码 / 截断 / 深度与数组限制） */
  private static sanitizeValue(value: Object | null, keyHint: string, depth: number, maxLen: number): Object | null {
    if (keyHint.length > 0 && SENSITIVE_KEY_PATTERN.test(keyHint)) {
      if (typeof value === 'string') {
        return ActionAuditStore.maskString(value as string);
      }
      return '[REDACTED]';
    }
    if (value === null || value === undefined) {
      return null;
    }
    if (typeof value === 'string') {
      // 普通字符串叶子（如邮件 address/brief/text）：文本兜底打码后截断
      return ActionAuditStore.truncateString(ActionAuditStore.redactText(value as string), maxLen);
    }
    if (typeof value === 'number' || typeof value === 'boolean') {
      return value;
    }
    if (depth >= MAX_DEPTH) {
      return '[TRUNCATED]';
    }
    if (value instanceof Array) {
      const src: Object[] = value as Object[];
      const out: Object[] = [];
      const limit: number = Math.min(src.length, MAX_ARRAY_LENGTH);
      for (let i = 0; i < limit; i++) {
        out.push(ActionAuditStore.sanitizeValue(src[i], keyHint, depth + 1, maxLen) as Object);
      }
      if (src.length > MAX_ARRAY_LENGTH) {
        out.push(`[${src.length - MAX_ARRAY_LENGTH} more items]`);
      }
      return out;
    }
    const src: Record<string, Object | null> = value as Record<string, Object | null>;
    const out: Record<string, Object | null> = {};
    const keys: string[] = Object.keys(src);
    for (const key of keys) {
      out[key] = ActionAuditStore.sanitizeValue(src[key], key, depth + 1, maxLen);
    }
    return out;
  }

  /** 敏感值遮蔽：11 位 → 前3****后4；长度 ≤4 → [REDACTED]；否则 前2***后2 */
  private static maskString(value: string): string {
    if (value.length === 0) {
      return '';
    }
    if (ELEVEN_DIGIT_PATTERN.test(value)) {
      return `${value.substring(0, 3)}****${value.substring(7)}`;
    }
    if (value.length <= 4) {
      return '[REDACTED]';
    }
    return `${value.substring(0, 2)}***${value.substring(value.length - 2)}`;
  }

  /** 文本级兜底打码：敏感 kv → 11 位数字 → 邮箱（对已打码文本幂等，不会二次误伤） */
  private static redactText(text: string): string {
    if (text.length === 0) {
      return text;
    }
    // 1. 敏感键 key=value / key: value → 值替换为 ***（保留键与分隔符）
    const noKv: string = text.replace(SENSITIVE_KV_TEXT_PATTERN, '$1$2***');
    // 2. 连续 11 位数字 → 前3****后4
    const noDigits: string = noKv.replace(ELEVEN_DIGIT_TEXT_PATTERN,
      (match: string): string => `${match.substring(0, 3)}****${match.substring(7)}`);
    // 3. 邮箱 → 前2***@域名
    return noDigits.replace(EMAIL_TEXT_PATTERN, (match: string): string => {
      const at: number = match.indexOf('@');
      return `${match.substring(0, 2)}***${match.substring(at)}`;
    });
  }

  private static truncateString(value: string, maxLen: number): string {
    if (value.length <= maxLen) {
      return value;
    }
    return `${value.substring(0, maxLen)}...`;
  }

  /** 从持久化的宽松 JSON 对象恢复严格 AuditRecord（逐字段类型校验） */
  private static toRecord(item: Object): AuditRecord {
    const src: Record<string, Object | null> = item as Record<string, Object | null>;
    const record: AuditRecord = new AuditRecord();
    record.id = ActionAuditStore.readString(src, 'id');
    record.timestamp = ActionAuditStore.readString(src, 'timestamp');
    record.toolName = ActionAuditStore.readString(src, 'toolName');
    record.parameters = ActionAuditStore.readString(src, 'parameters');
    record.result = ActionAuditStore.readString(src, 'result');
    record.success = ActionAuditStore.readBoolean(src, 'success');
    record.confirmed = ActionAuditStore.readBoolean(src, 'confirmed');
    record.toolTitle = ActionAuditStore.readString(src, 'toolTitle');
    record.risk = ActionAuditStore.readString(src, 'risk');
    record.status = ActionAuditStore.readString(src, 'status');
    record.confirmation = ActionAuditStore.readString(src, 'confirmation');
    record.resultSummary = ActionAuditStore.readString(src, 'resultSummary');
    record.errorMessage = ActionAuditStore.readString(src, 'errorMessage');
    record.permission = ActionAuditStore.readString(src, 'permission');
    record.paramsJson = ActionAuditStore.readString(src, 'paramsJson');
    record.previewAffectedResource = ActionAuditStore.readString(src, 'previewAffectedResource');
    record.verificationOk = ActionAuditStore.readBoolean(src, 'verificationOk');
    record.verificationMessage = ActionAuditStore.readString(src, 'verificationMessage');
    return record;
  }

  private static readString(src: Record<string, Object | null>, key: string): string {
    const value: Object | null = src[key];
    if (typeof value === 'string') {
      return value as string;
    }
    return '';
  }

  private static readBoolean(src: Record<string, Object | null>, key: string): boolean {
    const value: Object | null = src[key];
    if (typeof value === 'boolean') {
      return value as boolean;
    }
    return false;
  }
}
