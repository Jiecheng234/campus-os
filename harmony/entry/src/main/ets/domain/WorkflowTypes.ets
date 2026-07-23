export class Workflow {
  id: string = '';
  type: string = '';
  label: string = '';
  enabled: boolean = false;
  conditions: WorkflowCondition[] = [];
  notifyMessage: string = '';
}

export class WorkflowCondition {
  key: string = '';
  operator: string = '';
  threshold: string = '';
}

export class WorkflowCheckResult {
  workflowId: string = '';
  triggered: boolean = false;
  currentValue: string = '';
  thresholdValue: string = '';
}

export const PRESET_WORKFLOWS: Workflow[] = [];
