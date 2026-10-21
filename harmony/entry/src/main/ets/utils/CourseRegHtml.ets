/**
 * ============================================================================
 * CourseRegHtml — 选课系统 HTML 解析原语（纯函数，无网络/状态依赖）
 * ============================================================================
 *
 * 【来源】RN src/services/campus/courseRegistration.ts（node-html-parser 逻辑
 * 改写为正则实现，RD-03）；协议与解析索引与 RN 保持一致。
 *
 * 【容错约定】缺列行跳过、数字解析失败按 0、空结果返回空列表/空串，
 * 不抛异常；坏行计数由调用方（服务层）记日志。
 *
 * 【判定标记】（tsinghua-auth 技能警告：禁止用泛化的"用户未登录"字样判定
 * roam 失败——它们会合法出现在子系统页面 JS 里；此处三个标记仅用于
 * 响应归一与落点检查，语义见各常量注释）。
 * ============================================================================
 */
import {
  CrSemester,
  SelectedCourse,
  CrRemainingInfo,
  CrRemainingSearchResult,
} from '../domain/CourseRegTypes';

/** WebVPN 登录页标题（RN assertCrHtml 标记：落在 WebVPN 登录页 = 未登录） */
export const CR_WEBVPN_TITLE_MARK: string = '<title>清华大学WebVPN</title>';
/** ID 登录页公钥元素标记（最权威的"落在登录页"标记）。取裸 id 值以兼容
 *  单/双引号两种属性写法，与项目既有 sm2publicKey 判定一致。 */
export const CR_SM2_MARK: string = 'sm2publicKey';
/** 选课系统会话超时标记（RN assertCrHtml 第二标记） */
export const CR_TIMEOUT_MARK: string = '用户登陆超时或访问内容不存在';

/** 常用 HTML 实体解码（&amp; 最后处理，避免二次解码） */
export function decodeHtmlEntities(value: string): string {
  let out: string = value.replace(/&nbsp;/g, ' ');
  out = out.replace(/&lt;/g, '<');
  out = out.replace(/&gt;/g, '>');
  out = out.replace(/&quot;/g, '"');
  out = out.replace(/&#39;/g, "'");
  out = out.replace(/&#(\d+);/g, (match: string, code: string): string => {
    const n: number = Number(code);
    return Number.isFinite(n) && n > 0 && n < 0x110000 ? String.fromCharCode(n) : match;
  });
  out = out.replace(/&amp;/g, '&');
  return out;
}

/** 去 HTML 标签 + 实体解码 + 空白压缩（纯文本提取） */
export function stripHtml(html: string): string {
  return decodeHtmlEntities(html.replace(/<[^>]+>/g, ' ')).replace(/\s+/g, ' ').trim();
}

/**
 * 敏感信息脱敏（FR-012，纯函数，供服务层 sanitizeDetail 与自测使用）：
 *   - URL → `<url>`；
 *   - token= / XSRF-TOKEN= 赋值 → `<redacted>`；
 *   - 32+ 位十六进制串（webvpn/表单 token 形态）→ `<token>`；
 *   - 10 位数字（学号形态）→ `<id>`（安全优先的过度脱敏：10 位时间戳
 *     等同样会被掩盖；课程号为 8 位含字母形态，不受影响）。
 */
export function redactSensitive(text: string): string {
  let out: string = text.replace(/https?:\/\/\S+/gi, '<url>');
  out = out.replace(/(token\s*=\s*)\S+/gi, '$1<redacted>');
  out = out.replace(/\b[0-9a-f]{32,}\b/gi, '<token>');
  out = out.replace(/\b\d{10}\b/g, '<id>');
  return out;
}

/**
 * 提取表单令牌：查找 `<input … name="token" … value="…">` 的 value。
 * 属性顺序无关（RN querySelector('input[name=token]') 等价语义）；
 * 未找到返回空串（调用方映射 NO_FORM_TOKEN）。
 */
export function extractFormToken(html: string): string {
  const tagRe: RegExp = /<input\b[^>]*>/gi;
  let tag: RegExpExecArray | null = tagRe.exec(html);
  while (tag !== null) {
    const tagSrc: string = tag[0];
    const nameMatch: RegExpExecArray | null = /name\s*=\s*["']token["']/i.exec(tagSrc);
    if (nameMatch !== null) {
      const valueMatch: RegExpExecArray | null = /value\s*=\s*["']([^"']*)["']/i.exec(tagSrc);
      if (valueMatch !== null && valueMatch.length >= 2) {
        return decodeHtmlEntities(valueMatch[1]);
      }
      return '';
    }
    tag = tagRe.exec(html);
  }
  return '';
}

/**
 * 提取写操作结果消息：匹配 `showMsg("…");`（RN 正则原样）。
 * 缺失返回空串（服务层映射 PARSE——响应里连结果脚本都没有）。
 */
export function extractShowMsg(html: string): string {
  const m: RegExpExecArray | null = /showMsg\("(.+?)"\);/.exec(html);
  if (m !== null && m.length >= 2) {
    return decodeHtmlEntities(m[1]);
  }
  return '';
}

/**
 * 登录页/会话失效页判定（粗粒度；服务层按三个标记细分错误码）：
 * WebVPN 标题 / sm2publicKey / "用户登陆超时或访问内容不存在"。
 */
export function isLoginPage(html: string): boolean {
  return html.indexOf(CR_WEBVPN_TITLE_MARK) >= 0
    || html.indexOf(CR_SM2_MARK) >= 0
    || html.indexOf(CR_TIMEOUT_MARK) >= 0;
}

/**
 * 主页面基础学期提取（RN getCrAvailableSemesters 正则原样）：
 * 匹配 `m=showTree&p_xnxq=dddd-dddd-d` 形如 2024-2025-2；缺失返回空串
 * （服务层映射 NO_SEMESTER）。
 */
export function extractBaseSemester(mainHtml: string): string {
  const m: RegExpExecArray | null = /m=showTree&p_xnxq=(\d\d\d\d-\d\d\d\d-\d)/.exec(mainHtml);
  if (m !== null && m.length >= 2) {
    return m[1];
  }
  return '';
}

/**
 * 学期解析（US1，RN getCrAvailableSemesters 移植）：
 *   1. 主页面提取基础学期（缺失 → 返回空列表，服务层映射 NO_SEMESTER）；
 *   2. 树页面解析全部 `<option value="…">文本</option>`（属性顺序无关）；
 *   3. 丢弃空 value 或空名称选项（RN 保留 {id:''} 占位；按 T03 任务口径丢弃）；
 *      全部为空时返回空列表，由服务层映射 NO_SEMESTER。
 */
export function parseSemesters(mainHtml: string, treeHtml: string): CrSemester[] {
  const base: string = extractBaseSemester(mainHtml);
  if (base.length === 0) {
    return [];
  }
  const result: CrSemester[] = [];
  const optionRe: RegExp = /<option\b[^>]*value\s*=\s*["']([^"']*)["'][^>]*>([^<]*)<\/option>/gi;
  let m: RegExpExecArray | null = optionRe.exec(treeHtml);
  while (m !== null) {
    const id: string = decodeHtmlEntities(m[1]).trim();
    const name: string = decodeHtmlEntities(m[2]).replace(/\s+/g, ' ').trim();
    if (id.length > 0 && name.length > 0) {
      const semester: CrSemester = new CrSemester();
      semester.id = id;
      semester.name = name;
      result.push(semester);
    }
    m = optionRe.exec(treeHtml);
  }
  return result;
}

/** class 含 trr2 的元素定位（RN '.trr2' 选择器：行元素或行容器均匹配） */
interface CrTrR2Element {
  tagName: string;
  tagStart: number;
  contentStart: number;
}

/** 收集全部 class~="trr2" 的元素（trr2 行/容器），按文档序返回 */
function collectTrR2Elements(html: string): CrTrR2Element[] {
  const elements: CrTrR2Element[] = [];
  const openRe: RegExp = /<(\w+)\b[^>]*\bclass\s*=\s*["'][^"']*\btrr2\b[^"']*["'][^>]*>/gi;
  let m: RegExpExecArray | null = openRe.exec(html);
  while (m !== null) {
    const el: CrTrR2Element = {
      tagName: m[1].toLowerCase(),
      tagStart: m.index,
      contentStart: m.index + m[0].length,
    };
    elements.push(el);
    m = openRe.exec(html);
  }
  return elements;
}

/**
 * 查找元素自身闭合标签位置（大小写不敏感 + 同名标签嵌套深度感知）：
 * 从 fromIdx 起扫描 `<tag` 开标签与 `</tag>` 闭标签，深度归零处即闭合位置
 * （嵌套同名标签——如 table 套 table——不会被内层闭合标签提前截断）。
 * 找不到（无闭合标签或深度永远 >0）返回 -1。tagName 来自 collectTrR2Elements
 * 的 `\w+` 捕获并已 toLowerCase，可安全拼入正则。
 */
function findSelfCloseEnd(html: string, tagName: string, fromIdx: number): number {
  const tagRe: RegExp = new RegExp('<(\\/?)' + tagName + '\\b', 'gi');
  tagRe.lastIndex = fromIdx;
  let depth: number = 1;
  let m: RegExpExecArray | null = tagRe.exec(html);
  while (m !== null) {
    if (m[1] === '/') {
      depth--;
      if (depth === 0) {
        return m.index;
      }
    } else {
      depth++;
    }
    m = tagRe.exec(html);
  }
  return -1;
}

/**
 * trr2 元素的内容片段边界：优先取元素自身闭合标签（`</tr>`/`</tbody>`/
 * `</table>`/`</div>` …，大小写不敏感、嵌套深度感知），避免容器分支把
 * 闭合标签之后的无关表格当数据；找不到闭合标签或越界（如闭合标签在
 * 下一 trr2 元素之后）时回退下一 trr2 元素起点。
 */
function trR2SegmentEnd(html: string, el: CrTrR2Element, nextStart: number): number {
  const closeIdx: number = findSelfCloseEnd(html, el.tagName, el.contentStart);
  if (closeIdx >= 0 && closeIdx < nextStart) {
    return closeIdx;
  }
  return nextStart;
}

/** 收集片段内全部 `<td>` 单元格文本（'.tdd2, td' 并集；实体解码 + 空白压缩） */
function collectRowCells(segment: string): string[] {
  const tds: string[] = [];
  const tdRe: RegExp = /<td\b[^>]*>([\s\S]*?)<\/td>/gi;
  let tdMatch: RegExpExecArray | null = tdRe.exec(segment);
  while (tdMatch !== null) {
    tds.push(stripHtml(tdMatch[1]));
    tdMatch = tdRe.exec(segment);
  }
  return tds;
}

/** 已选课程志愿文本 → 数字（"第一志愿"→1、"第二志愿"→2、其他→3，RN 原样） */
export function willStringToNumber(will: string): number {
  if (will === '第一志愿') {
    return 1;
  }
  if (will === '第二志愿') {
    return 2;
  }
  return 3;
}

/**
 * 已选页结构识别（FR-019：区分"合法空结果"与"非预期页面"）。
 * 必须命中以下强结构标记之一才视为预期的已选页：
 *   class~="trr2" / yxSearchTab / tokenPriFlag。
 * `name="token"` 只作辅助信号（单独出现不充分——CR 布局内的错误页也可能
 * 带 token 表单）；服务端错误页/网关错误页等 200 HTML 不含强标记 →
 * recognized=false，由服务层抛 PARSE，不得当成空列表成功返回。
 */
export function isSelectedPage(html: string): boolean {
  if (/<\w+\b[^>]*\bclass\s*=\s*["'][^"']*\btrr2\b[^"']*["']/i.test(html)) {
    return true;
  }
  return html.indexOf('yxSearchTab') >= 0 || html.indexOf('tokenPriFlag') >= 0;
}

/** 已选页解析结果（FR-019：recognized=false 表示响应不是预期的已选页结构） */
export class SelectedParseResult {
  courses: SelectedCourse[] = [];
  /** 坏行计数（<9 列被跳过的数据行；不含表头 th 行） */
  skipped: number = 0;
  recognized: boolean = false;
}

/**
 * 已选课程解析（US2，RN getSelectedCourses 移植）。
 * RN 选择器 '.trr2 tbody tr, .trr2' 覆盖两种页面结构，正则实现等价展开：
 *   - class=trr2 的 `<tr>` → 自身即一行；
 *   - class=trr2 的容器（table/tbody 等）→ 内部全部 `<tr>` 为行；
 *     容器本身不再当行解析（RN 字面语义下容器会产出一条扁平坏记录，
 *     此处按"含 <tr> 的容器不自行成行"修正，两种结构均无重复/坏行）。
 * 单元格取行内全部 `<td>`（'.tdd2, td' 并集）；<9 列跳过（RN 原样）；
 * 列索引：type=1 will=2 id=3 name=4 seq=5 time=6 teacher=7 credit=8 secondary=9。
 */
export function parseSelected(html: string): SelectedCourse[] {
  return parseSelectedPage(html).courses;
}

/** 已选页完整解析（识别信号 + 行解析 + 坏行计数，FR-019） */
export function parseSelectedPage(html: string): SelectedParseResult {
  const parsed: SelectedParseResult = new SelectedParseResult();
  parsed.recognized = isSelectedPage(html);
  const elements: CrTrR2Element[] = collectTrR2Elements(html);
  for (let i: number = 0; i < elements.length; i++) {
    const el: CrTrR2Element = elements[i];
    const nextStart: number = i + 1 < elements.length ? elements[i + 1].tagStart : html.length;
    const endIdx: number = trR2SegmentEnd(html, el, nextStart);
    const segment: string = html.substring(el.contentStart, endIdx);
    if (el.tagName === 'tr') {
      if (!appendSelectedRow(segment, parsed.courses)) {
        parsed.skipped++;
      }
    } else {
      const rowRe: RegExp = /<tr\b[^>]*>([\s\S]*?)<\/tr>/gi;
      let rowMatch: RegExpExecArray | null = rowRe.exec(segment);
      let foundRow: boolean = false;
      while (rowMatch !== null) {
        // 纯 th 表头行不是数据行，直接忽略且不计坏行（大小写不敏感：<td/<TD 均 gate）
        if (/<td\b/i.test(rowMatch[1])) {
          foundRow = true;
          if (!appendSelectedRow(rowMatch[1], parsed.courses)) {
            parsed.skipped++;
          }
        }
        rowMatch = rowRe.exec(segment);
      }
      if (!foundRow && /<td\b/i.test(segment)) {
        // trr2 元素自身不含 <tr> 但含 <td>：按单行兜底（'.trr2' 自匹配语义）
        if (!appendSelectedRow(segment, parsed.courses)) {
          parsed.skipped++;
        }
      }
    }
  }
  return parsed;
}

/** 解析单个行片段的单元格并追加记录；<9 列跳过（返回 false），数字解析失败按 0 */
function appendSelectedRow(rowHtml: string, out: SelectedCourse[]): boolean {
  const tds: string[] = collectRowCells(rowHtml);
  if (tds.length < 9) {
    return false;
  }
  const course: SelectedCourse = new SelectedCourse();
  course.type = tds[1];
  course.will = willStringToNumber(tds[2]);
  course.id = tds[3];
  course.name = tds[4];
  course.seq = tds[5];
  course.time = tds[6];
  course.teacher = tds[7];
  const creditNum: number = Number(tds[8]);
  course.credit = Number.isFinite(creditNum) ? creditNum : 0;
  course.secondary = tds.length >= 10 && tds[9] === '是';
  out.push(course);
  return true;
}

/**
 * 课余量搜索页结构识别（FR-019：区分"合法空结果"与"非预期页面"）。
 * 必须命中以下强结构标记之一才视为预期的搜索结果页（合法空结果页含
 * p.yeM 分页脚注"共 0 条记录"，必然命中）：
 *   class~="yeM"（p.yeM 分页脚注）/ class~="trr2"。
 * `pathContent`/"课余量" 只作辅助信号（单独出现不充分——CR 布局内的
 * 错误页也可能回显 pathContent 隐藏域）；未命中强标记的 200 HTML →
 * recognized=false，由服务层抛 PARSE，不得当成空成功。
 */
export function isRemainingPage(html: string): boolean {
  if (/<p\b[^>]*\bclass\s*=\s*["'][^"']*\byeM\b[^"']*["']/i.test(html)) {
    return true;
  }
  return /<\w+\b[^>]*\bclass\s*=\s*["'][^"']*\btrr2\b[^"']*["']/i.test(html);
}

/** 课余量搜索页解析结果（FR-019：recognized=false 表示响应不是预期的搜索页） */
export class RemainingParseResult {
  result: CrRemainingSearchResult = new CrRemainingSearchResult();
  /** 坏行计数（<6 列被跳过的 trr2 行） */
  skipped: number = 0;
  recognized: boolean = false;
}

/**
 * 课余量搜索结果解析（US3，RN searchCrRemaining 移植）：
 *   - 分页脚注 `p.yeM`：去半角逗号后匹配
 *     `第 d 页 / 共 d 页（共 d 条记录）`；缺脚注/不匹配回退 1/1/0；
 *   - 行：`.trr2` 元素各为一行，行内全部 `<td>` 为单元格；
 *     <6 列跳过（计入 skipped）；≥8 列含队列列（queue=5 teacher=6 time=7），
 *     否则 teacher=5 time=6（恰好 6 列时 time 越界保护为空串）、queue=0；
 *     列索引：id=0 seq=1 name=2 capacity=3 remaining=4；数字解析失败按 0。
 */
export function parseRemaining(html: string): CrRemainingSearchResult {
  return parseRemainingPage(html).result;
}

/** 课余量搜索页完整解析（识别信号 + 行解析 + 坏行计数，FR-019） */
export function parseRemainingPage(html: string): RemainingParseResult {
  const parsed: RemainingParseResult = new RemainingParseResult();
  parsed.recognized = isRemainingPage(html);
  const result: CrRemainingSearchResult = parsed.result;
  const footerRe: RegExp = /<p\b[^>]*\bclass\s*=\s*["'][^"']*\byeM\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i;
  const footerMatch: RegExpExecArray | null = footerRe.exec(html);
  if (footerMatch !== null && footerMatch.length >= 2) {
    const footerText: string = stripHtml(footerMatch[1]).replace(/,/g, '');
    const pageRe: RegExp = /第\s*(\d+)\s*页\s*\/\s*共\s*(\d+)\s*页（共\s*(\d+)\s*条记录）/;
    const pageMatch: RegExpExecArray | null = pageRe.exec(footerText);
    if (pageMatch !== null && pageMatch.length >= 4) {
      const currNum: number = Number(pageMatch[1]);
      const totalNum: number = Number(pageMatch[2]);
      const countNum: number = Number(pageMatch[3]);
      result.currPage = Number.isFinite(currNum) ? currNum : 1;
      result.totalPage = Number.isFinite(totalNum) ? totalNum : 1;
      result.totalCount = Number.isFinite(countNum) ? countNum : 0;
    }
  }
  const elements: CrTrR2Element[] = collectTrR2Elements(html);
  for (let i: number = 0; i < elements.length; i++) {
    const el: CrTrR2Element = elements[i];
    const nextStart: number = i + 1 < elements.length ? elements[i + 1].tagStart : html.length;
    const endIdx: number = trR2SegmentEnd(html, el, nextStart);
    const tds: string[] = collectRowCells(html.substring(el.contentStart, endIdx));
    if (tds.length < 6) {
      parsed.skipped++;
      continue;
    }
    const hasQueue: boolean = tds.length >= 8;
    const info: CrRemainingInfo = new CrRemainingInfo();
    info.id = tds[0];
    const seqNum: number = Number(tds[1]);
    info.seq = Number.isFinite(seqNum) ? seqNum : 0;
    info.name = tds[2];
    const capNum: number = Number(tds[3]);
    info.capacity = Number.isFinite(capNum) ? capNum : 0;
    const remNum: number = Number(tds[4]);
    info.remaining = Number.isFinite(remNum) ? remNum : 0;
    if (hasQueue) {
      const queueNum: number = Number(tds[5]);
      info.queue = Number.isFinite(queueNum) ? queueNum : 0;
      info.teacher = tds[6];
      info.time = tds[7];
    } else {
      // 恰好 6 列（无队列列）时 time 列不存在：越界保护为空串
      info.queue = 0;
      info.teacher = tds.length > 5 ? tds[5] : '';
      info.time = tds.length > 6 ? tds[6] : '';
    }
    result.courses.push(info);
  }
  return parsed;
}
