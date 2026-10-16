/**
 * ============================================================================
 * AgentWriteTools — Agent 可逆写工具（10 个）+ 自建数据存储 + 共享辅助
 * ============================================================================
 *
 * 【对齐参考实现】src/services/ai/tools.ts（写工具语义逐条移植）：
 *   - 治理链（dryRun → 确认 → run → verify）由 AgentService.executeToolCall
 *     统一驱动；本文件只提供各环节的实现与文案。
 *   - 每个写工具 requiresConfirmation=true；演示模式被 requireRealSession
 *     阻止（真实写操作绝不静默执行）。
 *
 * 【与参考实现的差异】
 *   - undo 环节不迁移（plan D4：治理链为 dry-run→确认→run→verify→审计）。
 *   - 个人备忘 / 自建 DDL 存储自建于此（RN 走 redux slice + storage）：
 *     personal events → StorageKeys.PERSONAL_EVENTS（模型 AgentPersonalEvent）；
 *     manual deadlines → StorageKeys.MANUAL_DEADLINES（复用 domain ManualDeadline，
 *     date/time 拆分字段）。
 *   - 字段适配：delId→cancelId；图书馆写接口成功码 status===0（RN 为 1）；
 *     minReserveTime→minReserveMinute；研读间预约不返回 recordUuid →
 *     run 后经 getRoomBookingRecords 按 devName+时间配对回填。
 *   - remember_preference 基于既有 AIMemoryStore（结构化键位合并）。
 * ============================================================================
 */
import { AgentPersonalEvent, AgentToolDef } from '../../domain/AIAgentTypes';
import { ActionPreview, ConfirmationSpec, ToolRisk, VerificationResult } from '../../domain/ActionTypes';
import { ManualDeadline } from '../../domain/DeadlineTypes';
import { PreferencesStorage } from '../../storage/PreferencesStorage';
import { StorageKeys } from '../../storage/StorageKeys';
import { AIMemoryStore } from '../../state/AIMemoryStore';
import { SettingsManager } from '../../state/SettingsManager';
import { SessionManager } from '../auth/SessionManager';
import { LibraryBookResult, LibraryBookingRecord, LibrarySeatInfo, LibrarySeatService, seatStatusLabel } from '../campus/LibrarySeatService';
import { LibraryRoomService, LibRoomBookRecord, LibRoomBookRequest, LibRoomBookResult, LibRoomResource } from '../campus/LibraryRoomService';
import { CampusNetworkService, NetworkDevice, NetworkSnapshot } from '../campus/CampusNetworkService';
import { Log } from '../../utils/Logger';

const LOG_TAG: string = 'AgentWriteTools';

// ============================================================
// 工具入参读取辅助（Record<string, Object> → 强类型；AgentTools 共用）
// ============================================================

/** 取字符串参数（缺失/类型不符返回空串） */
export function argString(args: Record<string, Object>, key: string): string {
  const v: Object | undefined = args[key];
  if (typeof v === 'string') {
    return v;
  }
  if (typeof v === 'number' || typeof v === 'boolean') {
    return String(v);
  }
  return '';
}

/** 取数值参数（缺失/非法返回 NaN；调用方用 Number.isNaN 判定） */
export function argNumber(args: Record<string, Object>, key: string): number {
  const v: Object | undefined = args[key];
  if (typeof v === 'number') {
    return v;
  }
  if (typeof v === 'string') {
    const n: number = Number(v);
    return Number.isFinite(n) ? n : Number.NaN;
  }
  return Number.NaN;
}

/** 取字符串数组参数（缺失/元素类型不符的跳过） */
export function argStringArray(args: Record<string, Object>, key: string): string[] {
  const out: string[] = [];
  const v: Object | undefined = args[key];
  if (v !== undefined && Array.isArray(v)) {
    const arr: Object[] = v as Object[];
    for (let i: number = 0; i < arr.length; i++) {
      const e: Object = arr[i];
      if (typeof e === 'string') {
        out.push(e);
      }
    }
  }
  return out;
}

/** 取数值数组参数（字符串元素转数字，非法跳过） */
export function argNumberArray(args: Record<string, Object>, key: string): number[] {
  const out: number[] = [];
  const v: Object | undefined = args[key];
  if (v !== undefined && Array.isArray(v)) {
    const arr: Object[] = v as Object[];
    for (let i: number = 0; i < arr.length; i++) {
      const e: Object = arr[i];
      if (typeof e === 'number') {
        out.push(e);
      } else if (typeof e === 'string') {
        const n: number = Number(e);
        if (Number.isFinite(n)) {
          out.push(n);
        }
      }
    }
  }
  return out;
}

// ============================================================
// 共享辅助（日期/脱敏/会话闸门；对齐 RN tools.ts 模块级 helper）
// ============================================================

function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

/** 本地时区当前日期：YYYY-MM-DD */
export function todayLocalISO(): string {
  const d: Date = new Date();
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

/** 相对今天偏移的 ISO 日期 */
export function isoDateForOffset(offsetDays: number): string {
  const d: Date = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

/** 日期文本规整 → YYYY-MM-DD（支持 YYYYMMDD / 中文 / 斜杠点分隔；对齐 RN normalizeDateString） */
export function normalizeDateString(input: string): string {
  const str: string = input.trim();
  if (str.length === 0) {
    return '';
  }
  if (/^\d{4}-\d{2}-\d{2}/.test(str)) {
    return str.substring(0, 10);
  }
  if (/^\d{8}$/.test(str)) {
    return str.substring(0, 4) + '-' + str.substring(4, 6) + '-' + str.substring(6, 8);
  }
  const replaced: string = str.replace(/[年/.]/g, '-').replace(/月/g, '-').replace(/日/g, '');
  const d: Date = new Date(replaced);
  if (!Number.isNaN(d.getTime())) {
    return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
  }
  return str;
}

/** today/tomorrow/今天/明天/日期文本 → YYYY-MM-DD（对齐 RN normalizeDateArg） */
export function normalizeDateArg(value: string, fallbackOffset: number): string {
  if (value === 'today' || value === '今天' || value.length === 0) {
    return isoDateForOffset(fallbackOffset);
  }
  if (value === 'tomorrow' || value === '明天') {
    return isoDateForOffset(1);
  }
  const normalized: string = normalizeDateString(value);
  return normalized.length > 0 ? normalized : isoDateForOffset(fallbackOffset);
}

/** 座位日期参数 → DateChoice（1=明天，其余=今天） */
export function dateChoiceFromArg(value: Object | undefined): number {
  if (typeof value === 'number' && value === 1) {
    return 1;
  }
  if (typeof value === 'string' && (value === '1' || value === 'tomorrow' || value === '明天')) {
    return 1;
  }
  return 0;
}

/** YYYY-MM-DD → YYYYMMDD */
export function ymdFromIso(date: string): string {
  return date.replace(/-/g, '');
}

/** HH:mm 校验 + 规整（分钟须为 5 的倍数）→ 'YYYY-MM-DD HH:mm:00'（对齐 RN toRoomTimestamp） */
export function toRoomTimestamp(date: string, time: string): string {
  const cleanTime: string = time.trim();
  const match: RegExpExecArray | null = /^(\d{1,2}):(\d{2})(?::\d{2})?$/.exec(cleanTime);
  if (match === null) {
    throw new Error('研读间时间必须是 HH:mm，例如 14:00');
  }
  const hourNum: number = Number(match[1]);
  const minuteNum: number = Number(match[2]);
  if (hourNum > 23 || minuteNum > 59) {
    throw new Error('研读间时间必须是 HH:mm，例如 14:00');
  }
  if (minuteNum % 5 !== 0) {
    throw new Error('研读间预约分钟必须是 5 的倍数');
  }
  const hourText: string = hourNum < 10 ? '0' + String(hourNum) : String(hourNum);
  return date + ' ' + hourText + ':' + match[2] + ':00';
}

/** 'YYYY-MM-DD HH:MM:SS'（或含 T 的 ISO 文本）→ 毫秒；空串/不可解析返回 NaN */
export function parseRoomTimeMs(text: string): number {
  if (text.length === 0) {
    return Number.NaN;
  }
  const normalized: string = text.indexOf('T') >= 0 ? text : text.replace(' ', 'T');
  return new Date(normalized).getTime();
}

/** 两时刻相差小于 1 分钟视为同一时刻（NaN 视为不同） */
export function sameMinuteMs(leftMs: number, rightMs: number): boolean {
  if (Number.isNaN(leftMs) || Number.isNaN(rightMs)) {
    return false;
  }
  return Math.abs(leftMs - rightMs) < 60000;
}

/** 标识符打码（前 2 + *** + 后 2；过短全掩码） */
export function maskIdentifier(value: string): string {
  if (value.length <= 4) {
    return '****';
  }
  return value.substring(0, 2) + '***' + value.substring(value.length - 2);
}

/** 演示模式闸门：真实校园读写前置校验（对齐 RN requireRealSession） */
export function requireRealSession(): void {
  if (SettingsManager.isDemoMode()) {
    throw new Error('当前是演示模式，无法访问真实校园数据或执行操作');
  }
}

// ============================================================
// 结果/预览/确认构造辅助
// ============================================================

function okResult(message: string): Record<string, Object> {
  return { 'ok': true, 'message': message };
}

function failResult(message: string): Record<string, Object> {
  return { 'ok': false, 'message': message };
}

function okVerify(message: string): VerificationResult {
  const v: VerificationResult = new VerificationResult();
  v.ok = true;
  v.message = message;
  return v;
}

function failVerify(message: string): VerificationResult {
  const v: VerificationResult = new VerificationResult();
  v.ok = false;
  v.message = message;
  return v;
}

function previewOf(toolName: string, title: string, summary: string, affected: string, reversible: boolean): ActionPreview {
  const p: ActionPreview = new ActionPreview();
  p.toolName = toolName;
  p.title = title;
  p.summary = summary;
  p.description = summary;
  p.affectedResource = affected;
  p.reversible = reversible;
  return p;
}

function confirmSpecOf(title: string, message: string, destructive: boolean): ConfirmationSpec {
  const spec: ConfirmationSpec = new ConfirmationSpec();
  spec.title = title;
  spec.message = message;
  spec.destructive = destructive;
  spec.cancellable = true;
  return spec;
}

function strOr(v: Object | undefined): string {
  return typeof v === 'string' ? v : '';
}

// ============================================================
// 个人备忘存储（AgentPersonalEvent；StorageKeys.PERSONAL_EVENTS）
// ============================================================

let personalEventsCache: AgentPersonalEvent[] = [];
let personalEventsLoaded: boolean = false;

async function loadPersonalEvents(): Promise<AgentPersonalEvent[]> {
  if (personalEventsLoaded) {
    return personalEventsCache;
  }
  const items: AgentPersonalEvent[] = [];
  try {
    const raw: string = await PreferencesStorage.getString(StorageKeys.PERSONAL_EVENTS, '');
    if (raw.length > 0) {
      const parsed: Object = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[];
        for (let i: number = 0; i < arr.length; i++) {
          const item: AgentPersonalEvent | undefined = parsePersonalEvent(arr[i]);
          if (item !== undefined) {
            items.push(item);
          }
        }
      }
    }
  } catch (e) {
    Log.w(LOG_TAG, 'personal events load failed, fallback to empty');
  }
  personalEventsCache = items;
  personalEventsLoaded = true;
  return personalEventsCache;
}

function parsePersonalEvent(entry: Object): AgentPersonalEvent | undefined {
  if (entry === null || typeof entry !== 'object') {
    return undefined;
  }
  const rec: Record<string, Object> = entry as Record<string, Object>;
  const id: Object | undefined = rec['id'];
  const date: Object | undefined = rec['date'];
  const title: Object | undefined = rec['title'];
  if (typeof id !== 'string' || typeof date !== 'string' || typeof title !== 'string') {
    return undefined;
  }
  const ev: AgentPersonalEvent = new AgentPersonalEvent();
  ev.id = id;
  ev.date = date;
  ev.title = title;
  ev.startTime = strOr(rec['startTime']);
  ev.endTime = strOr(rec['endTime']);
  ev.location = strOr(rec['location']);
  ev.note = strOr(rec['note']);
  return ev;
}

async function persistPersonalEvents(items: AgentPersonalEvent[]): Promise<void> {
  personalEventsCache = items;
  personalEventsLoaded = true;
  try {
    await PreferencesStorage.setJson<AgentPersonalEvent[]>(StorageKeys.PERSONAL_EVENTS, items);
  } catch (e) {
    Log.w(LOG_TAG, 'personal events persist failed len=%{public}d', items.length);
  }
}

async function appendPersonalEvent(date: string, title: string, startTime: string,
  endTime: string, location: string, note: string): Promise<AgentPersonalEvent> {
  const events: AgentPersonalEvent[] = await loadPersonalEvents();
  const ev: AgentPersonalEvent = new AgentPersonalEvent();
  ev.id = 'pe-' + Date.now() + '-' + Math.random().toString(36).substring(2, 8);
  ev.date = normalizeDateString(date).length > 0 ? normalizeDateString(date) : date;
  ev.title = title;
  ev.startTime = startTime;
  ev.endTime = endTime;
  ev.location = location;
  ev.note = note;
  events.push(ev);
  await persistPersonalEvents(events);
  return ev;
}

async function deletePersonalEventById(id: string): Promise<boolean> {
  const trimmed: string = id.trim();
  if (trimmed.length === 0) {
    return false;
  }
  const events: AgentPersonalEvent[] = await loadPersonalEvents();
  const next: AgentPersonalEvent[] = [];
  let removed: boolean = false;
  for (let i: number = 0; i < events.length; i++) {
    if (events[i].id === trimmed) {
      removed = true;
    } else {
      next.push(events[i]);
    }
  }
  if (!removed) {
    return false;
  }
  await persistPersonalEvents(next);
  return true;
}

/** 备忘定位：id → 标题全等 → 标题包含（对齐 RN findPersonalEvent） */
async function findPersonalEvent(key: string): Promise<AgentPersonalEvent | undefined> {
  const trimmed: string = key.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const events: AgentPersonalEvent[] = await loadPersonalEvents();
  for (let i: number = 0; i < events.length; i++) {
    if (events[i].id === trimmed) {
      return events[i];
    }
  }
  for (let i: number = 0; i < events.length; i++) {
    if (events[i].title === trimmed) {
      return events[i];
    }
  }
  for (let i: number = 0; i < events.length; i++) {
    if (events[i].title.includes(trimmed)) {
      return events[i];
    }
  }
  return undefined;
}

/** 按日期区间列备忘（起止均闭区间；空串不设限；按日期+开始时间排序） */
async function listPersonalEventsInRange(startDate: string, endDate: string): Promise<AgentPersonalEvent[]> {
  const events: AgentPersonalEvent[] = await loadPersonalEvents();
  const start: string = startDate.length > 0 ? normalizeDateString(startDate) : '';
  const end: string = endDate.length > 0 ? normalizeDateString(endDate) : '';
  const out: AgentPersonalEvent[] = [];
  for (let i: number = 0; i < events.length; i++) {
    const d: string = normalizeDateString(events[i].date);
    if (start.length > 0 && d < start) {
      continue;
    }
    if (end.length > 0 && d > end) {
      continue;
    }
    out.push(events[i]);
  }
  out.sort((a: AgentPersonalEvent, b: AgentPersonalEvent): number => {
    const dc: number = a.date.localeCompare(b.date);
    return dc !== 0 ? dc : a.startTime.localeCompare(b.startTime);
  });
  return out;
}

function personalEventSummary(e: AgentPersonalEvent): Record<string, Object> {
  const rec: Record<string, Object> = {};
  rec['id'] = e.id;
  rec['date'] = e.date;
  rec['title'] = e.title;
  rec['startTime'] = e.startTime;
  rec['endTime'] = e.endTime;
  rec['location'] = e.location;
  rec['note'] = e.note;
  return rec;
}

// ============================================================
// 自建 DDL 存储（domain ManualDeadline；StorageKeys.MANUAL_DEADLINES）
// ============================================================

let manualDeadlinesCache: ManualDeadline[] = [];
let manualDeadlinesLoaded: boolean = false;

async function loadManualDeadlinesInternal(): Promise<ManualDeadline[]> {
  if (manualDeadlinesLoaded) {
    return manualDeadlinesCache;
  }
  const items: ManualDeadline[] = [];
  try {
    const raw: string = await PreferencesStorage.getString(StorageKeys.MANUAL_DEADLINES, '');
    if (raw.length > 0) {
      const parsed: Object = JSON.parse(raw) as Object;
      if (Array.isArray(parsed)) {
        const arr: Object[] = parsed as Object[];
        for (let i: number = 0; i < arr.length; i++) {
          const item: ManualDeadline | undefined = parseManualDeadline(arr[i]);
          if (item !== undefined) {
            items.push(item);
          }
        }
      }
    }
  } catch (e) {
    Log.w(LOG_TAG, 'manual deadlines load failed, fallback to empty');
  }
  manualDeadlinesCache = items;
  manualDeadlinesLoaded = true;
  return manualDeadlinesCache;
}

function parseManualDeadline(entry: Object): ManualDeadline | undefined {
  if (entry === null || typeof entry !== 'object') {
    return undefined;
  }
  const rec: Record<string, Object> = entry as Record<string, Object>;
  const id: Object | undefined = rec['id'];
  const title: Object | undefined = rec['title'];
  const date: Object | undefined = rec['date'];
  if (typeof id !== 'string' || typeof title !== 'string' || typeof date !== 'string') {
    return undefined;
  }
  const item: ManualDeadline = new ManualDeadline();
  item.id = id;
  item.title = title;
  item.date = date;
  item.time = strOr(rec['time']);
  item.course = strOr(rec['course']);
  item.note = strOr(rec['note']);
  item.createdAt = strOr(rec['createdAt']);
  return item;
}

async function persistManualDeadlines(items: ManualDeadline[]): Promise<void> {
  manualDeadlinesCache = items;
  manualDeadlinesLoaded = true;
  try {
    await PreferencesStorage.setJson<ManualDeadline[]>(StorageKeys.MANUAL_DEADLINES, items);
  } catch (e) {
    Log.w(LOG_TAG, 'manual deadlines persist failed len=%{public}d', items.length);
  }
}

/** 截止时间文本拆分（date：YYYY-MM-DD；time：HH:mm；纯日期默认 23:59） */
class DeadlineParts {
  date: string = '';
  time: string = '';
}

function splitDeadline(raw: string): DeadlineParts {
  const p: DeadlineParts = new DeadlineParts();
  const value: string = raw.trim();
  if (value.length === 0) {
    return p;
  }
  if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    p.date = value;
    p.time = '23:59';
    return p;
  }
  const match: RegExpExecArray | null = /^(\d{4}-\d{2}-\d{2})[T\s]+(\d{1,2}):(\d{2})/.exec(value);
  if (match !== null) {
    p.date = match[1];
    const hour: number = Number(match[2]);
    p.time = (hour < 10 ? '0' : '') + String(hour) + ':' + match[3];
    return p;
  }
  p.date = value;
  return p;
}

async function appendManualDeadline(title: string, deadline: string,
  courseName: string, note: string): Promise<ManualDeadline> {
  const items: ManualDeadline[] = await loadManualDeadlinesInternal();
  const parts: DeadlineParts = splitDeadline(deadline);
  const item: ManualDeadline = new ManualDeadline();
  item.id = 'md-' + Date.now() + '-' + Math.random().toString(36).substring(2, 8);
  item.title = title;
  item.date = parts.date;
  item.time = parts.time;
  item.course = courseName;
  item.note = note;
  item.createdAt = new Date().toISOString();
  items.push(item);
  await persistManualDeadlines(items);
  return item;
}

async function deleteManualDeadlineById(id: string): Promise<boolean> {
  const trimmed: string = id.trim();
  if (trimmed.length === 0) {
    return false;
  }
  const items: ManualDeadline[] = await loadManualDeadlinesInternal();
  const next: ManualDeadline[] = [];
  let removed: boolean = false;
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].id === trimmed) {
      removed = true;
    } else {
      next.push(items[i]);
    }
  }
  if (!removed) {
    return false;
  }
  await persistManualDeadlines(next);
  return true;
}

/** DDL 定位：id → 标题全等 → 标题包含（对齐 RN findManualDeadline） */
async function findManualDeadline(key: string): Promise<ManualDeadline | undefined> {
  const trimmed: string = key.trim();
  if (trimmed.length === 0) {
    return undefined;
  }
  const items: ManualDeadline[] = await loadManualDeadlinesInternal();
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].id === trimmed) {
      return items[i];
    }
  }
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].title === trimmed) {
      return items[i];
    }
  }
  for (let i: number = 0; i < items.length; i++) {
    if (items[i].title.includes(trimmed)) {
      return items[i];
    }
  }
  return undefined;
}

async function listManualDeadlinesInternal(): Promise<ManualDeadline[]> {
  const items: ManualDeadline[] = await loadManualDeadlinesInternal();
  const sorted: ManualDeadline[] = items.slice();
  sorted.sort((a: ManualDeadline, b: ManualDeadline): number =>
    (a.date + ' ' + a.time).localeCompare(b.date + ' ' + b.time));
  return sorted;
}

// ============================================================
// 写工具 1：添加自建 DDL
// ============================================================

function buildAddManualDeadlineTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'add_manual_deadline';
  t.title = '添加自建 DDL';
  t.description = '添加一条用户自建 DDL/待办。只写入本地，不影响老师布置的网络学堂作业。需要明确标题和截止时间，执行前会请用户确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"title":{"type":"string","description":"DDL 标题"},'
    + '"deadline":{"type":"string","description":"截止时间，如 2026-06-05 23:59 或 2026-06-05T23:59:00"},'
    + '"courseName":{"type":"string","description":"课程或分类，可选"},'
    + '"note":{"type":"string","description":"备注，可选"}'
    + '},"required":["title","deadline"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'learning.deadline.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => '添加 DDL：' + argString(args, 'title');
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    const p: ActionPreview = previewOf('add_manual_deadline', '添加自建 DDL',
      argString(args, 'deadline') + ' · ' + argString(args, 'title'),
      argString(args, 'title'), true);
    return p;
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const courseName: string = argString(args, 'courseName');
    const message: string = argString(args, 'deadline') + '\n' + argString(args, 'title') +
      (courseName.length > 0 ? '\n' + courseName : '');
    return confirmSpecOf('确认添加自建 DDL', message, false);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const idVal: Object | undefined = result['id'];
    if (typeof idVal === 'string' && idVal.length > 0) {
      const found: ManualDeadline | undefined = await findManualDeadline(idVal);
      if (found !== undefined) {
        return okVerify('已在自建 DDL 中确认');
      }
    }
    return failVerify('添加后未找到自建 DDL');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const title: string = argString(args, 'title').trim();
    const deadline: string = argString(args, 'deadline').trim();
    if (title.length === 0 || deadline.length === 0) {
      return failResult('请提供标题和截止时间');
    }
    const item: ManualDeadline = await appendManualDeadline(title, deadline,
      argString(args, 'courseName').trim(), argString(args, 'note').trim());
    return { 'ok': true, 'id': item.id, 'message': '已添加自建 DDL' };
  };
  return t;
}

// ============================================================
// 写工具 2：删除自建 DDL
// ============================================================

function buildRemoveManualDeadlineTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'remove_manual_deadline';
  t.title = '删除自建 DDL';
  t.description = '删除用户自己添加的 DDL。只能删除自建的 DDL，不能删除老师布置的作业。执行前会请用户确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"idOrTitle":{"type":"string","description":"自建 DDL id 或标题关键词"}'
    + '},"required":["idOrTitle"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'learning.deadline.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => '删除自建 DDL：' + argString(args, 'idOrTitle');
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    const found: ManualDeadline | undefined = await findManualDeadline(argString(args, 'idOrTitle'));
    if (found === undefined) {
      throw new Error('未找到匹配的自建 DDL：' + argString(args, 'idOrTitle'));
    }
    const deadlineText: string = found.time.length > 0 ? found.date + ' ' + found.time : found.date;
    return previewOf('remove_manual_deadline', '删除自建 DDL',
      deadlineText + ' · ' + found.title, found.title, true);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    return confirmSpecOf('确认删除自建 DDL',
      '将删除：' + argString(args, 'idOrTitle') + '\n（只能删除用户自建 DDL，不会删除老师布置的作业）', true);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const found: ManualDeadline | undefined = await findManualDeadline(argString(args, 'idOrTitle'));
    return found !== undefined ? failVerify('删除后该自建 DDL 仍存在') : okVerify('已确认自建 DDL 删除');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const key: string = argString(args, 'idOrTitle');
    const found: ManualDeadline | undefined = await findManualDeadline(key);
    if (found === undefined) {
      return failResult('未找到匹配的自建 DDL：' + key);
    }
    const ok: boolean = await deleteManualDeadlineById(found.id);
    if (!ok) {
      return failResult('删除失败');
    }
    const removed: Record<string, Object> = {};
    removed['title'] = found.title;
    removed['date'] = found.date;
    removed['time'] = found.time;
    removed['course'] = found.course;
    removed['note'] = found.note;
    return { 'ok': true, 'message': '已删除「' + found.title + '」', 'removed': removed };
  };
  return t;
}

// ============================================================
// 写工具 3：预约图书馆座位
// ============================================================

function buildBookSeatTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'book_library_seat';
  t.title = '预约图书馆座位';
  t.description = '预约一个图书馆座位（真实下单）。参数来自 find_available_seats（seatId、seatType）与 list_library_sections（sectionId）。执行前会请用户确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"seatId":{"type":"number"},'
    + '"seatType":{"type":"number"},'
    + '"sectionId":{"type":"number"},'
    + '"seatName":{"type":"string","description":"座位名，用于确认展示"},'
    + '"sectionName":{"type":"string","description":"分区名，用于确认展示"},'
    + '"date":{"type":"string","enum":["today","tomorrow"]}'
    + '},"required":["seatId","seatType","sectionId"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'campus.library.booking.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => {
    const seatName: string = argString(args, 'seatName');
    return '预约座位 ' + (seatName.length > 0 ? seatName : String(argNumber(args, 'seatId')));
  };
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const sectionId: number = argNumber(args, 'sectionId');
    if (Number.isNaN(sectionId)) {
      throw new Error('缺少分区 sectionId');
    }
    const seats: LibrarySeatInfo[] =
      await seatService.getLibrarySeatList(sectionId, dateChoiceFromArg(args['date']));
    const seatId: number = argNumber(args, 'seatId');
    let seat: LibrarySeatInfo | undefined = undefined;
    for (let i: number = 0; i < seats.length; i++) {
      if (seats[i].id === seatId) {
        seat = seats[i];
        break;
      }
    }
    if (seat === undefined) {
      throw new Error('未在该分区找到目标座位');
    }
    if (seat.status !== 1) {
      throw new Error('目标座位当前状态不是可预约：' + seatStatusLabel(seat.status));
    }
    const dateArg: Object | undefined = args['date'];
    const isTomorrow: boolean = typeof dateArg === 'string' && dateArg === 'tomorrow';
    const seatName: string = argString(args, 'seatName');
    const sectionName: string = argString(args, 'sectionName');
    const seatLabel: string = seatName.length > 0 ? seatName : seat.name;
    const summary: string = (sectionName.length > 0 ? sectionName + ' · ' : '') + seatLabel +
      '（' + (isTomorrow ? '明天' : '今天') + '）';
    return previewOf('book_library_seat', '预约图书馆座位', summary, seatLabel, true);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const dateArg: Object | undefined = args['date'];
    const isTomorrow: boolean = typeof dateArg === 'string' && dateArg === 'tomorrow';
    const seatName: string = argString(args, 'seatName');
    const sectionName: string = argString(args, 'sectionName');
    const seatLabel: string = seatName.length > 0 ? seatName : '座位 ' + String(argNumber(args, 'seatId'));
    const message: string = (sectionName.length > 0 ? sectionName + ' · ' : '') + seatLabel +
      '（' + (isTomorrow ? '明天' : '今天') + '）\n\n确认后将真实下单。';
    return confirmSpecOf('确认预约座位', message, false);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const okVal: Object | undefined = result['ok'];
    if (typeof okVal === 'boolean' && okVal) {
      const booking: Object | undefined = result['booking'];
      if (booking !== undefined) {
        return okVerify('已在预约记录中确认');
      }
      return okVerify('预约接口已返回成功，预约记录可能稍后刷新');
    }
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    try {
      const records: LibraryBookingRecord[] = await seatService.getLibraryBookingRecords();
      const seatLabel: string = argString(args, 'seatName');
      for (let i: number = 0; i < records.length; i++) {
        if (seatLabel.length > 0 && records[i].pos.includes(seatLabel)) {
          return okVerify('已在预约记录中确认');
        }
      }
    } catch (e) {
      // 记录查询失败：交由失败文案兜底
    }
    return failVerify('预约后未在记录中找到该座位');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const sectionId: number = argNumber(args, 'sectionId');
    const seatId: number = argNumber(args, 'seatId');
    const seatType: number = argNumber(args, 'seatType');
    if (Number.isNaN(sectionId) || Number.isNaN(seatId) || Number.isNaN(seatType)) {
      return failResult('缺少分区或座位参数（sectionId/seatId/seatType）');
    }
    const result: LibraryBookResult = await seatService.bookLibrarySeat(sectionId, seatId, seatType,
      dateChoiceFromArg(args['date']));
    if (result.status !== 0) {
      return failResult(result.msg.length > 0 ? result.msg : '预约失败');
    }
    const r: Record<string, Object> = { 'ok': true, 'message': '预约成功' };
    try {
      const records: LibraryBookingRecord[] = await seatService.getLibraryBookingRecords();
      const seatLabel: string = argString(args, 'seatName');
      for (let i: number = 0; i < records.length; i++) {
        if (seatLabel.length > 0 && records[i].pos.includes(seatLabel)) {
          const booking: Record<string, Object> = {};
          booking['id'] = records[i].id;
          booking['pos'] = records[i].pos;
          booking['time'] = records[i].time;
          booking['status'] = records[i].status;
          booking['cancelId'] = records[i].cancelId;
          r['booking'] = booking;
          break;
        }
      }
    } catch (e) {
      // 预约成功但记录查询失败：不阻断成功结果
    }
    return r;
  };
  return t;
}

// ============================================================
// 写工具 4：取消图书馆座位预约
// ============================================================

function buildCancelSeatBookingTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'cancel_library_seat_booking';
  t.title = '取消图书馆座位预约';
  t.description = '取消一个图书馆座位预约（真实操作）。bookingId 应优先使用 list_library_booking_records 返回的 cancelId。执行前会请用户确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"bookingId":{"type":"string","description":"预约取消 id，通常是记录里的 cancelId"},'
    + '"seatLabel":{"type":"string","description":"座位/位置描述，用于确认展示"},'
    + '"time":{"type":"string","description":"预约时间，用于确认展示"}'
    + '},"required":["bookingId"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'campus.library.booking.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => {
    const seatLabel: string = argString(args, 'seatLabel');
    return '取消座位预约 ' + (seatLabel.length > 0 ? seatLabel : argString(args, 'bookingId'));
  };
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const bookingId: string = argString(args, 'bookingId');
    const records: LibraryBookingRecord[] = await seatService.getLibraryBookingRecords();
    let record: LibraryBookingRecord | undefined = undefined;
    for (let i: number = 0; i < records.length; i++) {
      if (records[i].cancelId === bookingId || records[i].id === bookingId) {
        record = records[i];
        break;
      }
    }
    if (record === undefined) {
      throw new Error('未找到要取消的图书馆座位预约');
    }
    return previewOf('cancel_library_seat_booking', '取消图书馆座位预约',
      record.pos + ' · ' + record.time, record.pos, false);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const time: string = argString(args, 'time');
    const seatLabel: string = argString(args, 'seatLabel');
    const message: string = '将取消图书馆座位预约：' +
      (seatLabel.length > 0 ? seatLabel : argString(args, 'bookingId')) +
      (time.length > 0 ? '\n' + time : '') + '\n\n取消后如需使用座位，需要重新预约。';
    return confirmSpecOf('确认取消座位预约', message, true);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const bookingId: string = argString(args, 'bookingId');
    const records: LibraryBookingRecord[] = await seatService.getLibraryBookingRecords();
    for (let i: number = 0; i < records.length; i++) {
      if (records[i].cancelId === bookingId || records[i].id === bookingId) {
        return failVerify('取消后该预约仍在记录中');
      }
    }
    return okVerify('已确认预约记录消失');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const seatService: LibrarySeatService = SessionManager.getLibrarySeatService();
    const result: LibraryBookResult = await seatService.cancelLibraryBooking(argString(args, 'bookingId'));
    if (result.status === 0) {
      return okResult(result.msg.length > 0 ? result.msg : '已取消预约');
    }
    return failResult(result.msg.length > 0 ? result.msg : '取消失败');
  };
  return t;
}

// ============================================================
// 写工具 5：注销校园网设备
// ============================================================

async function findNetworkDevice(key: number): Promise<NetworkDevice | undefined> {
  const networkService: CampusNetworkService = SessionManager.getNetworkService();
  const snapshot: NetworkSnapshot = await networkService.getNetworkSnapshot();
  const devices: NetworkDevice[] = snapshot.devices;
  for (let i: number = 0; i < devices.length; i++) {
    if (devices[i].key === key) {
      return devices[i];
    }
  }
  return undefined;
}

function buildLogoutNetworkDeviceTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'logout_network_device';
  t.title = '注销校园网设备';
  t.description = '注销一个校园网在线设备。先用 list_network_devices 获取 key，再确认执行。不会尝试重新登录设备。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"key":{"type":"number","description":"list_network_devices 返回的设备 key"}'
    + '},"required":["key"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'campus.network.devices.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => '注销校园网设备 ' + String(argNumber(args, 'key'));
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    requireRealSession();
    const device: NetworkDevice | undefined = await findNetworkDevice(argNumber(args, 'key'));
    if (device === undefined) {
      throw new Error('未找到要注销的校园网设备');
    }
    const summary: string = device.authPermission + ' · ' + maskIdentifier(device.ip4) +
      ' · ' + maskIdentifier(device.mac);
    return previewOf('logout_network_device', '注销校园网设备', summary,
      maskIdentifier(device.ip4) + ' / ' + maskIdentifier(device.mac), false);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const message: string = preview !== undefined && preview.summary.length > 0 ? preview.summary :
      '将注销该在线设备。设备可能会立刻断网，需要用户自行重新认证。';
    return confirmSpecOf('确认注销校园网设备', message, true);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const device: NetworkDevice | undefined = await findNetworkDevice(argNumber(args, 'key'));
    return device !== undefined ? failVerify('注销后设备仍在线') : okVerify('已确认设备不在在线列表');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const networkService: CampusNetworkService = SessionManager.getNetworkService();
    const device: NetworkDevice | undefined = await findNetworkDevice(argNumber(args, 'key'));
    if (device === undefined) {
      return failResult('未找到要注销的设备');
    }
    const r = await networkService.logoutNetworkDevice(device.key, device.mac);
    return { 'ok': r.ok, 'message': r.message };
  };
  return t;
}

// ============================================================
// 写工具 6：预约研读间
// ============================================================

function buildBookLibraryRoomTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'book_library_room';
  t.title = '预约研读间';
  t.description = '预约一个研读间。必须来自 find_library_rooms 返回的 devId/kindId；startTime/endTime 为 HH:mm，date 为 today/tomorrow/YYYY-MM-DD。执行前会 dry-run 并确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"devId":{"type":"number"},'
    + '"kindId":{"type":"number"},'
    + '"date":{"type":"string","description":"today/tomorrow/YYYY-MM-DD"},'
    + '"startTime":{"type":"string","description":"HH:mm"},'
    + '"endTime":{"type":"string","description":"HH:mm"},'
    + '"devName":{"type":"string","description":"房间名，用于确认和验证"},'
    + '"memberAccNos":{"type":"array","items":{"type":"number"},"description":"search_library_room_members 返回的 accNo，可选"}'
    + '},"required":["devId","kindId","date","startTime","endTime"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'campus.library.room.booking.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => {
    const devName: string = argString(args, 'devName');
    return '预约研读间 ' + (devName.length > 0 ? devName : String(argNumber(args, 'devId')));
  };
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const date: string = normalizeDateArg(argString(args, 'date'), 0);
    const startMs: number = parseRoomTimeMs(toRoomTimestamp(date, argString(args, 'startTime')));
    const endMs: number = parseRoomTimeMs(toRoomTimestamp(date, argString(args, 'endTime')));
    if (Number.isNaN(startMs) || Number.isNaN(endMs) || !(startMs < endMs)) {
      throw new Error('研读间预约结束时间必须晚于开始时间');
    }
    const kindId: number = argNumber(args, 'kindId');
    const devId: number = argNumber(args, 'devId');
    if (Number.isNaN(kindId) || Number.isNaN(devId)) {
      throw new Error('缺少研读间参数 devId/kindId');
    }
    const resources: LibRoomResource[] = await roomService.getRoomResourceList(ymdFromIso(date), kindId);
    let room: LibRoomResource | undefined = undefined;
    for (let i: number = 0; i < resources.length; i++) {
      if (resources[i].devId === devId) {
        room = resources[i];
        break;
      }
    }
    if (room === undefined) {
      throw new Error('未找到目标研读间资源');
    }
    const minutes: number = Math.round((endMs - startMs) / 60000);
    if (room.minMinute > 0 && minutes < room.minMinute) {
      throw new Error('预约时长不能少于 ' + String(room.minMinute) + ' 分钟');
    }
    if (room.maxMinute > 0 && minutes > room.maxMinute) {
      throw new Error('预约时长不能超过 ' + String(room.maxMinute) + ' 分钟');
    }
    const memberAccNos: number[] = argNumberArray(args, 'memberAccNos');
    const userCount: number = 1 + memberAccNos.length;
    if (room.minUser > 0 && userCount < room.minUser) {
      throw new Error('该研读间至少需要 ' + String(room.minUser) + ' 人');
    }
    if (room.maxUser > 0 && userCount > room.maxUser) {
      throw new Error('该研读间最多允许 ' + String(room.maxUser) + ' 人');
    }
    for (let i: number = 0; i < room.usageList.length; i++) {
      const usageStartMs: number = parseRoomTimeMs(room.usageList[i].startText);
      const usageEndMs: number = parseRoomTimeMs(room.usageList[i].endText);
      if (!Number.isNaN(usageStartMs) && !Number.isNaN(usageEndMs)
        && startMs < usageEndMs && usageStartMs < endMs) {
        throw new Error('该时段已被占用');
      }
    }
    const summary: string = room.devName + ' · ' + date + ' ' +
      argString(args, 'startTime') + '-' + argString(args, 'endTime') + ' · ' + String(userCount) + ' 人';
    return previewOf('book_library_room', '预约研读间', summary, room.devName, true);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const message: string = (preview !== undefined && preview.summary.length > 0 ? preview.summary : '将预约研读间') +
      '\n\n预约占用公共资源，确认后会真实提交。';
    return confirmSpecOf('确认预约研读间', message, false);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const date: string = normalizeDateArg(argString(args, 'date'), 0);
    const startMs: number = parseRoomTimeMs(toRoomTimestamp(date, argString(args, 'startTime')));
    const endMs: number = parseRoomTimeMs(toRoomTimestamp(date, argString(args, 'endTime')));
    const records: LibRoomBookRecord[] = await roomService.getRoomBookingRecords();
    const uuidVal: Object | undefined = result['recordUuid'];
    const recordUuid: string = typeof uuidVal === 'string' ? uuidVal : '';
    const devName: string = argString(args, 'devName');
    for (let i: number = 0; i < records.length; i++) {
      const rec: LibRoomBookRecord = records[i];
      if (recordUuid.length > 0 && rec.uuid === recordUuid) {
        return okVerify('已在研读间预约记录中确认');
      }
      const beginMs: number = parseRoomTimeMs(rec.beginFull);
      const finishMs: number = parseRoomTimeMs(rec.endFull);
      if ((devName.length === 0 || rec.devName.includes(devName))
        && sameMinuteMs(beginMs, startMs) && sameMinuteMs(finishMs, endMs)) {
        return okVerify('已在研读间预约记录中确认');
      }
    }
    return failVerify('预约后未在研读间记录中找到该预约');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const date: string = normalizeDateArg(argString(args, 'date'), 0);
    const req: LibRoomBookRequest = new LibRoomBookRequest();
    req.devId = argNumber(args, 'devId');
    req.kindId = argNumber(args, 'kindId');
    req.date = date;
    req.startTime = argString(args, 'startTime');
    req.endTime = argString(args, 'endTime');
    req.memberAccNos = argNumberArray(args, 'memberAccNos');
    if (Number.isNaN(req.devId) || Number.isNaN(req.kindId)) {
      return failResult('缺少研读间参数 devId/kindId');
    }
    const result: LibRoomBookResult = await roomService.bookLibraryRoom(req);
    const r: Record<string, Object> = { 'ok': result.ok, 'message': result.message };
    if (!result.ok) {
      return r;
    }
    // 服务不返回 recordUuid → 按 devName + 起止时间配对回填（verify/取消入口用）
    try {
      const records: LibRoomBookRecord[] = await roomService.getRoomBookingRecords();
      const startMs: number = parseRoomTimeMs(toRoomTimestamp(date, req.startTime));
      const endMs: number = parseRoomTimeMs(toRoomTimestamp(date, req.endTime));
      const devName: string = argString(args, 'devName');
      for (let i: number = 0; i < records.length; i++) {
        const rec: LibRoomBookRecord = records[i];
        const beginMs: number = parseRoomTimeMs(rec.beginFull);
        const finishMs: number = parseRoomTimeMs(rec.endFull);
        if ((devName.length === 0 || rec.devName.includes(devName))
          && sameMinuteMs(beginMs, startMs) && sameMinuteMs(finishMs, endMs)) {
          r['recordUuid'] = rec.uuid;
          r['recordDevName'] = rec.devName;
          break;
        }
      }
    } catch (e) {
      // 预约成功但记录查询失败：不阻断成功结果（verify 有兜底文案）
    }
    return r;
  };
  return t;
}

// ============================================================
// 写工具 7：取消研读间预约
// ============================================================

function buildCancelLibraryRoomBookingTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'cancel_library_room_booking';
  t.title = '取消研读间预约';
  t.description = '取消研读间预约。先用 list_library_room_booking_records 获取 uuid，再确认执行。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"uuid":{"type":"string","description":"研读间预约 uuid"},'
    + '"roomLabel":{"type":"string","description":"房间/时间描述，用于确认展示"}'
    + '},"required":["uuid"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'campus.library.room.booking.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => {
    const roomLabel: string = argString(args, 'roomLabel');
    return '取消研读间预约 ' + (roomLabel.length > 0 ? roomLabel : argString(args, 'uuid'));
  };
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const uuid: string = argString(args, 'uuid');
    const records: LibRoomBookRecord[] = await roomService.getRoomBookingRecords();
    let record: LibRoomBookRecord | undefined = undefined;
    for (let i: number = 0; i < records.length; i++) {
      if (records[i].uuid === uuid) {
        record = records[i];
        break;
      }
    }
    if (record === undefined) {
      throw new Error('未找到要取消的研读间预约');
    }
    return previewOf('cancel_library_room_booking', '取消研读间预约',
      record.devName + ' · ' + record.beginText + '-' + record.endText, record.devName, false);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const message: string = (preview !== undefined && preview.summary.length > 0 ? preview.summary : '将取消研读间预约') +
      '\n\n取消后如需使用，需要重新预约。';
    return confirmSpecOf('确认取消研读间预约', message, true);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const uuid: string = argString(args, 'uuid');
    const records: LibRoomBookRecord[] = await roomService.getRoomBookingRecords();
    for (let i: number = 0; i < records.length; i++) {
      if (records[i].uuid === uuid) {
        return failVerify('取消后该研读间预约仍在记录中');
      }
    }
    return okVerify('已确认研读间预约记录消失');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    requireRealSession();
    const roomService: LibraryRoomService = SessionManager.getLibraryRoomService();
    const result: LibRoomBookResult = await roomService.cancelRoomBooking(argString(args, 'uuid'));
    return { 'ok': result.ok, 'message': result.message };
  };
  return t;
}

// ============================================================
// 写工具 8：添加个人备忘
// ============================================================

function buildAddPersonalEventTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'add_personal_event';
  t.title = '添加个人备忘';
  t.description = '为用户添加一条自建备忘日程（写入本地，与教务课表合并展示）。需明确日期、标题与时间段；执行前会请用户确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"date":{"type":"string","description":"日期 YYYY-MM-DD"},'
    + '"title":{"type":"string"},'
    + '"startTime":{"type":"string","description":"如 14:00"},'
    + '"endTime":{"type":"string","description":"如 16:00"},'
    + '"location":{"type":"string"},'
    + '"note":{"type":"string"}'
    + '},"required":["date","title","startTime","endTime"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'schedule.personal.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => '添加备忘：' + argString(args, 'title');
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    const date: string = normalizeDateString(argString(args, 'date'));
    const summary: string = date + ' ' + argString(args, 'startTime') + '-' +
      argString(args, 'endTime') + ' · ' + argString(args, 'title');
    return previewOf('add_personal_event', '添加个人备忘', summary, argString(args, 'title'), true);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    const location: string = argString(args, 'location');
    const message: string = argString(args, 'date') + ' ' + argString(args, 'startTime') + '-' +
      argString(args, 'endTime') + '\n' + argString(args, 'title') +
      (location.length > 0 ? '\n' + location : '');
    return confirmSpecOf('确认添加备忘', message, false);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const idVal: Object | undefined = result['id'];
    if (typeof idVal === 'string' && idVal.length > 0) {
      const found: AgentPersonalEvent | undefined = await findPersonalEvent(idVal);
      if (found !== undefined) {
        return okVerify('已在个人备忘中确认');
      }
    }
    return failVerify('添加后未找到个人备忘');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const date: string = normalizeDateString(argString(args, 'date'));
    const title: string = argString(args, 'title').trim();
    if (date.length === 0 || title.length === 0) {
      return failResult('请提供有效日期与标题');
    }
    const ev: AgentPersonalEvent = await appendPersonalEvent(date, title,
      argString(args, 'startTime').trim(), argString(args, 'endTime').trim(),
      argString(args, 'location').trim(), argString(args, 'note').trim());
    return { 'ok': true, 'id': ev.id, 'message': '已添加备忘' };
  };
  return t;
}

// ============================================================
// 写工具 9：删除个人备忘
// ============================================================

function buildRemovePersonalEventTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'remove_personal_event';
  t.title = '删除个人备忘';
  t.description = '删除一条用户自建备忘。用 list_personal_events 返回的 id，或标题关键词匹配。不能删除教务课表。执行前会请用户确认。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"idOrTitle":{"type":"string","description":"备忘 id 或标题关键词"}'
    + '},"required":["idOrTitle"]}';
  t.risk = ToolRisk.LOW;
  t.permission = 'schedule.personal.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => '删除备忘：' + argString(args, 'idOrTitle');
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    const found: AgentPersonalEvent | undefined = await findPersonalEvent(argString(args, 'idOrTitle'));
    if (found === undefined) {
      throw new Error('未找到匹配备忘：' + argString(args, 'idOrTitle'));
    }
    const summary: string = found.date + ' ' + found.startTime + '-' + found.endTime + ' · ' + found.title;
    return previewOf('remove_personal_event', '删除个人备忘', summary, found.title, true);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    return confirmSpecOf('确认删除备忘',
      '将删除：' + argString(args, 'idOrTitle') + '\n（仅删除自建备忘，不影响教务课表）', false);
  };
  t.verify = async (args: Record<string, Object>, result: Record<string, Object>): Promise<VerificationResult> => {
    const found: AgentPersonalEvent | undefined = await findPersonalEvent(argString(args, 'idOrTitle'));
    return found !== undefined ? failVerify('删除后该备忘仍存在') : okVerify('已确认备忘删除');
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const key: string = argString(args, 'idOrTitle');
    const found: AgentPersonalEvent | undefined = await findPersonalEvent(key);
    if (found === undefined) {
      return failResult('未找到匹配备忘：' + key);
    }
    const ok: boolean = await deletePersonalEventById(found.id);
    if (!ok) {
      return failResult('删除失败');
    }
    return { 'ok': true, 'message': '已删除「' + found.title + '」', 'removed': personalEventSummary(found) };
  };
  return t;
}

// ============================================================
// 写工具 10：更新长期偏好记忆
// ============================================================

function buildRememberPreferenceTool(): AgentToolDef {
  const t: AgentToolDef = new AgentToolDef();
  t.name = 'remember_preference';
  t.title = '更新长期偏好记忆';
  t.description = '记住用户的长期偏好，便于后续个性化（如常用图书馆/分区、默认电费充值额、关注的课程）。当用户表达明确偏好时调用。';
  t.parametersJson = '{"type":"object","properties":{'
    + '"favoriteLibrary":{"type":"string"},'
    + '"favoriteSection":{"type":"string"},'
    + '"defaultRechargeAmount":{"type":"number"},'
    + '"watchedCourses":{"type":"array","items":{"type":"string"}},'
    + '"note":{"type":"string","description":"其它要记住的自由偏好"}'
    + '}}';
  t.risk = ToolRisk.LOW;
  t.permission = 'ai.memory.write';
  t.requiresConfirmation = true;
  t.summarize = (args: Record<string, Object>): string => '更新个性化记忆';
  t.dryRun = async (args: Record<string, Object>): Promise<ActionPreview> => {
    return previewOf('remember_preference', '更新长期偏好记忆',
      JSON.stringify(args), '本机 AI 记忆', true);
  };
  t.confirmPrompt = (args: Record<string, Object>, preview: ActionPreview | undefined): ConfirmationSpec => {
    return confirmSpecOf('确认更新记忆', '将记住这些长期偏好：' + JSON.stringify(args), false);
  };
  t.run = async (args: Record<string, Object>): Promise<Record<string, Object>> => {
    const favoriteLibrary: string = argString(args, 'favoriteLibrary').trim();
    if (favoriteLibrary.length > 0) {
      await AIMemoryStore.remember('favoriteLibrary', favoriteLibrary);
    }
    const favoriteSection: string = argString(args, 'favoriteSection').trim();
    if (favoriteSection.length > 0) {
      await AIMemoryStore.remember('favoriteSection', favoriteSection);
    }
    const amount: number = argNumber(args, 'defaultRechargeAmount');
    if (!Number.isNaN(amount)) {
      await AIMemoryStore.remember('defaultRechargeAmount', String(amount));
    }
    const watchedCourses: string[] = argStringArray(args, 'watchedCourses');
    if (watchedCourses.length > 0) {
      await AIMemoryStore.remember('watchedCourses', watchedCourses.join('、'));
    }
    const note: string = argString(args, 'note').trim();
    if (note.length > 0) {
      await AIMemoryStore.remember('notes', note);
    }
    return okResult('已更新个性化记忆');
  };
  return t;
}

// ============================================================
// 注册表（AgentTools 合并调用）
// ============================================================

export class AgentWriteTools {
  /** 全部可逆写工具（10 个；每次调用构造新实例，避免共享可变状态） */
  static list(): AgentToolDef[] {
    return [
      buildAddManualDeadlineTool(),
      buildRemoveManualDeadlineTool(),
      buildAddPersonalEventTool(),
      buildRemovePersonalEventTool(),
      buildRememberPreferenceTool(),
      buildBookSeatTool(),
      buildCancelSeatBookingTool(),
      buildBookLibraryRoomTool(),
      buildCancelLibraryRoomBookingTool(),
      buildLogoutNetworkDeviceTool(),
    ];
  }

  /** 自建 DDL 列表（按截止时间排序；AgentService.buildContext 合并待办用） */
  static async listManualDeadlines(): Promise<ManualDeadline[]> {
    return listManualDeadlinesInternal();
  }

  /** 按日期区间列个人备忘（AgentTools 读工具 get_week_schedule / list_personal_events 用） */
  static async listPersonalEventsInRange(startDate: string, endDate: string): Promise<AgentPersonalEvent[]> {
    return listPersonalEventsInRange(startDate, endDate);
  }
}
