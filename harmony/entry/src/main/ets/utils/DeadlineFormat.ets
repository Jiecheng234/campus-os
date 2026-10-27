/**
 * DeadlineFormat — DDL 截止时间工具（学习详情深链）
 *
 * 从 HomePage 页内实现抽出，供 学习页 / 首页 / 手动 DDL 排序共用：
 *   - parseDeadlineMs          "YYYY-MM-DD HH:mm" → 毫秒（失败 NaN）
 *   - manualDeadlineMs         手动 DDL date + time → 毫秒（time 缺省 23:59）
 *   - formatDeadlineDistance   截止时间距离文案（对齐原项目 formatDeadlineDistance）
 *   - compareDeadlineTextAsc   截止文本升序比较（无法解析的排最后）
 */
import { I18n } from './I18n';

/** 解析 "YYYY-MM-DD HH:mm" 截止时间为毫秒；失败返回 NaN（对齐原项目 parseDeadline） */
export function parseDeadlineMs(deadline: string): number {
  return new Date(deadline.replace(' ', 'T')).getTime();
}

/** 手动 DDL（date: YYYY-MM-DD；time: HH:mm）→ 毫秒；time 为空按 23:59；失败返回 NaN */
export function manualDeadlineMs(date: string, time: string): number {
  const t: string = time.length > 0 ? time : '23:59';
  return parseDeadlineMs(date + ' ' + t);
}

/** 截止时间距离文案（对齐原项目 formatDeadlineDistance；无法解析时回退原文，空串给占位） */
export function formatDeadlineDistance(deadline: string, locale: string): string {
  const time: number = parseDeadlineMs(deadline);
  if (isNaN(time)) {
    return deadline.length > 0 ? deadline : I18n.t('home.suggest.noDeadline', locale);
  }
  const diffDays: number = Math.ceil((time - Date.now()) / (24 * 60 * 60 * 1000));
  if (diffDays < 0) {
    return I18n.t('home.suggest.overdue', locale);
  }
  if (diffDays === 0) {
    return I18n.t('home.suggest.dueToday', locale);
  }
  if (diffDays === 1) {
    return I18n.t('home.suggest.dueTomorrow', locale);
  }
  return I18n.tp('home.suggest.dueInDays', { 'n': String(diffDays) }, locale);
}

/**
 * 截止文本升序比较：可解析的按毫秒升序在前，无法解析的统一排最后。
 * 用于「远程未提交作业 + 手动 DDL」合并排序（FR-021）。
 */
export function compareDeadlineTextAsc(a: string, b: string): number {
  const msA: number = parseDeadlineMs(a);
  const msB: number = parseDeadlineMs(b);
  const validA: boolean = !isNaN(msA);
  const validB: boolean = !isNaN(msB);
  if (validA && validB) {
    return msA - msB;
  }
  if (validA) {
    return -1;
  }
  if (validB) {
    return 1;
  }
  return 0;
}
