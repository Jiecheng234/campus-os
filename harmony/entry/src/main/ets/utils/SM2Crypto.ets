import { buffer } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const SM2_PREFIX: string = '04';

const SM2_DER_HEADER: Uint8Array = new Uint8Array([
  0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D,
  0x02, 0x01, 0x06, 0x08, 0x2A, 0x81, 0x1C, 0xCF, 0x55, 0x01, 0x82,
  0x2D, 0x03, 0x42, 0x00
]);

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

function hexToUint8Array(hex: string): Uint8Array {
  const clean: string = hex.replace(/\s/g, '');
  const len: number = Math.floor(clean.length / 2);
  const bytes: Uint8Array = new Uint8Array(len);
  for (let i: number = 0; i < len; i++) {
    bytes[i] = parseInt(clean.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function uint8ArrayToHex(data: Uint8Array): string {
  let result: string = '';
  for (let i: number = 0; i < data.length; i++) {
    const byteHex: string = ('00' + data[i].toString(16)).slice(-2);
    result = result + byteHex;
  }
  return result;
}

function buildSm2DerPublicKey(rawHexKey: string): Uint8Array {
  let keyHex: string = rawHexKey.trim();
  if (keyHex.startsWith(SM2_PREFIX)) {
    keyHex = keyHex.substring(2);
  }
  if (keyHex.length !== 128) {
    return new Uint8Array(0);
  }
  const keyBytes: Uint8Array = hexToUint8Array(keyHex);
  const bitStringHeader: Uint8Array = new Uint8Array([0x03, 0x42, 0x00, 0x04]);
  const totalLen: number = SM2_DER_HEADER.length + bitStringHeader.length + keyBytes.length;
  const derBytes: Uint8Array = new Uint8Array(totalLen);
  let offset: number = 0;
  for (let i: number = 0; i < SM2_DER_HEADER.length; i++) {
    derBytes[offset] = SM2_DER_HEADER[i];
    offset = offset + 1;
  }
  for (let i: number = 0; i < bitStringHeader.length; i++) {
    derBytes[offset] = bitStringHeader[i];
    offset = offset + 1;
  }
  for (let i: number = 0; i < keyBytes.length; i++) {
    derBytes[offset] = keyBytes[i];
    offset = offset + 1;
  }
  return derBytes;
}

export function encryptPassword(password: string, publicKey: string): string {
  const derKey: Uint8Array = buildSm2DerPublicKey(publicKey);
  if (derKey.length === 0) {
    return '';
  }

  const pubKeyBlob: cryptoFramework.DataBlob = { data: derKey };
  const priPlaceholder: Uint8Array = new Uint8Array(50);
  const priKeyBlob: cryptoFramework.DataBlob = { data: priPlaceholder };

  const generator: cryptoFramework.AsyKeyGenerator = cryptoFramework.createAsyKeyGenerator('SM2_256');
  let keyPair: cryptoFramework.KeyPair;
  try {
    keyPair = generator.convertKeySync(pubKeyBlob, priKeyBlob);
  } catch (e) {
    return '';
  }

  const plainBytes: Uint8Array = new Uint8Array(buffer.from(password, 'utf-8').buffer);
  const plainBlob: cryptoFramework.DataBlob = { data: plainBytes };

  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('SM2_256|SM3');
  cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
  const encryptData: cryptoFramework.DataBlob = cipher.doFinalSync(plainBlob);

  return SM2_PREFIX + uint8ArrayToHex(encryptData.data);
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
