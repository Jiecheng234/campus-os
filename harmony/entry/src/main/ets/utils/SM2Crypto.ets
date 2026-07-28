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
    return SM2_PREFIX + uint8ArrayToHex(encryptData.data);
  } catch (e) {
    return '';
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
