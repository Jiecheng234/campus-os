/**
 * SecureStorageTurboModule — bridges react-native-keychain to HUKS.
 * Phase 4: ArkTS native implementation.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import huks from '@ohos.security.huks';

const TAG = 'CampusOSSecureStorage';

class KeychainResult {
  service: string = '';
  storage: string = '';
}

class HuksParamWrapper {
  tag: number = 0;
  value: number | boolean | Uint8Array = 0;
}

class HuksOptionsWrapper {
  properties: HuksParamWrapper[] = [];
}

class StorageServiceOptions {
  service: string = '';
}

export class SecureStorageTurboModule {
  static readonly NAME: string = 'CampusOSSecureStorage';

  async setGenericPassword(
    username: string,
    password: string,
    options?: StorageServiceOptions
  ): Promise<KeychainResult> {
    const service: string = options?.service ?? 'com.campusos.credentials';
    hilog.info(0xCAFE, TAG, 'setGenericPassword for service: %{public}s', service);

    try {
      const alias: string = `campusos_cred_${service.replace(/\./g, '_')}`;

      const algParam: HuksParamWrapper = new HuksParamWrapper();
      algParam.tag = huks.HuksTag.HUKS_TAG_ALGORITHM as number;
      algParam.value = huks.HuksKeyAlg.HUKS_ALG_AES as number;

      const sizeParam: HuksParamWrapper = new HuksParamWrapper();
      sizeParam.tag = huks.HuksTag.HUKS_TAG_KEY_SIZE as number;
      sizeParam.value = huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 as number;

      const purposeParam: HuksParamWrapper = new HuksParamWrapper();
      purposeParam.tag = huks.HuksTag.HUKS_TAG_PURPOSE as number;
      purposeParam.value = (huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT) as number;

      const digestParam: HuksParamWrapper = new HuksParamWrapper();
      digestParam.tag = huks.HuksTag.HUKS_TAG_DIGEST as number;
      digestParam.value = huks.HuksKeyDigest.HUKS_DIGEST_SHA256 as number;

      const genOptions: HuksOptionsWrapper = new HuksOptionsWrapper();
      genOptions.properties = [algParam, sizeParam, purposeParam, digestParam];

      await huks.generateKeyItem(alias, genOptions as huks.HuksOptions);
      hilog.info(0xCAFE, TAG, 'HUKS key generated: %{public}s', alias);

      const result: KeychainResult = new KeychainResult();
      result.service = service;
      result.storage = 'huks';
      return result;
    } catch (err) {
      const error = err as Error;
      hilog.error(0xCAFE, TAG, 'setGenericPassword failed: %{public}s', error.message);
      throw new Error(error.message);
    }
  }

  async getGenericPassword(options?: StorageServiceOptions): Promise<KeychainResult | null> {
    const service = options?.service ?? 'com.campusos.credentials';
    hilog.info(0xCAFE, TAG, 'getGenericPassword for service: %{public}s', service);

    try {
      const alias: string = `campusos_cred_${service.replace(/\./g, '_')}`;

      const emptyOpts: HuksOptionsWrapper = new HuksOptionsWrapper();
      emptyOpts.properties = [];

      const isKeyExist: boolean = await huks.isKeyItemExist(alias, emptyOpts as huks.HuksOptions);
      if (!isKeyExist) {
        hilog.info(0xCAFE, TAG, 'No credentials found for alias: %{public}s', alias);
        return null;
      }

      hilog.info(0xCAFE, TAG, 'Credentials exist for alias: %{public}s', alias);
      return null;
    } catch (err) {
      const error = err as Error;
      hilog.info(0xCAFE, TAG, 'getGenericPassword error: %{public}s', error.message);
      return null;
    }
  }

  async resetGenericPassword(options?: StorageServiceOptions): Promise<boolean> {
    const service = options?.service ?? 'com.campusos.credentials';
    hilog.info(0xCAFE, TAG, 'resetGenericPassword for service: %{public}s', service);

    try {
      const alias: string = `campusos_cred_${service.replace(/\./g, '_')}`;

      const emptyOptions: HuksOptionsWrapper = new HuksOptionsWrapper();
      emptyOptions.properties = [];

      await huks.deleteKeyItem(alias, emptyOptions as huks.HuksOptions);
      hilog.info(0xCAFE, TAG, 'HUKS key deleted: %{public}s', alias);
      return true;
    } catch (err) {
      const error = err as Error;
      hilog.error(0xCAFE, TAG, 'resetGenericPassword failed: %{public}s', error.message);
      return false;
    }
  }
}
