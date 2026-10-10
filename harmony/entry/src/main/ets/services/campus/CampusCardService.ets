/**
 * CampusCardService — 校园卡只读查询（余额/信息/近 7 天流水）
 * 对齐原项目 src/services/campus/campusCard.ts（thu-info-lib card.ts 协议）：
 *   - 会话：roamCardPolicy（callback 直接访问，不包 WebVPN）+ getUserInfoFromToken 校验
 *   - 加密响应：AES-128-ECB(PKCS7)，key = data 前 16 字符（CryptoUtils.aesEcbDecryptBase64）
 *   - 兜底：withSessionRecovery 两层恢复 + 登录态快照校验（对齐原项目 withCardRetry）
 * 充值链（支付宝 deep link）不迁移。
 */
import { HttpClient, HttpResponse, JsonBodyValue } from '../HttpClient';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { CampusCredentials } from '../../domain/AuthTypes';
import { aesEcbDecryptBase64 } from '../../utils/CryptoUtils';
import { Log } from '../../utils/Logger';

const CARD_USER_BY_TOKEN_URL: string = 'https://card.tsinghua.edu.cn/login/getUserInfoFromToken';
const CARD_INFO_BY_USER_URL: string = 'https://card.tsinghua.edu.cn/business/getCardUserinfo';
const CARD_TRANSACTION_URL: string = 'https://card.tsinghua.edu.cn/business/querySelfTradeList';
const CARD_LOGIN_PAYLOAD: string = 'eea30cbedcaf97c69d28b2d92f22a259/0?/userindex';

/** 入账关键词（对齐原项目 normalizeCampusCardTransactionAmount 的正则） */
const CARD_INCOME_RE: RegExp = /充值|圈存|补助|补贴|退款|退费|转入|入账|收入|发放/;

export class CampusCardInfo {
  userId: string = '';
  userName: string = '';
  departmentName: string = '';
  balance: number = 0;
  cardId: string = '';
  cardStatus: string = '';
  lastTransactionTimestamp: string = '';
  maxDailyTransactionAmount: number = 0;
  maxOneTimeTransactionAmount: number = 0;
}

export class CampusCardTransaction {
  id: string = '';
  summary: string = '';
  timestamp: string = '';
  balance: number = 0;
  amount: number = 0;
  address: string = '';
  name: string = '';
  txName: string = '';
}

/** Object → Record（非对象返回空表，调用方各自兜底，对齐原项目 ?? {} 语义） */
function asRecord(value: Object | undefined): Record<string, Object> {
  if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, Object>;
  }
  const empty: Record<string, Object> = {};
  return empty;
}

/** Object → 对象数组（非数组返回空数组） */
function asObjectArray(value: Object | undefined): Record<string, Object>[] {
  if (value !== undefined && value !== null && Array.isArray(value)) {
    return value as Record<string, Object>[];
  }
  const empty: Record<string, Object>[] = [];
  return empty;
}

/** 对齐原项目 parseDate：空→''；非法日期→原样字符串；合法→ISO 串 */
function parseCardDate(value: Object | undefined): string {
  if (value === undefined || value === null) {
    return '';
  }
  const text: string = String(value);
  if (text.length === 0) {
    return '';
  }
  const d: Date = new Date(text);
  if (Number.isNaN(d.getTime())) {
    return text;
  }
  return d.toISOString();
}

/** 金额（分→元）+ 正负号推断（对齐原项目 normalizeCampusCardTransactionAmount） */
function normalizeTransactionAmount(item: Record<string, Object>): number {
  const txamt: Object | undefined = item['txamt'];
  const raw: number = (txamt === undefined || txamt === null ? 0 : Number(txamt) || 0) / 100;
  if (!Number.isFinite(raw) || raw === 0) {
    return 0;
  }
  if (raw < 0) {
    return raw;
  }
  const tradetype: Object | undefined = item['tradetype'];
  const type: number = tradetype === undefined || tradetype === null ? 0 : Number(tradetype) || 0;
  if (type === 2 || type === 3) {
    return raw;
  }
  if (type === 1) {
    return -raw;
  }
  const parts: string[] = [];
  const summary: Object | undefined = item['summary'];
  if (summary !== undefined && summary !== null) {
    parts.push(String(summary));
  }
  const mername: Object | undefined = item['mername'];
  if (mername !== undefined && mername !== null) {
    parts.push(String(mername));
  }
  const meraddr: Object | undefined = item['meraddr'];
  if (meraddr !== undefined && meraddr !== null) {
    parts.push(String(meraddr));
  }
  const txname: Object | undefined = item['txname'];
  if (txname !== undefined && txname !== null) {
    parts.push(String(txname));
  }
  return CARD_INCOME_RE.test(parts.join(' ')) ? raw : -raw;
}

export class CampusCardService {
  private http: HttpClient;
  private auth: TsinghuaAuthService;
  /** 卡系统会话标识（对齐原项目 accountBaseInfo） */
  private accountUser: string = '';
  private accountCardId: string = '';

  constructor(http: HttpClient, auth: TsinghuaAuthService) {
    this.http = http;
    this.auth = auth;
  }

  /**
   * 卡系统 JSON API（对齐原项目 cardFetchParsed）：
   * 无 body → GET，有 body → POST JSON。响应解析：
   *   - success===true → resultData
   *   - data 为 >16 字符的字符串 → AES-ECB 解密（key=data 前 16 字符）→ decoded.success===true → resultData
   *   - resultData 存在且无 success 字段 → resultData
   *   - 否则抛 message
   */
  private async cardFetchParsed(url: string, jsonBody?: Record<string, JsonBodyValue>): Promise<Object> {
    const resp: HttpResponse = jsonBody === undefined
      ? await this.http.get(url)
      : await this.http.postJson(url, jsonBody);
    const text: string = resp.body;
    Log.i('CampusCard', 'CARD_FETCH %{public}s code=%{public}d len=%{public}d',
      url, resp.statusCode, text.length);
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      throw new Error('校园卡接口响应非 JSON: ' + text.substring(0, 80));
    }
    const successVal: Object | undefined = parsed['success'];
    if (successVal === true) {
      return this.takeResultData(parsed);
    }
    const dataVal: Object | undefined = parsed['data'];
    if (typeof dataVal === 'string' && (dataVal as string).length > 16) {
      const encrypted: string = dataVal as string;
      const key: string = encrypted.substring(0, 16);
      let decodedText: string = '';
      try {
        decodedText = aesEcbDecryptBase64(encrypted.substring(16), key);
      } catch (e) {
        throw new Error('校园卡加密响应解密失败');
      }
      let decoded: Record<string, Object>;
      try {
        decoded = JSON.parse(decodedText) as Record<string, Object>;
      } catch (e) {
        throw new Error('校园卡加密响应解密失败');
      }
      if (decoded['success'] === true) {
        return this.takeResultData(decoded);
      }
      throw new Error(this.errorMessage(decoded));
    }
    if (successVal === undefined && parsed['resultData'] !== undefined) {
      return parsed['resultData'] as Object;
    }
    throw new Error(this.errorMessage(parsed));
  }

  /** success===true 时取 resultData；缺失返回空对象（对齐原项目 ?? 语义） */
  private takeResultData(container: Record<string, Object>): Object {
    const resultVal: Object | undefined = container['resultData'];
    if (resultVal === undefined || resultVal === null) {
      const empty: Record<string, Object> = {};
      return empty;
    }
    return resultVal;
  }

  private errorMessage(container: Record<string, Object>): string {
    const msg: Object | undefined = container['message'];
    if (msg !== undefined && msg !== null && String(msg).length > 0) {
      return String(msg);
    }
    return '校园卡接口返回失败';
  }

  /** 建立卡系统会话（roamCardPolicy + getUserInfoFromToken 校验）；force=true 强制重漫游 */
  private async ensureCampusCardLogin(force: boolean): Promise<void> {
    if (this.accountUser.length > 0 && !force) {
      return;
    }
    if (this.accountUser.length > 0 || this.accountCardId.length > 0) {
      this.accountUser = '';
      this.accountCardId = '';
    }
    const creds: CampusCredentials = await this.auth.getRoamCredentials();
    Log.i('CampusCard', 'CARD_LOGIN roam start');
    await this.auth.roamCardPolicy(creds, CARD_LOGIN_PAYLOAD);
    const userObj: Object = await this.cardFetchParsed(CARD_USER_BY_TOKEN_URL);
    const loginuser: string = String(asRecord(userObj)['loginuser'] ?? '');
    if (loginuser.length === 0) {
      throw new Error('校园卡登录后未获取到用户标识');
    }
    this.accountUser = loginuser;
    this.accountCardId = '';
    Log.i('CampusCard', 'CARD_LOGIN ok');
  }

  /** 会话探测：getUserInfoFromToken 与缓存一致则复用；否则强制重登录（对齐 assureCampusCardSession） */
  private async assureCampusCardSession(): Promise<void> {
    try {
      const userObj: Object = await this.cardFetchParsed(CARD_USER_BY_TOKEN_URL);
      const loginuser: string = String(asRecord(userObj)['loginuser'] ?? '');
      if (loginuser.length > 0 && loginuser === this.accountUser) {
        return;
      }
    } catch (e) {
      // 探测失败 → 走强制重登录
    }
    await this.ensureCampusCardLogin(true);
  }

  /**
   * 两层兜底（对齐原项目 withCardRetry）：
   * ensure + 探测 + 快照校验包在 withSessionRecovery 内；reroam 阶段强制重登录卡系统。
   */
  private async withCardRetry<T>(operation: () => Promise<T>): Promise<T> {
    return this.auth.withSessionRecovery<T>(async (): Promise<T> => {
      await this.ensureCampusCardLogin(false);
      await this.assureCampusCardSession();
      const snapUser: string = this.accountUser;
      const snapCardId: string = this.accountCardId;
      const result: T = await operation();
      if (this.accountUser !== snapUser || this.accountCardId !== snapCardId) {
        throw new Error('校园卡登录态在请求期间被并发修改');
      }
      return result;
    }, async (): Promise<void> => {
      this.accountUser = '';
      this.accountCardId = '';
      await this.ensureCampusCardLogin(true);
    }, 'campus-card');
  }

  /** 校园卡信息（余额/卡号/限额；同时缓存 accountCardId） */
  async getCampusCardInfo(): Promise<CampusCardInfo> {
    return this.withCardRetry<CampusCardInfo>(async (): Promise<CampusCardInfo> => {
      const body: Record<string, JsonBodyValue> = {};
      body['idserial'] = this.accountUser;
      const rawObj: Object = await this.cardFetchParsed(CARD_INFO_BY_USER_URL, body);
      const raw: Record<string, Object> = asRecord(rawObj);
      const cards: Record<string, Object>[] = asObjectArray(raw['cardInfos']);
      const firstCard: Record<string, Object> = cards.length > 0 ? cards[0] : asRecord(undefined);

      const info: CampusCardInfo = new CampusCardInfo();
      info.userId = String(raw['idserial'] ?? '');
      info.userName = String(raw['username'] ?? '');
      info.departmentName = String(raw['departname'] ?? '');
      info.balance = Number(asRecord(raw['baseAccount'])['balance'] ?? 0) / 100;
      info.cardId = String(firstCard['cardid'] ?? '');
      info.cardStatus = String(firstCard['accstatus'] ?? '');
      info.lastTransactionTimestamp = parseCardDate(firstCard['lasttxdate']);
      info.maxDailyTransactionAmount = Number(firstCard['maxconstolamt'] ?? 0) / 100;
      info.maxOneTimeTransactionAmount = Number(firstCard['maxconsamt'] ?? 0) / 100;
      this.accountCardId = info.cardId;
      Log.i('CampusCard', 'CARD_INFO balance=%{public}f cards=%{public}d', info.balance, cards.length);
      return info;
    });
  }

  /** 流水（start/end 为 'YYYY-MM-DD'；type: -1 全部 / 1 消费 / 2 充值 / 3 补助） */
  async getCampusCardTransactions(start: string, end: string, type: number): Promise<CampusCardTransaction[]> {
    return this.withCardRetry<CampusCardTransaction[]>(async (): Promise<CampusCardTransaction[]> => {
      const body: Record<string, JsonBodyValue> = {};
      body['idserial'] = this.accountUser;
      body['starttime'] = start;
      body['endtime'] = end;
      body['tradetype'] = type;
      body['pageSize'] = 100;
      body['pageNumber'] = 0;
      const rawObj: Object = await this.cardFetchParsed(CARD_TRANSACTION_URL, body);
      const rows: Record<string, Object>[] = asObjectArray(asRecord(rawObj)['rows']);
      const list: CampusCardTransaction[] = [];
      for (let i: number = 0; i < rows.length; i++) {
        const item: Record<string, Object> = rows[i];
        const tx: CampusCardTransaction = new CampusCardTransaction();
        tx.id = String(item['id'] ?? '');
        tx.summary = String(item['summary'] ?? '');
        tx.timestamp = parseCardDate(item['txdate']);
        tx.balance = Number(item['balance'] ?? 0) / 100;
        tx.amount = normalizeTransactionAmount(item);
        tx.address = String(item['meraddr'] ?? '');
        const mername: Object | undefined = item['mername'];
        tx.name = mername !== undefined && mername !== null ? String(mername) : '';
        tx.txName = String(item['txname'] ?? '');
        list.push(tx);
      }
      Log.i('CampusCard', 'CARD_TX rows=%{public}d', list.length);
      return list;
    });
  }
}
