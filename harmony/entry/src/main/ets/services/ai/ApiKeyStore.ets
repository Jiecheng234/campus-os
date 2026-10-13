/**
 * ============================================================================
 * ApiKeyStore — AI API Key 安全存储（系统关键资产存储 Asset Store Kit）
 * ============================================================================
 *
 * 【存储形态】单条关键资产（复用 SecureStorage 的 ASSET 范式）：
 *   - 别名 ASSET_ALIAS（固定值，唯一索引，不加密，不含敏感信息）
 *   - 密文 SECRET = API Key 原文（仅存于唯一加密字段；严禁放入
 *     ALIAS / DATA_LABEL 类字段，严禁写入偏好设置明文）
 *   - 访问条件：设备开机后可用（不设"需用户认证"，保证后台可读）
 *
 * 【故障边界】保存失败不抛出（返回 false，由调用方决定 UI 提示）；
 * 读取失败 / ASSET 不可用返回空串，绝不回退为明文写入；
 * 清除幂等（NOT_FOUND 视为已清除）。
 *
 * 【日志】仅输出步骤、命中/存在布尔、长度与错误码——
 * 禁止输出 API Key 明文或任何鉴权头内容（FR-002 / FR-015 / SC-008）。
 * ============================================================================
 */
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { Log } from '../../utils/Logger';

/** 统一日志标签（禁止在日志中出现 Key 内容） */
const LOG_TAG: string = 'ApiKeyStore';
/** 关键资产别名（唯一索引；不加密，不含任何敏感信息） */
const ASSET_ALIAS: string = 'campusos.ai.apikey';

export class ApiKeyStore {
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
    query.set(asset.Tag.ALIAS, ApiKeyStore.textToBytes(ASSET_ALIAS));
    return query;
  }

  /**
   * 幂等写入关键资产：先新增，命中"已存在"（DUPLICATED）则更新
   * （同别名仅保留一份；不用"先删后增"，避免异常窗口内 Key 丢失）。
   * 返回是否写入成功；任何异常记日志、不抛出、不回退明文写入。
   */
  private static async assetPutSecret(secret: string): Promise<boolean> {
    const attrs: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attrs.set(asset.Tag.SECRET, ApiKeyStore.textToBytes(secret));
    attrs.set(asset.Tag.ALIAS, ApiKeyStore.textToBytes(ASSET_ALIAS));
    // 访问条件：设备开机后可用（不设"需用户认证"，保证发送消息前可静默读取）
    attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_POWERED_ON);
    try {
      await asset.add(attrs);
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code !== asset.ErrorCode.DUPLICATED) {
        Log.e(LOG_TAG, 'KEY_SAVE add failed code=%{public}d', err.code);
        return false;
      }
    }
    // 已存在 → 更新（幂等）
    const updates: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    updates.set(asset.Tag.SECRET, ApiKeyStore.textToBytes(secret));
    try {
      await asset.update(ApiKeyStore.buildAliasQuery(), updates);
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      Log.e(LOG_TAG, 'KEY_SAVE update failed code=%{public}d', err.code);
      return false;
    }
  }

  /**
   * 保存 API Key（幂等；同别名仅保留一份）。
   * 返回 true=已写入安全存储；false=写入失败（已记日志，不抛出），
   * 由调用方（设置页）转为可读提示。
   */
  static async save(key: string): Promise<boolean> {
    if (key.length === 0) {
      // 空值保存视为清除语义由 clear() 承担；此处直接拒绝并记日志
      Log.w(LOG_TAG, 'KEY_SAVE rejected empty');
      return false;
    }
    const saved: boolean = await ApiKeyStore.assetPutSecret(key);
    if (saved) {
      // 仅记录长度，绝不记录 Key 内容
      Log.i(LOG_TAG, 'KEY_SAVE ok len=%{public}d', key.length);
    }
    return saved;
  }

  /**
   * 读取 API Key：未配置 / ASSET 不可用 / 读取失败一律返回空串（不抛出）。
   * 调用方以空串判定"未配置"（FR-008：未配置不发起请求）。
   */
  static async get(): Promise<string> {
    const query: asset.AssetMap = ApiKeyStore.buildAliasQuery();
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) {
        return '';
      }
      const secretValue: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (!(secretValue instanceof Uint8Array)) {
        Log.e(LOG_TAG, 'KEY_QUERY secret type invalid');
        return '';
      }
      const key: string = ApiKeyStore.bytesToText(secretValue);
      Log.i(LOG_TAG, 'KEY_QUERY hit=%{public}s', key.length > 0);
      return key;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code !== asset.ErrorCode.NOT_FOUND) {
        Log.e(LOG_TAG, 'KEY_QUERY query failed code=%{public}d', err.code);
      }
      return '';
    }
  }

  /**
   * 清除 API Key（幂等：NOT_FOUND 视为已清除）。异常记日志、不抛出。
   */
  static async clear(): Promise<void> {
    try {
      await asset.remove(ApiKeyStore.buildAliasQuery());
      Log.i(LOG_TAG, 'KEY_CLEAR ok');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === asset.ErrorCode.NOT_FOUND) {
        return;
      }
      Log.e(LOG_TAG, 'KEY_CLEAR remove failed code=%{public}d', err.code);
    }
  }
}
