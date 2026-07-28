export class WorkflowCondition {
  key: string = '';
  operator: string = '';
  threshold: number = 0;
}

export class Workflow {
  id: string = '';
  type: string = '';
  label: string = '';
  enabled: boolean = false;
  conditions: WorkflowCondition[] = [];
  notifyMessage: string = '';
}

export function getPresetWorkflows(): Workflow[] {
  const list: Workflow[] = [];

  const w1: Workflow = new Workflow();
  w1.id = 'elec_alert'; w1.type = 'electricity'; w1.label = '电费余额告警';
  w1.enabled = false; w1.notifyMessage = '电费余额不足，请及时充值';
  const c1: WorkflowCondition = new WorkflowCondition();
  c1.key = 'balance'; c1.operator = '<'; c1.threshold = 10;
  w1.conditions.push(c1);
  list.push(w1);

  const w2: Workflow = new Workflow();
  w2.id = 'network_alert'; w2.type = 'network'; w2.label = '网费余额告警';
  w2.enabled = false; w2.notifyMessage = '校园网余额不足';
  const c2: WorkflowCondition = new WorkflowCondition();
  c2.key = 'balance'; c2.operator = '<'; c2.threshold = 5;
  w2.conditions.push(c2);
  list.push(w2);

  const w3: Workflow = new Workflow();
  w3.id = 'ddl_warning'; w3.type = 'deadline'; w3.label = 'DDL 提醒';
  w3.enabled = true; w3.notifyMessage = '你有即将到期的作业，请及时完成';
  list.push(w3);

  return list;
}
