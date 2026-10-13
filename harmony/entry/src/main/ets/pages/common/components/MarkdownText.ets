/**
 * ============================================================================
 * MarkdownText — 纯 ArkUI 的轻量 Markdown 渲染组件
 * ============================================================================
 *
 * 【用途】AI 助手回复（通常为 Markdown 文本）的富文本展示。
 *   纯 ArkUI 实现：无脚本、无 Web 注入；任何输入只经过"解析 → 组件树"，
 *   不存在执行面，恶意/畸形 Markdown 最多按字面量渲染，不会抛错。
 *
 * 【块级支持】标题(#~######)、围栏代码块(```)、引用(>)、有序/无序列表、
 *   水平分割线、段落（逐行渲染，天然支持换行）。
 * 【行内支持】**粗体**、*斜体*、`行内代码`、[链接文本](url)（仅渲染链接
 *   文本，不携带可点击 URL）、普通文本。不做嵌套行内解析（如粗体内代码）。
 *
 * 【刷新机制】解析在渲染期进行；ForEach key 以内容指纹（长度+哈希）加盐，
 *   内容任何变化（含流式追加）都强制整树重建，规避块结构相同时 key 撞车
 *   导致的陈旧渲染。
 * ============================================================================
 */
import { Theme, Radius } from '../../Theme';

/** 代码块背景（深色底，与浅色气泡区分） */
const MD_CODE_BG: string = '#1E1E26';
/** 代码块文字 */
const MD_CODE_TEXT: string = '#E8E8EE';
/** 行内代码文字色 */
const MD_INLINE_CODE: string = '#B3261E';
/** 引用左侧竖条 */
const MD_QUOTE_BAR: string = 'rgba(124,92,250,0.45)';

/** 块类型 */
export class MdBlockType {
  static readonly PARAGRAPH: string = 'paragraph';
  static readonly HEADING: string = 'heading';
  static readonly CODE: string = 'code';
  static readonly QUOTE: string = 'quote';
  static readonly LIST: string = 'list';
  static readonly RULE: string = 'rule';
}

/** 列表项（text 为行内 Markdown；orderNum 为有序序号） */
export class MdListItem {
  text: string = '';
  orderNum: number = 0;
}

/** 块级节点 */
export class MdBlock {
  type: string = MdBlockType.PARAGRAPH;
  /** 标题级别（HEADING：1-6；其余 0） */
  level: number = 0;
  /** 行内容（PARAGRAPH/HEADING：单元素；QUOTE：剥离 > 后逐行；CODE：原始代码行） */
  lines: string[] = [];
  /** 列表项（仅 LIST） */
  items: MdListItem[] = [];
  /** 有序列表标记 */
  ordered: boolean = false;
}

/** 行内片段类型 */
export class MdSpanKind {
  static readonly TEXT: string = 'text';
  static readonly BOLD: string = 'bold';
  static readonly ITALIC: string = 'italic';
  static readonly CODE: string = 'code';
  static readonly LINK: string = 'link';
}

/** 行内片段 */
export class MdSpan {
  kind: string = MdSpanKind.TEXT;
  text: string = '';
}

/** 列表项解析结果（项 + 是否有序） */
class ParsedListItem {
  item: MdListItem = new MdListItem();
  ordered: boolean = false;
}

/**
 * Markdown 解析器（块级 + 行内，纯静态方法）。
 * 所有解析对任意输入安全：未闭合语法按字面量原样保留，不抛错、不越界。
 */
export class MdParser {
  /** 块级解析：Markdown 文本 → 块序列 */
  static parseBlocks(content: string): MdBlock[] {
    const lines: string[] = content.split('\n');
    const blocks: MdBlock[] = [];
    let i: number = 0;
    while (i < lines.length) {
      const trimmed: string = lines[i].trim();
      // 1. 围栏代码块：``` 开头，至闭合 ``` 或文本结尾
      if (MdParser.isCodeFence(trimmed)) {
        const codeLines: string[] = [];
        i++;
        while (i < lines.length && !MdParser.isCodeFence(lines[i].trim())) {
          codeLines.push(lines[i]);
          i++;
        }
        if (i < lines.length) {
          i++; // 跳过闭合围栏
        }
        const code: MdBlock = new MdBlock();
        code.type = MdBlockType.CODE;
        code.lines = codeLines.length > 0 ? codeLines : [''];
        blocks.push(code);
        continue;
      }
      // 2. 空行：块分隔，跳过
      if (trimmed.length === 0) {
        i++;
        continue;
      }
      // 3. 水平分割线：--- / *** / ___（≥3 个相同字符）
      if (MdParser.isRuleLine(trimmed)) {
        const rule: MdBlock = new MdBlock();
        rule.type = MdBlockType.RULE;
        blocks.push(rule);
        i++;
        continue;
      }
      // 4. 标题：1-6 个 # 后跟空格（或行尾）
      const headingLevel: number = MdParser.headingLevelOf(trimmed);
      if (headingLevel > 0) {
        let headText: string = trimmed.substring(headingLevel);
        if (headText.charAt(0) === ' ') {
          headText = headText.substring(1);
        }
        const head: MdBlock = new MdBlock();
        head.type = MdBlockType.HEADING;
        head.level = headingLevel;
        head.lines = [headText.trim()];
        blocks.push(head);
        i++;
        continue;
      }
      // 5. 引用：连续 > 行合并为一块
      if (trimmed.charAt(0) === '>') {
        const quoteLines: string[] = [];
        while (i < lines.length) {
          const t: string = lines[i].trim();
          if (t.charAt(0) !== '>') {
            break;
          }
          let inner: string = t.substring(1);
          if (inner.charAt(0) === ' ') {
            inner = inner.substring(1);
          }
          quoteLines.push(inner.trim());
          i++;
        }
        const quote: MdBlock = new MdBlock();
        quote.type = MdBlockType.QUOTE;
        quote.lines = quoteLines;
        blocks.push(quote);
        continue;
      }
      // 6. 列表：连续同型（有序/无序）列表项合并为一块
      const first: ParsedListItem | undefined = MdParser.parseListItem(trimmed);
      if (first !== undefined) {
        const list: MdBlock = new MdBlock();
        list.type = MdBlockType.LIST;
        list.ordered = first.ordered;
        list.items.push(first.item);
        i++;
        while (i < lines.length) {
          const next: ParsedListItem | undefined = MdParser.parseListItem(lines[i].trim());
          if (next === undefined || next.ordered !== list.ordered) {
            break;
          }
          list.items.push(next.item);
          i++;
        }
        blocks.push(list);
        continue;
      }
      // 7. 段落：其余非空行逐行成块（天然支持换行）
      const para: MdBlock = new MdBlock();
      para.type = MdBlockType.PARAGRAPH;
      para.lines = [trimmed];
      blocks.push(para);
      i++;
    }
    return blocks;
  }

  /** 行内解析：文本 → 片段序列（`code` 优先于 *italic*；**bold** 优先于 *italic*） */
  static parseInline(text: string): MdSpan[] {
    const spans: MdSpan[] = [];
    let buffer: string = '';
    let i: number = 0;
    while (i < text.length) {
      const c: string = text.charAt(i);
      // 行内代码：`...`（须非空且闭合）
      if (c === '`') {
        const end: number = text.indexOf('`', i + 1);
        if (end > i + 1) {
          MdParser.appendText(spans, buffer);
          buffer = '';
          spans.push(MdParser.spanOf(MdSpanKind.CODE, text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
      }
      // 粗体：**...**（先于斜体判定，须非空且闭合）
      if (c === '*' && text.charAt(i + 1) === '*') {
        const end: number = text.indexOf('**', i + 2);
        if (end > i + 2) {
          MdParser.appendText(spans, buffer);
          buffer = '';
          spans.push(MdParser.spanOf(MdSpanKind.BOLD, text.substring(i + 2, end)));
          i = end + 2;
          continue;
        }
      }
      // 斜体：*...*（须非空且闭合）
      if (c === '*') {
        const end: number = text.indexOf('*', i + 1);
        if (end > i + 1) {
          MdParser.appendText(spans, buffer);
          buffer = '';
          spans.push(MdParser.spanOf(MdSpanKind.ITALIC, text.substring(i + 1, end)));
          i = end + 1;
          continue;
        }
      }
      // 链接：[文本](url) —— 仅渲染链接文本
      if (c === '[') {
        const closeBracket: number = text.indexOf('](', i + 1);
        if (closeBracket > i) {
          const closeParen: number = text.indexOf(')', closeBracket + 2);
          if (closeParen > closeBracket + 1) {
            MdParser.appendText(spans, buffer);
            buffer = '';
            spans.push(MdParser.spanOf(MdSpanKind.LINK, text.substring(i + 1, closeBracket)));
            i = closeParen + 1;
            continue;
          }
        }
      }
      buffer += c;
      i++;
    }
    MdParser.appendText(spans, buffer);
    return spans;
  }

  /** 围栏判定：行首 ```（语言标注忽略） */
  private static isCodeFence(line: string): boolean {
    return line.length >= 3 && line.substring(0, 3) === '```';
  }

  /** 水平分割线判定：≥3 个相同的 - / * / _ */
  private static isRuleLine(line: string): boolean {
    if (line.length < 3) {
      return false;
    }
    const first: string = line.charAt(0);
    if (first !== '-' && first !== '*' && first !== '_') {
      return false;
    }
    for (let i: number = 0; i < line.length; i++) {
      if (line.charAt(i) !== first) {
        return false;
      }
    }
    return true;
  }

  /** 标题级别（0=非标题；# 后须为空格或行尾，避免误判 #tag） */
  private static headingLevelOf(line: string): number {
    let level: number = 0;
    while (level < 6 && level < line.length && line.charAt(level) === '#') {
      level++;
    }
    if (level === 0) {
      return 0;
    }
    const after: string = line.charAt(level);
    if (after === ' ' || after === '\t' || level === line.length) {
      return level;
    }
    return 0;
  }

  /** 列表项判定：无序（- * + 后跟空格/行尾）或有序（1-3 位数字 + . 或 ) 后跟空格） */
  private static parseListItem(line: string): ParsedListItem | undefined {
    const first: string = line.charAt(0);
    if (first === '-' || first === '*' || first === '+') {
      const rest: string = line.substring(1);
      if (rest.length === 0 || rest.charAt(0) === ' ') {
        const result: ParsedListItem = new ParsedListItem();
        result.item.text = rest.trim();
        result.ordered = false;
        return result;
      }
      return undefined;
    }
    // 有序列表：1~3 位数字 + '.' 或 ')' + 空格
    let numEnd: number = 0;
    while (numEnd < 3 && numEnd < line.length && MdParser.isDigit(line.charAt(numEnd))) {
      numEnd++;
    }
    if (numEnd === 0 || numEnd >= line.length) {
      return undefined;
    }
    const marker: string = line.charAt(numEnd);
    if (marker !== '.' && marker !== ')') {
      return undefined;
    }
    const rest: string = line.substring(numEnd + 1);
    if (rest.length === 0 || rest.charAt(0) !== ' ') {
      return undefined;
    }
    const result: ParsedListItem = new ParsedListItem();
    result.item.text = rest.trim();
    result.item.orderNum = MdParser.toNumber(line.substring(0, numEnd));
    result.ordered = true;
    return result;
  }

  private static isDigit(c: string): boolean {
    return c >= '0' && c <= '9';
  }

  private static toNumber(digits: string): number {
    let n: number = 0;
    for (let i: number = 0; i < digits.length; i++) {
      n = n * 10 + (digits.charCodeAt(i) - 48);
    }
    return n;
  }

  /** 缓冲文本落为 TEXT 片段（空串忽略） */
  private static appendText(spans: MdSpan[], text: string): void {
    if (text.length === 0) {
      return;
    }
    spans.push(MdParser.spanOf(MdSpanKind.TEXT, text));
  }

  private static spanOf(kind: string, text: string): MdSpan {
    const span: MdSpan = new MdSpan();
    span.kind = kind;
    span.text = text;
    return span;
  }
}

@Component
export struct MarkdownText {
  /** Markdown 源文本（变更时整树重新解析渲染） */
  @Prop content: string = '';

  /** 内容指纹缓存（避免流式追加时 key 生成重复哈希） */
  private stampContent: string = '\u0000';
  private stampValue: string = '';

  /** 内容指纹：长度 + djb2 哈希（ForEach key 盐，内容变化强制整树刷新） */
  private contentStamp(): string {
    if (this.content !== this.stampContent) {
      const s: string = this.content;
      let hash: number = 5381;
      for (let i: number = 0; i < s.length; i++) {
        hash = ((hash << 5) + hash + s.charCodeAt(i)) | 0;
      }
      this.stampContent = s;
      this.stampValue = `${s.length}_${hash}`;
    }
    return this.stampValue;
  }

  /** 标题字号（1→19，2→17，3→16，4→15，5/6→14） */
  private headingSize(level: number): number {
    if (level <= 1) {
      return 19;
    }
    if (level === 2) {
      return 17;
    }
    if (level === 3) {
      return 16;
    }
    if (level === 4) {
      return 15;
    }
    return 14;
  }

  /** 行内片段渲染（粗体/斜体/行内代码/链接文本/普通文本） */
  @Builder
  spanBuilder(span: MdSpan) {
    if (span.kind === MdSpanKind.BOLD) {
      Span(span.text)
        .fontWeight(FontWeight.Bold)
    } else if (span.kind === MdSpanKind.ITALIC) {
      Span(span.text)
        .fontStyle(FontStyle.Italic)
    } else if (span.kind === MdSpanKind.CODE) {
      Span(span.text)
        .fontFamily('monospace')
        .fontColor(MD_INLINE_CODE)
        .fontSize(13)
    } else if (span.kind === MdSpanKind.LINK) {
      Span(span.text)
        .fontColor(Theme.primary)
        .decoration({ type: TextDecorationType.Underline })
    } else {
      Span(span.text)
    }
  }

  /** 块渲染：按块类型分发（标题/代码块/引用/列表/分割线/段落） */
  @Builder
  blockBuilder(block: MdBlock) {
    if (block.type === MdBlockType.HEADING) {
      Text() {
        ForEach(MdParser.parseInline(block.lines.length > 0 ? block.lines[0] : ''),
          (span: MdSpan) => {
            this.spanBuilder(span)
          }, (span: MdSpan, idx: number) => `${idx}_${span.kind}_${this.contentStamp()}`)
      }
      .fontSize(this.headingSize(block.level))
      .fontWeight(FontWeight.Bold)
      .fontColor(Theme.text)
      .wordBreak(WordBreak.BREAK_WORD)
      .margin({ top: 8, bottom: 4 })
    } else if (block.type === MdBlockType.CODE) {
      Column() {
        ForEach(block.lines, (codeLine: string) => {
          Text(codeLine.length > 0 ? codeLine : ' ')
            .fontSize(12)
            .fontColor(MD_CODE_TEXT)
            .fontFamily('monospace')
            .wordBreak(WordBreak.BREAK_ALL)
        }, (codeLine: string, idx: number) => `${idx}_${codeLine.length}_${this.contentStamp()}`)
      }
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(MD_CODE_BG)
      .borderRadius(Radius.sm)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .margin({ top: 6, bottom: 6 })
    } else if (block.type === MdBlockType.QUOTE) {
      Column() {
        ForEach(block.lines, (quoteLine: string, idx: number) => {
          Text() {
            ForEach(MdParser.parseInline(quoteLine),
              (span: MdSpan) => {
                this.spanBuilder(span)
              }, (span: MdSpan, sIdx: number) => `${sIdx}_${span.kind}_${this.contentStamp()}`)
          }
          .fontSize(14)
          .fontColor(Theme.textSecondary)
          .wordBreak(WordBreak.BREAK_WORD)
          .margin({ top: idx > 0 ? 2 : 0 })
        }, (quoteLine: string, idx: number) => `${idx}_${quoteLine.length}_${this.contentStamp()}`)
      }
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 10, right: 8, top: 6, bottom: 6 })
      .border({ width: { left: 3 }, color: MD_QUOTE_BAR })
      .margin({ top: 6, bottom: 6 })
    } else if (block.type === MdBlockType.LIST) {
      Column() {
        ForEach(block.items, (item: MdListItem, idx: number) => {
          Text() {
            Span(block.ordered ? `${item.orderNum}. ` : '• ')
              .fontColor(Theme.textMuted)
              .fontWeight(FontWeight.Medium)
            ForEach(MdParser.parseInline(item.text),
              (span: MdSpan) => {
                this.spanBuilder(span)
              }, (span: MdSpan, sIdx: number) => `${sIdx}_${span.kind}_${this.contentStamp()}`)
          }
          .fontSize(14)
          .fontColor(Theme.text)
          .wordBreak(WordBreak.BREAK_WORD)
          .margin({ top: idx > 0 ? 3 : 0 })
        }, (item: MdListItem, idx: number) => `${idx}_${item.text.length}_${this.contentStamp()}`)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 3, bottom: 3 })
    } else if (block.type === MdBlockType.RULE) {
      Divider()
        .color(Theme.divider)
        .margin({ top: 8, bottom: 8 })
    } else {
      Text() {
        ForEach(MdParser.parseInline(block.lines.length > 0 ? block.lines[0] : ''),
          (span: MdSpan) => {
            this.spanBuilder(span)
          }, (span: MdSpan, idx: number) => `${idx}_${span.kind}_${this.contentStamp()}`)
      }
      .fontSize(14)
      .fontColor(Theme.text)
      .wordBreak(WordBreak.BREAK_WORD)
      .margin({ top: 3, bottom: 3 })
    }
  }

  build() {
    Column() {
      ForEach(MdParser.parseBlocks(this.content), (block: MdBlock) => {
        this.blockBuilder(block)
      }, (block: MdBlock, index: number) => `${index}_${block.type}_${this.contentStamp()}`)
    }
    .alignItems(HorizontalAlign.Start)
  }
}
