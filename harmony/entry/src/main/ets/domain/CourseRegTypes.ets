/**
 * ============================================================================
 * CourseRegTypes — 选课系统领域模型（对齐 RN src/domain/courseRegistration.ts）
 * ============================================================================
 *
 * 【来源】RN 领域模型 + T03 spec/plan 的错误契约；旧占位类（startDate/endDate/
 * keyword/department 等字段）与真实接口不匹配且无任何引用，已整体替换（RD-06）。
 *
 * 【错误契约】CourseRegError：code（稳定错误码）+ messageKey（I18n 键）+
 * retryable（调用方可重试标志）+ detail（已脱敏/截断的服务端信息）。
 * `message` 固定为错误码文本（非用户文案）；调用方用 I18n.t(messageKey) 本地化。
 *
 * 【优先级映射】bx→bxk、xx→xxk、rx→rx、ty→rxTy（RN selectCourse 原样；
 * 注意 ty 的表单字段前缀是 p_rxTy_*，不是 p_tyk_*）。
 * ============================================================================
 */

/** 选课类型（仅承诺 RN 线上验证过的四种） */
export enum CourseRegPriority {
  BX = 'bx',
  XX = 'xx',
  RX = 'rx',
  TY = 'ty',
}

/** 是否为服务支持的选课类型（xwk/fxwk/tyk/cx 等 RN 类型声明值不作承诺） */
export function isSupportedCourseRegPriority(value: string): boolean {
  return value === CourseRegPriority.BX || value === CourseRegPriority.XX
    || value === CourseRegPriority.RX || value === CourseRegPriority.TY;
}

/**
 * 选课表单字段前缀映射（RN selectCourse 原样移植）：
 *   bx → 'bxk'   （p_bxk_id / p_bxk_xkzy）
 *   xx → 'xxk'   （p_xxk_id / p_xxk_xkzy）
 *   rx → 'rx'    （p_rx_id  / p_rx_xkzy）
 *   ty → 'rxTy'  （p_rxTy_id / p_rxTy_xkzy；体育随任选-体育通道提交）
 */
export function courseRegFieldKey(priority: string): string {
  if (priority === CourseRegPriority.RX) {
    return 'rx';
  }
  if (priority === CourseRegPriority.TY) {
    return 'rxTy';
  }
  return priority + 'k';
}

/** 选课提交的 m 参数（RN `save + priority[0].toUpperCase() + priority[1] + Kc`） */
export function courseRegSaveMethod(priority: string): string {
  return 'save' + priority.charAt(0).toUpperCase() + priority.charAt(1) + 'Kc';
}

/** 学期（ID 形如 2024-2025-2，是其余接口的必需输入） */
export class CrSemester {
  id: string = '';
  name: string = '';
}

/** 已选课程记录（RN SelectedCourse；缺列行由解析层跳过） */
export class SelectedCourse {
  type: string = '';
  /** 志愿：1/2/3（"第一志愿"→1、"第二志愿"→2、其他→3） */
  will: number = 0;
  id: string = '';
  seq: string = '';
  name: string = '';
  time: string = '';
  teacher: string = '';
  credit: number = 0;
  /** 是否二级选课（"是"/"否"） */
  secondary: boolean = false;
}

/** 课余量课程记录（数字解析失败按 0 处理） */
export class CrRemainingInfo {
  id: string = '';
  seq: number = 0;
  name: string = '';
  capacity: number = 0;
  remaining: number = 0;
  queue: number = 0;
  teacher: string = '';
  time: string = '';
}

/** 课余量搜索结果（无分页脚注时回退 1/1/0） */
export class CrRemainingSearchResult {
  currPage: number = 1;
  totalPage: number = 1;
  totalCount: number = 0;
  courses: CrRemainingInfo[] = [];
}

/** 课余量搜索参数（dayOfWeek 0=未指定 1–7；period 0=未指定 1–12；page ≥ 1） */
export class CourseSearchParams {
  semester: string = '';
  page: number = 1;
  id: string = '';
  name: string = '';
  dayOfWeek: number = 0;
  period: number = 0;
}

/** 选课参数（priority ∈ bx/xx/rx/ty；will ∈ 1/2/3） */
export class SelectCourseParams {
  semester: string = '';
  priority: string = '';
  courseId: string = '';
  courseSeq: string = '';
  will: number = 0;
}

/** 退课参数 */
export class DropCourseParams {
  semester: string = '';
  courseId: string = '';
  courseSeq: string = '';
}

/** 稳定错误码（FR-011；调用方与 T14 据此分支，不解析中文） */
export enum CourseRegErrorCode {
  NOT_LOGGED_IN = 'NOT_LOGGED_IN',
  SESSION_EXPIRED = 'SESSION_EXPIRED',
  NETWORK = 'NETWORK',
  HTTP = 'HTTP',
  PARSE = 'PARSE',
  NO_SEMESTER = 'NO_SEMESTER',
  NO_FORM_TOKEN = 'NO_FORM_TOKEN',
  REJECTED = 'REJECTED',
  UNCONFIRMED = 'UNCONFIRMED',
  UNSUPPORTED_PRIORITY = 'UNSUPPORTED_PRIORITY',
  INVALID_PARAM = 'INVALID_PARAM',
  SERVER = 'SERVER',
}

/**
 * 统一失败描述。所有失败抛出本类型；`message` 为错误码文本（诊断用），
 * 用户文案由调用方通过 I18n.t(messageKey) 获取。
 * detail：已剥离 HTML/控制字符并截断，不含 token/Cookie/学号/密码（FR-012）。
 */
export class CourseRegError extends Error {
  readonly code: CourseRegErrorCode;
  readonly messageKey: string;
  readonly retryable: boolean;
  readonly detail: string;

  constructor(code: CourseRegErrorCode, messageKey: string, retryable: boolean, detail: string) {
    super(String(code));
    this.name = 'CourseRegError';
    this.code = code;
    this.messageKey = messageKey;
    this.retryable = retryable;
    this.detail = detail;
  }
}

/** 错误码 → i18n key 静态映射（键目录见 utils/I18n.ets courseReg.error.*） */
export class CourseRegI18n {
  static keyOf(code: CourseRegErrorCode): string {
    switch (code) {
      case CourseRegErrorCode.NOT_LOGGED_IN:
        return 'courseReg.error.notLoggedIn';
      case CourseRegErrorCode.SESSION_EXPIRED:
        return 'courseReg.error.sessionExpired';
      case CourseRegErrorCode.NETWORK:
        return 'courseReg.error.network';
      case CourseRegErrorCode.HTTP:
        return 'courseReg.error.http';
      case CourseRegErrorCode.PARSE:
        return 'courseReg.error.parse';
      case CourseRegErrorCode.NO_SEMESTER:
        return 'courseReg.error.noSemester';
      case CourseRegErrorCode.NO_FORM_TOKEN:
        return 'courseReg.error.noFormToken';
      case CourseRegErrorCode.REJECTED:
        return 'courseReg.error.rejected';
      case CourseRegErrorCode.UNCONFIRMED:
        return 'courseReg.error.unconfirmed';
      case CourseRegErrorCode.UNSUPPORTED_PRIORITY:
        return 'courseReg.error.unsupportedPriority';
      case CourseRegErrorCode.INVALID_PARAM:
        return 'courseReg.error.invalidParam';
      case CourseRegErrorCode.SERVER:
        return 'courseReg.error.server';
      default:
        return 'courseReg.error.server';
    }
  }
}
