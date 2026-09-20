/**
 * ============================================================================
 * EncodingUtils — GBK/GB2312 编解码（教务等老系统的字符集处理）
 * ============================================================================
 *
 * 职责：
 *   - decodeGBK(bytes)：GBK 字节 → 字符串（教务/电费等老 ASP/Java 系统默认 GBK）。
 *   - decodeURLEncodedGBK(str)：GBK percent-encoding 解码。
 *   - isGBKContentType(contentType)：按 content-type 判断是否 GBK。
 *
 * 注意：zhjw 教务系统可能未在 content-type 标记 GBK——必要时需按 URL 强制 GBK 解码。
 * ============================================================================
 */
import { util } from '@kit.ArkTS';

export function decodeGBK(bytes: Uint8Array): string {
  try {
    const decoder: util.TextDecoder = util.TextDecoder.create('gbk', { ignoreBOM: true });
    return decoder.decodeToString(bytes, { stream: false });
  } catch (e) {
    let result: string = '';
    for (let i: number = 0; i < bytes.length; i++) {
      if (bytes[i] < 0x80) {
        result = result + String.fromCharCode(bytes[i]);
      }
    }
    return result;
  }
}

export function decodeURLEncodedGBK(str: string): string {
  let result: string = '';
  let i: number = 0;
  while (i < str.length) {
    if (str.charAt(i) === '%' && i + 2 < str.length) {
      const hex: string = str.substring(i + 1, i + 3);
      const byteVal: number = parseInt(hex, 16);
      if (!isNaN(byteVal) && byteVal < 0x80) {
        result = result + String.fromCharCode(byteVal);
        i = i + 3;
        continue;
      }
    }
    result = result + str.charAt(i);
    i = i + 1;
  }
  return result;
}

export function isGBKContentType(contentType: string): boolean {
  const lower: string = contentType.toLowerCase();
  return lower.indexOf('gb2312') >= 0 || lower.indexOf('gbk') >= 0;
}

/**
 * ============================================================================
 * GBK 反向编码表 — gb2312PercentEncode 的支撑
 * ============================================================================
 *
 * 系统侧只有 GBK TextDecoder（util.TextEncoder 仅支持 UTF-8/16），没有 GBK 编码器；
 * 首次调用 gb2312PercentEncode 时用 GBK 解码器暴力反解出
 * "CJK 统一汉字 [\u4e00-\u9fa5] → GBK 双字节码" 的反向表：
 *   - 遍历 GBK 双字节空间（lead 0x81-0xFE × trail 0x40-0x7E/0x80-0xFE，跳过 0x7F），
 *     每对之间插入 0x01 分隔符（GBK 双字节序列不可能包含 0x01），整体一次性解码；
 *   - 解码结果长度校验通过则按"偶数位 = 双字节解码字符"建表；否则逐对解码兜底。
 * 一次性构建；与 decodeGBK 用同一解码器，保证编解码往返一致。
 */
let gbkReverseTable: Map<number, number> | null = null;

const GBK_PCT_HEX: string = '0123456789ABCDEF';

function gbkPctByte(b: number): string {
  return '%' + GBK_PCT_HEX.charAt((b >> 4) & 0xf) + GBK_PCT_HEX.charAt(b & 0xf);
}

function isCjkUnifiedCode(code: number): boolean {
  return code >= 0x4e00 && code <= 0x9fa5;
}

function buildGbkReverseTable(): Map<number, number> {
  const map: Map<number, number> = new Map<number, number>();
  const leads: number[] = [];
  const trails: number[] = [];
  for (let lead: number = 0x81; lead <= 0xfe; lead++) {
    leads.push(lead);
  }
  for (let trail: number = 0x40; trail <= 0xfe; trail++) {
    if (trail !== 0x7f) {
      trails.push(trail);
    }
  }
  const pairCount: number = leads.length * trails.length;
  const bytes: Uint8Array = new Uint8Array(pairCount * 3);
  let idx: number = 0;
  for (let i: number = 0; i < leads.length; i++) {
    for (let j: number = 0; j < trails.length; j++) {
      bytes[idx] = leads[i];
      bytes[idx + 1] = trails[j];
      bytes[idx + 2] = 0x01;
      idx = idx + 3;
    }
  }
  try {
    const decoder: util.TextDecoder = util.TextDecoder.create('gbk', { ignoreBOM: true });
    const decoded: string = decoder.decodeToString(bytes, { stream: false });
    if (decoded.length === pairCount * 2) {
      for (let k: number = 0; k < pairCount; k++) {
        const code: number = decoded.charCodeAt(k * 2);
        if (isCjkUnifiedCode(code)) {
          map.set(code, (bytes[k * 3] << 8) | bytes[k * 3 + 1]);
        }
      }
      return map;
    }
  } catch (e) {
    // 整体解码失败 → 走逐对解码兜底
  }
  try {
    const decoder: util.TextDecoder = util.TextDecoder.create('gbk', { ignoreBOM: true });
    const pair: Uint8Array = new Uint8Array(2);
    for (let i: number = 0; i < leads.length; i++) {
      for (let j: number = 0; j < trails.length; j++) {
        pair[0] = leads[i];
        pair[1] = trails[j];
        const decoded: string = decoder.decodeToString(pair, { stream: false });
        if (decoded.length === 1) {
          const code: number = decoded.charCodeAt(0);
          if (isCjkUnifiedCode(code)) {
            map.set(code, (leads[i] << 8) | trails[j]);
          }
        }
      }
    }
  } catch (e) {
    // GBK 解码器不可用：保持空表，编码时退回 UTF-8 percent-encode
  }
  return map;
}

/**
 * 把字符串里的 CJK 汉字按 GBK 编码逐字节 percent-encode；其余字符（含已编码 %XX 串）原样穿透。
 * 与原项目 utils/encoding.ts `gb2312PercentEncode` 语义完全一致：
 *   "六教"          → "%C1%F9%BD%CC"
 *   "%C1%F9%BD%CC"  → "%C1%F9%BD%CC"   ← 已编码穿透（不会二次 escape）
 *   "六教_2024"     → "%C1%F9%BD%CC_2024"
 * 字符不在 GBK 汉字表内（或表构建失败）时退回 UTF-8 percent-encode（iconv 缺失兜底行为）。
 */
export function gb2312PercentEncode(input: string): string {
  if (input.length === 0) {
    return '';
  }
  if (gbkReverseTable === null) {
    gbkReverseTable = buildGbkReverseTable();
  }
  const table: Map<number, number> = gbkReverseTable;
  let out: string = '';
  for (let i: number = 0; i < input.length; i++) {
    const code: number = input.charCodeAt(i);
    if (isCjkUnifiedCode(code)) {
      const gbkCode: number | undefined = table.get(code);
      if (gbkCode !== undefined) {
        out = out + gbkPctByte((gbkCode >> 8) & 0xff) + gbkPctByte(gbkCode & 0xff);
        continue;
      }
      out = out + encodeURIComponent(input.charAt(i));
      continue;
    }
    out = out + input.charAt(i);
  }
  return out;
}
