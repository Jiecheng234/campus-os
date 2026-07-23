import { util } from '@kit.ArkTS';

export function encodeBase64(input: string): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  const uint8Array: Uint8Array = stringToUint8Array(input);
  return helper.encodeToStringSync(uint8Array);
}

export function decodeBase64(input: string): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  const uint8Array: Uint8Array = helper.decodeSync(input);
  return uint8ArrayToString(uint8Array);
}

export function stringToUint8Array(str: string): Uint8Array {
  const encoder: util.TextEncoder = new util.TextEncoder('utf-8');
  return encoder.encodeInto(str);
}

export function uint8ArrayToString(arr: Uint8Array): string {
  const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
  const result: util.TextDecodeResult = decoder.decodeWithStream(arr, undefined);
  return result.text;
}

export function bytesToHex(bytes: Uint8Array): string {
  let result: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    const hex: string = bytes[i].toString(16).padStart(2, '0');
    result = result + hex;
  }
  return result;
}

export function hexToBytes(hex: string): Uint8Array {
  const len: number = Math.floor(hex.length / 2);
  const bytes: Uint8Array = new Uint8Array(len);
  for (let i: number = 0; i < len; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

export function generateUUID(): string {
  return util.generateRandomUUID();
}

export function generateRandomBytes(length: number): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(length);
  for (let i: number = 0; i < length; i++) {
    bytes[i] = Math.floor(Math.random() * 256);
  }
  return bytes;
}

export function sha256(input: string): string {
  const uint8Array: Uint8Array = stringToUint8Array(input);
  const hash: Uint8Array = util.computeSHA256(uint8Array);
  return bytesToHex(hash);
}

export function md5(input: string): string {
  const uint8Array: Uint8Array = stringToUint8Array(input);
  const hash: Uint8Array = util.computeMD5(uint8Array);
  return bytesToHex(hash);
}

export function formatDate(date: Date): string {
  const year: number = date.getFullYear();
  const month: string = String(date.getMonth() + 1).padStart(2, '0');
  const day: string = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

export function getTodayDateStr(): string {
  return formatDate(new Date());
}

export function getWeekDates(): string[] {
  const today: Date = new Date();
  const dayOfWeek: number = today.getDay();
  const mondayOffset: number = dayOfWeek === 0 ? -6 : 1 - dayOfWeek;
  const monday: Date = new Date(today);
  monday.setDate(today.getDate() + mondayOffset);
  const dates: string[] = [];
  for (let i: number = 0; i < 7; i++) {
    const d: Date = new Date(monday);
    d.setDate(monday.getDate() + i);
    dates.push(`${String(d.getMonth() + 1).padStart(2, '0')}/${String(d.getDate()).padStart(2, '0')}`);
  }
  return dates;
}
