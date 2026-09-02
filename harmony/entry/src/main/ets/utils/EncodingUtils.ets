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
