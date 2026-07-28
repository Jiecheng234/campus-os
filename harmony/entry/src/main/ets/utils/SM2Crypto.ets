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

function genSM2CommonSpec(): cryptoFramework.ECCCommonParamsSpec {
  const fieldFp: cryptoFramework.ECFieldFp = {
    fieldType: 'Fp',
    p: BigInt('0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF')
  };
  const G: cryptoFramework.Point = {
    x: BigInt('0x32C4AE2C1F1981195F9904466A39C9948FE30BBFF2660BE1715A4589334C74C7'),
    y: BigInt('0xBC3736A2F4F6779C59BDCEE36B692153D0A9877CC62A474002DF32E52139F0A0')
  };
  const spec: cryptoFramework.ECCCommonParamsSpec = {
    algName: 'ECC',
    specType: cryptoFramework.AsyKeySpecType.COMMON_PARAMS_SPEC,
    field: fieldFp,
    a: BigInt('0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFC'),
    b: BigInt('0x28E9FA9E9D9F5E344D5A9E4BCF6509A7F39789F515AB8F92DDBCBD414D940E93'),
    g: G,
    n: BigInt('0xFFFFFFFEFFFFFFFFFFFFFFFFFFFFFFFF7203DF6B21C6052B53BBF40939D54123'),
    h: 1
  };
  return spec;
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
    params: genSM2CommonSpec(),
    pk: pk,
    algName: 'ECC',
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
