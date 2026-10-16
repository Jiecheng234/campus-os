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
 *     urlencoded POST（复用 postFormWithHeaders，Content-Type 精确为
 *     "application/x-www-form-urlencoded; charset=UTF-8"）。
 *   - 修复轮 R1（真实模式缺口，实测驱动）：本部署 `/coremail/s`（XML RPC）对所有读信
 *     func 均返回 XML "Invalid method"/FR_INVALID_REQUEST，故读信改走 JSON 端点
 *     `/coremail/s/json`：① `mbox:getMessageInfos` 取元信息；② `mbox:getMessageData`
 *     {id,part:'1',mode:'download'} 取正文；③ 无 part 取原始 RFC822 解析 MIME 附件；
 *     列表附件标记派生链对齐参考 parseMessage（上游无线索时退化为详情页展示）。
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
/** 实测可用：邮件元信息（JSON 端点 S_OK，返回 var:[{from,to,subject,sentDate,...}]） */
const FUNC_GET_INFOS: string = 'mbox:getMessageInfos';
/** 实测可用：邮件正文/原始数据（JSON 端点 status=200，part=1 返回正文，无 part 返回原始 RFC822） */
const FUNC_GET_DATA: string = 'mbox:getMessageData';
const FUNC_COMPOSE_INIT: string = 'compose';
const FUNC_UPDATE_INFOS: string = 'mbox:updateMessageInfos';
const FUNC_DELETE: string = 'mbox:deleteMessages';
const FUNC_COMPOSE: string = 'mbox:compose';

/** Coremail POST 公共请求头（对齐参考 coremailXhrText 的 XHR 装配） */
const COREMAIL_JSON_HEADERS: Record<string, string> = {
  'X-Requested-With': 'XMLHttpRequest',
  'Accept': 'text/x-json, application/json, */*'
};

/** Coremail form/RPC POST 公共请求头（对齐参考 formCall：精确 charset 的 urlencoded Content-Type） */
const COREMAIL_FORM_HEADERS: Record<string, string> = {
  'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
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
  /** Coremail part 标识（附件定位用；本轮仅记录元信息，不用于下载） */
  part: string = '';
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
  // 附件标记派生链（修复轮 R1 / T025，对齐参考 parseMessage）：
  // attached | hasAttachment | attach | attr.attached | attr.hasAttachment | envelope.hasAttachment，
  // 全缺时回退 attachments 数组长度；上游列表接口实测不返回任何附件线索 →
  // 列表标记退化为"未知"（false，不显示附件标、不伪造），附件以详情页元信息为准。
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

/** Coremail 原始响应（未解析，供读信正文/原始邮件使用） */
class RawReadResponse {
  statusCode: number = 0;
  text: string = '';
}

/** 搜索候选（JSON 端点；多候选方法名覆盖不同 Coremail 部署） */
class SearchCandidate {
  func: string = '';
  body: Record<string, Object> = {};
}

// ============================================================
// MIME 辅助（读信：从原始邮件解析正文与附件）
// ============================================================

/** 头部/正文分离（兼容 CRLF 与 LF；无分隔则返回 ['', raw]） */
function splitHeadersBody(raw: string): string[] {
  const idx: number = raw.indexOf('\r\n\r\n');
  if (idx >= 0) {
    const out: string[] = [raw.substring(0, idx), raw.substring(idx + 4)];
    return out;
  }
  const idx2: number = raw.indexOf('\n\n');
  if (idx2 >= 0) {
    const out2: string[] = [raw.substring(0, idx2), raw.substring(idx2 + 2)];
    return out2;
  }
  const out3: string[] = ['', raw];
  return out3;
}

/** 头部字段取值（大小写不敏感；含折行续行合并；无则 ''） */
function headerValue(headers: string, name: string): string {
  const lines: string[] = headers.replace(/\r/g, '').split('\n');
  const lower: string = name.toLowerCase();
  let value: string = '';
  let capturing: boolean = false;
  for (let i: number = 0; i < lines.length; i++) {
    const line: string = lines[i];
    if (line.length > 0 && (line.charAt(0) === ' ' || line.charAt(0) === '\t')) {
      if (capturing) {
        value = value + ' ' + line.trim();
      }
      continue;
    }
    const idx: number = line.indexOf(':');
    if (idx <= 0) {
      capturing = false;
      continue;
    }
    const key: string = line.substring(0, idx).trim().toLowerCase();
    if (key === lower) {
      value = line.substring(idx + 1).trim();
      capturing = true;
    } else {
      capturing = false;
    }
  }
  return value;
}

/** Content-Type/Disposition 参数提取（boundary / name / filename） */
function headerParam(header: string, param: string): string {
  if (header.length === 0) {
    return '';
  }
  const re: RegExp = new RegExp(param + '\\s*=\\s*("[^"]*"|[^;\\s]+)', 'i');
  const m: RegExpExecArray | null = re.exec(header);
  if (m === null) {
    return '';
  }
  return m[1].replace(/^"|"$/g, '').trim();
}

/** RFC2047 编码字解码（=?charset?B|Q?...?=），失败保留原文 */
function decodeMimeWords(value: string): string {
  if (value.length === 0 || value.indexOf('=?') < 0) {
    return value;
  }
  let out: string = value;
  const re: RegExp = /=\?[^?]+\?([BbQq])\?([^?]*)\?=/g;
  let m: RegExpExecArray | null = re.exec(value);
  while (m !== null) {
    const enc: string = m[1].toUpperCase();
    let text: string = '';
    if (enc === 'B') {
      try {
        text = safeBase64Decode(m[2]);
      } catch (e) {
        text = m[2];
      }
    } else {
      text = decodeQuotedWord(m[2]);
    }
    out = out.replace(m[0], text);
    m = re.exec(value);
  }
  return out;
}

/** Q 编码字解码（_→空格 + =XX 十六进制，按 UTF-8 字节还原） */
function decodeQuotedWord(value: string): string {
  const bytes: number[] = [];
  let i: number = 0;
  while (i < value.length) {
    const c: string = value.charAt(i);
    if (c === '_') {
      bytes.push(0x20);
      i++;
    } else if (c === '=' && i + 2 < value.length) {
      const hex: string = value.substring(i + 1, i + 3);
      const n: number = parseInt(hex, 16);
      if (!Number.isNaN(n)) {
        bytes.push(n);
        i += 3;
      } else {
        bytes.push(c.charCodeAt(0));
        i++;
      }
    } else {
      bytes.push(c.charCodeAt(0));
      i++;
    }
  }
  return utf8FromBytes(bytes);
}

/** base64 → UTF-8 文本（失败抛错由调用方兜底） */
function safeBase64Decode(value: string): string {
  const bytes: number[] = [];
  const clean: string = value.replace(/[^A-Za-z0-9+/=]/g, '');
  for (let i: number = 0; i < clean.length; i += 4) {
    const c0: number = base64Index(clean.charAt(i));
    const c1: number = base64Index(clean.charAt(i + 1));
    const c2: number = base64Index(clean.charAt(i + 2));
    const c3: number = base64Index(clean.charAt(i + 3));
    if (c0 < 0 || c1 < 0) {
      break;
    }
    bytes.push((c0 << 2) | (c1 >> 4));
    if (c2 >= 0) {
      bytes.push(((c1 & 15) << 4) | (c2 >> 2));
    }
    if (c3 >= 0) {
      bytes.push(((c2 & 3) << 6) | c3);
    }
  }
  return utf8FromBytes(bytes);
}

/** base64 字符 → 6bit 值（非法返回 -1；'=' 返回 -2 语义由调用方按 <0 处理） */
function base64Index(c: string): number {
  if (c.length === 0 || c === '=') {
    return -1;
  }
  const code: number = c.charCodeAt(0);
  if (code >= 65 && code <= 90) { return code - 65; }
  if (code >= 97 && code <= 122) { return code - 71; }
  if (code >= 48 && code <= 57) { return code + 4; }
  if (c === '+') { return 62; }
  if (c === '/') { return 63; }
  return -1;
}

/** UTF-8 字节序列 → 字符串（严格按 UTF-8 解码；非法字节以 U+FFFD 兜底） */
function utf8FromBytes(bytes: number[]): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const b: number = bytes[i];
    let cp: number = 0;
    let len: number = 1;
    if (b < 0x80) {
      cp = b; len = 1;
    } else if (b >= 0xC0 && b < 0xE0) {
      cp = b & 0x1F; len = 2;
    } else if (b >= 0xE0 && b < 0xF0) {
      cp = b & 0x0F; len = 3;
    } else if (b >= 0xF0) {
      cp = b & 0x07; len = 4;
    } else {
      out = out + '\uFFFD'; i++; continue;
    }
    if (i + len > bytes.length) {
      out = out + '\uFFFD'; break;
    }
    for (let j: number = 1; j < len; j++) {
      cp = (cp << 6) | (bytes[i + j] & 0x3F);
    }
    out = out + String.fromCodePoint(cp);
    i += len;
  }
  return out;
}

/** 按 boundary 拆分 MIME 部件（去 preamble/epilogue 与分隔行） */
function splitMimeParts(body: string, boundary: string): string[] {
  const delim: string = '--' + boundary;
  const chunks: string[] = body.split(delim);
  const parts: string[] = [];
  for (let i: number = 0; i < chunks.length; i++) {
    let c: string = chunks[i];
    if (c.length === 0) {
      continue;
    }
    if (c.startsWith('--')) {
      continue;
    }
    const nl: number = c.indexOf('\n');
    if (nl >= 0 && nl < 4) {
      c = c.substring(nl + 1);
    } else if (nl > 4) {
      continue;
    }
    if (c.endsWith('\r\n')) {
      c = c.substring(0, c.length - 2);
    } else if (c.endsWith('\n')) {
      c = c.substring(0, c.length - 1);
    }
    if (c.trim().length > 0) {
      parts.push(c);
    }
  }
  return parts;
}

/** 递归收集原邮件中的附件（Content-Disposition: attachment 或带 filename/name 的部件） */
function collectAttachments(part: string, out: MailAttachment[], depth: number): void {
  if (depth > 4) {
    return;
  }
  const hb: string[] = splitHeadersBody(part);
  const headers: string = hb[0];
  const body: string = hb[1];
  const ct: string = headerValue(headers, 'Content-Type');
  const boundary: string = headerParam(ct, 'boundary');
  if (ct.toLowerCase().indexOf('multipart/') >= 0 && boundary.length > 0) {
    const subs: string[] = splitMimeParts(body, boundary);
    for (let i: number = 0; i < subs.length; i++) {
      collectAttachments(subs[i], out, depth + 1);
    }
    return;
  }
  const cd: string = headerValue(headers, 'Content-Disposition');
  let name: string = headerParam(cd, 'filename');
  if (name.length === 0) {
    name = headerParam(ct, 'name');
  }
  const isAttachment: boolean = cd.toLowerCase().indexOf('attachment') >= 0 || name.length > 0;
  if (!isAttachment) {
    return;
  }
  const enc: string = headerValue(headers, 'Content-Transfer-Encoding').toLowerCase();
  const att: MailAttachment = new MailAttachment();
  att.name = decodeMimeWords(name);
  if (att.name.length === 0) {
    att.name = '附件';
  }
  att.size = estimateEncodedSize(body, enc);
  out.push(att);
}

/** 部件正文大小估算（base64 按 3/4 还原；其余按字符数近似） */
function estimateEncodedSize(body: string, encoding: string): number {
  if (encoding.indexOf('base64') >= 0) {
    const clean: string = body.replace(/[^A-Za-z0-9+/=]/g, '');
    let pad: number = 0;
    if (clean.endsWith('==')) { pad = 2; } else if (clean.endsWith('=')) { pad = 1; }
    return Math.max(0, Math.floor(clean.length * 3 / 4) - pad);
  }
  return body.length;
}

/** 文本是否疑似二进制（PDF/压缩包/图片等；非可打印字符占比 > 10%） */
function looksBinaryText(text: string): boolean {
  const head: string = text.substring(0, 8);
  if (head.startsWith('%PDF') || head.startsWith('PK\u0003')) {
    return true;
  }
  const sample: number = Math.min(text.length, 512);
  if (sample === 0) {
    return false;
  }
  let bad: number = 0;
  for (let i: number = 0; i < sample; i++) {
    const code: number = text.charCodeAt(i);
    if (code === 9 || code === 10 || code === 13) {
      continue;
    }
    if (code < 32 || code === 0xFFFD) {
      bad++;
    }
  }
  return bad / sample > 0.1;
}

/** quoted-printable 解码（软换行 + =XX 十六进制字节 → UTF-8 文本） */
function decodeQuotedPrintable(text: string): string {
  const cleaned: string = text.replace(/=\r?\n/g, '');
  const bytes: number[] = [];
  let i: number = 0;
  while (i < cleaned.length) {
    const c: string = cleaned.charAt(i);
    if (c === '=' && i + 2 < cleaned.length) {
      const hex: string = cleaned.substring(i + 1, i + 3);
      if (/^[0-9A-Fa-f]{2}$/.test(hex)) {
        bytes.push(parseInt(hex, 16));
        i += 3;
        continue;
      }
    }
    bytes.push(c.charCodeAt(0));
    i++;
  }
  return utf8FromBytes(bytes);
}

/** Content-Transfer-Encoding 解码（base64 / quoted-printable / 原文） */
function decodeTransfer(body: string, encoding: string): string {
  const e: string = encoding.toLowerCase();
  if (e.indexOf('base64') >= 0) {
    try {
      return safeBase64Decode(body);
    } catch (err) {
      return body;
    }
  }
  if (e.indexOf('quoted-printable') >= 0) {
    return decodeQuotedPrintable(body);
  }
  return body;
}

/**
 * 从原始 RFC822 邮件提取正文（返回 [正文, isHtml('1'/'0')]）：
 * 递归 multipart（跳过 attachment 部件），优先 text/html → text/plain，
 * 并按 Content-Transfer-Encoding 解码；未知类型（application/pdf 等）不作为正文。
 */
function extractMimeBody(raw: string, depth: number): string[] {
  if (depth > 4) {
    const empty: string[] = ['', '0'];
    return empty;
  }
  const hb: string[] = splitHeadersBody(raw);
  const headers: string = hb[0];
  const ct: string = headerValue(headers, 'Content-Type');
  const ctLower: string = ct.toLowerCase();
  const boundary: string = headerParam(ct, 'boundary');
  if (ctLower.indexOf('multipart/') >= 0 && boundary.length > 0) {
    const subs: string[] = splitMimeParts(hb[1], boundary);
    let html: string = '';
    let plain: string = '';
    for (let i: number = 0; i < subs.length; i++) {
      const sub: string = subs[i];
      const shb: string[] = splitHeadersBody(sub);
      const subCd: string = headerValue(shb[0], 'Content-Disposition').toLowerCase();
      if (subCd.indexOf('attachment') >= 0) {
        continue;
      }
      const subCt: string = headerValue(shb[0], 'Content-Type').toLowerCase();
      if (subCt.indexOf('multipart/') >= 0) {
        const nested: string[] = extractMimeBody(sub, depth + 1);
        if (nested[1] === '1' && html.length === 0) {
          html = nested[0];
        } else if (nested[0].length > 0 && plain.length === 0) {
          plain = nested[0];
        }
        continue;
      }
      const enc: string = headerValue(shb[0], 'Content-Transfer-Encoding');
      const txt: string = decodeTransfer(shb[1], enc);
      if (subCt.indexOf('text/html') >= 0 && html.length === 0) {
        html = txt;
      } else if (subCt.indexOf('text/plain') >= 0 && plain.length === 0) {
        plain = txt;
      }
    }
    if (html.length > 0) {
      const r: string[] = [html, '1'];
      return r;
    }
    const rp: string[] = [plain, '0'];
    return rp;
  }
  const encTop: string = headerValue(headers, 'Content-Transfer-Encoding');
  const txtTop: string = decodeTransfer(hb[1], encTop);
  if (ctLower.indexOf('text/html') >= 0) {
    const rh: string[] = [txtTop, '1'];
    return rh;
  }
  if (ctLower.indexOf('text/plain') >= 0 || ctLower.length === 0) {
    const rt: string[] = [txtTop, '0'];
    return rt;
  }
  const rn: string[] = ['', '0'];
  return rn;
}

/** 是否为 Coremail 错误响应（XML / 带 FA_/FR_ 码的 JSON 壳） */
function isCoremailErrorText(text: string): boolean {
  const t: string = text.replace(/^\s+/, '');
  if (t.startsWith('<?xml') || t.startsWith('<result>')) {
    return true;
  }
  if (t.startsWith('{')) {
    try {
      const p: Record<string, Object> = JSON.parse(t) as Record<string, Object>;
      const code: string = strCoalesce([p['code']]);
      if (code.indexOf('FA_') === 0 || code.indexOf('FR_') === 0) {
        return true;
      }
      if (strCoalesce([p['result']]) === 'error') {
        return true;
      }
    } catch (e) {
      return false;
    }
  }
  return false;
}

/** 联系人 → 文本（本地搜索匹配用） */
function contactsText(contacts: MailContact[]): string {
  const parts: string[] = [];
  for (let i: number = 0; i < contacts.length; i++) {
    parts.push(contacts[i].name);
    parts.push(contacts[i].address);
  }
  return parts.join(' ');
}

/** 服务端搜索候选（JSON 端点多方法名；本部署 `mail:` 模块无效，故不列 mail:） */
function buildSearchCandidates(pattern: string, start: number, limit: number): SearchCandidate[] {
  const list: SearchCandidate[] = [];
  const names: string[] = ['mbox:searchMessages', 'mbox:search', 'global:searchMessages'];
  for (let i: number = 0; i < names.length; i++) {
    const c: SearchCandidate = new SearchCandidate();
    c.func = names[i];
    c.body['start'] = start;
    c.body['limit'] = limit;
    c.body['pattern'] = pattern;
    c.body['order'] = 'date';
    c.body['desc'] = true;
    c.body['returnTotal'] = true;
    c.body['summaryWindowSize'] = limit;
    c.body['mboxa'] = '';
    list.push(c);
  }
  const kw: SearchCandidate = new SearchCandidate();
  kw.func = 'mbox:searchMessages';
  kw.body['keyword'] = pattern;
  kw.body['start'] = start;
  kw.body['limit'] = limit;
  list.push(kw);
  return list;
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

  /**
   * 会话瞬态复位（SessionManager.resetSessionState() 统一扇出调用）：
   * 清 Coremail 会话缓存（sid/baseUrl），避免进程内"退出→再登录"复用
   * 上一会话的陈旧邮箱会话。
   * 契约：无参、同步、幂等、不抛；仅清本服务进程内瞬态态，
   * 不触及 Cookie/凭证/网络。
   */
  resetSessionState(): void {
    this.session = undefined;
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

  /** urlencoded POST 调用包装（读信/搜索/写信初始化等；精确 charset 的 Content-Type） */
  private async formCall(func: string, form: Record<string, string>,
    force: boolean): Promise<Record<string, Object>> {
    const s: CoremailSession = await this.obtainSession(force);
    const url: string = this.rpcUrl(s, func);
    const resp: HttpResponse = await this.http.postFormWithHeaders(url, form, COREMAIL_FORM_HEADERS);
    Log.i('CampusMail', 'FORM func=%{public}s status=%{public}d bodyLen=%{public}d head=%{public}s',
      func, resp.statusCode, resp.body.length, resp.body.length > 0 ? resp.body.charAt(0) : '');
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
    // T025：附件标记计数（上游列表无附件线索时恒为 0，验证阶段据此确认退化结论）
    let attFlagCount: number = 0;
    for (let i: number = 0; i < messages.length; i++) {
      if (messages[i].hasAttachment) {
        attFlagCount++;
      }
    }
    Log.i('CampusMail', 'LIST fid=%{public}d start=%{public}d got=%{public}d total=%{public}d attFlag=%{public}d',
      fid, start, messages.length, result.total, attFlagCount);
    return result;
  }

  /**
   * 关键词搜索。
   *
   * 实测结论：本部署 `/coremail/s`（XML RPC）返回 XML "Invalid module mail"/FR_INVALID_REQUEST，
   * `mail:searchMessages` 在 JSON 端点亦报 "Invalid module mail"（`mail` 模块不存在）。故改为：
   *   ① JSON 端点多候选服务端搜索方法（mbox:searchMessages / mbox:search / global:searchMessages）；
   *   ② 全部失败时回退**本地过滤**（对齐参考 nativeMail 的 listNativeMailMessages 客户端过滤：
   *      拉取收件箱邮件并按 主题/摘要/发件人 匹配关键词）。
   */
  async searchMessages(pattern: string, start: number, limit: number): Promise<MailListResult> {
    const cands: SearchCandidate[] = buildSearchCandidates(pattern, start, limit);
    const marks: string[] = [];
    for (let i: number = 0; i < cands.length; i++) {
      const c: SearchCandidate = cands[i];
      const resp: RawReadResponse | undefined = await this.postJsonRawResponse(c.func, c.body);
      if (resp === undefined) {
        marks.push(c.func + '=EXC');
        continue;
      }
      Log.i('CampusMail',
        'SEARCHPROBE[%{public}d] func=%{public}s status=%{public}d head=%{public}s body=%{public}s',
        i, c.func, resp.statusCode, resp.text.length > 0 ? resp.text.charAt(0) : '',
        resp.text.substring(0, 300));
      if (isCoremailErrorText(resp.text)) {
        marks.push(c.func + '=ERR');
        continue;
      }
      let parsed: Record<string, Object> | undefined = undefined;
      try {
        parsed = JSON.parse(resp.text) as Record<string, Object>;
      } catch (e) {
        marks.push(c.func + '=NONJSON');
        continue;
      }
      if (this.isCoremailErrorPayload(parsed)) {
        marks.push(c.func + '=SHELL');
        continue;
      }
      const uw: RawList = unwrapMessageList(parsed);
      if (uw.messages.length > 0 || uw.total > 0) {
        const result: MailListResult = new MailListResult();
        result.messages = parseMessageList(uw.messages);
        result.total = uw.total > 0 ? uw.total : result.messages.length;
        Log.i('CampusMail', 'SEARCH ok func=%{public}s got=%{public}d total=%{public}d',
          c.func, result.messages.length, result.total);
        return result;
      }
      marks.push(c.func + '=EMPTY');
    }
    Log.i('CampusMail', 'SEARCH rpc-fail patternLen=%{public}d marks=%{public}s → local',
      pattern.length, marks.join(','));
    return await this.localSearch(pattern, start, limit);
  }

  /** 本地过滤回退（收件箱按 主题/摘要/发件人 匹配；最多扫描 200 封，对齐参考客户端过滤） */
  private async localSearch(pattern: string, start: number, limit: number): Promise<MailListResult> {
    const needle: string = pattern.trim().toLowerCase();
    const hits: MailMessageSummary[] = [];
    const pageSize: number = 50;
    let offset: number = 0;
    let scanned: number = 0;
    while (offset < 200) {
      let page: MailListResult;
      try {
        page = await this.listMessages(1, offset, pageSize);
      } catch (e) {
        Log.i('CampusMail', 'SEARCH local list fail offset=%{public}d: %{public}s',
          offset, e instanceof Error ? e.message : String(e));
        break;
      }
      scanned = scanned + page.messages.length;
      for (let i: number = 0; i < page.messages.length; i++) {
        const m: MailMessageSummary = page.messages[i];
        const hay: string = (m.subject + ' ' + m.brief + ' ' + contactsText(m.from)).toLowerCase();
        if (needle.length === 0 || hay.indexOf(needle) >= 0) {
          hits.push(m);
        }
      }
      if (page.messages.length < pageSize) {
        break;
      }
      offset = offset + pageSize;
      if (page.total > 0 && offset >= page.total) {
        break;
      }
    }
    const result: MailListResult = new MailListResult();
    result.messages = hits.slice(start, start + limit);
    result.total = hits.length;
    Log.i('CampusMail', 'SEARCH local patternLen=%{public}d scanned=%{public}d hits=%{public}d',
      pattern.length, scanned, hits.length);
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

  /**
   * 邮件详情（抄送、正文文本/HTML、附件元信息）。
   *
   * 修复轮 R1（实测结论驱动）：本部署 `/coremail/s`（XML RPC）对所有读信 func 均返回
   * XML "Invalid method"/FR_INVALID_REQUEST，且 `readMessage` 非有效方法——故改用实测可用的
   * **JSON 端点 `/coremail/s/json`**：
   *   ① `mbox:getMessageInfos` {ids,returnOriginalMsgInfos} → var:[{from,to,subject,sentDate,...}]（元信息）
   *   ② `mbox:getMessageData` {id,part:'1',mode:'download'} → 正文（status=200，非 JSON 文本/HTML）
   *   ③ `mbox:getMessageData` {id,mode:'download'} → 原始 RFC822（解析 MIME 附件与正文兜底）
   * 正文/附件/元信息均取不到时抛可读中文错误；解析异常不崩溃。
   */
  async readMessage(id: string): Promise<MailMessageDetail> {
    const detail: MailMessageDetail = new MailMessageDetail();
    detail.id = id;
    // ① 元信息（mbox:getMessageInfos）
    const ids: string[] = [id];
    const infoBody: Record<string, Object> = {};
    infoBody['ids'] = ids;
    infoBody['returnOriginalMsgInfos'] = true;
    let metaFound: boolean = false;
    try {
      const parsed: Record<string, Object> =
        await this.postCoremailJson(FUNC_GET_INFOS, infoBody, false, false);
      const uw: RawList = unwrapMessageList(parsed);
      if (uw.messages.length > 0) {
        detail.loadSummary(parseMessage(uw.messages[0]));
        metaFound = true;
      }
    } catch (e) {
      Log.i('CampusMail', 'READ meta fail: %{public}s', e instanceof Error ? e.message : String(e));
    }
    detail.id = id;
    // ② 原始邮件（正文权威来源 + 附件）
    let rawMail: string = '';
    const rawResp: RawReadResponse | undefined = await this.fetchMessageData(id, '');
    if (rawResp !== undefined && !isCoremailErrorText(rawResp.text) && rawResp.text.length > 0) {
      rawMail = rawResp.text;
    }
    let bodyText: string = '';
    let bodyIsHtml: boolean = false;
    if (rawMail.length > 0) {
      const b: string[] = extractMimeBody(rawMail, 0);
      bodyText = b[0];
      bodyIsHtml = b[1] === '1';
    }
    // ③ 兜底：part=N 逐级回退（仅当原始邮件未解析出正文；跳过二进制/附件内容）
    if (bodyText.length === 0) {
      const parts: string[] = ['1', '1.1', '1.2', '2'];
      for (let i: number = 0; i < parts.length && bodyText.length === 0; i++) {
        const resp: RawReadResponse | undefined = await this.fetchMessageData(id, parts[i]);
        if (resp === undefined || isCoremailErrorText(resp.text)) {
          continue;
        }
        const t: string = resp.text;
        if (t.trim().length === 0 || looksBinaryText(t)) {
          continue;
        }
        bodyText = t;
        bodyIsHtml = /<[a-zA-Z][^>]*>/.test(t);
      }
    }
    if (bodyIsHtml) {
      detail.contentHtml = bodyText;
      detail.contentText = stripHtml(bodyText);
    } else {
      detail.contentText = bodyText;
      detail.contentHtml = '';
    }
    const attachments: MailAttachment[] = [];
    if (rawMail.length > 0) {
      collectAttachments(rawMail, attachments, 0);
    }
    detail.attachments = attachments;
    detail.hasAttachment = attachments.length > 0;
    Log.i('CampusMail',
      'READ idLen=%{public}d meta=%{public}d htmlLen=%{public}d textLen=%{public}d att=%{public}d rawLen=%{public}d',
      id.length, metaFound ? 1 : 0, detail.contentHtml.length, detail.contentText.length,
      attachments.length, rawMail.length);
    if (!metaFound && detail.contentText.length === 0 && detail.contentHtml.length === 0
      && attachments.length === 0) {
      throw new Error('邮件详情读取失败，请稍后重试');
    }
    return detail;
  }

  /** JSON 端点原始响应（不做 JSON 解析/错误抛出，供读信正文等非 JSON 响应使用） */
  private async postJsonRawResponse(func: string,
    body: Record<string, Object>): Promise<RawReadResponse | undefined> {
    try {
      const s: CoremailSession = await this.obtainSession(false);
      const resp: HttpResponse = await this.http.postJsonRaw(this.jsonUrl(s, func),
        JSON.stringify(body), COREMAIL_JSON_HEADERS);
      const r: RawReadResponse = new RawReadResponse();
      r.statusCode = resp.statusCode;
      r.text = resp.body;
      return r;
    } catch (e) {
      Log.i('CampusMail', 'RAWRESP exc func=%{public}s: %{public}s',
        func, e instanceof Error ? e.message : String(e));
      return undefined;
    }
  }

  /** 取邮件正文/原始数据（mbox:getMessageData；part 为空串取原始 RFC822） */
  private async fetchMessageData(id: string, part: string): Promise<RawReadResponse | undefined> {
    const body: Record<string, Object> = {};
    body['id'] = id;
    body['part'] = part;
    body['mode'] = 'download';
    return this.postJsonRawResponse(FUNC_GET_DATA, body);
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
