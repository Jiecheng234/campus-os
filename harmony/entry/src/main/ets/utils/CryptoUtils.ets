import { util, buffer } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

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
  return new Uint8Array(buffer.from(str, 'utf-8').buffer);
}

export function uint8ArrayToString(arr: Uint8Array): string {
  const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { fatal: false, ignoreBOM: true });
  return decoder.decodeToString(arr, { stream: false });
}

export function bytesToHex(bytes: Uint8Array): string {
  let result: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    const hex: string = ('00' + bytes[i].toString(16)).slice(-2);
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
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  const uint8Array: Uint8Array = stringToUint8Array(input);
  md.updateSync({ data: uint8Array });
  const result: cryptoFramework.DataBlob = md.digestSync();
  return bytesToHex(result.data);
}

export function md5(input: string): string {
  const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
  const uint8Array: Uint8Array = stringToUint8Array(input);
  md.updateSync({ data: uint8Array });
  const result: cryptoFramework.DataBlob = md.digestSync();
  return bytesToHex(result.data);
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
