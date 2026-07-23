export enum ToolRisk {
  NONE = 'none',
  LOW = 'low',
  MEDIUM = 'medium',
  HIGH = 'high'
}

export class ConfirmationSpec {
  toolName: string = '';
  summary: string = '';
  risk: ToolRisk = ToolRisk.NONE;
  details: Record<string, string> = {};
  cancellable: boolean = true;
}

export class ActionPreview {
  toolName: string = '';
  description: string = '';
  parameters: Record<string, string> = {};
}

export class AuditRecord {
  id: string = '';
  timestamp: string = '';
  toolName: string = '';
  parameters: string = '';
  result: string = '';
  success: boolean = false;
  confirmed: boolean = false;
}
