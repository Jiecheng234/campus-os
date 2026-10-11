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

/**
 * AES-128-ECB（PKCS7）解密 Base64 密文（校园卡加密响应）。
 * key 为 16 字符 UTF-8 串（对齐 crypto-js：enc.Utf8.parse(data.substring(0,16)) + AES.decrypt ECB/Pkcs7）。
 */
export function aesEcbDecryptBase64(base64Ciphertext: string, key: string): string {
  const helper: util.Base64Helper = new util.Base64Helper();
  const cipherBytes: Uint8Array = helper.decodeSync(base64Ciphertext);
  const keyBytes: Uint8Array = stringToUint8Array(key.substring(0, 16));
  const keyGenerator: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
  const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
  const symKey: cryptoFramework.SymKey = keyGenerator.convertKeySync(keyBlob);
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|ECB|PKCS7');
  cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, null);
  const input: cryptoFramework.DataBlob = { data: cipherBytes };
  const output: cryptoFramework.DataBlob = cipher.doFinalSync(input);
  return uint8ArrayToString(output.data);
}

// ============================================================
// RSA 公钥加密（PKCS#1 v1.5，对齐参考实现 JSEncrypt 的默认填充）
// ============================================================

/** 读取 ASN.1 长度域：返回 [内容长度, 长度域字节数]；非法返回 undefined */
function readAsn1Length(der: Uint8Array, offset: number): number[] | undefined {
  if (offset >= der.length) {
    return undefined;
  }
  const first: number = der[offset];
  if (first < 0x80) {
    return [first, 1];
  }
  const count: number = first & 0x7f;
  if (count === 0 || count > 4 || offset + 1 + count > der.length) {
    return undefined;
  }
  let len: number = 0;
  for (let i: number = 0; i < count; i++) {
    len = len * 256 + der[offset + 1 + i];
  }
  return [len, 1 + count];
}

/** 编码 ASN.1 长度域（短形式优先，长形式最多 4 字节） */
function encodeAsn1Length(contentLen: number): number[] {
  if (contentLen < 0x80) {
    return [contentLen];
  }
  const bytes: number[] = [];
  let v: number = contentLen;
  while (v > 0) {
    bytes.unshift(v & 0xff);
    v = Math.floor(v / 256);
  }
  bytes.unshift(0x80 | bytes.length);
  return bytes;
}

/** PKCS#1 RSAPublicKey DER 包装为 X.509 SPKI DER（convertKeySync 需要 X.509 格式公钥） */
function wrapPkcs1ToSpki(pkcs1: Uint8Array): Uint8Array {
  // AlgorithmIdentifier: SEQUENCE { OID 1.2.840.113549.1.1.1 (rsaEncryption), NULL }
  const algId: number[] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00];
  const bitContentLen: number = 1 + pkcs1.length; // 首字节为 unused bits（0x00）
  const bitLen: number[] = encodeAsn1Length(bitContentLen);
  const spkiContentLen: number = algId.length + 1 + bitLen.length + bitContentLen;
  const outerLen: number[] = encodeAsn1Length(spkiContentLen);
  const total: number = 1 + outerLen.length + spkiContentLen;
  const out: Uint8Array = new Uint8Array(total);
  let pos: number = 0;
  out[pos] = 0x30;
  pos++;
  for (let i: number = 0; i < outerLen.length; i++) {
    out[pos] = outerLen[i];
    pos++;
  }
  for (let i: number = 0; i < algId.length; i++) {
    out[pos] = algId[i];
    pos++;
  }
  out[pos] = 0x03;
  pos++;
  for (let i: number = 0; i < bitLen.length; i++) {
    out[pos] = bitLen[i];
    pos++;
  }
  out[pos] = 0x00;
  pos++;
  for (let i: number = 0; i < pkcs1.length; i++) {
    out[pos] = pkcs1[i];
    pos++;
  }
  return out;
}

/**
 * 从 RSA 公钥 DER 解析模数字节长度（兼容 X.509 SPKI 与 PKCS#1 RSAPublicKey 两种形态）；
 * 解析失败返回 0。模数长度用于推断密钥位数（256 字节 → 2048 位，128 字节 → 1024 位）。
 */
function rsaModulusBytesFromDer(der: Uint8Array): number {
  if (der.length < 8 || der[0] !== 0x30) {
    return 0;
  }
  const outerLen: number[] | undefined = readAsn1Length(der, 1);
  if (outerLen === undefined) {
    return 0;
  }
  let pos: number = 1 + outerLen[1];
  if (pos >= der.length) {
    return 0;
  }
  if (der[pos] === 0x30) {
    // SPKI: SEQUENCE { SEQUENCE{OID,...}, BIT STRING { SEQUENCE { INTEGER modulus, INTEGER e } } }
    const algLen: number[] | undefined = readAsn1Length(der, pos + 1);
    if (algLen === undefined) {
      return 0;
    }
    const bitPos: number = pos + 1 + algLen[1] + algLen[0];
    if (bitPos >= der.length || der[bitPos] !== 0x03) {
      return 0;
    }
    const bitLen: number[] | undefined = readAsn1Length(der, bitPos + 1);
    if (bitLen === undefined) {
      return 0;
    }
    // BIT STRING 内容首字节为 unused bits（0x00），其后才是 RSAPublicKey
    const seqPos: number = bitPos + 1 + bitLen[1] + 1;
    if (seqPos >= der.length || der[seqPos] !== 0x30) {
      return 0;
    }
    const seqLen: number[] | undefined = readAsn1Length(der, seqPos + 1);
    if (seqLen === undefined) {
      return 0;
    }
    pos = seqPos + 1 + seqLen[1];
  } else if (der[pos] !== 0x02) {
    // 既非 SPKI 也非 PKCS#1
    return 0;
  }
  if (pos >= der.length || der[pos] !== 0x02) {
    return 0;
  }
  const intLen: number[] | undefined = readAsn1Length(der, pos + 1);
  if (intLen === undefined) {
    return 0;
  }
  let modulusBytes: number = intLen[0];
  const contentStart: number = pos + 1 + intLen[1];
  // DER INTEGER 符号位前导 0x00 不属于模数本体
  if (modulusBytes > 1 && contentStart < der.length && der[contentStart] === 0x00) {
    modulusBytes -= 1;
  }
  return modulusBytes;
}

/**
 * RSA 公钥加密（PKCS#1 v1.5 填充，对齐参考实现 JSEncrypt 默认填充）：
 * PEM 体部 Base64 → DER（SPKI / PKCS#1 均兼容）→ 按模数长度推断密钥位数 →
 * convertKeySync 公钥 + createCipher('RSAxxx|PKCS1') 加密 → Base64 输出。
 * 校园网验证码登录用（密码加密，服务端按 JSEncrypt 同款填充解密验签）。
 */
export function rsaEncryptPkcs1(plainText: string, publicKeyPem: string): string {
  // 提取 PEM 体部（去头尾标记与全部空白）
  const pemBody: string = publicKeyPem
    .replace(/-----BEGIN [A-Z ]+-----/g, '')
    .replace(/-----END [A-Z ]+-----/g, '')
    .replace(/\s+/g, '');
  const helper: util.Base64Helper = new util.Base64Helper();
  let der: Uint8Array = helper.decodeSync(pemBody);
  if (der.length < 8 || der[0] !== 0x30) {
    throw new Error('invalid public key PEM');
  }
  const outerLen: number[] | undefined = readAsn1Length(der, 1);
  if (outerLen === undefined) {
    throw new Error('invalid public key DER');
  }
  // PKCS#1（首子元素为 INTEGER）先包装为 X.509 SPKI
  const firstChildPos: number = 1 + outerLen[1];
  if (firstChildPos < der.length && der[firstChildPos] === 0x02) {
    der = wrapPkcs1ToSpki(der);
  }
  // 密钥位数从模数长度推断（256B→2048 / 128B→1024，向上取整到 1024 整数倍）
  const modulusBytes: number = rsaModulusBytesFromDer(der);
  if (modulusBytes <= 0) {
    throw new Error('invalid RSA modulus');
  }
  const keyBits: number = Math.ceil((modulusBytes * 8) / 1024) * 1024;
  const generator: cryptoFramework.AsyKeyGenerator =
    cryptoFramework.createAsyKeyGenerator('RSA' + keyBits.toString());
  const pubBlob: cryptoFramework.DataBlob = { data: der };
  const keyPair: cryptoFramework.KeyPair = generator.convertKeySync(pubBlob, null);
  const cipher: cryptoFramework.Cipher =
    cryptoFramework.createCipher('RSA' + keyBits.toString() + '|PKCS1');
  cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, keyPair.pubKey, null);
  const input: cryptoFramework.DataBlob = { data: stringToUint8Array(plainText) };
  const output: cryptoFramework.DataBlob = cipher.doFinalSync(input);
  return helper.encodeToStringSync(output.data);
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
