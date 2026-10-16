export enum ToolRisk {
  NONE = 'none',
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

/**
 * 工具执行状态（对齐 RN actions 域 ActionExecutionStatus 的字符串枚举语义）。
 * success=成功；error=执行/验证失败；cancelled=用户取消/确认拒绝/被阻止。
 */
export class ActionExecutionStatus {
  static readonly SUCCESS: string = 'success';
  static readonly ERROR: string = 'error';
  static readonly CANCELLED: string = 'cancelled';
}

/**
 * 写操作确认状态（对齐 RN actions 域 ConfirmationStatus 的字符串枚举语义）。
 * not_required=无需确认；approved=用户已批准；denied=用户已拒绝；
 * unavailable=缺少确认通道（被阻止执行）。
 */
export class ConfirmationStatus {
  static readonly NOT_REQUIRED: string = 'not_required';
  static readonly APPROVED: string = 'approved';
  static readonly DENIED: string = 'denied';
  static readonly UNAVAILABLE: string = 'unavailable';
}

/** 执行后验证结果（ok/message） */
export class VerificationResult {
  ok: boolean = false;
  message: string = '';
}

export class ConfirmationSpec {
  toolName: string = '';
  summary: string = '';
  risk: ToolRisk = ToolRisk.NONE;
  details: Record<string, string> = {};
  cancellable: boolean = true;
  /** 扩展字段（对齐 RN 确认弹窗语义） */
  title: string = '';
  message: string = '';
  destructive: boolean = false;
}

export class ActionPreview {
  toolName: string = '';
  description: string = '';
  parameters: Record<string, string> = {};
  /** 扩展字段（对齐 RN dry-run 预览语义） */
  title: string = '';
  summary: string = '';
  affectedResource: string = '';
  reversible: boolean = true;
}

export class AuditRecord {
  id: string = '';
  timestamp: string = '';
  toolName: string = '';
  parameters: string = '';
  result: string = '';
  success: boolean = false;
  confirmed: boolean = false;
  /** 扩展字段（会话内审计详情：D4 治理链留痕） */
  toolTitle: string = '';
  risk: string = '';
  status: string = '';
  confirmation: string = '';
  resultSummary: string = '';
  errorMessage: string = '';
}
