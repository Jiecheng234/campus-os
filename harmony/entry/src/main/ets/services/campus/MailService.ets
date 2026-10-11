/**
 * ============================================================================
 * MailService — 清华邮箱（Coremail 读写）服务
 * ============================================================================
 *
 * 对齐原项目 src/services/campus/mail.ts：
 *   - 会话（ensureMailSession）：①信息门户漫游（roamByYyfwidHtml）建立门户会话；
 *     ②对"邮箱门户地址 / Coremail 入口地址"依次 resolveFinalUrl 取最终地址并解析
 *     sid（URL 参数优先，落地页正文与 Cookie 兜底）；③再取一次完成落地；
 *     ④内存缓存约 20 分钟；⑤失败抛可读中文错误。
 *   - 自愈：接口返回会话失效类错误码（FA_INVALID_SESSION / FA_SECURITY）时清缓存
 *     强制重建一次后重试；业务错误（result=error / FA_* 码）转可读中文错误。
 *   - 接口：JSON POST（func 查询参数 + JSON 体，复用 HttpClient.postJsonRaw）与
 *     urlencoded POST（复用 postFormWithHeaders）。
 *   - 列表多形态回退：线程/扁平 × 排序字段（date/receivedDate），全空再试兼容
 *     XML 接口（RPC + {var: xml}）；"总数 > 0 但解析 0 条"抛可读错误。
 *   - 解析容错：递归寻找邮件数组/总数、逐条失败跳过、联系人兼容字符串/对象/数组。
 *   - 写操作：标记已读 / 删除 / 移动（mbox:updateMessageInfos / mbox:deleteMessages）
 *     与发送（compose 初始化 + mbox:compose）。
 *
 * 常量来源（只读参考，勿臆造）：原项目 src/services/webvpn/constants.ts
 * （INFO_PORTAL_YYFWID / SUBSYSTEM_YYFWID.mail）与
 * src/services/campus/campusEndpoints.ts（MAIL_PORTAL_URL 组成）。
 * ============================================================================
 */
import { HttpClient, HttpResponse } from '../HttpClient';
import { CampusDataService } from './CampusDataService';
import { TsinghuaAuthService } from '../auth/TsinghuaAuthService';
import { Log } from '../../utils/Logger';
import { webview } from '@kit.ArkWeb';

// ============================================================
// 端点与 func 常量（对齐原项目 mail.ts / campusEndpoints.ts / constants.ts）
// ============================================================

const COREMAIL_BASE_URL: string = 'https://mails.tsinghua.edu.cn';
const COREMAIL_INDEX_URL: string = COREMAIL_BASE_URL + '/coremail/XT/index.jsp';
/** 信息门户子系统 yyfwid（建立 info 门户后端会话，原项目 INFO_PORTAL_YYFWID） */
const INFO_PORTAL_YYFWID: string = '10000ea055dd8d81d09d5a1ba55d39ad';
/** 清华邮箱 yyfwid（信息门户"清华邮箱"入口，原项目 SUBSYSTEM_YYFWID.mail） */
const MAIL_YYFWID: string = 'F315577F5BF20E1B1668EDD594B2C04F';
/** info 门户 webvpn token（原项目 INFO_TOKEN） */
const INFO_TOKEN: string = '77726476706e69737468656265737421f9f9479369247b59700f81b9991b2631506205de';
/** 邮箱门户地址（webvpn info 门户 roamingToApp，原项目 MAIL_PORTAL_URL） */
const MAIL_PORTAL_URL: string = 'https://webvpn.tsinghua.edu.cn/https/' + INFO_TOKEN
  + '/f/info/portal_fg/common/roamingToApp?yyfwid=' + MAIL_YYFWID;

/** 会话缓存时长（约 20 分钟） */
const MAIL_SESSION_TTL_MS: number = 20 * 60 * 1000;

// ── Coremail func 名 ──
const FUNC_LIST_THREADS: string = 'mbox:listThreads';
const FUNC_LIST_MESSAGES: string = 'mbox:listMessages';
const FUNC_SEARCH: string = 'mail:searchMessages';
const FUNC_READ: string = 'readMessage';
const FUNC_COMPOSE_INIT: string = 'compose';
const FUNC_UPDATE_INFOS: string = 'mbox:updateMessageInfos';
const FUNC_DELETE: string = 'mbox:deleteMessages';
const FUNC_COMPOSE: string = 'mbox:compose';

/** Coremail POST 公共请求头（对齐参考 coremailXhrText 的 XHR 装配） */
const COREMAIL_JSON_HEADERS: Record<string, string> = {
  'X-Requested-With': 'XMLHttpRequest',
  'Accept': 'text/x-json, application/json, */*'
};

// ============================================================
// 数据模型（全字段非可选默认值）
// ============================================================

export class MailFolder {
  id: number = 0;
  name: string = '';
  system: string = '';
}

export class MailContact {
  name: string = '';
  address: string = '';
}

export class MailAttachment {
  id: string = '';
  name: string = '';
  size: number = 0;
}

export class MailMessageSummary {
  id: string = '';
  fid: number = 0;
  from: MailContact[] = [];
  to: MailContact[] = [];
  subject: string = '';
  date: string = '';
  unread: boolean = false;
  flagged: boolean = false;
  hasAttachment: boolean = false;
  brief: string = '';
}

export class MailMessageDetail extends MailMessageSummary {
  cc: MailContact[] = [];
  contentText: string = '';
  contentHtml: string = '';
  attachments: MailAttachment[] = [];

  loadSummary(summary: MailMessageSummary): void {
    this.id = summary.id;
    this.fid = summary.fid;
    this.from = summary.from;
    this.to = summary.to;
    this.subject = summary.subject;
    this.date = summary.date;
    this.unread = summary.unread;
    this.flagged = summary.flagged;
    this.hasAttachment = summary.hasAttachment;
    this.brief = summary.brief;
  }
}

export class MailListResult {
  messages: MailMessageSummary[] = [];
  total: number = 0;
}

export class ComposeDraft {
  to: string = '';
  cc: string = '';
  bcc: string = '';
  subject: string = '';
  content: string = '';
}

/** 5 个系统文件夹（收件箱/草稿箱/已发送/已删除/垃圾邮件） */
function buildMailFolders(): MailFolder[] {
  const defs: string[][] = [
    ['1', '收件箱', 'inbox'],
    ['2', '草稿箱', 'drafts'],
    ['3', '已发送', 'sent'],
    ['4', '已删除', 'deleted'],
    ['5', '垃圾邮件', 'junk'],
  ];
  const list: MailFolder[] = [];
  for (let i: number = 0; i < defs.length; i++) {
    const f: MailFolder = new MailFolder();
    f.id = Number(defs[i][0]);
    f.name = defs[i][1];
    f.system = defs[i][2];
    list.push(f);
  }
  return list;
}

export const MAIL_FOLDERS: MailFolder[] = buildMailFolders();

/** 按 fid 取文件夹名（未命中返回空串） */
export function mailFolderName(fid: number): string {
  for (let i: number = 0; i < MAIL_FOLDERS.length; i++) {
    if (MAIL_FOLDERS[i].id === fid) {
      return MAIL_FOLDERS[i].name;
    }
  }
  return '';
}

// ============================================================
// 容错解析辅助（模块级，对齐参考 parseContacts/findMessageArrays/findTotal 等）
// ============================================================

/** Object → Record（非对象/数组返回空表，调用方各自兜底） */
function asRecord(value: Object | undefined): Record<string, Object> {
  if (value !== undefined && value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, Object>;
  }
  const empty: Record<string, Object> = {};
  return empty;
}

/** 任意值 → 数组元素列表（非数组返回空数组；元素类型由调用方判别） */
function asArrayItems(value: Object | undefined): Object[] {
  if (value !== undefined && value !== null && Array.isArray(value)) {
    return value as Object[];
  }
  const empty: Object[] = [];
  return empty;
}

/** 首个非空值（跳过 undefined/null/''，对齐参考 coalesce） */
function firstNonEmpty(values: (Object | undefined)[]): Object | undefined {
  for (let i: number = 0; i < values.length; i++) {
    const v: Object | undefined = values[i];
    if (v !== undefined && v !== null && v !== '') {
      return v;
    }
  }
  return undefined;
}

/** 首个非空值 → 字符串（全空返回 ''） */
function strCoalesce(values: (Object | undefined)[]): string {
  const v: Object | undefined = firstNonEmpty(values);
  return v !== undefined ? String(v) : '';
}

/** 首个非空值 → 数字（全空/非法返回 0） */
function numCoalesce(values: (Object | undefined)[]): number {
  const v: Object | undefined = firstNonEmpty(values);
  if (v === undefined) {
    return 0;
  }
  const n: number = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/** JS 真值语义近似（boolean/number/string/对象） */
function isTruthy(value: Object | undefined): boolean {
  if (value === undefined || value === null || value === false) {
    return false;
  }
  if (value === true) {
    return true;
  }
  if (typeof value === 'number') {
    return Number(value) !== 0;
  }
  if (typeof value === 'string') {
    return String(value).length > 0;
  }
  return true;
}

/** HTML → 纯文本（去标签 + 基本实体解码 + 压缩空行，摘要/纯文本正文用） */
function stripHtml(html: string): string {
  let s: string = html;
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n');
  s = s.replace(/<li>/gi, '· ');
  s = s.replace(/<style[\s\S]*?<\/style>/gi, '');
  s = s.replace(/<[^>]+>/g, '');
  s = s.replace(/&nbsp;/gi, ' ');
  s = s.replace(/&lt;/g, '<');
  s = s.replace(/&gt;/g, '>');
  s = s.replace(/&quot;/g, '"');
  s = s.replace(/&#39;/g, '\'');
  s = s.replace(/&amp;/g, '&');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s.trim();
}

/** 联系人三形态解析：字符串（"名字<地址>"）/ 对象 / 数组 */
function parseContacts(value: Object | undefined): MailContact[] {
  const result: MailContact[] = [];
  if (value === undefined || value === null) {
    return result;
  }
  const list: Object[] = Array.isArray(value) ? (value as Object[]) : [value];
  for (let i: number = 0; i < list.length; i++) {
    const entry: Object = list[i];
    if (entry === undefined || entry === null) {
      continue;
    }
    if (typeof entry === 'string') {
      const raw: string = String(entry);
      const m: RegExpExecArray | null = /(.*)<(.+?)>/.exec(raw);
      const c: MailContact = new MailContact();
      c.name = m !== null ? m[1].replace(/["']/g, '').trim() : '';
      c.address = m !== null ? m[2].trim() : raw.trim();
      if (c.name.length > 0 || c.address.length > 0) {
        result.push(c);
      }
      continue;
    }
    if (typeof entry === 'object') {
      const obj: Record<string, Object> = asRecord(entry);
      const c: MailContact = new MailContact();
      c.name = strCoalesce([obj['name'], obj['personal'], obj['nickName'], obj['trueName']]);
      c.address = strCoalesce([obj['email'], obj['address'], obj['addr']]);
      if (c.name.length > 0 || c.address.length > 0) {
        result.push(c);
      }
    }
  }
  return result;
}

/** 邮件 id 提取（线程/扁平多形态字段兜底，parseMessage 与 looksLikeMessage 共用） */
function extractMessageId(item: Record<string, Object>, attr: Record<string, Object>,
  envelope: Record<string, Object>): string {
  const midList: Object[] = asArrayItems(item['midList']);
  const nestedMsgs: Object[] = asArrayItems(item['messages']);
  let nestedId: Object | undefined = undefined;
  if (nestedMsgs.length > 0) {
    const nm: Record<string, Object> = asRecord(nestedMsgs[0]);
    nestedId = firstNonEmpty([nm['id'], nm['mid']]);
  }
  return strCoalesce([
    item['id'], item['mid'], item['uid'], item['msgid'], item['mailId'], item['messageId'],
    midList.length > 0 ? midList[0] : undefined,
    nestedId,
    attr['id'], attr['mid'], envelope['id'], envelope['mid'],
  ]);
}

/** 单条邮件摘要解析（字段漂移时逐字段兜底，失败字段留默认值） */
function parseMessage(raw: Object): MailMessageSummary {
  const item: Record<string, Object> = asRecord(raw);
  const attr: Record<string, Object> = asRecord(
    firstNonEmpty([item['attr'], item['attrs'], item['attributes']]));
  const envelope: Record<string, Object> = asRecord(
    firstNonEmpty([item['envelope'], item['mail'], item['message']]));
  const flags: Record<string, Object> = asRecord(item['flags']);
  const m: MailMessageSummary = new MailMessageSummary();
  m.id = extractMessageId(item, attr, envelope);
  const subjectRaw: string = strCoalesce([item['subject'], attr['subject'], envelope['subject']]).trim();
  m.subject = subjectRaw.length > 0 ? subjectRaw : '(无主题)';
  const contentRaw: string = strCoalesce([
    item['summary'], item['brief'], item['content'], item['abstract'],
    attr['summary'], envelope['summary'], envelope['brief'],
  ]);
  const attachments: Object[] = asArrayItems(
    firstNonEmpty([item['attachments'], item['attachInfos'], attr['attachments'], envelope['attachments']]));
  m.fid = numCoalesce([item['fid'], attr['fid'], envelope['fid']]);
  m.from = parseContacts(firstNonEmpty([item['from'], item['sender'], attr['from'], attr['sender'], envelope['from']]));
  m.to = parseContacts(firstNonEmpty([item['to'], attr['to'], envelope['to']]));
  m.date = strCoalesce([
    item['date'], item['sentDate'], item['receivedDate'], item['lastModifiedDate'],
    item['firstDate'], item['lastDate'], item['time'], item['createTime'],
    attr['date'], attr['sentDate'], attr['receivedDate'], envelope['date'], envelope['receivedDate'],
  ]);
  const flagKeys: string[] = Object.keys(flags);
  m.unread = flags['read'] === false || item['read'] === false
    || attr['read'] === false || item['isRead'] === false
    || (flags['read'] === undefined && flagKeys.length > 0);
  m.flagged = isTruthy(firstNonEmpty([flags['flagged'], item['flagged'], item['label0']]));
  const attachFlag: Object | undefined = firstNonEmpty([
    item['attached'], item['hasAttachment'], item['attach'],
    attr['attached'], attr['hasAttachment'], envelope['hasAttachment'],
  ]);
  m.hasAttachment = attachFlag !== undefined ? isTruthy(attachFlag) : attachments.length > 0;
  m.brief = stripHtml(contentRaw);
  return m;
}

/** 数组元素是否"像一封邮件"（有 id/subject/发件人任一） */
function looksLikeMessage(value: Object): boolean {
  if (Array.isArray(value)) {
    return false;
  }
  const item: Record<string, Object> = asRecord(value);
  const attr: Record<string, Object> = asRecord(
    firstNonEmpty([item['attr'], item['attrs'], item['attributes']]));
  const emptyEnv: Record<string, Object> = {};
  if (extractMessageId(item, attr, emptyEnv).length > 0) {
    return true;
  }
  if (strCoalesce([item['subject'], attr['subject']]).length > 0) {
    return true;
  }
  return firstNonEmpty([item['from'], item['sender'], attr['from'], attr['sender']]) !== undefined;
}

/** 递归寻找"邮件数组"（深度 ≤ 6，只要包含 looksLikeMessage 元素即入选） */
function findMessageArrays(value: Object | undefined, depth: number): Object[][] {
  const results: Object[][] = [];
  if (depth > 6 || value === undefined || value === null) {
    return results;
  }
  if (Array.isArray(value)) {
    const arr: Object[] = value as Object[];
    const objectItems: Object[] = [];
    for (let i: number = 0; i < arr.length; i++) {
      const it: Object = arr[i];
      if (it !== undefined && it !== null && typeof it === 'object') {
        objectItems.push(it);
      }
    }
    let some: boolean = false;
    for (let i: number = 0; i < objectItems.length; i++) {
      if (looksLikeMessage(objectItems[i])) {
        some = true;
        break;
      }
    }
    if (objectItems.length > 0 && some) {
      results.push(objectItems);
    }
    for (let i: number = 0; i < arr.length; i++) {
      const nested: Object[][] = findMessageArrays(arr[i], depth + 1);
      for (let j: number = 0; j < nested.length; j++) {
        results.push(nested[j]);
      }
    }
    return results;
  }
  if (typeof value === 'object') {
    const rec: Record<string, Object> = value as Record<string, Object>;
    const keys: string[] = Object.keys(rec);
    for (let i: number = 0; i < keys.length; i++) {
      const nested: Object[][] = findMessageArrays(rec[keys[i]], depth + 1);
      for (let j: number = 0; j < nested.length; j++) {
        results.push(nested[j]);
      }
    }
  }
  return results;
}

/** 常见"总数"字段 → 数字（未命中返回 -1） */
function firstNumberFromKeys(rec: Record<string, Object>): number {
  const keys: string[] = ['total', 'totalCount', 'count', 'messageCount', 'msgCount', 'allCount'];
  for (let i: number = 0; i < keys.length; i++) {
    const raw: Object | undefined = rec[keys[i]];
    if (raw !== undefined && raw !== null && String(raw).length > 0) {
      const n: number = Number(raw);
      if (!Number.isNaN(n)) {
        return n;
      }
    }
  }
  return -1;
}

/** 递归寻找总数（深度 ≤ 5；未找到返回 -1） */
function findTotal(value: Object | undefined, depth: number): number {
  if (depth > 5 || value === undefined || value === null || typeof value !== 'object') {
    return -1;
  }
  if (Array.isArray(value)) {
    const arr: Object[] = value as Object[];
    for (let i: number = 0; i < arr.length; i++) {
      const nested: number = findTotal(arr[i], depth + 1);
      if (nested >= 0) {
        return nested;
      }
    }
    return -1;
  }
  const rec: Record<string, Object> = value as Record<string, Object>;
  const direct: number = firstNumberFromKeys(rec);
  if (direct >= 0) {
    return direct;
  }
  const keys: string[] = Object.keys(rec);
  for (let i: number = 0; i < keys.length; i++) {
    const nested: number = findTotal(rec[keys[i]], depth + 1);
    if (nested >= 0) {
      return nested;
    }
  }
  return -1;
}

/** 解析后的原始列表（messages 原始行 + 总数） */
class RawList {
  messages: Object[] = [];
  total: number = 0;
}

/** 取 var/object/data 载荷（对齐参考 pickPayload） */
function pickPayload(parsed: Record<string, Object>): Object {
  if (parsed['var'] !== undefined) {
    return parsed['var'];
  }
  if (parsed['object'] !== undefined) {
    return parsed['object'];
  }
  if (parsed['data'] !== undefined) {
    return parsed['data'];
  }
  return parsed;
}

/** 多形态消息列表解包（扁平数组 / 命名数组 / 递归寻找） */
function unwrapMessageList(parsed: Record<string, Object>): RawList {
  const payload: Object = pickPayload(parsed);
  const result: RawList = new RawList();
  if (Array.isArray(payload)) {
    const arr: Object[] = payload as Object[];
    let msgs: Object[] = [];
    for (let i: number = 0; i < arr.length; i++) {
      if (Array.isArray(arr[i])) {
        msgs = arr[i] as Object[];
        break;
      }
    }
    let num: number = -1;
    for (let i: number = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'number') {
        num = Number(arr[i]);
        break;
      }
    }
    if (msgs.length === 0) {
      // 实测形态：var 直接是扁平邮件数组 var:[{id,subject,from,...},...]
      const flat: Object[] = [];
      for (let i: number = 0; i < arr.length; i++) {
        const it: Object = arr[i];
        if (it !== undefined && it !== null && typeof it === 'object'
          && !Array.isArray(it) && looksLikeMessage(it)) {
          flat.push(it);
        }
      }
      msgs = flat;
    }
    result.messages = msgs;
    if (num >= 0) {
      result.total = num;
    } else {
      const topTotal: number = firstNumberFromKeys(parsed);
      result.total = topTotal >= 0 ? topTotal : msgs.length;
    }
    return result;
  }
  const obj: Record<string, Object> = asRecord(payload);
  const namedKeys: string[] = ['messages', 'list', 'msgs', 'mails', 'items', 'rows'];
  let found: boolean = false;
  for (let i: number = 0; i < namedKeys.length; i++) {
    const v: Object | undefined = obj[namedKeys[i]];
    if (v !== undefined && v !== null && Array.isArray(v)) {
      result.messages = v as Object[];
      found = true;
      break;
    }
  }
  if (!found) {
    const arrays: Object[][] = findMessageArrays(payload, 0);
    let best: Object[] = [];
    for (let i: number = 0; i < arrays.length; i++) {
      if (arrays[i].length > best.length) {
        best = arrays[i];
      }
    }
    result.messages = best;
  }
  const totalFound: number = findTotal(payload, 0);
  result.total = totalFound >= 0 ? totalFound : result.messages.length;
  return result;
}

/** 逐条解析并过滤无 id 条目（单条失败跳过，不影响其余） */
function parseMessageList(rawMessages: Object[]): MailMessageSummary[] {
  const result: MailMessageSummary[] = [];
  for (let i: number = 0; i < rawMessages.length; i++) {
    try {
      const m: MailMessageSummary = parseMessage(rawMessages[i]);
      if (m.id.length > 0) {
        result.push(m);
      }
    } catch (e) {
      Log.i('CampusMail', 'PARSE_MSG skip one: %{public}s',
        e instanceof Error ? e.message : String(e));
    }
  }
  return result;
}

/** Coremail 业务错误 → 可读中文（messages 摘要拼接，对齐参考 coremailErrorMessage） */
function coremailErrorMessage(parsed: Record<string, Object>): string {
  const summaries: string[] = [];
  const rows: Object[] = asArrayItems(parsed['messages']);
  for (let i: number = 0; i < rows.length; i++) {
    const row: Record<string, Object> = asRecord(rows[i]);
    const summary: string = strCoalesce([row['summary']]);
    if (summary.length > 0) {
      summaries.push(summary);
    }
  }
  const joined: string = summaries.join('；');
  const code: string = strCoalesce([parsed['code']]);
  if (code === 'FA_SECURITY') {
    return '邮箱接口安全校验失败' + (joined.length > 0 ? '：' + joined : '');
  }
  const candidates: string[] = [
    strCoalesce([parsed['errorMsg']]),
    strCoalesce([parsed['message']]),
    joined,
    code,
  ];
  for (let i: number = 0; i < candidates.length; i++) {
    if (candidates[i].length > 0) {
      return candidates[i];
    }
  }
  return '邮箱接口失败';
}

/** sid 提取：URL 参数优先 → 分号/空白分隔形态 → 引号包裹的 JSON 形态 */
function extractSid(text: string): string {
  const normalized: string = text.replace(/&amp;/g, '&');
  const m1: RegExpExecArray | null = /[?&]sid=([^&#"'<>\s]+)/i.exec(normalized);
  if (m1 !== null) {
    return safeDecode(m1[1]);
  }
  const m2: RegExpExecArray | null = /(?:^|[;\s])sid=([^;&#"'<>\s]+)/i.exec(normalized);
  if (m2 !== null) {
    return safeDecode(m2[1]);
  }
  const m3: RegExpExecArray | null = /["']sid["']\s*[:=]\s*["']([^"']+)/i.exec(normalized);
  if (m3 !== null) {
    return safeDecode(m3[1]);
  }
  return '';
}

function safeDecode(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch (e) {
    return value;
  }
}

/** 最终地址 → Coremail baseUrl（截到 /coremail/ 之前；无标记回退源站） */
function buildBaseUrl(finalUrl: string): string {
  const idx: number = finalUrl.indexOf('/coremail/');
  if (idx >= 0) {
    return finalUrl.substring(0, idx);
  }
  const proto: number = finalUrl.indexOf('://');
  if (proto > 0) {
    const afterProto: string = finalUrl.substring(proto + 3);
    const slash: number = afterProto.indexOf('/');
    if (slash > 0) {
      return finalUrl.substring(0, proto + 3 + slash);
    }
    return finalUrl;
  }
  return COREMAIL_BASE_URL;
}

// ============================================================
// Coremail 会话与请求体构造
// ============================================================

class CoremailSession {
  sid: string = '';
  baseUrl: string = '';
  finalUrl: string = '';
  createdAt: number = 0;
}

/** 兼容 XML 列表请求体（对齐参考 listMessagesXml） */
function listMessagesXml(fid: number, start: number, limit: number): string {
  return '<?xml version="1.0"?><object><int name="fid">' + String(fid)
    + '</int><string name="order">date</string><boolean name="desc">true</boolean><int name="limit">'
    + String(limit) + '</int><int name="start">' + String(start)
    + '</int><boolean name="skipLockedFolders">false</boolean><boolean name="returnTag">true</boolean>'
    + '<boolean name="returnTotal">true</boolean><int name="summaryWindowSize">'
    + String(limit) + '</int><string name="mboxa"></string><boolean name="topFirst">true</boolean></object>';
}

/** JSON 列表请求体（对齐参考 listRequestBody） */
function listRequestBody(fid: number, start: number, limit: number, order: string): Record<string, Object> {
  const body: Record<string, Object> = {};
  body['start'] = start;
  body['limit'] = limit;
  body['mode'] = 'count';
  body['order'] = order;
  body['desc'] = true;
  body['returnTotal'] = true;
  body['returnTag'] = true;
  body['summaryWindowSize'] = limit;
  body['fid'] = fid;
  body['mboxa'] = '';
  body['topFirst'] = true;
  return body;
}

// ============================================================
// 服务
// ============================================================

export class MailService {
  private http: HttpClient;
  private campus: CampusDataService;
  private auth: TsinghuaAuthService;
  /** Coremail 会话缓存（sid + baseUrl，约 20 分钟） */
  private session: CoremailSession | undefined = undefined;

  constructor(http: HttpClient, campus: CampusDataService, auth: TsinghuaAuthService) {
    this.http = http;
    this.campus = campus;
    this.auth = auth;
  }

  /** 建立邮箱会话（缓存未过期且未强制时直接返回；供外部预热/手动刷新用） */
  async ensureMailSession(force?: boolean): Promise<void> {
    await this.obtainSession(force === true);
  }

  /** 取会话：缓存命中（未过期且未强制）直接返回，否则重建 */
  private async obtainSession(force: boolean): Promise<CoremailSession> {
    if (!force && this.session !== undefined
      && Date.now() - this.session.createdAt < MAIL_SESSION_TTL_MS) {
      return this.session;
    }
    // 未登录（无保存的凭证）→ 可读错误
    const hydrated: boolean = await this.auth.hydrateCredentials();
    if (!hydrated) {
      throw new Error('未登录，无法访问清华邮箱');
    }
    // ① 门户会话：信息门户漫游（失败返回空串，不阻断后续解析尝试）
    const portalHtml: string = await this.campus.roamByYyfwidHtml(INFO_PORTAL_YYFWID);
    if (portalHtml.length === 0) {
      Log.i('CampusMail', 'PORTAL_ROAM empty (continue to resolve)');
    }
    // ② 依次解析"邮箱门户地址 / Coremail 入口地址"
    const candidates: string[] = [MAIL_PORTAL_URL, COREMAIL_INDEX_URL];
    for (let i: number = 0; i < candidates.length; i++) {
      const resolved: CoremailSession | undefined = await this.tryResolveFromUrl(candidates[i]);
      if (resolved !== undefined) {
        // ③ 再取一次完成落地（刷新 Cookie / 跟随 Coremail 侧跳转）
        try {
          await this.http.resolveFinalUrl(resolved.finalUrl);
        } catch (e) {
          Log.i('CampusMail', 'LANDING extra fetch fail: %{public}s',
            e instanceof Error ? e.message : String(e));
        }
        resolved.createdAt = Date.now();
        this.session = resolved;
        Log.i('CampusMail', 'SESSION ok baseUrl=%{public}s sidLen=%{public}d',
          resolved.baseUrl, resolved.sid.length);
        return resolved;
      }
    }
    throw new Error('未能建立清华邮箱会话，请下拉重试；若持续失败请退出后重新登录');
  }

  /** 单入口解析：resolveFinalUrl 取最终地址 → sid（URL 参数优先 → 落地页正文 → Cookie 兜底） */
  private async tryResolveFromUrl(url: string): Promise<CoremailSession | undefined> {
    try {
      const finalUrl: string = await this.http.resolveFinalUrl(url);
      let sid: string = extractSid(finalUrl);
      if (sid.length === 0) {
        // 落地页正文兜底（script/跳转链接里可能带 sid）
        const resp: HttpResponse = await this.http.get(finalUrl);
        sid = extractSid(resp.body);
      }
      if (sid.length === 0) {
        sid = this.sidFromCookieJar();
      }
      if (sid.length === 0) {
        Log.i('CampusMail', 'RESOLVE no sid url=%{public}s', url.substring(0, 120));
        return undefined;
      }
      const s: CoremailSession = new CoremailSession();
      s.sid = sid;
      s.baseUrl = buildBaseUrl(finalUrl);
      const withSid: string = finalUrl.indexOf('sid=') >= 0
        ? finalUrl
        : finalUrl + (finalUrl.indexOf('?') >= 0 ? '&' : '?') + 'sid=' + encodeURIComponent(sid);
      s.finalUrl = withSid;
      Log.i('CampusMail', 'RESOLVE ok finalUrlLen=%{public}d sidLen=%{public}d',
        finalUrl.length, sid.length);
      return s;
    } catch (e) {
      Log.i('CampusMail', 'RESOLVE ex=%{public}s', e instanceof Error ? e.message : String(e));
      return undefined;
    }
  }

  /** Cookie 兜底：从 Cookie 池解析 sid（名为 sid 或值内含 sid=） */
  private sidFromCookieJar(): string {
    const urls: string[] = [
      COREMAIL_BASE_URL + '/',
      COREMAIL_BASE_URL + '/coremail/',
      COREMAIL_INDEX_URL,
      MAIL_PORTAL_URL,
    ];
    for (let i: number = 0; i < urls.length; i++) {
      const cookies: string = this.http.getCookieManager().getCookieHeader(urls[i]);
      if (cookies.length === 0) {
        continue;
      }
      const parts: string[] = cookies.split(';');
      for (let j: number = 0; j < parts.length; j++) {
        const kv: string = parts[j].trim();
        const eq: number = kv.indexOf('=');
        if (eq <= 0) {
          continue;
        }
        const name: string = kv.substring(0, eq).trim();
        const value: string = kv.substring(eq + 1).trim();
        const pairSid: string = extractSid(name + '=' + value);
        if (pairSid.length > 0) {
          return pairSid;
        }
        if (name.toLowerCase() === 'sid' && value.length > 0) {
          return value;
        }
      }
    }
    return '';
  }

  /** Coremail JSON 接口地址（/coremail/s/json?sid=..&func=..） */
  private jsonUrl(s: CoremailSession, func: string): string {
    return s.baseUrl + '/coremail/s/json?sid=' + encodeURIComponent(s.sid)
      + '&func=' + encodeURIComponent(func);
  }

  /** Coremail RPC 接口地址（/coremail/s?sid=..&func=..） */
  private rpcUrl(s: CoremailSession, func: string): string {
    return s.baseUrl + '/coremail/s?sid=' + encodeURIComponent(s.sid)
      + '&func=' + encodeURIComponent(func);
  }

  /** 统一响应处理：非 JSON → 可读错误；会话失效码 → 清缓存强制重建一次重试；业务错误 → 可读中文 */
  private async handleCoremailResponse(text: string, force: boolean,
    retry: () => Promise<Record<string, Object>>): Promise<Record<string, Object>> {
    let parsed: Record<string, Object>;
    try {
      parsed = JSON.parse(text) as Record<string, Object>;
    } catch (e) {
      throw new Error('邮箱接口响应非 JSON: ' + text.substring(0, 80));
    }
    const code: string = strCoalesce([parsed['code']]);
    if (!force && (code === 'FA_INVALID_SESSION' || code === 'FA_SECURITY')) {
      this.session = undefined;
      return retry();
    }
    if (strCoalesce([parsed['result']]) === 'error' || code.indexOf('FA_') === 0) {
      throw new Error(coremailErrorMessage(parsed));
    }
    return parsed;
  }

  /** JSON POST 调用包装（useRpcUrl=true 走 /coremail/s，否则 /coremail/s/json） */
  private async postCoremailJson(func: string, body: Record<string, Object>,
    force: boolean, useRpcUrl: boolean): Promise<Record<string, Object>> {
    const s: CoremailSession = await this.obtainSession(force);
    const url: string = useRpcUrl ? this.rpcUrl(s, func) : this.jsonUrl(s, func);
    const resp: HttpResponse = await this.http.postJsonRaw(url, JSON.stringify(body), COREMAIL_JSON_HEADERS);
    return this.handleCoremailResponse(resp.body, force,
      (): Promise<Record<string, Object>> => this.postCoremailJson(func, body, true, useRpcUrl));
  }

  /** urlencoded POST 调用包装（搜索/读信/写信初始化等） */
  private async formCall(func: string, form: Record<string, string>,
    force: boolean): Promise<Record<string, Object>> {
    const s: CoremailSession = await this.obtainSession(force);
    const url: string = this.rpcUrl(s, func);
    const resp: HttpResponse = await this.http.postFormWithHeaders(url, form, COREMAIL_JSON_HEADERS);
    return this.handleCoremailResponse(resp.body, force,
      (): Promise<Record<string, Object>> => this.formCall(func, form, true));
  }

  // ============================================================
  // 列表 / 搜索 / 详情
  // ============================================================

  /** 文件夹邮件列表（多形态回退：线程/扁平 × 排序 → 兼容 XML 接口） */
  async listMessages(fid: number, start: number, limit: number): Promise<MailListResult> {
    let rawMessages: Object[] = [];
    let total: number = 0;
    const attempts: string[][] = [
      [FUNC_LIST_THREADS, 'date'],
      [FUNC_LIST_THREADS, 'receivedDate'],
      [FUNC_LIST_MESSAGES, 'date'],
      [FUNC_LIST_MESSAGES, 'receivedDate'],
    ];
    for (let i: number = 0; i < attempts.length; i++) {
      try {
        const body: Record<string, Object> = listRequestBody(fid, start, limit, attempts[i][1]);
        const parsed: Record<string, Object> = await this.postCoremailJson(attempts[i][0], body, false, false);
        const unwrapped: RawList = unwrapMessageList(parsed);
        if (unwrapped.messages.length > 0 || unwrapped.total > 0) {
          rawMessages = unwrapped.messages;
          total = unwrapped.total;
          break;
        }
      } catch (e) {
        // 尝试下一种列表形态（Web 端在会话设置不同时返回线程/扁平不同结构）
        Log.i('CampusMail', 'LIST attempt fail func=%{public}s order=%{public}s: %{public}s',
          attempts[i][0], attempts[i][1], e instanceof Error ? e.message : String(e));
      }
    }
    if (rawMessages.length === 0 && total === 0) {
      try {
        const xmlBody: Record<string, Object> = {};
        xmlBody['var'] = listMessagesXml(fid, start, limit);
        const parsed: Record<string, Object> = await this.postCoremailJson(
          FUNC_LIST_MESSAGES, xmlBody, false, true);
        const unwrapped: RawList = unwrapMessageList(parsed);
        rawMessages = unwrapped.messages;
        total = unwrapped.total;
      } catch (e) {
        Log.i('CampusMail', 'LIST legacy fail: %{public}s',
          e instanceof Error ? e.message : String(e));
      }
    }
    const messages: MailMessageSummary[] = parseMessageList(rawMessages);
    if (total > 0 && messages.length === 0) {
      throw new Error('邮箱列表已返回 ' + String(total) + ' 封邮件，但当前版本无法解析邮件结构，请反馈后继续适配');
    }
    const result: MailListResult = new MailListResult();
    result.messages = messages;
    result.total = total > 0 ? total : messages.length;
    Log.i('CampusMail', 'LIST fid=%{public}d start=%{public}d got=%{public}d total=%{public}d',
      fid, start, messages.length, result.total);
    return result;
  }

  /** 关键词搜索（urlencoded '!' → urlencoded → JSON 多模块前缀逐级回退） */
  async searchMessages(pattern: string, start: number, limit: number): Promise<MailListResult> {
    const form: Record<string, string> = {};
    form['start'] = String(start);
    form['limit'] = String(limit);
    form['pattern'] = pattern;
    form['order'] = 'date';
    form['desc'] = 'true';
    form['returnTotal'] = 'true';
    form['summaryWindowSize'] = String(limit);
    form['mboxa'] = '';
    const body: Record<string, Object> = {};
    body['start'] = start;
    body['limit'] = limit;
    body['pattern'] = pattern;
    body['order'] = 'date';
    body['desc'] = true;
    body['returnTotal'] = true;
    body['summaryWindowSize'] = limit;
    body['mboxa'] = '';
    const jsonFuncs: string[] = ['mail:searchMessages', 'mbox:searchMessages', '!mail:searchMessages'];
    let parsed: Record<string, Object> = {};
    let ok: boolean = false;
    let lastErr: string = '';
    const marks: string[] = [];
    for (let i: number = 0; i < 2 + jsonFuncs.length && !ok; i++) {
      try {
        let candidate: Record<string, Object>;
        if (i === 0) {
          candidate = await this.formCall('!' + FUNC_SEARCH, form, false);
        } else if (i === 1) {
          candidate = await this.formCall(FUNC_SEARCH, form, false);
        } else {
          candidate = await this.postCoremailJson(jsonFuncs[i - 2], body, false, false);
        }
        if (this.isCoremailErrorPayload(candidate)) {
          lastErr = this.coremailErrorPayloadText(candidate);
          marks.push('invalid' + String(i));
        } else {
          parsed = candidate;
          ok = true;
          marks.push('ok' + String(i));
        }
      } catch (e) {
        lastErr = e instanceof Error ? e.message : String(e);
        marks.push('fail' + String(i));
      }
    }
    if (!ok) {
      throw new Error(lastErr.length > 0 ? lastErr : '邮件搜索失败，请稍后重试');
    }
    Log.i('CampusMail', 'SEARCH variants=%{public}s', marks.join(','));
    const unwrapped: RawList = unwrapMessageList(parsed);
    const result: MailListResult = new MailListResult();
    result.messages = parseMessageList(unwrapped.messages);
    result.total = unwrapped.total > 0 ? unwrapped.total : result.messages.length;
    Log.i('CampusMail', 'SEARCH patternLen=%{public}d got=%{public}d total=%{public}d',
      pattern.length, result.messages.length, result.total);
    return result;
  }

  /**
   * Coremail 空壳错误：HTTP 200 / code=S_OK 外壳内以
   * messages[0].severity === 'ERROR'（如 "Invalid method !readMessage"）报告失败。
   */
  private isCoremailErrorPayload(parsed: Record<string, Object>): boolean {
    const payload: Record<string, Object> = asRecord(pickPayload(parsed));
    const arr: Object[] = asArrayItems(payload['messages']);
    if (arr.length === 0) {
      return false;
    }
    const first: Record<string, Object> = asRecord(arr[0]);
    return strCoalesce([first['severity']]).toUpperCase() === 'ERROR';
  }

  /** messages[0] 错误摘要（供可读错误提示） */
  private coremailErrorPayloadText(parsed: Record<string, Object>): string {
    const payload: Record<string, Object> = asRecord(pickPayload(parsed));
    const arr: Object[] = asArrayItems(payload['messages']);
    if (arr.length === 0) {
      return '';
    }
    return strCoalesce([asRecord(arr[0])['summary']]);
  }

  /** 邮件详情（抄送、正文文本/HTML、附件元信息） */
  async readMessage(id: string): Promise<MailMessageDetail> {
    const form: Record<string, string> = {};
    form['mid'] = id;
    form['mboxa'] = '';
    const jsonBody: Record<string, Object> = {};
    jsonBody['mid'] = id;
    jsonBody['mboxa'] = '';
    // 多形态回退：JSON(/s/json) → JSON '!' → urlencoded(/s) → urlencoded '!'
    // 实测：本部署 /s 端点返回 XML；'!' 前缀在 JSON 端点非法（Invalid method），
    // 故 JSON(无前缀 readMessage) 为可靠路径。
    let parsed: Record<string, Object> = {};
    let ok: boolean = false;
    let lastErr: string = '';
    const marks: string[] = [];
    for (let i: number = 0; i < 4 && !ok; i++) {
      try {
        let candidate: Record<string, Object>;
        if (i === 0) {
          candidate = await this.postCoremailJson(FUNC_READ, jsonBody, false, false);
        } else if (i === 1) {
          candidate = await this.postCoremailJson('!' + FUNC_READ, jsonBody, false, false);
        } else if (i === 2) {
          candidate = await this.formCall(FUNC_READ, form, false);
        } else {
          candidate = await this.formCall('!' + FUNC_READ, form, false);
        }
        if (this.isCoremailErrorPayload(candidate)) {
          lastErr = this.coremailErrorPayloadText(candidate);
          marks.push('invalid' + String(i));
        } else {
          parsed = candidate;
          ok = true;
          marks.push('ok' + String(i));
        }
      } catch (e) {
        lastErr = e instanceof Error ? e.message : String(e);
        marks.push('fail' + String(i));
      }
    }
    if (!ok) {
      throw new Error(lastErr.length > 0 ? lastErr : '邮件详情读取失败，请稍后重试');
    }
    Log.i('CampusMail', 'READ variants=%{public}s', marks.join(','));
    const payload: Record<string, Object> = asRecord(pickPayload(parsed));
    const msgArr: Object[] = asArrayItems(payload['messages']);
    const msgObj: Record<string, Object> = asRecord(payload['messages']);
    // 实测：JSON readMessage 返回 {code, messages:[mailObj]} 或 {code, var:{...}}
    const mail: Record<string, Object> = asRecord(firstNonEmpty([
      payload['mail'], payload['message'], msgArr.length > 0 ? msgArr[0] : undefined,
      msgObj['mail'], msgObj['mailInfo'], msgObj,
    ]));
    const info: Record<string, Object> = asRecord(firstNonEmpty([
      payload['mailInfo'], payload['info'], msgArr.length > 1 ? msgArr[1] : undefined, msgObj,
    ]));
    // mail + info 合并（info 覆盖）后按摘要解析，id 强制回填
    const merged: Record<string, Object> = {};
    const mailKeys: string[] = Object.keys(mail);
    for (let i: number = 0; i < mailKeys.length; i++) {
      merged[mailKeys[i]] = mail[mailKeys[i]];
    }
    const infoKeys: string[] = Object.keys(info);
    for (let i: number = 0; i < infoKeys.length; i++) {
      merged[infoKeys[i]] = info[infoKeys[i]];
    }
    merged['id'] = id;
    const summary: MailMessageSummary = parseMessage(merged);
    const detail: MailMessageDetail = new MailMessageDetail();
    detail.loadSummary(summary);
    detail.cc = parseContacts(firstNonEmpty([mail['cc'], info['cc'], merged['cc']]));
    detail.contentHtml = strCoalesce([
      mail['content'], mail['html'], mail['text'],
      info['content'], info['html'], info['text'],
      merged['content'], merged['html'], merged['text'],
    ]);
    detail.contentText = stripHtml(detail.contentHtml);
    const attachments: MailAttachment[] = [];
    const attRows: Object[] = asArrayItems(firstNonEmpty([
      mail['attachments'], info['attachments'], merged['attachments'],
    ]));
    for (let i: number = 0; i < attRows.length; i++) {
      const attRec: Record<string, Object> = asRecord(attRows[i]);
      const att: MailAttachment = new MailAttachment();
      att.id = strCoalesce([attRec['id'], attRec['attachId']]);
      att.name = strCoalesce([attRec['name'], attRec['fileName'], attRec['displayName']]);
      if (att.name.length === 0) {
        att.name = '附件';
      }
      att.size = numCoalesce([attRec['size']]);
      attachments.push(att);
    }
    detail.attachments = attachments;
    Log.i('CampusMail', 'READ idLen=%{public}d htmlLen=%{public}d textLen=%{public}d att=%{public}d',
      id.length, detail.contentHtml.length, detail.contentText.length, attachments.length);
    return detail;
  }

  // ============================================================
  // 写操作
  // ============================================================

  /** 标记已读/未读（mbox:updateMessageInfos） */
  async markRead(ids: string[], read: boolean): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const flags: Record<string, Object> = {};
    flags['read'] = read;
    const attrs: Record<string, Object> = {};
    attrs['flags'] = flags;
    const body: Record<string, Object> = {};
    body['ids'] = ids;
    body['attrs'] = attrs;
    body['returnOriginalMsgInfos'] = true;
    await this.postCoremailJson(FUNC_UPDATE_INFOS, body, false, false);
    Log.i('CampusMail', 'MARK_READ count=%{public}d read=%{public}s',
      ids.length, read ? '1' : '0');
  }

  /** 删除邮件（mbox:deleteMessages；语义为移入"已删除"由服务端定） */
  async deleteMessages(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const body: Record<string, Object> = {};
    body['ids'] = ids;
    await this.postCoremailJson(FUNC_DELETE, body, false, false);
    Log.i('CampusMail', 'DELETE count=%{public}d', ids.length);
  }

  /** 移动邮件到目标文件夹（mbox:updateMessageInfos 改 fid） */
  async moveMessages(ids: string[], fid: number): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const attrs: Record<string, Object> = {};
    attrs['fid'] = fid;
    const body: Record<string, Object> = {};
    body['ids'] = ids;
    body['attrs'] = attrs;
    body['returnOriginalMsgInfos'] = true;
    await this.postCoremailJson(FUNC_UPDATE_INFOS, body, false, false);
    Log.i('CampusMail', 'MOVE count=%{public}d fid=%{public}d', ids.length, fid);
  }

  /** 撰写并发送邮件（compose 初始化 → mbox:compose action=deliver） */
  async sendMail(draft: ComposeDraft): Promise<void> {
    const initForm: Record<string, string> = {};
    initForm['ctype'] = 'normal';
    let composeInit: Record<string, Object>;
    try {
      composeInit = await this.formCall('!' + FUNC_COMPOSE_INIT, initForm, false);
    } catch (e) {
      composeInit = await this.formCall(FUNC_COMPOSE_INIT, initForm, false);
    }
    const composeRec: Record<string, Object> = asRecord(pickPayload(composeInit));
    const composeNested: Record<string, Object> = asRecord(composeRec['compose']);
    const composeData: Record<string, Object> = asRecord(composeRec['data']);
    const composeId: string = strCoalesce([
      composeRec['id'], composeRec['composeId'], composeNested['id'], composeData['id'],
    ]);
    if (composeId.length === 0) {
      throw new Error('邮箱写信草稿初始化失败，请稍后重试');
    }
    const attrs: Record<string, Object> = {};
    attrs['to'] = draft.to;
    attrs['cc'] = draft.cc;
    attrs['bcc'] = draft.bcc;
    attrs['subject'] = draft.subject;
    attrs['content'] = draft.content.replace(/\n/g, '<br>');
    const body: Record<string, Object> = {};
    body['id'] = composeId;
    body['attrs'] = attrs;
    body['returnInfo'] = true;
    body['action'] = 'deliver';
    body['autosaveHitCounter'] = true;
    await this.postCoremailJson(FUNC_COMPOSE, body, false, false);
    Log.i('CampusMail', 'SEND ok to=%{public}s', draft.to);
  }

  /**
   * 将 Coremail 域会话 Cookie 同步到 ArkWeb Cookie 存储——
   * 详情正文中的内嵌图片走 mails.tsinghua.edu.cn，无会话 Cookie 会 401/403
   * （对齐 NewsPage 的 syncWebvpnCookiesForWebView 做法）。
   */
  syncCoremailCookiesForWebView(): void {
    try {
      const header: string = this.http.getCookieManager().getCookieHeader(COREMAIL_BASE_URL + '/');
      if (header.length === 0) {
        return;
      }
      const pairs: string[] = header.split(';');
      for (let i: number = 0; i < pairs.length; i++) {
        const pair: string = pairs[i].trim();
        if (pair.length > 0) {
          webview.WebCookieManager.configCookieSync(COREMAIL_BASE_URL + '/', pair);
        }
      }
      Log.i('CampusMail', 'COOKIE_SYNC pairs=%{public}d', pairs.length);
    } catch (e) {
      Log.i('CampusMail', 'COOKIE_SYNC fail');
    }
  }
}
