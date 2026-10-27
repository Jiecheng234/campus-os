/**
 * LearningFileStore — 学习资料下载/打开的统一入口（学习详情深链 US3）
 *
 * 职责（FR-013 ~ FR-017）：
 *   - 确定性本地路径：`filesDir/learn_downloads/<文件标识>_<清洗标题>.<扩展名>`；
 *     标识回退 id → title；无扩展名回退 `.bin`（FR-030）。
 *   - 下载：复用 CampusDataService.downloadFileBytes（带会话 Cookie）；
 *     先嗅探 HTML 登录页（会话失效时下载接口会返回登录 HTML，二进制文件永远不该是 HTML）；
 *     先写临时文件再替换目标——失败不覆盖已下载文件。
 *   - 打开：系统预览（Preview Kit）优先，startAbility(viewData) 回退。
 *
 * 服务层错误一律技术英文（页面负责转成 i18n 可读文案），不硬编码用户可见中文。
 */
import { common, Want } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { filePreview } from '@kit.PreviewKit';
import { CampusDataService, CampusFile } from '../campus/CampusDataService';
import { SessionManager } from '../auth/SessionManager';
import { Log } from '../../utils/Logger';

/** 下载目录名（位于应用 filesDir 下） */
const DOWNLOAD_DIR_NAME: string = 'learn_downloads';
/** 清洗后的文件名（不含扩展名）最大长度 */
const BASE_NAME_MAX_LEN: number = 80;

export class LearningFileStore {
  /** 下载目录绝对路径 */
  static downloadDir(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + DOWNLOAD_DIR_NAME;
  }

  /**
   * 确定性本地路径：文件标识 + 清洗标题 + 扩展名。
   * 标识回退顺序 fileId → id → 清洗标题；无扩展名回退 `.bin`。
   */
  static localPath(context: common.UIAbilityContext, file: CampusFile): string {
    const dir: string = LearningFileStore.downloadDir(context);
    let key: string = file.fileId.length > 0 ? file.fileId : file.id;
    key = LearningFileStore.sanitize(key, 40);
    let title: string = LearningFileStore.sanitize(file.title, 60);
    let ext: string = LearningFileStore.extOf(file.title);
    if (ext.length === 0) {
      ext = LearningFileStore.extOf(LearningFileStore.stripQuery(file.downloadUrl));
    }
    const suffix: string = ext.length > 0 ? '.' + ext : '.bin';
    let base: string = '';
    if (key.length > 0 && title.length > 0) {
      base = key + '_' + title;
    } else if (key.length > 0) {
      base = key;
    } else if (title.length > 0) {
      base = title;
    } else {
      base = 'download';
    }
    if (base.length > BASE_NAME_MAX_LEN) {
      base = base.substring(0, BASE_NAME_MAX_LEN);
    }
    return dir + '/' + base + suffix;
  }

  /** 已下载探测：存在返回本地路径，不存在返回空串 */
  static downloadedPath(context: common.UIAbilityContext, file: CampusFile): string {
    const path: string = LearningFileStore.localPath(context, file);
    try {
      fileIo.statSync(path);
      return path;
    } catch (e) {
      return '';
    }
  }

  /**
   * 下载资料到本地（FR-014）：返回最终本地路径。
   * 失败抛 Error（空 URL / 登录页 / 网络异常）；失败不覆盖已有文件。
   */
  static async download(context: common.UIAbilityContext, file: CampusFile): Promise<string> {
    const service: CampusDataService = SessionManager.getCampusDataService();
    const bytes: Uint8Array = await service.downloadFileBytes(file.downloadUrl);
    if (bytes.length === 0) {
      throw new Error('Empty file body');
    }
    // HTML 登录页嗅探：会话失效时下载端点返回登录 HTML，视为失败（不落盘）
    const prefix: string = LearningFileStore.sniffAsciiPrefix(bytes, 1024);
    if (prefix.includes('<!doctype html') || prefix.includes('<html')) {
      Log.i('LearnFile', 'FILE_DOWNLOAD blocked: html login page');
      throw new Error('Login page returned');
    }
    const dir: string = LearningFileStore.downloadDir(context);
    LearningFileStore.ensureDir(dir);
    const finalPath: string = LearningFileStore.localPath(context, file);
    const tmpPath: string = finalPath + '.tmp';
    LearningFileStore.removeIfExists(tmpPath);
    const opened: fileIo.File = fileIo.openSync(tmpPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const body: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      fileIo.writeSync(opened.fd, body);
    } catch (e) {
      fileIo.closeSync(opened);
      LearningFileStore.removeIfExists(tmpPath);
      throw new Error('Write file failed');
    }
    fileIo.closeSync(opened);
    // 临时文件写入成功后替换目标：优先直接 rename（目标存在时多数实现可原子覆盖），
    // 失败再清理目标重试一次；保证「失败不覆盖已有文件」
    try {
      fileIo.renameSync(tmpPath, finalPath);
    } catch (e) {
      LearningFileStore.removeIfExists(finalPath);
      fileIo.renameSync(tmpPath, finalPath);
    }
    Log.i('LearnFile', 'FILE_DOWNLOADED bytes=%{public}d', bytes.length);
    return finalPath;
  }

  /**
   * 打开已下载文件（FR-015）：系统预览（Preview Kit）优先，startAbility(viewData) 回退。
   * 返回是否成功拉起。
   */
  static async openDownloaded(context: common.UIAbilityContext, path: string, file: CampusFile): Promise<boolean> {
    const uri: string = fileUri.getUriFromPath(path);
    const mimeType: string = LearningFileStore.guessMimeType(path);
    try {
      const previewInfo: filePreview.PreviewInfo = {
        title: file.title.length > 0 ? file.title : 'download',
        uri: uri,
        mimeType: mimeType
      };
      await filePreview.openPreview(context, previewInfo);
      Log.i('LearnFile', 'FILE_OPEN preview ok');
      return true;
    } catch (e) {
      Log.i('LearnFile', 'FILE_OPEN preview fallback');
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: uri,
        type: mimeType
      };
      await context.startAbility(want);
      Log.i('LearnFile', 'FILE_OPEN startAbility ok');
      return true;
    } catch (e) {
      Log.i('LearnFile', 'FILE_OPEN all failed');
      return false;
    }
  }

  /** 按扩展名给出 MIME（对照 Preview Kit 支持类型表）；无法确定返回空串（系统按后缀判断） */
  static guessMimeType(fileName: string): string {
    const ext: string = LearningFileStore.extOf(fileName);
    if (ext === 'txt') {
      return 'text/plain';
    }
    if (ext === 'html' || ext === 'htm') {
      return 'text/html';
    }
    if (ext === 'xml') {
      return 'text/xml';
    }
    if (ext === 'csv') {
      return 'text/csv';
    }
    if (ext === 'pdf') {
      return 'application/pdf';
    }
    if (ext === 'doc') {
      return 'application/msword';
    }
    if (ext === 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (ext === 'xls') {
      return 'application/vnd.ms-excel';
    }
    if (ext === 'xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (ext === 'ppt') {
      return 'application/vnd.ms-powerpoint';
    }
    if (ext === 'pptx') {
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    }
    if (ext === 'jpg' || ext === 'jpeg') {
      return 'image/jpeg';
    }
    if (ext === 'png') {
      return 'image/png';
    }
    if (ext === 'gif') {
      return 'image/gif';
    }
    if (ext === 'webp') {
      return 'image/webp';
    }
    if (ext === 'bmp') {
      return 'image/bmp';
    }
    if (ext === 'svg') {
      return 'image/svg+xml';
    }
    if (ext === 'mp4') {
      return 'video/mp4';
    }
    if (ext === 'mp3') {
      return 'audio/mpeg';
    }
    if (ext === 'wav') {
      return 'audio/x-wav';
    }
    if (ext === 'zip') {
      return 'application/zip';
    }
    return '';
  }

  /** 清洗文件名片段：仅保留中文/字母/数字/下划线/连字符/点，其余替换为下划线，并限长 */
  private static sanitize(raw: string, maxLen: number): string {
    let out: string = '';
    for (let i: number = 0; i < raw.length; i++) {
      const ch: string = raw.charAt(i);
      const code: number = raw.charCodeAt(i);
      const isCjk: boolean = code >= 0x4e00 && code <= 0x9fff;
      const isDigit: boolean = code >= 0x30 && code <= 0x39;
      const isUpper: boolean = code >= 0x41 && code <= 0x5a;
      const isLower: boolean = code >= 0x61 && code <= 0x7a;
      const isSafeSep: boolean = ch === '_' || ch === '-' || ch === '.';
      if (isCjk || isDigit || isUpper || isLower || isSafeSep) {
        out += ch;
      } else {
        out += '_';
      }
    }
    if (out.length > maxLen) {
      out = out.substring(0, maxLen);
    }
    return out;
  }

  /** 取小写 ASCII 前缀（HTML 嗅探用；非 ASCII 字节按原码位拼接，不影响 `<html` 等标记判断） */
  private static sniffAsciiPrefix(bytes: Uint8Array, maxLen: number): string {
    const n: number = Math.min(bytes.length, maxLen);
    let out: string = '';
    for (let i: number = 0; i < n; i++) {
      out += String.fromCharCode(bytes[i]);
    }
    return out.toLowerCase();
  }

  /** 提取扩展名（小写）；非纯字母数字扩展名视为无扩展名 */
  private static extOf(name: string): string {
    const idx: number = name.lastIndexOf('.');
    if (idx < 0 || idx === name.length - 1) {
      return '';
    }
    const ext: string = name.substring(idx + 1).toLowerCase();
    for (let i: number = 0; i < ext.length; i++) {
      const code: number = ext.charCodeAt(i);
      const isDigit: boolean = code >= 0x30 && code <= 0x39;
      const isLower: boolean = code >= 0x61 && code <= 0x7a;
      if (!isDigit && !isLower) {
        return '';
      }
    }
    return ext;
  }

  /** 去掉 URL 查询串（downloadUrl 常带 ?downloadOnly 等参数，取扩展名前先剥离） */
  private static stripQuery(url: string): string {
    const idx: number = url.indexOf('?');
    if (idx >= 0) {
      return url.substring(0, idx);
    }
    return url;
  }

  private static ensureDir(dir: string): void {
    let exists: boolean = false;
    try {
      fileIo.statSync(dir);
      exists = true;
    } catch (e) {
      exists = false;
    }
    if (!exists) {
      fileIo.mkdirSync(dir);
    }
  }

  private static removeIfExists(path: string): void {
    try {
      fileIo.unlinkSync(path);
    } catch (e) {
      // 目标不存在即视为成功
    }
  }
}
