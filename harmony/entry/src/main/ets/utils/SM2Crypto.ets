import { buffer, util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const SM2_PREFIX: string = '04';

function regexCapture(html: string, pattern: string): string {
  const re: RegExp = new RegExp(pattern, 'i');
  const match = re.exec(html);
  if (match === null) {
    return '';
  }
  if (match.length < 2) {
    return '';
  }
  const idx: number = 1;
  const captured: string = match[idx];
  if (captured === undefined) {
    return '';
  }
  return captured.trim();
}

export function extractSm2PublicKey(html: string): string {
  const pattern: string = 'id\\s*=\\s*["\']sm2publicKey["\'][^>]*>([\\s\\S]*?)<';
  return regexCapture(html, pattern);
}

function hexToBigInt(hex: string): bigint {
  if (hex.length === 0) {
    return BigInt(0);
  }
  return BigInt('0x' + hex);
}

function stringToUint8Array(str: string): Uint8Array {
  return new Uint8Array(buffer.from(str, 'utf-8').buffer);
}

function uint8ArrayToHex(data: Uint8Array): string {
  let result: string = '';
  for (let i: number = 0; i < data.length; i++) {
    const byteHex: string = ('00' + data[i].toString(16)).slice(-2);
    result = result + byteHex;
  }
  return result;
}

async function genPubKeyFromRaw(keyHex: string): Promise<cryptoFramework.PubKey | undefined> {
  let hex: string = keyHex.trim();
  if (hex.startsWith(SM2_PREFIX)) {
    hex = hex.substring(2);
  }
  if (hex.length !== 128) {
    return undefined;
  }
  const xHex: string = hex.substring(0, 64);
  const yHex: string = hex.substring(64, 128);
  const pk: cryptoFramework.Point = {
    x: hexToBigInt(xHex),
    y: hexToBigInt(yHex)
  };
  const pubKeySpec: cryptoFramework.ECCPubKeySpec = {
    params: cryptoFramework.ECCKeyUtil.genECCCommonParamsSpec('NID_sm2'),
    pk: pk,
    algName: 'SM2',
    specType: cryptoFramework.AsyKeySpecType.PUBLIC_KEY_SPEC
  };
  const generator: cryptoFramework.AsyKeyGeneratorBySpec = cryptoFramework.createAsyKeyGeneratorBySpec(pubKeySpec);
  const pubKey: cryptoFramework.PubKey = await generator.generatePubKey();
  return pubKey;
}

export async function encryptPassword(password: string, publicKey: string): Promise<string> {
  const pubKey: cryptoFramework.PubKey | undefined = await genPubKeyFromRaw(publicKey);
  if (pubKey === undefined) {
    return '';
  }
  const plainBytes: Uint8Array = stringToUint8Array(password);
  const plainBlob: cryptoFramework.DataBlob = { data: plainBytes };
  let cipher: cryptoFramework.Cipher;
  try {
    cipher = cryptoFramework.createCipher('SM2_256|SM3');
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, pubKey, null);
    const encryptData: cryptoFramework.DataBlob = await cipher.doFinal(plainBlob);
    const raw: Uint8Array = derToRawSM2(encryptData.data);
    return uint8ArrayToHex(raw);
  } catch (e) {
    return '';
  }
}

function readDerLength(data: Uint8Array, offset: number): number {
  const first: number = data[offset];
  if ((first & 0x80) === 0) {
    return first;
  }
  const numBytes: number = first & 0x7F;
  let len: number = 0;
  for (let i: number = 1; i <= numBytes; i++) {
    len = len * 256 + data[offset + i];
  }
  return len;
}

function derToRawSM2(der: Uint8Array): Uint8Array {
  try {
    let offset: number = 0;
    if (der[offset] !== 0x30) {
      return der;
    }
    offset = offset + 1;
    const seqLen: number = readDerLength(der, offset);
    offset = offset + 1;
    if (seqLen > 0x7F) {
      offset = offset + 1;
    }

    const parts: Uint8Array[] = [];
    const end: number = offset + seqLen;
    while (offset < end) {
      const tag: number = der[offset];
      offset = offset + 1;
      const len: number = readDerLength(der, offset);
      offset = offset + 1;
      if (len > 0x7F) {
        offset = offset + 1;
      }
      if (offset + len > der.length) {
        break;
      }
      let valueStart: number = offset;
      if (tag === 0x02 && der[valueStart] === 0x00) {
        valueStart = valueStart + 1;
      }
      const part: Uint8Array = new Uint8Array(len - (valueStart - offset));
      for (let i: number = 0; i < part.length; i++) {
        part[i] = der[valueStart + i];
      }
      parts.push(part);
      offset = offset + len;
    }

    if (parts.length >= 4) {
      const total: number = 1 + parts[0].length + parts[1].length + parts[2].length + parts[3].length;
      const raw: Uint8Array = new Uint8Array(total);
      let idx: number = 0;
      raw[idx] = 0x04;
      idx = idx + 1;
      for (let i: number = 0; i < parts[0].length; i++) { raw[idx] = parts[0][i]; idx = idx + 1; }
      for (let i: number = 0; i < parts[1].length; i++) { raw[idx] = parts[1][i]; idx = idx + 1; }
      for (let i: number = 0; i < parts[2].length; i++) { raw[idx] = parts[2][i]; idx = idx + 1; }
      for (let i: number = 0; i < parts[3].length; i++) { raw[idx] = parts[3][i]; idx = idx + 1; }
      return raw;
    }
    return der;
  } catch (e) {
    return der;
  }
}

export function extractFirstAnchorHref(html: string): string {
  const pattern: string = '<a[^>]+href\\s*=\\s*["\']([^"\']+)["\']';
  return regexCapture(html, pattern);
}

export function extractElementTextById(html: string, id: string): string {
  const pattern: string = 'id\\s*=\\s*["\']' + id + '["\'][^>]*>([\\s\\S]*?)<';
  return regexCapture(html, pattern);
}

export function extractMsgNote(html: string): string {
  return extractElementTextById(html, 'msg_note');
}

export function extractCsrfToken(html: string): string {
  const pattern: string = 'name\\s*=\\s*["\']_csrf["\']\\s+value\\s*=\\s*["\']([^"\']+)["\']';
  return regexCapture(html, pattern);
}

export function extractFormAction(html: string): string {
  const pattern: string = '<form[^>]+action\\s*=\\s*["\']([^"\']+)["\']';
  return regexCapture(html, pattern);
}

export function extractMetaRedirect(html: string): string {
  const pattern: string = 'url=([^"\'>\\s]+)';
  const re: RegExp = new RegExp(pattern, 'i');
  const match = re.exec(html);
  if (match === null || match.length < 2) {
    return '';
  }
  const idx: number = 1;
  const captured: string = match[idx];
  if (captured === undefined) {
    return '';
  }
  return captured.trim();
}
