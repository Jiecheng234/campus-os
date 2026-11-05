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
import { common, Want, wantConstant } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { filePreview } from '@kit.PreviewKit';
import { CampusDataService, CampusFile } from '../campus/CampusDataService';
import { HttpBytesResponse } from '../HttpClient';
import { SessionManager } from '../auth/SessionManager';
import { Log } from '../../utils/Logger';

/** 下载目录名（位于应用 filesDir 下） */
const DOWNLOAD_DIR_NAME: string = 'learn_downloads';
/** 清洗后的文件名（不含扩展名）最大长度 */
const BASE_NAME_MAX_LEN: number = 80;
/** 进行中的下载（按最终路径去重：同一文件并发请求共享同一 Promise，settle 后移除） */
const inflightDownloads: Map<string, Promise<string>> = new Map();

export class LearningFileStore {
  /** 下载目录绝对路径 */
  static downloadDir(context: common.UIAbilityContext): string {
    return context.filesDir + '/' + DOWNLOAD_DIR_NAME;
  }

  /**
   * 确定性本地路径：文件标识 + 清洗标题 + 扩展名。
   * 扩展名优先取服务端 fileType（wjlx），其次标题/下载 URL；无扩展名回退 `.bin`。
   */
  static localPath(context: common.UIAbilityContext, file: CampusFile): string {
    return LearningFileStore.buildPath(context, file, LearningFileStore.resolveExt(file, '', ''));
  }

  /** 已下载探测：先查确定性路径，未命中则按文件标识前缀扫描（兼容旧的 `.bin` 文件） */
  static downloadedPath(context: common.UIAbilityContext, file: CampusFile): string {
    const path: string = LearningFileStore.localPath(context, file);
    try {
      fileIo.statSync(path);
      return path;
    } catch (e) {
      // 继续按前缀扫描
    }
    return LearningFileStore.scanFirst(context, file);
  }

  /**
   * 下载资料到本地（FR-014）：返回最终本地路径。
   * 失败抛 Error（空 URL / 登录页 / 网络异常）；失败不覆盖已有文件。
   * 按文件标识前缀 in-flight 去重：同一文件并发下载共享同一 Promise。
   */
  static async download(context: common.UIAbilityContext, file: CampusFile): Promise<string> {
    const inflightKey: string = LearningFileStore.downloadDir(context) + '/' + LearningFileStore.fileKey(file);
    const inflight: Promise<string> | undefined = inflightDownloads.get(inflightKey);
    if (inflight !== undefined) {
      return inflight;
    }
    const task: Promise<string> = LearningFileStore.doDownload(context, file);
    inflightDownloads.set(inflightKey, task);
    try {
      return await task;
    } finally {
      inflightDownloads.delete(inflightKey);
    }
  }

  /** 实际下载与落盘（由 download 包装去重后调用；按响应元信息修正扩展名） */
  private static async doDownload(context: common.UIAbilityContext, file: CampusFile): Promise<string> {
    const service: CampusDataService = SessionManager.getCampusDataService();
    const meta: HttpBytesResponse = await service.downloadFile(file.downloadUrl);
    const bytes: Uint8Array = meta.bytes;
    if (bytes.length === 0) {
      throw new Error('Empty file body');
    }
    const contentType: string = LearningFileStore.headerValue(meta.headers, 'content-type');
    const disposition: string = LearningFileStore.headerValue(meta.headers, 'content-disposition');
    const ext: string = LearningFileStore.resolveExt(file, contentType, disposition);
    const declaredExt: string = LearningFileStore.resolveDeclaredExt(file);
    const finalPath: string = LearningFileStore.buildPath(context, file, ext);
    // HTML 登录页嗅探：只有「服务端声明/标题」明确是 html 才豁免；
    // 不用 Content-Type 推断出的 html，否则会话失效的登录页会被当成资料保存
    if (declaredExt !== 'html' && declaredExt !== 'htm') {
      const prefix: string = LearningFileStore.sniffAsciiPrefix(bytes, 1024);
      if (prefix.includes('<!doctype html') || prefix.includes('<html')) {
        Log.i('LearnFile', 'FILE_DOWNLOAD blocked: html login page');
        throw new Error('Login page returned');
      }
    }
    const dir: string = LearningFileStore.downloadDir(context);
    LearningFileStore.ensureDir(dir);
    // 临时文件带唯一后缀：并发写同一目标也不会互相破坏
    const tmpPath: string = finalPath + '.tmp-' + Date.now() + '-' + Math.random().toString(36).substring(2, 8);
    LearningFileStore.removeIfExists(tmpPath);
    const opened: fileIo.File = fileIo.openSync(tmpPath,
      fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      const body: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const written: number = fileIo.writeSync(opened.fd, body);
      // 校验写入字节数：磁盘满等场景 writeSync 可能短写，此时视为失败
      if (written !== bytes.length) {
        throw new Error('Short write');
      }
    } catch (e) {
      fileIo.closeSync(opened);
      LearningFileStore.removeIfExists(tmpPath);
      throw new Error('Write file failed');
    }
    fileIo.closeSync(opened);
    // 替换前先备份旧文件：备份名唯一，且不删除历史 .bak（极端恢复失败时可能是唯一副本）
    const bakPath: string = finalPath + '.bak-' + Date.now() + '-' + Math.random().toString(36).substring(2, 8);
    let hadOld: boolean = false;
    try {
      fileIo.statSync(finalPath);
      hadOld = true;
      fileIo.renameSync(finalPath, bakPath);
    } catch (e) {
      // 旧文件仍存在说明备份失败：保留旧文件并中止本次替换（避免覆盖唯一副本）
      let stillExists: boolean = false;
      try {
        fileIo.statSync(finalPath);
        stillExists = true;
      } catch (e2) {
        stillExists = false;
      }
      if (stillExists) {
        LearningFileStore.removeIfExists(tmpPath);
        throw new Error('Backup old file failed');
      }
      hadOld = false;
    }
    try {
      fileIo.renameSync(tmpPath, finalPath);
    } catch (e) {
      // 替换失败：恢复旧文件（恢复失败则保留 .bak 供人工恢复），清理临时文件
      if (hadOld) {
        try {
          fileIo.renameSync(bakPath, finalPath);
        } catch (e2) {
          Log.w('LearnFile', 'FILE_DOWNLOAD bak restore failed');
        }
      }
      LearningFileStore.removeIfExists(tmpPath);
      throw new Error('Replace file failed');
    }
    LearningFileStore.removeIfExists(bakPath);
    // 清理同前缀旧 `.bin`（修复前下载的文件），避免同一资料出现两份
    LearningFileStore.removeLegacyBin(context, file, finalPath);
    Log.i('LearnFile', 'FILE_DOWNLOADED bytes=%{public}d', bytes.length);
    return finalPath;
  }

  /**
   * 打开已下载文件（FR-015）：系统预览（Preview Kit）优先，startAbility(viewData) 回退。
   * 返回是否成功拉起。目标不存在直接返回 false（不拉起空 URI）。
   */
  static async openDownloaded(context: common.UIAbilityContext, path: string, file: CampusFile): Promise<boolean> {
    // 打开前确认文件仍存在（下载记录可能已被系统清理）
    try {
      fileIo.statSync(path);
    } catch (e) {
      Log.i('LearnFile', 'FILE_OPEN target missing');
      return false;
    }
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
        // 临时授权读：接收方应用需要读该 URI 的权限
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
      };
      // MIME 无法确定时不传空 type（交由系统按后缀判断）
      if (mimeType.length > 0) {
        want.type = mimeType;
      }
      await context.startAbility(want);
      Log.i('LearnFile', 'FILE_OPEN startAbility ok');
      return true;
    } catch (e) {
      Log.i('LearnFile', 'FILE_OPEN all failed');
      return false;
    }
  }

  /**
   * 删除已下载文件（含修复前遗留的同前缀 `.bin`）；至少删掉一个返回 true。
   * 只作用于应用私有下载目录，不影响课程原件。
   */
  static async deleteDownloaded(context: common.UIAbilityContext, file: CampusFile): Promise<boolean> {
    const dir: string = LearningFileStore.downloadDir(context);
    // 先精确删除当前确定性路径（标题为空时文件名为 key.ext，不能用 key_ 前缀命中）
    LearningFileStore.removeIfExists(LearningFileStore.localPath(context, file));
    const key: string = LearningFileStore.fileKey(file);
    const names: string[] = LearningFileStore.listDirSafe(dir);
    for (let i: number = 0; i < names.length; i++) {
      const name: string = LearningFileStore.baseName(names[i]);
      if (!LearningFileStore.matchesFileKey(name, key) || LearningFileStore.isTempOrBak(name)) {
        continue;
      }
      LearningFileStore.removeIfExists(dir + '/' + name);
    }
    // 复核：仍有可命中的下载文件则视为删除失败（避免 UI 清空但文件仍在）
    return LearningFileStore.downloadedPath(context, file).length === 0;
  }

  /**
   * 另存为：打开系统文件选择器，把已下载文件复制到用户可见位置。
   * 返回是否成功保存（用户取消返回 false）。
   */
  static async exportTo(context: common.UIAbilityContext, path: string, file: CampusFile): Promise<string> {
    try {
      const ext: string = LearningFileStore.extOf(path);
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [LearningFileStore.displayFileName(file, ext)];
      if (ext.length > 0) {
        options.fileSuffixChoices = ['.' + ext];
      }
      const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return 'cancelled';
      }
      const src: fileIo.File = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY);
      let dst: fileIo.File | undefined = undefined;
      try {
        dst = fileIo.openSync(uris[0],
          fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        fileIo.copyFileSync(src.fd, dst.fd);
      } finally {
        fileIo.closeSync(src);
        if (dst !== undefined) {
          fileIo.closeSync(dst);
        }
      }
      Log.i('LearnFile', 'FILE_EXPORT ok');
      return 'ok';
    } catch (e) {
      Log.w('LearnFile', 'FILE_EXPORT failed');
      return 'failed';
    }
  }

  /** 按扩展名给出 MIME（对照 Preview Kit 支持类型表）；无法确定返回空串（系统按后缀判断） */
  static guessMimeType(fileName: string): string {    const ext: string = LearningFileStore.extOf(fileName);
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

  /** 文件标识前缀（fileId → id → 标题 → download），用于路径、扫描与删除 */
  private static fileKey(file: CampusFile): string {
    let key: string = file.fileId.length > 0 ? file.fileId : file.id;
    if (key.length === 0) {
      key = file.title.length > 0 ? file.title : 'download';
    }
    return LearningFileStore.sanitize(key, 40);
  }

  /** 组建本地路径：key_标题.扩展名 */
  private static buildPath(context: common.UIAbilityContext, file: CampusFile, ext: string): string {
    const dir: string = LearningFileStore.downloadDir(context);
    const key: string = LearningFileStore.fileKey(file);
    const title: string = LearningFileStore.sanitize(file.title, 60);
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
    const suffix: string = ext.length > 0 ? '.' + ext : '.bin';
    return dir + '/' + base + suffix;
  }

  /** 扩展名解析：fileType → Content-Disposition → 标题 → Content-Type → 下载 URL → bin */
  private static resolveExt(file: CampusFile, contentType: string, disposition: string): string {
    let ext: string = LearningFileStore.normalizeFileType(file.fileType);
    if (ext.length === 0) {
      ext = LearningFileStore.extFromDisposition(disposition);
    }
    if (ext.length === 0) {
      ext = LearningFileStore.extOf(file.title);
    }
    if (ext.length === 0) {
      ext = LearningFileStore.extFromMime(contentType);
    }
    if (ext.length === 0) {
      ext = LearningFileStore.extOf(LearningFileStore.stripQuery(file.downloadUrl));
    }
    return ext.length > 0 ? ext : 'bin';
  }

  /** 仅由服务端声明/标题得出的扩展名（不信任 Content-Type，用于 HTML 登录页嗅探豁免） */
  private static resolveDeclaredExt(file: CampusFile): string {
    let ext: string = LearningFileStore.normalizeFileType(file.fileType);
    if (ext.length === 0) {
      ext = LearningFileStore.extOf(file.title);
    }
    if (ext.length === 0) {
      ext = LearningFileStore.extOf(LearningFileStore.stripQuery(file.downloadUrl));
    }
    return ext;
  }

  /** 展示用扩展名（与下载落盘同一套解析，供详情页类型/图标使用） */
  static displayExtension(file: CampusFile): string {
    return LearningFileStore.resolveExt(file, '', '');
  }

  /** 服务端 fileType 归一：去掉前导点；若本身是 MIME 则映射 */
  private static normalizeFileType(raw: string): string {
    let value: string = raw.trim().toLowerCase();
    if (value.startsWith('.')) {
      value = value.substring(1);
    }
    if (value.indexOf('/') >= 0) {
      return LearningFileStore.extFromMime(value);
    }
    return LearningFileStore.extOf('x.' + value);
  }

  /** MIME → 扩展名（常见课程文件类型） */
  private static extFromMime(raw: string): string {
    const mime: string = raw.toLowerCase().split(';')[0].trim();
    if (mime === 'application/pdf') { return 'pdf'; }
    if (mime === 'application/msword') { return 'doc'; }
    if (mime.indexOf('wordprocessingml.document') >= 0) { return 'docx'; }
    if (mime === 'application/vnd.ms-excel') { return 'xls'; }
    if (mime.indexOf('spreadsheetml.sheet') >= 0) { return 'xlsx'; }
    if (mime === 'application/vnd.ms-powerpoint') { return 'ppt'; }
    if (mime.indexOf('presentationml.presentation') >= 0) { return 'pptx'; }
    if (mime === 'text/plain') { return 'txt'; }
    if (mime === 'text/html') { return 'html'; }
    if (mime === 'text/csv') { return 'csv'; }
    if (mime === 'image/jpeg') { return 'jpg'; }
    if (mime === 'image/png') { return 'png'; }
    if (mime === 'image/gif') { return 'gif'; }
    if (mime === 'image/webp') { return 'webp'; }
    if (mime === 'image/svg+xml') { return 'svg'; }
    if (mime === 'application/zip') { return 'zip'; }
    if (mime === 'video/mp4') { return 'mp4'; }
    if (mime === 'audio/mpeg') { return 'mp3'; }
    return '';
  }

  /** Content-Disposition → 扩展名（filename / filename* 的尾部后缀） */
  private static extFromDisposition(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    const lower: string = raw.toLowerCase();
    const idx: number = lower.indexOf('filename=');
    if (idx < 0) {
      return '';
    }
    let value: string = raw.substring(idx + 9).trim();
    const semi: number = value.indexOf(';');
    if (semi >= 0) {
      value = value.substring(0, semi);
    }
    value = value.replace(/"/g, '').trim();
    const slash: number = value.lastIndexOf('/');
    if (slash >= 0) {
      value = value.substring(slash + 1);
    }
    return LearningFileStore.extOf(value);
  }

  /** 大小写不敏感读取响应头（数组取第一个） */
  private static headerValue(headers: Record<string, string | string[] | undefined>, name: string): string {
    const target: string = name.toLowerCase();
    const keys: string[] = Object.keys(headers);
    for (let i: number = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() !== target) {
        continue;
      }
      const value: string | string[] | undefined = headers[keys[i]];
      if (typeof value === 'string') {
        return value;
      }
      if (Array.isArray(value) && value.length > 0) {
        return value[0];
      }
    }
    return '';
  }

  /** 目录列表（失败返回空数组） */
  private static listDirSafe(dir: string): string[] {
    try {
      return fileIo.listFileSync(dir);
    } catch (e) {
      return [];
    }
  }

  /** 条目名（listFile 可能返回完整路径或文件名） */
  private static baseName(entry: string): string {
    const slash: number = entry.lastIndexOf('/');
    return slash >= 0 ? entry.substring(slash + 1) : entry;
  }

  private static isTempOrBak(name: string): boolean {
    return name.indexOf('.tmp-') >= 0 || name.indexOf('.bak-') >= 0 ||
      name.endsWith('.tmp') || name.endsWith('.bak');
  }

  /** 文件名是否属于该资料（key_标题.ext / key.ext / 旧标题.ext） */
  private static matchesFileKey(name: string, key: string): boolean {
    if (key.length === 0) {
      return false;
    }
    return name === key || name.startsWith(key + '_') || name.startsWith(key + '.');
  }

  /** 按文件标识前缀扫描第一个已下载文件（兼容旧扩展名） */
  private static scanFirst(context: common.UIAbilityContext, file: CampusFile): string {
    const dir: string = LearningFileStore.downloadDir(context);
    const key: string = LearningFileStore.fileKey(file);
    const names: string[] = LearningFileStore.listDirSafe(dir);
    for (let i: number = 0; i < names.length; i++) {
      const name: string = LearningFileStore.baseName(names[i]);
      if (LearningFileStore.matchesFileKey(name, key) && !LearningFileStore.isTempOrBak(name)) {
        return dir + '/' + name;
      }
    }
    return '';
  }

  /** 删除同前缀旧 `.bin`（修复前下载的文件），避免同一资料出现两份 */
  private static removeLegacyBin(context: common.UIAbilityContext, file: CampusFile, finalPath: string): void {
    const dir: string = LearningFileStore.downloadDir(context);
    const key: string = LearningFileStore.fileKey(file);
    const names: string[] = LearningFileStore.listDirSafe(dir);
    for (let i: number = 0; i < names.length; i++) {
      const name: string = LearningFileStore.baseName(names[i]);
      const path: string = dir + '/' + name;
      if (LearningFileStore.matchesFileKey(name, key) && LearningFileStore.extOf(name) === 'bin' && path !== finalPath) {
        LearningFileStore.removeIfExists(path);
      }
    }
  }

  /** 导出文件名：标题已有扩展名直接用，否则补当前扩展名 */
  private static displayFileName(file: CampusFile, ext: string): string {
    const title: string = file.title.trim();
    if (title.length === 0) {
      return ext.length > 0 ? 'download.' + ext : 'download';
    }
    if (LearningFileStore.extOf(title).length > 0) {
      return title;
    }
    return ext.length > 0 ? title + '.' + ext : title;
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

  /** 创建目录（递归）：已存在视为成功；创建后仍不存在才报错（错误向上传播为下载失败） */
  private static ensureDir(dir: string): void {
    try {
      fileIo.mkdirSync(dir, true);
      return;
    } catch (e) {
      // 递归创建抛错（多为已存在）：回查确认
    }
    try {
      fileIo.statSync(dir);
    } catch (e) {
      throw new Error('Create download dir failed');
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
