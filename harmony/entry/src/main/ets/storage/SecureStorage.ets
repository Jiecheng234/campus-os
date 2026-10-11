import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { PreferencesStorage } from './PreferencesStorage';
import { Log } from '../utils/Logger';

/**
 * ============================================================================
 * SecureStorage — 登录凭证安全存储（系统关键资产存储 + 惰性自动迁移）
 * ============================================================================
 *
 * 【存储形态】单条关键资产（Asset Store Kit）：
 *   - 别名 ASSET_ALIAS（固定值，唯一索引，不加密，不含敏感信息）
 *   - 密文 SECRET = encodeURIComponent(学号):encodeURIComponent(密码):指纹
 *     （三项凭证全部序列化进唯一加密字段；严禁放入 ALIAS / DATA_LABEL 类字段）
 *   - 访问条件：设备开机后可用（不设"需用户认证"，保证静默自动登录）
 *   - 查询返回类型：属性 + 明文（ReturnType.ALL）
 *
 * 【迁移】读取路径惰性自动迁移：ASSET 未命中 → 读旧明文（偏好设置键
 *   LEGACY_PREF_KEY，历史"@secure:credentials"）→ 写入 ASSET 成功后才清除
 *   旧明文；写入失败保留旧明文（不丢数据）。迁移 = 原样搬运字符串。
 *
 * 【故障边界】保存失败只记日志不抛出（不阻断登录）；读取失败/ASSET 不可用
 *   返回空值，绝不回退为明文写入；清除对 ASSET 与旧明文各自容错、幂等。
 *
 * 【日志】仅输出步骤、命中/存在布尔、长度与错误码——禁止输出密码明文。
 * ============================================================================
 */

/** 统一日志标签（验证阶段以此判定迁移与清除行为） */
const LOG_TAG: string = 'SecureStore';
/** 关键资产别名（唯一索引；不加密，不含任何敏感信息） */
const ASSET_ALIAS: string = 'campusos.credentials';
/** 旧明文偏好键（沿用历史值；仅迁移读取与清除使用，之后不再写入） */
const LEGACY_PREF_KEY: string = '@secure:credentials';

export class SecureStorage {
  // ============================================================
  // 序列化 / 反序列化（沿用既有格式，迁移 = 原样搬运字符串）
  // ============================================================

  /** 序列化：encodeURIComponent(学号):encodeURIComponent(密码):指纹 */
  private static serialize(studentId: string, password: string, fingerprint: string): string {
    const encodedId: string = encodeURIComponent(studentId);
    const encodedPw: string = encodeURIComponent(password);
    return `${encodedId}:${encodedPw}:${fingerprint}`;
  }

  /** 反序列化：兼容既有 `:` 分段与 parts.length >= 3 语义；空串/段数不足/解码失败返回 undefined */
  private static deserialize(raw: string): SecureCredentials | undefined {
    if (raw.length === 0) {
      return undefined;
    }
    const parts: string[] = raw.split(':');
    if (parts.length < 2) {
      return undefined;
    }
    const result: SecureCredentials = new SecureCredentials();
    try {
      result.studentId = decodeURIComponent(parts[0]);
      result.password = decodeURIComponent(parts[1]);
    } catch (e) {
      // 脏数据兜底：解码失败按"无凭证"处理（FR-005 不抛异常到调用方）
      Log.e(LOG_TAG, 'CRED_QUERY deserialize failed');
      return undefined;
    }
    if (parts.length >= 3) {
      result.fingerprint = parts[2];
    }
    return result;
  }

  // ============================================================
  // 关键资产（Asset Store Kit）读写辅助
  // ============================================================

  private static textToBytes(text: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(text);
  }

  private static bytesToText(bytes: Uint8Array): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
    return decoder.decodeToString(bytes, { stream: false });
  }

  /** 仅按别名构造关键资产操作条件 */
  private static buildAliasQuery(): asset.AssetMap {
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, SecureStorage.textToBytes(ASSET_ALIAS));
    return query;
  }

  /**
   * 查询关键资产明文（RETURN_TYPE = ALL：属性 + 明文）。
   * 返回 SECRET 字符串；未找到（NOT_FOUND）返回 undefined；
   * 其他异常记日志并返回 undefined（不抛出到调用方）。
   */
  private static async assetQuerySecret(): Promise<string | undefined> {
    const query: asset.AssetMap = SecureStorage.buildAliasQuery();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) {
        return undefined;
      }
      const secretValue: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (!(secretValue instanceof Uint8Array)) {
        Log.e(LOG_TAG, 'CRED_QUERY secret type invalid');
        return undefined;
      }
      return SecureStorage.bytesToText(secretValue);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        Log.e(LOG_TAG, 'CRED_QUERY query failed code=%{public}d', err.code);
      }
      return undefined;
    }
  }

  /**
   * 幂等写入关键资产明文：先新增，命中"已存在"（DUPLICATED）则更新
   * （同别名仅保留一份；不用"先删后增"，避免异常窗口内凭证丢失）。
   * 返回是否写入成功；任何异常记日志、不抛出。
   */
  private static async assetPutSecret(secret: string): Promise<boolean> {
    const attrs: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attrs.set(asset.Tag.SECRET, SecureStorage.textToBytes(secret));
    attrs.set(asset.Tag.ALIAS, SecureStorage.textToBytes(ASSET_ALIAS));
    // 访问条件：设备开机后可用（不设"需用户认证"，保证静默自动登录）
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
    try {
      await asset.add(attrs);
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code !== asset.ErrorCode.DUPLICATED) {
        Log.e(LOG_TAG, 'CRED_SAVE add failed code=%{public}d', err.code);
        return false;
      }
    }
    // 已存在 → 更新（幂等）
    const updates: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    updates.set(asset.Tag.SECRET, SecureStorage.textToBytes(secret));
    try {
      await asset.update(SecureStorage.buildAliasQuery(), updates);
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(LOG_TAG, 'CRED_SAVE update failed code=%{public}d', err.code);
      return false;
    }
  }

  /**
   * 删除关键资产（幂等：NOT_FOUND 视为已清除）。
   * 返回是否无残留；异常记日志、不抛出。
   */
  private static async assetRemoveSecret(): Promise<boolean> {
    try {
      await asset.remove(SecureStorage.buildAliasQuery());
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === asset.ErrorCode.NOT_FOUND) {
        return true;
      }
      Log.e(LOG_TAG, 'CRED_CLEAR asset remove failed code=%{public}d', err.code);
      return false;
    }
  }

  // ============================================================
  // 旧明文（偏好设置）辅助——仅迁移读取与清除使用，不再写入
  // ============================================================

  /** 读取旧明文（无则返回空串；异常记日志并返回空串，不抛出） */
  private static async legacyRead(): Promise<string> {
    try {
      return await PreferencesStorage.getString(LEGACY_PREF_KEY, '');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(LOG_TAG, 'CRED_MIGRATE legacy read failed code=%{public}d', err.code);
      return '';
    }
  }

  /** 清除旧明文（幂等；异常记日志、不抛出） */
  private static async legacyRemove(): Promise<void> {
    try {
      await PreferencesStorage.remove(LEGACY_PREF_KEY);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.w(LOG_TAG, 'CRED_CLEAR legacy remove failed code=%{public}d', err.code);
    }
  }

  /** 清除旧明文残留（先读后删，输出存在布尔与长度；幂等，不抛出） */
  private static async removeLegacyResidue(step: string): Promise<void> {
    const raw: string = await SecureStorage.legacyRead();
    if (raw.length === 0) {
      return;
    }
    await SecureStorage.legacyRemove();
    Log.i(LOG_TAG, '%{public}s legacy residue cleared len=%{public}d', step, raw.length);
  }

  // ============================================================
  // 对外接口（签名与语义保持不变，调用方零改动）
  // ============================================================

  /**
   * 幂等写入关键资产（新增 → 命中"已存在"则更新）；不再写入旧明文字段。
   * 写入失败仅记日志、不向调用方抛出（登录流程不因存储故障中断）；
   * 成功后尝试清除旧明文残留（清除失败不阻断，下次读取会重试）。
   */
  static async saveCredentials(studentId: string, password: string, fingerprint: string): Promise<void> {
    const secret: string = SecureStorage.serialize(studentId, password, fingerprint);
    const saved: boolean = await SecureStorage.assetPutSecret(secret);
    if (!saved) {
      // assetPutSecret 内部已记录错误码；此处不抛出、不回退明文写入
      return;
    }
    Log.i(LOG_TAG, 'CRED_SAVE ok secret_len=%{public}d', secret.length);
    await SecureStorage.removeLegacyResidue('CRED_SAVE');
  }

  /**
   * 读取凭证（优先关键资产，未命中时惰性迁移旧明文）：
   *  ① 查询关键资产：命中 → 返回结果，并尝试清除旧明文残留；
   *  ② 未命中 → 读旧明文字段：存在则先写入关键资产、写入成功后才清除旧明文，
   *     返回该凭证；写入失败不得清除旧明文（保留并返回该凭证，记可读日志）；
   *  ③ 两者皆无 → 返回 undefined；
   *  ④ 全过程异常不得抛出到调用方（无数据/异常 → 空值）。
   */
  static async getCredentials(): Promise<SecureCredentials | undefined> {
    // ① 关键资产查询
    const secret: string | undefined = await SecureStorage.assetQuerySecret();
    if (secret !== undefined) {
      Log.i(LOG_TAG, 'CRED_QUERY hit=true');
      // 迁移已完成的历史残留清理（幂等；失败不影响本次返回，下次读取重试）
      await SecureStorage.removeLegacyResidue('CRED_QUERY');
      return SecureStorage.deserialize(secret);
    }
    // ② 惰性迁移：旧明文 → 关键资产（写入成功才清除旧明文）
    const legacyRaw: string = await SecureStorage.legacyRead();
    if (legacyRaw.length === 0) {
      Log.i(LOG_TAG, 'CRED_QUERY hit=false legacy_present=false');
      return undefined;
    }
    Log.i(LOG_TAG, 'CRED_QUERY hit=false legacy_present=true legacy_len=%{public}d', legacyRaw.length);
    const migrated: boolean = await SecureStorage.assetPutSecret(legacyRaw);
    if (migrated) {
      await SecureStorage.legacyRemove();
      Log.i(LOG_TAG, 'CRED_MIGRATE migrated=true cleared=true');
    } else {
      // 写入失败：保留旧明文（不丢数据），仍返回该凭证，下次读取重试迁移
      Log.w(LOG_TAG, 'CRED_MIGRATE migrated=false cleared=false legacy_kept=true');
    }
    return SecureStorage.deserialize(legacyRaw);
  }

  /**
   * 清除凭证：同时清除关键资产与本模块旧明文字段（各自容错、幂等，
   * NOT_FOUND 视为已清除）。任何异常均不抛出到调用方。
   */
  static async clearCredentials(): Promise<void> {
    const assetCleared: boolean = await SecureStorage.assetRemoveSecret();
    await SecureStorage.legacyRemove();
    Log.i(LOG_TAG, 'CRED_CLEAR ok asset_cleared=%{public}s legacy_cleared=true', assetCleared);
  }
}

export class SecureCredentials {
  studentId: string = '';
  password: string = '';
  fingerprint: string = '';
}
