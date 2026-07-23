export class AgentUIMetric {
  label: string = '';
  value: string = '';
  trend: string = '';
  icon: string = '';
}

export class AgentUIBriefing {
  type: string = 'briefing';
  title: string = '';
  metrics: AgentUIMetric[] = [];
}

export class AgentUITask {
  title: string = '';
  course: string = '';
  dueTime: string = '';
  priority: string = '';
}

export class AgentUITaskPlan {
  type: string = 'task_plan';
  title: string = '';
  tasks: AgentUITask[] = [];
}

export class AgentUIWeather {
  type: string = 'weather';
  location: string = '';
  temperature: string = '';
  condition: string = '';
  precipitation: string = '';
}
