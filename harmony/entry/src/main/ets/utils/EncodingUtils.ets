export function decodeGBK(bytes: Uint8Array): string {
  let result: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    if (bytes[i] < 0x80) {
      result = result + String.fromCharCode(bytes[i]);
    }
  }
  return result;
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
